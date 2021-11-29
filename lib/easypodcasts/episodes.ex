defmodule Easypodcasts.Episodes do
  @moduledoc """
  The Episodes context.
  """

  import Ecto.Query, warn: false
  alias Easypodcasts.Repo
  alias Phoenix.PubSub

  alias Ecto.Changeset
  alias Easypodcasts.Helpers.{Utils, Search}
  alias Easypodcasts.Episodes.{Episode, EpisodeAudio}
  alias Easypodcasts.Queue
  alias Easypodcasts.Workers.Worker
  require Logger

  def list_episodes_audio_url(channel_id),
    do:
      from(e in Episode, where: e.channel_id == ^channel_id, select: e.original_audio_url)
      |> Repo.all()

  def list_episodes_audio_url(),
    do:
      from(e in Episode, select: e.original_audio_url)
      |> Repo.all()

  def list_episodes(channel_id, search, page) do
    episode_query = from(e in Episode, where: e.channel_id == ^channel_id)

    case Search.validate_search(search) do
      %{valid?: true, changes: %{search_phrase: search_phrase}} ->
        Search.search(episode_query, search_phrase)

      _ ->
        # This should never happen when searching from the web
        episode_query
    end
    |> order_by([{:desc, :publication_date}])
    |> Repo.paginate(page: page)
    |> Map.put(:params, search: search, page: page)
  end

  def queue_state() do
    from(e in Episode,
      where: e.status in [:processing, :queued],
      order_by: [{:asc, :status}]
    )
    |> Repo.all()
  end

  def queue_size() do
    from(e in Episode,
      where: e.status in [:processing, :queued],
      select: count(e)
    )
    |> Repo.one()
  end

  def query_done_episodes(channel_id) do
    from(e in Episode,
      where: e.status == :done and e.channel_id == ^channel_id,
      order_by: [{:desc, e.publication_date}]
    )
  end

  def list_episodes_updated_before(date) do
    from(e in Episode, where: e.updated_at <= ^date and e.status == :done)
  end

  @doc """
  Gets a single episode.

  Raises `Ecto.NoResultsError` if the Episode does not exist.

  ## Examples

      iex> get_episode!(123)
      %Episode{}

      iex> get_episode!(456)
      ** (Ecto.NoResultsError)

  """
  def get_episode!(id), do: Repo.get!(Episode, id)
  def create_episodes(episodes), do: Repo.insert_all(Episode, episodes, returning: true)

  def update_episode(%Episode{} = episode, attrs \\ %{}) do
    episode
    |> Changeset.change(attrs)
    |> Repo.update()
  end

  def inc_episode_downloads(episode_id) do
    from(e in Episode, update: [inc: [downloads: 1]], where: e.id == ^episode_id)
    |> Repo.update_all([])
  end

  def enqueue(episode_id) do
    episode = get_episode!(episode_id)

    case episode.status do
      status when status in [:new, :processing] ->
        {:ok, episode} = update_episode(episode, %{status: :queued})
        Queue.in_(episode)
        broadcast_queue_changed()
        :ok

      _ ->
        :error
    end
  end

  def next_episode(worker_id) do
    case Queue.out() do
      :empty ->
        :noop

      episode ->
        DynamicSupervisor.start_child(
          WorkerSupervisor,
          {Worker, {episode.id, worker_id}}
        )

        {:ok, episode} = update_episode(episode, %{status: :processing})
        broadcast_episode_state_change(:episode_processing, episode.id, episode.channel_id)
        %{id: episode.id, url: episode.original_audio_url}
    end
  end

  def converted(episode_id, upload, worker_id) do
    # dest = "priv/tmp/#{episode_id}"
    # File.cp!(upload.path, dest)
    episode = get_episode!(episode_id)

    pid =
      case Registry.lookup(WorkerRegistry, episode_id) do
        [] ->
          nil

        [{pid, _}] ->
          pid
      end

    if pid && Worker.worker_id(pid) == worker_id do
      case EpisodeAudio.store({%{upload | filename: "episode.opus"}, episode}) do
        {:ok, _} ->
          size = Utils.get_file_size(upload.path)

          episode
          |> Changeset.change(%{status: :done, processed_size: size, worker_id: worker_id})
          |> Repo.update()

          DynamicSupervisor.terminate_child(WorkerSupervisor, pid)
          broadcast_episode_state_change(:episode_processed, episode.id, episode.channel_id)

        {:error, _} ->
          enqueue(episode.id)
      end
    end
  end

  def cancel(episode_id, worker_id) do
    episode = get_episode!(episode_id)

    pid =
      case Registry.lookup(WorkerRegistry, episode_id) do
        [] ->
          nil

        [{pid, _}] ->
          pid
      end

    if pid && Worker.worker_id(pid) == worker_id do
      DynamicSupervisor.terminate_child(WorkerSupervisor, pid)
      enqueue(episode.id)
    end
  end

  defp broadcast_queue_changed() do
    PubSub.broadcast(Easypodcasts.PubSub, "queue_state", {:queue_changed, queue_size()})
  end

  defp broadcast_episode_state_change(event, channel_id, episode_id) do
    PubSub.broadcast(
      Easypodcasts.PubSub,
      "channel#{channel_id}",
      {event, %{episode_id: episode_id}}
    )
  end

  def save_new_episodes(channel, feed_data) do
    # episode_audio_urls = get_episodes_url_from_channel(channel.id)
    episode_audio_urls = list_episodes_audio_url()

    (feed_data["items"] || [])
    |> Stream.filter(&(&1["enclosures"] && hd(&1["enclosures"])["url"] not in episode_audio_urls))
    |> Stream.map(&episode_item_to_map(&1, channel.id))
    |> Enum.to_list()
    |> create_episodes()
  end

  defp episode_item_to_map(item, channel_id) do
    publication_date =
      with {:ok, parsed_datetime} <- Timex.parse(item["publishedParsed"], "{ISO:Extended}"),
           {:ok, shifted_datetime} <- DateTime.shift_zone(parsed_datetime, "Etc/UTC") do
        shifted_datetime
      else
        _ -> DateTime.utc_now()
      end

    %{
      description: item["description"],
      title: item["title"],
      link: item["link"],
      original_audio_url: item["enclosures"] && hd(item["enclosures"])["url"],
      original_size:
        item["enclosures"] &&
          (hd(item["enclosures"])["length"] || "0") |> String.trim() |> String.to_integer(),
      channel_id: channel_id,
      publication_date: publication_date,
      feed_data: item
    }
  end
end

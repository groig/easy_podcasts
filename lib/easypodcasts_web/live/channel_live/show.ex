defmodule EasypodcastsWeb.ChannelLive.Show do
  use EasypodcastsWeb, :live_view
  import Ecto.Changeset
  alias Easypodcasts.Channels.DataProcess
  alias Easypodcasts.Repo

  alias Easypodcasts.Channels

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    IO.puts("HANDLE PARAMS")

    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:channel, Channels.get_channel!(id))}
  end

  @impl true
  def handle_event("process_episode", %{"episode_id" => episode_id}, socket) do
    DataProcess.process_episode(episode_id)

    # TODO: Move this from here
    Channels.get_episode!(episode_id)
    |> change(%{status: :processing})
    |> Repo.update()

    socket =
      socket
      # TODO: Don't fetch the channel again, just the episode that changed
      |> update(:channel, fn _ -> Channels.get_channel!(socket.assigns.channel.id) end)
      |> put_flash(:info, "The episode is in queue")

    {:noreply, socket}
  end

  defp page_title(:show), do: "Show Channel"

  defp format_date(date) do
    localized = DateTime.shift_zone!(date, "America/Havana")
    "#{localized.year}/#{localized.month}/#{localized.day} #{localized.hour}:#{localized.minute}"
  end
end

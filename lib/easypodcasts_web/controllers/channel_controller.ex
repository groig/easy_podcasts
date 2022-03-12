defmodule EasypodcastsWeb.ChannelController do
  use EasypodcastsWeb, :controller
  alias Easypodcasts.{Channels, Episodes}

  def feed(conn, %{"slug" => slug} = _params) do
    [channel_id | _slug] = String.split(slug, "-")
    channel = Channels.get_channel_for_feed(channel_id)

    conn
    |> put_resp_content_type("text/xml")
    |> put_layout(false)
    |> render("feed.xml", channel: channel)
  end

  def list_feed(conn, %{"channels" => channels} = _params) do
    titles = Channels.list_channels_titles(channels)

    conn
    |> put_resp_content_type("text/xml")
    |> put_layout(false)
    |> render("list_feed.xml",
      titles: titles,
      episodes: Episodes.list_episodes_for_channels(channels)
    )
  end

  def tag_feed(conn, %{"tag" => tag} = _params) do
    conn
    |> put_resp_content_type("text/xml")
    |> put_layout(false)
    |> render("tag_feed.xml", tag: tag, episodes: Episodes.list_episodes_for_tag(tag))
  end

  def counter(conn, _params) do
    case Plug.Conn.get_req_header(conn, "x-original-uri") do
      [] ->
        send_resp(conn, 404, "Not found")

      [original_uri | _rest] ->
        Task.start(fn -> count_download(original_uri) end)
        send_resp(conn, :ok, "")
    end
  end

  defp count_download(uri) do
    uri
    |> String.split("/")
    |> Enum.take(-2)
    |> hd
    |> Episodes.inc_episode_downloads()
  end
end

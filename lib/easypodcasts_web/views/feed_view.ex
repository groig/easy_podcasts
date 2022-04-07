defmodule EasypodcastsWeb.FeedView do
  use EasypodcastsWeb, :view
  alias Easypodcasts.Episodes.EpisodeAudio
  require EEx

  EEx.function_from_file(:def, :feed, "lib/easypodcasts_web/templates/feed/feed.xml.eex", [
    :assigns
  ])

  EEx.function_from_file(
    :def,
    :list_feed,
    "lib/easypodcasts_web/templates/feed/list_feed.xml.eex",
    [
      :assigns
    ]
  )

  EEx.function_from_file(
    :def,
    :tag_feed,
    "lib/easypodcasts_web/templates/feed/tag_feed.xml.eex",
    [
      :assigns
    ]
  )

  def render("feed.xml", %{channel: channel}) do
    feed(channel)
  end

  def render("list_feed.xml", %{channel: channel}) do
    list_feed(channel)
  end

  def render("tag_feed.xml", %{channel: channel}) do
    tag_feed(channel)
  end

  defp clear_ampersand(nil), do: ""
  defp clear_ampersand(string), do: String.replace(string, "&", "&amp;")
end

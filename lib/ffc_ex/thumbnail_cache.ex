defmodule FfcEx.ThumbnailCache do
  alias Nostrum.Struct.Embed.Thumbnail
  alias Nostrum.Struct.Embed
  use GenServer
  require Logger
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    tab = :ets.new(__MODULE__, [:named_table])
    {:ok, tab}
  end

  @impl true
  def handle_call({:cache_url, path, url}, _from, table) do
    :ets.insert(table, {path, url})
    {:reply, :ok, table}
  end

  def send_with_thumbnail_caching!(channel, message) do
    with {:ok, [{:add_thumbnail, path}]} <- Keyword.fetch(message, :files) do
      case :ets.lookup(__MODULE__, path) do
        [{^path, cached_url}] -> cached_url_send(channel, message, cached_url)
        [] -> must_cache_url_send(channel, message)
      end
    else
      _ -> Nostrum.Api.create_message!(channel, message)
    end
  end

  defp cached_url_send(channel, message, cached_url) do
    message =
      message
      |> Keyword.delete(:files)
      |> Keyword.update!(:embeds, fn [embed] ->
        [%Embed{embed | thumbnail: %Thumbnail{url: cached_url}}]
      end)

    Nostrum.Api.create_message!(channel, message)
  end

  defp must_cache_url_send(channel, message) do
    [{:add_thumbnail, path}] = Keyword.fetch!(message, :files)
    Logger.debug(["Adding thumbnail for path ", path])

    message =
      message
      |> Keyword.put(:files, [path])
      |> Keyword.update!(:embeds, fn [embed] ->
        [%Embed{embed | thumbnail: %Thumbnail{url: "attachment://#{Path.basename(path)}"}}]
      end)

    out_message = Nostrum.Api.create_message!(channel, message)
    [embed] = out_message.embeds
    url = embed.thumbnail.url
    GenServer.call(__MODULE__, {:cache_url, path, url})
  end
end

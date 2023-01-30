defmodule FfcEx.BaseConsumer do
  use Nostrum.Consumer
  require Logger

  alias Nostrum.Api

  def start_link() do
    Consumer.start_link(__MODULE__, name: __MODULE__)
  end

  @impl true
  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    prefix = Application.fetch_env!(:ffc_ex, :prefix)

    if msg.guild_id == nil do
      # Handle DM message
    else
      # Handle guild message
      if String.starts_with?(msg.content, prefix) do
        command = String.slice(msg.content, String.length(prefix)..-1//1)

        case command do
          "ping" ->
            Api.create_message(msg.channel_id, "pong from ffc_ex!")

          _ ->
            :ignore
        end
      end
    end
  end

  @impl true
  def handle_event(_event) do
    :noop
  end
end

defmodule FfcEx.BaseConsumer do
  use Nostrum.Consumer
  alias FfcEx.GameLobbies
  alias Nostrum.Struct.Embed

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
        handle_guild_commands(command, msg)
      end
    end
  end

  @impl true
  def handle_event(_event) do
    :noop
  end

  defp handle_guild_commands(command, msg) do
    case command do
      "ping" -> ping(msg)
      "join" -> join(msg)
      "spectate" -> spectate(msg)
      "close" -> close(msg)
      _ -> :ignore
    end
  end

  defp ping(msg) do
    prev = System.monotonic_time(:millisecond)
    {:ok, message} = Api.create_message(msg.channel_id, "Pinging...")
    ms = System.monotonic_time(:millisecond) - prev

    embed = %Embed{
      title: "FFCex v#{Keyword.fetch!(Application.spec(:ffc_ex), :vsn)}",
      description:
        "**API latency:** #{ms}ms\n" <>
          "**Erlang/OTP release:** #{System.otp_release()}\n" <>
          "**Elixir version:** #{System.version()}\n" <>
          "**Memory usage:** #{div(:erlang.memory(:total), 1_000_000)}MB",
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      color: 0xFF3030
    }

    Api.edit_message(message, content: "", embed: embed)
  end

  defp join(msg) do
    case GameLobbies.join(msg.channel_id, msg.author.id) do
      {:new, id, timeout} ->
        Api.create_message(
          msg.channel_id,
          "Created lobby \##{id}, etc. etc. Will timeout <t:#{DateTime.to_unix(timeout)}:R>"
        )

      {:joined, id} ->
        Api.create_message(msg.channel_id, "Joined game \##{id}")

      {:already_joined, id} ->
        Api.create_message(msg.channel_id, "Already joined game \##{id}")
    end
  end

  defp spectate(msg) do
    case GameLobbies.spectate(msg.channel_id, msg.author.id) do
      {:spectating, id} ->
        Api.create_message(msg.channel_id, "Spectating game \##{id}")

      :cannot_spectate ->
        Api.create_message(msg.channel_id, "Cannot spectate game in this channel")
    end
  end

  defp close(msg) do
    case GameLobbies.close(msg.channel_id, msg.author.id) do
      {:closed, lobby} ->
        Api.create_message(msg.channel_id, inspect(lobby))

      :cannot_close ->
        Api.create_message(msg.channel_id, "Cannot close lobby as you are not the owner or it doesn't exist.")

      :player_count_invalid ->
        Api.create_message(msg.channel_id, "Cannot close lobby as the number of players is invalid.")
    end
  end
end

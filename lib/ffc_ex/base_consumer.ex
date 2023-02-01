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
      description: """
      **API latency:** #{ms}ms
      **Erlang/OTP release:** #{System.otp_release()}
      **Elixir version:** #{System.version()}
      **Memory usage:** #{(:erlang.memory(:total) / 1_000_000) |> :erlang.float_to_binary(decimals: 2)}MB
      """,
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      color: Application.fetch_env!(:ffc_ex, :color)
    }

    Api.edit_message(message, content: "", embed: embed)
  end

  defp join(msg) do
    case GameLobbies.join(msg.channel_id, msg.author.id) do
      {:new, id, timeout} ->
        prefix = Application.fetch_env!(:ffc_ex, :prefix)

        embed = %Embed{
          title: "Final Fantastic Card",
          description: """
          <@#{msg.author.id}> has started game \##{id}!
          - To join, type `#{prefix}join`;
          - To spectate the game, type `#{prefix}spectate`;
          - Once everyone's in, <@#{msg.author.id}> can use `#{prefix}close` to close the lobby and start the game!
          *The lobby will timeout <t:#{DateTime.to_unix(timeout)}:R>.*
          """,
          timestamp: DateTime.to_iso8601(DateTime.utc_now()),
          color: Application.fetch_env!(:ffc_ex, :color)
        }

        Api.create_message(msg.channel_id, embeds: [embed])

      {:joined, id} ->
        Api.create_message(
          msg.channel_id,
          "**#{msg.author.username}\##{msg.author.discriminator}** has joined lobby \##{id}."
        )

      {:already_joined, id} ->
        Api.create_message(msg.channel_id, "You have already joined game \##{id}!")
    end
  end

  defp spectate(msg) do
    case GameLobbies.spectate(msg.channel_id, msg.author.id) do
      {:spectating, id} ->
        Api.create_message(
          msg.channel_id,
          "**#{msg.author.username}\##{msg.author.discriminator}** is spectating lobby \##{id}."
        )

      :cannot_spectate ->
        Api.create_message(msg.channel_id, "Cannot spectate game!")

      :already_spectating ->
        Api.create_message(msg.channel.id, "You are already spectating the game!")
    end
  end

  defp close(msg) do
    case GameLobbies.close(msg.channel_id, msg.author.id) do
      {:closed, lobby} ->
        Api.create_message(
          msg.channel_id,
          "**Lobby \##{lobby.id}** was closed and the game is starting."
        )

      :cannot_close ->
        Api.create_message(
          msg.channel_id,
          "Cannot close lobby as you are not the owner or it doesn't exist."
        )

      :player_count_invalid ->
        Api.create_message(
          msg.channel_id,
          "Cannot close lobby as the number of players is invalid."
        )
    end
  end
end

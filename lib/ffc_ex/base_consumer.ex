defmodule FfcEx.BaseConsumer do
  use Nostrum.Consumer

  alias FfcEx.{Game, GameCmdParser, GameLobbies, GameRegistry, PlayerRouter}
  alias Nostrum.{Api, Struct.Embed, Struct.User, Util}

  require Logger

  def start_link() do
    Consumer.start_link(__MODULE__, name: __MODULE__)
  end

  @impl true
  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    prefix = Application.fetch_env!(:ffc_ex, :prefix)

    case msg.guild_id do
      nil ->
        # Handle DM message
        {int, cmd} = GameCmdParser.parse(msg.content)

        game =
          case int do
            nil ->
              id = PlayerRouter.lookup(msg.author.id)
              GameRegistry.get_game(id)

            x ->
              GameRegistry.get_game(x)
          end

        if game != nil and Game.part_of?(game, msg.author.id) do
          res = Game.do_cmd(game, msg.author.id, cmd)

          if int != nil do
            PlayerRouter.set_for(msg.author.id, int)
          end
          if res and match?({:chat, _}, cmd) do
            Api.create_reaction!(msg.channel_id, msg.id, "✅")
          end
        end

      _ ->
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
      "join" -> join(msg, [])
      "join " <> args -> join(msg, args |> String.trim() |> String.to_charlist())
      "spectate" -> spectate(msg)
      "close" -> close(msg)
      "help" -> help(msg)
      _ -> :ignore
    end
  end

  defp help(msg) do
    embed = %Embed{
      title: "ℹ️ FFCex Help",
      description: """
      `ffc:ping` - checks if bot is online and shows general info.
      `ffc:help` - gets this message.
      `ffc:join` - starts a new game lobby or joins an existing one.
      `ffc:spectate` - spectates a game lobby.
      `ffc:close` - closes the game lobby and starts the game.
      [**Click here to view game instructions.**](https://vrabbers.github.io/ffc_ex/index.html)
      """,
      color: Application.fetch_env!(:ffc_ex, :color),
      thumbnail: %Embed.Thumbnail{url: User.avatar_url(Api.get_current_user!())}
    }

    Api.create_message!(msg.channel_id, embeds: [embed])
  end

  defp os_str() do
    type =
      case :os.type() do
        {:win32, _} -> "Windows"
        {:unix, os_type} -> os_type |> Atom.to_string() |> String.capitalize()
      end

    version =
      case :os.version() do
        {major, minor, release} -> "#{major}.#{minor}.#{release}"
        str -> str
      end

    "#{type} v#{version}"
  end

  defp ping(msg) do
    prev = System.monotonic_time(:millisecond)
    message = Api.create_message!(msg.channel_id, "Pinging 📶...")
    api_latency = System.monotonic_time(:millisecond) - prev

    latencies = Util.get_all_shard_latencies() |> Map.values()
    heartbeat = Enum.sum(latencies) / length(latencies)

    embed = %Embed{
      title: "FFCex v#{Keyword.fetch!(Application.spec(:ffc_ex), :vsn)}",
      description: """
      **Heartbeat:** #{heartbeat}ms
      **API latency:** #{api_latency}ms
      **Erlang/OTP release:** #{System.otp_release()}
      **Elixir version:** #{System.version()}
      **Memory usage:** #{(:erlang.memory(:total) / 1_000_000) |> :erlang.float_to_binary(decimals: 2)}MB
      **Operating system:** #{os_str()}
      """,
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      color: Application.fetch_env!(:ffc_ex, :color),
      thumbnail: %Embed.Thumbnail{url: User.avatar_url(Api.get_current_user!())}
    }

    Api.edit_message(message, content: "", embed: embed)
  end

  defp house_rules(char) do
    case char do
      ?c -> :cumulative_draw
      _ -> nil
    end
  end

  defp join(msg, args) do
    house_rules = args |> Enum.map(&house_rules/1) |> Enum.filter(& &1 != nil) |> Enum.uniq()
    case GameLobbies.join(msg.channel_id, msg.author.id, house_rules) do
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

        Api.create_message!(msg.channel_id, embeds: [embed])

      {:joined, id} ->
        Api.create_message!(
          msg.channel_id,
          "**#{msg.author.username}\##{msg.author.discriminator}** has joined lobby \##{id}."
        )

      {:already_joined, id} ->
        Api.create_message!(msg.channel_id, "You have already joined game \##{id}!")

      :cannot_house_rules ->
        Api.create_message!(msg.channel_id, "You cannot specify new house rules!")
    end
  end

  defp spectate(msg) do
    case GameLobbies.spectate(msg.channel_id, msg.author.id) do
      {:spectating, id} ->
        Api.create_message!(
          msg.channel_id,
          "**#{msg.author.username}\##{msg.author.discriminator}** is spectating lobby \##{id}."
        )

      :cannot_spectate ->
        Api.create_message!(msg.channel_id, "Cannot spectate game!")

      :already_spectating ->
        Api.create_message!(msg.channel.id, "You are already spectating the game!")
    end
  end

  defp close(msg) do
    case GameLobbies.close(msg.channel_id, msg.author.id) do
      {:closed, lobby, game} ->
        case Game.start_game(game) do
          :ok ->
            Api.create_message!(
              msg.channel_id,
              "**Lobby \##{lobby.id}** was closed and the game is starting."
            )

          {:cannot_dm, users} ->
            Api.create_message!(
              msg.channel_id,
              """
              Game \##{lobby.id} could not start as I have not been able to DM these players:
              #{users |> Enum.map_join(" ", &"<@#{&1}>")}
              Please change settings so I can send these people direct messages.
              """
            )
        end

      :cannot_close ->
        Api.create_message!(
          msg.channel_id,
          "Cannot close lobby as you are not the owner or it doesn't exist."
        )

      :player_count_invalid ->
        Api.create_message!(
          msg.channel_id,
          "The lobby was closed, but the game was not started as the player count is invalid."
        )
    end
  end
end

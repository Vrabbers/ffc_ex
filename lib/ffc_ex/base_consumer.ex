defmodule FfcEx.BaseConsumer do
  use Nostrum.Consumer

  alias FfcEx.Interactions
  alias FfcEx.{Game, GameCmdParser, GameLobbies, GameRegistry, PlayerRouter}
  alias Nostrum.{Api, Struct.Embed, Struct.Event, Struct.User, Struct.Message, Util}

  require Logger

  def start_link() do
    Consumer.start_link(__MODULE__, name: __MODULE__)
  end

  @impl true
  def handle_event({:READY, %Event.Ready{v: v}, _ws_state}) do
    Logger.info("#{__MODULE__} ready on gateway v#{v}.")
    Interactions.prepare_app_commands()
    :noop
  end

  @impl true
  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    {:ok, fun} = Interactions.handle(interaction)
    fun.()
  end

  @impl true
  def handle_event({:MESSAGE_CREATE, %Message{author: %User{bot: nil}, guild_id: nil} = msg, _}) do
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
  end

  @impl true
  def handle_event(_event) do
    :noop
  end

  defp handle_guild_commands(command, msg) do
    case command do
      "join" -> join(msg, [])
      "join " <> args -> join(msg, args |> String.trim() |> String.to_charlist())
      "spectate" -> spectate(msg)
      "close" -> close(msg)
      _ -> :ignore
    end
  end

  defp join(msg, args) do
    house_rules = []

    case GameLobbies.join(msg.channel_id, msg.author.id, house_rules) do
      {:new, id, timeout} ->
        prefix = Application.fetch_env!(:ffc_ex, :prefix)

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

defmodule FfcEx.BaseConsumer do
  use Nostrum.Consumer

  alias FfcEx.Interactions
  alias FfcEx.{Game, GameCmdParser, GameRegistry, PlayerRouter}
  alias Nostrum.{Api, Struct.Event, Struct.User, Struct.Message}

  require Logger

  def start_link() do
    Consumer.start_link(__MODULE__, name: __MODULE__)
  end

  @impl true
  def handle_event({:READY, %Event.Ready{v: v}, _ws_state}) do
    Logger.info("#{__MODULE__} ready on gateway v#{v}.")
    Interactions.prepare_app_commands()
  end

  @impl true
  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    :ok = Interactions.handle(interaction)
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
end

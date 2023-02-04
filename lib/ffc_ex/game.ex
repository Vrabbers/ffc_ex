defmodule FfcEx.Game do
  # Doesn't make much sense to try restarting a crashed game
  use GenServer, restart: :temporary
  alias FfcEx.{DmCache, Game, Game.Card, Game.Deck, Lobby, PlayerRouter}
  alias Nostrum.Struct.{Embed, Embed.Thumbnail, User}
  alias Nostrum.Api
  require Logger

  @enforce_keys [:id, :players, :hands, :spectators, :deck, :last, :turn_of]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{
          id: Lobby.id(),
          players: [User.id()],
          hands: %{required(User.id()) => {Deck.t()}},
          spectators: [User.id()],
          deck: Deck.t(),
          last: Card.t() | nil,
          turn_of: User.id()
        }

  @spec playercount_valid?(non_neg_integer()) :: boolean()
  def playercount_valid?(count) do
    count >= 2 && count <= 10
  end

  @spec start_game(pid()) :: :ok | {:cannot_dm, [User.id()]}
  def start_game(game) do
    GenServer.call(game, :start_game, :infinity)
  end

  def is_part_of(game, user) do
    GenServer.call(game, {:is_part_of, user})
  end

  def do_cmd(game, user, cmd) do
    if is_part_of(game, user) do
      GenServer.cast(game, {user, cmd})
      true
    else
      false
    end
  end

  def start_link(lobby) do
    GenServer.start_link(__MODULE__, lobby)
  end

  @impl true
  def init(lobby) do
    deck = Deck.new()
    {groups, deck} = Deck.get_many_groups(deck, 7, length(lobby.players))
    hands = Enum.zip(lobby.players, groups) |> Map.new()
    {last, deck} = Deck.get_matching(deck, &Card.is_valid_first_card/1)

    game = %Game{
      id: lobby.id,
      players: lobby.players,
      hands: hands,
      spectators: lobby.spectators,
      deck: deck,
      last: last,
      turn_of: List.first(lobby.players)
    }

    {:ok, game}
  end

  @impl true
  def handle_cast({user_id, {:state}}, game) do
    tell(user_id, "```elixir\n#{inspect(game, pretty: true, limit: 10, width: 120)}```")
    {:noreply, game}
  end

  @impl true
  def handle_cast({user_id, {:chat, chat_msg}}, game) do
    {:ok, user} = Api.get_user(user_id)
    broadcast_except(game, [user_id], "**#{user.username}\##{user.discriminator}:** #{chat_msg}")
    {:noreply, game}
  end

  @impl true
  def handle_call({:is_part_of, user_id}, _from, game) do
    {:reply, user_id in participants(game), game}
  end

  @impl true
  def handle_call(:start_game, _from, game) do
    responses =
      for user <- participants(game) do
        {:ok, dm_channel} = DmCache.create(user)
        {Api.create_message(dm_channel, "Starting game \##{game.id}..."), user}
      end

    if Enum.all?(responses, fn {{resp, _}, _} -> resp == :ok end) do
      embed =
        %Embed{
          title: "Final Fantastic Card",
          description: """
          Welcome to Final Fanstastic Card!
          """,
          color: Application.fetch_env!(:ffc_ex, :color),
          thumbnail: %Thumbnail{url: "attachment://draw.png"}
        }
        |> put_id_footer(game)

      broadcast(game, embeds: [embed], files: ["./img/draw.png"])
      PlayerRouter.add_all_to(participants(game), game.id)
      {:reply, :ok, game}
    else
      {:stop, :error, {:cannot_dm, for({{:error, _}, user} <- responses, do: user)}, game}
    end
  end

  @spec participants(Game.t()) :: [User.id()]
  defp participants(game) do
    game.players ++ game.spectators
  end

  defp broadcast(game, message) do
    broadcast_to(participants(game), message)
  end

  defp broadcast_except(game, except_users, message) do
    broadcast_to(participants(game) -- except_users, message)
  end

  defp broadcast_to(users, message) do
    for user <- users do
      tell(user, message)
    end

    :ok
  end

  defp tell(user, message) do
    {:ok, dm_channel} = DmCache.create(user)

    Task.start(fn ->
      case Api.create_message(dm_channel, message) do
        {:error, error} ->
          Logger.error(
            "Error telling #{inspect(user)} message: #{inspect(message)}: #{inspect(error)}"
          )

        {:ok, _} ->
          :noop
      end
    end)
  end

  defp put_id_footer(embed, game) do
    Embed.put_footer(embed, "Game \##{game.id}")
  end
end

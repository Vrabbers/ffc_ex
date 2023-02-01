defmodule FfcEx.Game do
  alias FfcEx.Lobby
  alias FfcEx.Game
  alias Nostrum.Struct.User
  use GenServer, restart: :temporary

  @enforce_keys [:id, :players, :spectators]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{
          id: Lobby.id(),
          players: [User.id()],
          spectators: [User.id()]
        }

  @spec playercount_valid?(non_neg_integer()) :: boolean()
  def playercount_valid?(count) do
    count >= 2 && count <= 10
  end

  def start_link(lobby) do
    GenServer.start_link(__MODULE__, lobby)
  end

  @impl true
  def init(lobby) do
    game = %Game{
      id: lobby.id,
      players: lobby.players,
      spectators: lobby.spectators
    }

    {:ok, game}
  end
end

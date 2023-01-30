defmodule FfcEx.GameLobbies do
  use GenServer
  alias Nostrum.Struct.Channel
  alias Nostrum.Snowflake

  @type state() :: {[Lobby.t()], increasing_id :: Lobby.id()}
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  @spec init([]) :: {:ok, state()}
  def init([]) do
    {:ok, {[], 1}}
  end

  defmodule Lobby do
    @type id() :: non_neg_integer()
    @enforce_keys [:id, :channel, :starting_user]
    defstruct id: nil, channel: nil, starting_user: nil, players: [], spectators: []

    @type t() :: %__MODULE__{
            id: id(),
            channel: Channel.id(),
            starting_user: Snowflake.t(),
            players: [Snowflake.t()],
            spectators: [Snowflake.t()]
          }
  end
end

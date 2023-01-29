defmodule FfcEx.GameRegistry do
  use GenServer
  alias FfcEx.GameRegistry
  alias Nostrum.Struct.Channel
  alias Nostrum.Snowflake

  # Types registration
  @type key :: non_neg_integer()
  @type game_registration ::
          {pid :: pid(), guild :: Channel.id(), user_id :: Snowflake.t(), closed :: boolean()}

  defstruct current_id: 1, games: %{}, references: %{}
  @opaque games_map() :: %{required(key()) => game_registration()}
  @opaque references_map() :: %{required(reference()) => key()}
  @opaque state() :: %__MODULE__{
            current_id: key(),
            games: games_map(),
            references: references_map()
          }

  # Client-side
  @spec start_link([]) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Server-side
  @spec init([]) :: {:ok, state()}
  def init([]) do
    {:ok, %GameRegistry{}}
  end
end

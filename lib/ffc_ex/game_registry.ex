defmodule FfcEx.GameRegistry do
  use GenServer
  alias FfcEx.GameRegistry
  alias FfcEx.GameLobbies.Lobby
  require Logger

  # Types registration
  @type key :: non_neg_integer()
  @type game_registration :: {pid(), Lobby.t()}

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
  @impl true
  def init([]) do
    {:ok, %GameRegistry{}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    {id, references} = Map.pop(state.references, ref)
    games = Map.delete(state.games, id)
    Logger.info("Game #{id}, PID: #{pid} closed (#{reason})")
    {:noreply, %{state | games: games, references: references}}
  end

  @impl true
  def handle_info(msg, state) do
    require Logger
    Logger.debug("Unknown message received by GameRegistry: #{inspect(msg)}")
    {:noreply, state}
  end
end

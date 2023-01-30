defmodule FfcEx.GameRegistry do
  use GenServer
  alias FfcEx.GameLobbies.Lobby
  require Logger

  # Types registration
  @type game_registration() :: {pid(), Lobby.t()}

  @opaque games_map() :: %{required(Lobby.id()) => game_registration()}
  @opaque references_map() :: %{required(reference()) => Lobby.id()}
  @opaque state() :: {games :: games_map(), references :: references_map()}

  # Client-side
  @spec start_link([]) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Server-side
  @impl true
  @spec init([]) :: {:ok, state()}
  def init([]) do
    {:ok, {%{}, %{}}}
  end

  @impl true
  @spec handle_info({:DOWN, reference(), :process, pid(), term()}, state()) :: {:noreply, state()}
  def handle_info({:DOWN, ref, :process, pid, reason}, {games, references}) do
    {id, references} = Map.pop(references, ref)
    games = Map.delete(games, id)
    Logger.info("Game #{id}, PID: #{pid} closed (reason: #{reason})")
    {:noreply, {games, references}}
  end

  @impl true
  def handle_info(msg, state) do
    require Logger
    Logger.debug("Unknown message received by GameRegistry: #{inspect(msg)}")
    {:noreply, state}
  end
end

defmodule FfcEx.GameRegistry do
  use GenServer
  require Logger

  alias FfcEx.GameSupervisor
  alias FfcEx.GameLobbies.Lobby

  # Types registration
  @opaque games_map() :: %{required(Lobby.id()) => pid()}
  @opaque references_map() :: %{required(reference()) => Lobby.id()}
  @opaque state() :: {games :: games_map(), references :: references_map()}

  # Client-side
  @spec start_link([]) :: GenServer.on_start()
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec create_game(Lobby.t()) :: pid()
  def create_game(lobby) do
    GenServer.call(__MODULE__, {:create_game, lobby})
  end

  def get_game(id) do
    GenServer.call(__MODULE__, {:get_game, id})
  end

  # Server-side
  @impl true
  @spec init([]) :: {:ok, state()}
  def init([]) do
    {:ok, {%{}, %{}}}
  end

  @impl true
  def handle_call({:create_game, lobby}, _from, {games, references}) do
    if Map.has_key?(games, lobby.id) do
      raise "This game ID already exists in the registry. Game IDs must be unique."
    else
      {:ok, game} = GameSupervisor.start_child(lobby)
      games = Map.put(games, lobby.id, game)
      ref = Process.monitor(game)
      references = Map.put(references, ref, lobby.id)
      {:reply, game, {games, references}}
    end
  end

  @impl true
  def handle_call({:get_game, id}, _from, {games, _} = state) do
    {:reply, games[id], state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, {games, references}) do
    {id, references} = Map.pop(references, ref)
    games = Map.delete(games, id)
    Logger.info("Game #{id}, PID: #{inspect(pid)} closed (reason: #{inspect(reason)})")
    {:noreply, {games, references}}
  end

  @impl true
  def handle_info(msg, state) do
    require Logger
    Logger.debug("Unknown message received by GameRegistry: #{inspect(msg)}")
    {:noreply, state}
  end
end

defmodule FfcEx.GameResponder do
  alias FfcEx.PlayerRouter
  alias FfcEx.Game
  use GenServer, restart: :transient

  require Logger

  def start_game(pid) do
    GenServer.call(pid, :start_game, :infinity)
  end

  def command(pid, uid, command) do
    GenServer.call(pid, {:cmd, uid, command})
  end

  def part_of?(pid, uid) do
    GenServer.call(pid, {:part_of?, uid})
  end

  @impl true
  def init({lobby, game}) do
    Process.monitor(game)
    {:ok, {lobby.players, lobby.spectators, game, lobby.id}}
  end

  def start_link({lobby, game}) do
    GenServer.start_link(__MODULE__, {lobby, game},
      name: {:via, Registry, {FfcEx.GameRegistry, {:resp, lobby.id}}}
    )
  end

  @impl true
  def handle_call(:start_game, _from, {players, spectators, game, id} = state) do
    FfcEx.Game.MessageQueue.broadcast_to(players ++ spectators, "start #{id}")
    PlayerRouter.add_all_to(players ++ spectators, id)
    resp = Game.start_game(game)
    respond(resp, state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:cmd, uid, command}, _from, {_p, _s, game, _i} = state) do
    resp = GenServer.call(game, {uid, command})
    respond(resp, state)
    {:reply, resp, state}
  end

  @impl true
  def handle_call({:part_of?, uid}, _from, {players, spectators, _g, _i} = state) do
    {:reply, uid in (players ++ spectators), state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, game, reason}, {_players, _spectators, game, id})
      when reason != :normal do
    Logger.notice("Game \##{id}, PID: #{inspect(game)} closed (reason: #{inspect(reason)})")
    exit(:shutdown)
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unknown message received by GameResponder #{inspect(self())}: #{inspect(msg)}")
    {:noreply, state}
  end

  defp respond(terms, state) when is_list(terms) do
    terms |> Enum.reverse() |> Enum.each(&respond(&1, state))
  end

  defp respond(term, {players, spectators, _game, id}) do
    Game.MessageQueue.broadcast_to(players ++ spectators, "#{id}: #{inspect(term)}")
  end

end

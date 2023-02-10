defmodule FfcEx.GameLobbies do
  use GenServer

  alias FfcEx.GameRegistry
  alias FfcEx.Lobby
  alias Nostrum.Api
  alias Nostrum.Struct.Channel
  alias Nostrum.Struct.User
  require Logger

  @opaque state() :: {%{required(Channel.id()) => Lobby.t()}, current_id :: Lobby.id()}

  ## Clientside
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec join(Channel.id(), User.id()) ::
          {:new, Lobby.id(), DateTime.t()} | {:joined, Lobby.id()} | {:already_joined, Lobby.id()}
  def join(channel, user) do
    GenServer.call(__MODULE__, {:join, channel, user})
  end

  @spec spectate(Channel.id(), User.id()) ::
          {:spectating, Lobby.id()} | :cannot_spectate | :already_spectating
  def spectate(channel, user) do
    GenServer.call(__MODULE__, {:spectate, channel, user})
  end

  @spec close(Channel.id(), User.id()) ::
          {:closed, Lobby.t(), pid()} | :cannot_close | :player_count_invalid
  def close(channel, user) do
    GenServer.call(__MODULE__, {:close, channel, user})
  end

  ## Server side
  @impl true
  @spec init([]) :: {:ok, state()}
  def init([]) do
    {:ok, {%{}, 1}}
  end

  @impl true
  def handle_call({:join, channel, user}, _from, {lobbies, current_id} = state) do
    lobby = lobbies[channel]

    cond do
      lobby == nil ->
        new_lobby = %Lobby{id: current_id, starting_user: user, players: [user]}
        new_lobbies = Map.put(lobbies, channel, new_lobby)
        new_id = current_id + 1
        timeout = DateTime.add(DateTime.utc_now(), 5, :minute)
        Process.send_after(self(), {:time_out_lobby, current_id}, 5 * 60 * 1000)
        {:reply, {:new, current_id, timeout}, {new_lobbies, new_id}}

      lobby.starting_user == user || Enum.any?(lobby.players, &(&1 == user)) ->
        {:reply, {:already_joined, lobby.id}, state}

      true ->
        new_players = [user | lobby.players]
        new_spectators = lobby.spectators -- [user]
        new_lobby = %Lobby{lobby | players: new_players, spectators: new_spectators}
        new_lobbies = Map.put(lobbies, channel, new_lobby)
        {:reply, {:joined, lobby.id}, {new_lobbies, current_id}}
    end
  end

  @impl true
  def handle_call({:spectate, channel, user}, _from, {lobbies, current_id} = state) do
    lobby = lobbies[channel]

    cond do
      lobby == nil || lobby.starting_user == user ->
        {:reply, :cannot_spectate, state}

      Enum.any?(lobby.spectators, &(&1 == user)) ->
        {:reply, :already_spectating, state}

      true ->
        new_spectators = [user | lobby.spectators]
        new_players = lobby.players -- [user]
        new_lobby = %Lobby{lobby | spectators: new_spectators, players: new_players}
        new_lobbies = Map.put(lobbies, channel, new_lobby)
        {:reply, {:spectating, lobby.id}, {new_lobbies, current_id}}
    end
  end

  @impl true
  def handle_call({:close, channel, user}, _from, {lobbies, current_id} = state) do
    lobby = lobbies[channel]

    cond do
      lobby == nil || lobby.starting_user != user ->
        {:reply, :cannot_close, state}

      !FfcEx.Game.playercount_valid?(length(lobby.players)) ->
        {:reply, :player_count_invalid, state}

      true ->
        new_lobbies = Map.delete(lobbies, channel)
        game = GameRegistry.create_game(lobby)
        {:reply, {:closed, lobby, game}, {new_lobbies, current_id}}
    end
  end

  @impl true
  def handle_info({:time_out_lobby, id}, {lobbies, current_id} = state) do
    case lobbies |> Enum.find(fn {_, lobby} -> lobby.id == id end) do
      {channel, lobby} ->
        {^lobby, new_lobbies} = Map.pop(lobbies, channel)

        Task.start(fn ->
          Api.create_message(channel, "Lobby \##{lobby.id} timed out and has been disbanded.")
        end)

        {:noreply, {new_lobbies, current_id}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unknown message received by FfcEx.GameLobbies: #{inspect(msg)}")
    {:noreply, state}
  end
end

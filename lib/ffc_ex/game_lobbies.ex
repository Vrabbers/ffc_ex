defmodule FfcEx.Lobby do
  alias Nostrum.Struct.User

  @type id() :: non_neg_integer()
  @enforce_keys [:id, :starting_user]
  defstruct id: nil, starting_user: nil, players: [], spectators: [], house_rules: []

  @type t() :: %__MODULE__{
          id: id(),
          starting_user: User.id(),
          players: [User.id()],
          spectators: [User.id()],
          house_rules: [atom()]
        }
end

defmodule FfcEx.GameLobbies do
  use GenServer

  alias FfcEx.{GameRegistry, Lobby}
  alias Nostrum.{Api, Struct.Interaction, Struct.User}

  require Logger

  @opaque state() ::
            {%{required(Interaction.id()) => {Lobby.t(), Interaction.token()}},
             current_id :: Lobby.id()}

  ## Client side
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec create(Interaction.id(), Interaction.token(), User.id(), [atom()]) ::
          {:new, Lobby.id(), DateTime.t()}
  def create(id, token, user, house_rules) do
    GenServer.call(__MODULE__, {:create, id, token, user, house_rules})
  end

  @spec join(Interaction.id(), User.id()) ::
          {:joined, Lobby.id()}
          | {:already_joined, Lobby.id()}
          | :timeout
  def join(interaction_id, user) do
    GenServer.call(__MODULE__, {:join, interaction_id, user})
  end

  @spec spectate(Interaction.id(), User.id()) ::
          {:spectating, Lobby.id()} | :cannot_spectate | :already_spectating | :timeout
  def spectate(interaction_id, user) do
    GenServer.call(__MODULE__, {:spectate, interaction_id, user})
  end

  @spec start_game(Interaction.id(), User.id()) ::
          {:started, Lobby.t(), pid()} | :cannot_start | :player_count_invalid | :timeout
  def start_game(interaction_id, user) do
    GenServer.call(__MODULE__, {:start, interaction_id, user})
  end

  @spec leave(Interaction.id(), User.id()) ::
          {:left, Lobby.id()} | :cannot_leave | :not_in_game | :timeout
  def leave(interaction_id, user) do
    GenServer.call(__MODULE__, {:leave, interaction_id, user})
  end

  ## Server side
  @impl true
  @spec init([]) :: {:ok, state()}
  def init([]) do
    {:ok, {%{}, 1}}
  end

  defp lookup(lobbies, interaction_id) do
    case lobbies[interaction_id] do
      {lobby, token} -> {lobby, token}
      nil -> {nil, nil}
    end
  end

  @lobby_expire_time :timer.minutes(5)

  @impl true
  def handle_call({:create, int_id, int_token, user, house_rules}, _, {lobbies, current_id}) do
    lobby = %Lobby{
      id: current_id,
      starting_user: user,
      players: [user],
      house_rules: house_rules
    }

    lobbies = Map.put(lobbies, int_id, {lobby, int_token})
    new_id = current_id + 1
    timeout = DateTime.add(DateTime.utc_now(), @lobby_expire_time, :millisecond)
    Process.send_after(self(), {:time_out_lobby, current_id}, @lobby_expire_time)
    {:reply, {:new, current_id, timeout}, {lobbies, new_id}}
  end

  @impl true
  def handle_call({:join, int_id, user}, _from, {lobbies, current_id} = state) do
    {lobby, token} = lookup(lobbies, int_id)

    cond do
      lobby == nil ->
        {:reply, :timeout, state}

      lobby.starting_user == user or Enum.any?(lobby.players, &(&1 == user)) ->
        {:reply, {:already_joined, lobby.id}, state}

      true ->
        new_players = lobby.players ++ [user]
        new_spectators = lobby.spectators -- [user]
        new_lobby = {%Lobby{lobby | players: new_players, spectators: new_spectators}, token}
        new_lobbies = Map.put(lobbies, int_id, new_lobby)
        {:reply, {:joined, lobby.id}, {new_lobbies, current_id}}
    end
  end

  @impl true
  def handle_call({:spectate, int_id, user}, _from, {lobbies, current_id} = state) do
    {lobby, token} = lookup(lobbies, int_id)

    cond do
      lobby == nil ->
        {:reply, :timeout, state}

      lobby.starting_user == user ->
        {:reply, :cannot_spectate, state}

      Enum.any?(lobby.spectators, &(&1 == user)) ->
        {:reply, :already_spectating, state}

      true ->
        new_spectators = [user | lobby.spectators]
        new_players = lobby.players -- [user]
        new_lobby = {%Lobby{lobby | spectators: new_spectators, players: new_players}, token}
        new_lobbies = Map.put(lobbies, int_id, new_lobby)
        {:reply, {:spectating, lobby.id}, {new_lobbies, current_id}}
    end
  end

  @impl true
  def handle_call({:leave, int_id, user}, _from, {lobbies, current_id} = state) do
    {lobby, token} = lookup(lobbies, int_id)

    cond do
      lobby == nil ->
        {:reply, :timeout, state}

      lobby.starting_user == user ->
        {:reply, :cannot_leave, state}

      user not in lobby.players and user not in lobby.spectators ->
        {:reply, :not_in_game, state}

      true ->
        players = lobby.players -- [user]
        spectators = lobby.spectators -- [user]
        lobby = %Lobby{lobby | players: players, spectators: spectators}
        lobbies = Map.put(lobbies, int_id, {lobby, token})
        {:reply, {:left, lobby.id}, {lobbies, current_id}}
    end
  end

  @impl true
  def handle_call({:start, int_id, user}, _from, {lobbies, current_id} = state) do
    {lobby, _token} = lookup(lobbies, int_id)

    cond do
      lobby == nil ->
        {:reply, :timeout, state}

      lobby.starting_user != user ->
        {:reply, :cannot_start, state}

      !FfcEx.Game.playercount_valid?(length(lobby.players)) ->
        new_lobbies = Map.delete(lobbies, int_id)
        {:reply, :player_count_invalid, {new_lobbies, current_id}}

      true ->
        new_lobbies = Map.delete(lobbies, int_id)
        game = GameRegistry.create_game(lobby)
        {:reply, {:started, lobby, game}, {new_lobbies, current_id}}
    end
  end

  @impl true
  def handle_info({:time_out_lobby, id}, {lobbies, current_id} = state) do
    case lobbies |> Enum.find(fn {_, {lobby, _}} -> lobby.id == id end) do
      {int_id, {lobby, token}} ->
        {_lobby_token, new_lobbies} = Map.pop(lobbies, int_id)

        Task.Supervisor.start_child(FfcEx.TaskSupervisor, fn ->
          Api.create_followup_message!(
            token,
            %{content: "Lobby \##{lobby.id} timed out and has been disbanded."}
          )
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

defmodule FfcEx.GameRegistry do
  alias FfcEx.GameSupervisor
  alias FfcEx.GameLobbies.Lobby
  require Logger

  @spec create_game(Lobby.t()) :: pid()
  def create_game(lobby) do
    {:ok, pid} = GameSupervisor.start_child(lobby)
    pid
  end

  @spec get_game_responder(Lobby.id()) :: pid() | nil
  def get_game_responder(id) do
    with [{pid, nil}] <- Registry.lookup(__MODULE__, id) do
      pid
    else
      _ -> nil
    end
  end
end

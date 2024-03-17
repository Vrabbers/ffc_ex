defmodule FfcEx.GameSupervisor do
  use DynamicSupervisor

  alias FfcEx.GameResponder
  alias FfcEx.Lobby

  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec start_child(Lobby.t()) :: DynamicSupervisor.on_start_child()
  def start_child(lobby) do
    DynamicSupervisor.start_child(__MODULE__, {GameResponder, lobby})
  end

  @impl true
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end

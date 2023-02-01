defmodule FfcEx.GameRegistrySupervisor do
  use Supervisor

  def start_link([]) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    children = [
      FfcEx.GameSupervisor,
      FfcEx.GameRegistry
    ]

    # The registry and the supervisor are largely interdependent
    Supervisor.init(children, strategy: :one_for_all)
  end
end

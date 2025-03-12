defmodule FfcEx.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: FfcEx.TaskSupervisor},
      FfcEx.PlayerRouter,
      FfcEx.GameRegistrySupervisor,
      FfcEx.GameLobbies,
      FfcEx.DmCache,
      FfcEx.Interactions,
      FfcEx.BaseConsumer,
      FfcEx.ThumbnailCache,
      FfcEx.RateLimit
    ]

    opts = [strategy: :one_for_one, name: FfcEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule FfcEx.GameRegistrySupervisor do
  use Supervisor

  def start_link([]) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    children = [
      FfcEx.GameSupervisor,
      {Registry, keys: :unique, name: FfcEx.GameRegistry}
    ]

    # The registry and the supervisor are interdependent
    Supervisor.init(children, strategy: :one_for_all)
  end
end

defmodule FfcEx.RateLimit do
  use Hammer, backend: :atomic, algorithm: :fix_window
end

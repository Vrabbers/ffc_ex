defmodule FfcEx.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FfcEx.GameRegistrySupervisor,
      FfcEx.GameLobbies,
      FfcEx.BaseConsumer
    ]

    opts = [strategy: :one_for_one, name: FfcEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule FfcEx.Game.MessageQueue do
  alias FfcEx.DmCache
  alias Nostrum.Api

  use GenServer

  def start_link([]) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(nil) do
    {:ok, nil}
  end

  def tell(user_id, message) do
    GenServer.cast(__MODULE__, {:tell, user_id, message})
  end

  def broadcast_to(users, message) do
    GenServer.cast(__MODULE__, {:broadcast_to, users, message})
  end

  @impl true
  def handle_cast({:tell, uid, msg}, _) do
    Task.await(do_tell(uid, msg))
    {:noreply, nil}
  end

  @impl true
  def handle_cast({:broadcast_to, uids, msg}, _) do
    Task.await_many(
      for user_id <- uids do
        do_tell(user_id, msg)
      end
    )

    {:noreply, nil}
  end

  defp do_tell(user_id, message) do
    Task.Supervisor.async(FfcEx.Game.MsgQueueTaskSupervisor, fn -> do_send_to(user_id, message) end)
  end

  defp do_send_to(user_id, message) do
    {:ok, channel} = DmCache.create(user_id)
    Api.create_message!(channel, message)
  end
end

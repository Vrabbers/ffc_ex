defmodule FfcEx.Broadcaster do
  alias FfcEx.DmCache
  alias Nostrum.Api

  def tell(user_id, message) do
    send_messages({:tell, user_id, message})
  end

  def broadcast_to(users, message) do
    send_messages({:broadcast_to, users, message})
  end

  def send_messages(messages) when is_list(messages) do
    Enum.each(messages, &send_messages/1)
  end

  def send_messages({:tell, uid, msg}) do
    Task.await(do_tell(uid, msg))
  end

  def send_messages({:broadcast_to, uids, msg}) do
    Task.await_many(
      for user_id <- uids do
        do_tell(user_id, msg)
      end
    )
  end

  defp do_tell(user_id, message) do
    Task.Supervisor.async(FfcEx.TaskSupervisor, fn -> do_send_to(user_id, message) end)
  end

  defp do_send_to(user_id, message) do
    {:ok, channel} = DmCache.create(user_id)
    Api.create_message!(channel, message)
  end
end

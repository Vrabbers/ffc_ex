defmodule FfcEx.Broadcaster do
  alias FfcEx.DmCache
  alias Nostrum.Api

  def tell(user_id, message) do
    send_messages({:tell, user_id, message}, :no_author)
  end

  def broadcast_to(users, message) do
    send_messages({:broadcast_to, users, message}, :no_author)
  end

  def send_messages(messages, author_id) when is_list(messages) do
    Enum.each(messages, &send_messages(&1, author_id))
  end

  def send_messages({:tell, uid, msg}, author_id) do
    Task.await(do_tell(uid, msg, author_id))
  end

  def send_messages({:broadcast_to, uids, msg}, _author_id) do
    Task.await_many(
      for user_id <- uids do
        do_tell(user_id, msg)
      end
    )
  end

  defp do_tell(user_id, message, author_id) do
    id =
      if user_id == :author do
        author_id
      else
        user_id
      end
    Task.Supervisor.async(FfcEx.TaskSupervisor, fn -> do_send_to(id, message) end)
  end

  defp do_tell(user_id, message) do
    Task.Supervisor.async(FfcEx.TaskSupervisor, fn -> do_send_to(user_id, message) end)
  end

  defp do_send_to(user_id, message) do
    {:ok, channel} = DmCache.create(user_id)
    Api.create_message!(channel, message)
  end
end

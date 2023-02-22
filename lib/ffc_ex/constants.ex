defmodule FfcEx.Constants do
  @constants %{
    chat_input: 1,
    pong: 1,
    application_command: 2,
    channel_message_with_source: 4
  }

  @spec const(atom()) :: term()
  def const(name) do
    @constants[name]
  end
end

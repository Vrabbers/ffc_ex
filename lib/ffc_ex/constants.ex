defmodule FfcEx.Constants do
  import Bitwise

  @application_command_types %{
    chat_input: 1
  }
  def application_command_type(name) do
    @application_command_types[name]
  end

  @application_command_option_types %{
    string: 3
  }
  def application_command_option_type(name) do
    @application_command_option_types[name]
  end

  @interaction_types %{
    application_command: 2,
    message_component: 3
  }
  def interaction_type(name) do
    @interaction_types[name]
  end

  @interaction_callback_types %{
    channel_message_with_source: 4
  }
  def interaction_callback_type(name) do
    @interaction_callback_types[name]
  end

  @message_flags %{
    ephemeral: 1 <<< 6
  }
  def message_flags(name) do
    @message_flags[name]
  end

  @component_types %{
    action_row: 1,
    button: 2
  }
  def component_type(name) do
    @component_types[name]
  end

  @button_styles %{
    primary: 1,
    secondary: 2,
    success: 3,
    danger: 4,
    link: 5
  }
  def button_style(name) do
    @button_styles[name]
  end
end

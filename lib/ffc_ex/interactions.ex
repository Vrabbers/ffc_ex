defmodule FfcEx.Interactions do
  Module.register_attribute(__MODULE__, :slash_command, accumulate: true)
  use GenServer

  alias Nostrum.Struct.Interaction
  alias Nostrum.Api

  import FfcEx.Constants
  require Logger

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def prepare_app_commands(), do: GenServer.call(__MODULE__, :prepare_app_commands)

  def handle(interaction), do: GenServer.call(__MODULE__, {:handle, interaction})

  @impl true
  def init([]) do
    {:ok, %{}}
  end

  @slash_command {:ping,
                  %{
                    name: "ping",
                    description: "Checks if bot is online and prints information.",
                    type: const(:chat_input)
                  }}
  def ping(interaction) do
    Api.create_interaction_response!(interaction, %{
      type: const(:channel_message_with_source),
      data: %{content: "pong"}
    })
  end

  @slash_commands Map.new(@slash_command)
  defp slash_commands(), do: @slash_commands

  @impl true
  def handle_call(:prepare_app_commands, _from, _state) do
    # Delete old commands
    dbg_guild = Application.fetch_env!(:ffc_ex, :debug_guild)

    {:ok, cmds_list} =
      case dbg_guild do
        nil -> prepare_global_app_cmds()
        _ -> prepare_guild_app_cmds(dbg_guild)
      end

    cmds =
      for %{name: name, id: id} <- cmds_list, into: %{} do
        {String.to_integer(id), String.to_existing_atom(name)}
      end

    {:reply, :ok, cmds}
  end

  @impl true
  def handle_call({:handle, %Interaction{type: 2} = interaction}, _from, cmds) do
    fun = cmds[interaction.data.id]

    if fun != nil do
      apply(__MODULE__, fun, [interaction])
      {:reply, :ok, cmds}
    else
      {:reply, :not_found, cmds}
    end
  end

  defp prepare_guild_app_cmds(dbg_gld_str) do
    {debug_guild, ""} = Integer.parse(String.trim(dbg_gld_str))

    Api.bulk_overwrite_guild_application_commands(debug_guild, Map.values(slash_commands()))
  end

  defp prepare_global_app_cmds() do
    Api.bulk_overwrite_global_application_commands(Map.values(slash_commands()))
  end
end

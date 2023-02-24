defmodule FfcEx.Interactions do
  Module.register_attribute(__MODULE__, :slash_command, accumulate: true)
  use GenServer

  alias FfcEx.GameLobbies
  alias Nostrum.Struct.User
  alias Nostrum.Struct.Embed
  alias Nostrum.Struct.Interaction
  alias Nostrum.Util
  alias Nostrum.Api

  import FfcEx.Constants
  require Logger

  defmodule Components do
    def base() do
      [
        %{
          type: component_type(:action_row),
          components: []
        }
      ]
    end

    def put_button([%{components: comps} = act_row], keyword) do
      comps =
        comps ++
          [
            %{
              type: component_type(:button),
              style: button_style(Keyword.fetch!(keyword, :style)),
              label: Keyword.fetch!(keyword, :label),
              custom_id: Keyword.fetch!(keyword, :id)
            }
          ]

      [Map.put(act_row, :components, comps)]
    end
  end

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec prepare_app_commands() :: :ok
  def prepare_app_commands(), do: GenServer.call(__MODULE__, :prepare_app_commands)

  @spec handle(Interaction.t()) :: {:ok, fun()} | {:error, term()}
  def handle(interaction), do: GenServer.call(__MODULE__, {:handle, interaction})

  @impl true
  def init([]) do
    {:ok, %{}}
  end

  @slash_command {:ping,
                  %{
                    name: "ping",
                    description: "Check if FFC is online",
                    type: application_command_type(:chat_input)
                  }}
  def ping(interaction) do
    latencies = Util.get_all_shard_latencies() |> Map.values()
    heartbeat = Enum.sum(latencies) / length(latencies)

    embed = %Embed{
      title: "FFCex v#{Keyword.fetch!(Application.spec(:ffc_ex), :vsn)}",
      description: """
      **Heartbeat:** #{heartbeat}ms
      **Erlang/OTP release:** #{System.otp_release()}
      **Elixir version:** #{System.version()}
      **Memory usage:** #{(:erlang.memory(:total) / 1_000_000) |> :erlang.float_to_binary(decimals: 2)}MB
      **Operating system:** #{os_str()}
      """,
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      color: Application.fetch_env!(:ffc_ex, :color),
      thumbnail: %Embed.Thumbnail{url: User.avatar_url(Api.get_current_user!(), "png")}
    }

    Api.create_interaction_response!(interaction, %{
      type: interaction_callback_type(:channel_message_with_source),
      data: %{embeds: [embed]}
    })
  end

  @slash_command {:help,
                  %{
                    name: "help",
                    description: "Output commands as well as a link to game instructions",
                    type: application_command_type(:chat_input)
                  }}
  def help(interaction) do
    cmds =
      slash_commands()
      |> Map.values()
      |> Enum.map_join("\n", fn cmd -> "`/#{cmd.name}` - #{cmd.description}" end)

    embed = %Embed{
      title: "ℹ️ FFCex Help",
      description:
        cmds <>
          "\n[*Click here to view the game manual.*](https://vrabbers.github.io/ffc_ex/index.html)",
      color: Application.fetch_env!(:ffc_ex, :color)
    }

    Api.create_interaction_response(interaction, %{
      type: interaction_callback_type(:channel_message_with_source),
      data: %{embeds: [embed], flags: message_flags(:ephemeral)}
    })
  end

  @slash_command {:create,
                  %{
                    name: "create",
                    description: "Creates and new game lobby.",
                    options: [
                      %{
                        name: "house_rules",
                        type: application_command_option_type(:string),
                        description: "House rule characters"
                      }
                    ]
                  }}
  def create(interaction) do
    house_rules =
      case interaction.data.options do
        nil ->
          []

        [%{name: "house_rules", value: x}] ->
          x
          |> String.to_charlist()
          |> Enum.map(&house_rules/1)
          |> Enum.filter(&(&1 != nil))
          |> Enum.uniq()
      end

    house_rules_str =
      if house_rules == [] do
        "none"
      else
        Enum.map_join(house_rules, ", ", &Atom.to_string/1)
      end

    {:new, id, timeout} = GameLobbies.join(interaction.id, interaction.user.id, house_rules)
    embed = %Embed{
      title: "Final Fantastic Card",
      description: """
      <@#{interaction.user.id}> has started game \##{id}!
      **House rules:** #{house_rules_str}
      *The lobby will timeout <t:#{DateTime.to_unix(timeout)}:R>.*
      """,
      timestamp: DateTime.to_iso8601(DateTime.utc_now()),
      color: Application.fetch_env!(:ffc_ex, :color),
      thumbnail: %Embed.Thumbnail{url: User.avatar_url(Api.get_current_user!(), "png")}

    }

    Api.create_interaction_response!(interaction, %{
      type: interaction_callback_type(:channel_message_with_source),
      data: %{
        embeds: [embed],
        components:
          Components.base()
          |> Components.put_button(id: "join", label: "Join \##{id}", style: :primary)
          |> Components.put_button(id: "spectate", label: "Spectate \##{id}", style: :secondary)
          |> Components.put_button(id: "leave", label: "Leave \##{id}", style: :danger)
          |> Components.put_button(id: "start", label: "Start \##{id}", style: :success)
      }
    })
  end

  defp house_rules(char) do
    case char do
      ?c -> :cumulative_draw
      _ -> nil
    end
  end

  @impl true
  # Handles slash commands
  def handle_call({:handle, %Interaction{type: 2} = interaction}, _from, cmds) do
    fun = cmds[interaction.data.id]

    if fun != nil do
      {:reply, {:ok, fn -> apply(__MODULE__, fun, [interaction]) end}, cmds}
    else
      {:reply, {:error, :not_found}, cmds}
    end
  end

  @impl true
  def handle_call({:handle, interaction}, _from, cmds) do
    IO.inspect(interaction)
    {:reply, {:ok, fn -> nil end}, cmds}
  end

  @impl true
  def handle_call(:prepare_app_commands, _from, _state) do
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

    Logger.info("Registered slash commands.")
    {:reply, :ok, cmds}
  end

  @slash_commands Map.new(@slash_command)
  defp slash_commands(), do: @slash_commands

  defp prepare_guild_app_cmds(dbg_gld_str) do
    {debug_guild, ""} = Integer.parse(String.trim(dbg_gld_str))
    Api.bulk_overwrite_guild_application_commands(debug_guild, Map.values(slash_commands()))
  end

  defp prepare_global_app_cmds() do
    Api.bulk_overwrite_global_application_commands(Map.values(slash_commands()))
  end

  defp os_str() do
    type =
      case :os.type() do
        {:win32, _} -> "Windows"
        {:unix, os_type} -> os_type |> Atom.to_string() |> String.capitalize()
      end

    version =
      case :os.version() do
        {major, minor, release} -> "#{major}.#{minor}.#{release}"
        str -> str
      end

    "#{type} v#{version}"
  end
end

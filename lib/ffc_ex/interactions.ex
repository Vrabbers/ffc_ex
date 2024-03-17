defmodule FfcEx.Interactions do
  Module.register_attribute(__MODULE__, :slash_command, accumulate: true)
  use GenServer

  alias FfcEx.Format
  alias FfcEx.Util
  alias FfcEx.Broadcaster
  alias FfcEx.GameLobbies
  alias Nostrum.{Api, Struct.Embed, Struct.Interaction, Struct.User, Util}

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
                    description: "Create a new FFC game lobby.",
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

    {:new, id, timeout} =
      GameLobbies.create(interaction.id, interaction.token, interaction.user.id, house_rules)

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
          |> Components.put_button(id: "start", label: "Close and start \##{id}", style: :success)
      }
    })
  end

  defp handle_component("join", orig_int, interaction) do
    result = GameLobbies.join(orig_int.id, interaction.user.id)

    {msg, flags} =
      case result do
        :timeout ->
          {"Lobby no longer exists: it may have closed or timed out.", message_flags(:ephemeral)}

        {:joined, id} ->
          {"**#{Format.uname(interaction.user)}** has joined game \##{id}!", 0}

        {:already_joined, id} ->
          {"You have already joined \##{id}.", message_flags(:ephemeral)}
      end

    Api.create_interaction_response!(interaction, %{
      type: interaction_callback_type(:channel_message_with_source),
      data: %{content: msg, flags: flags}
    })
  end

  defp handle_component("spectate", orig_int, interaction) do
    result = GameLobbies.spectate(orig_int.id, interaction.user.id)

    {msg, flags} =
      case result do
        :timeout ->
          {"Lobby no longer exists: it may have closed or timed out.", message_flags(:ephemeral)}

        :cannot_spectate ->
          {"As you created this game, you cannot spectate this game.", message_flags(:ephemeral)}

        {:spectating, id} ->
          {"**#{Format.uname(interaction.user)}** is spectating game \##{id}!", 0}

        :already_spectating ->
          {"You are already spectating this game.", message_flags(:ephemeral)}
      end

    Api.create_interaction_response!(interaction, %{
      type: interaction_callback_type(:channel_message_with_source),
      data: %{content: msg, flags: flags}
    })
  end

  defp handle_component("leave", orig_int, interaction) do
    result = GameLobbies.leave(orig_int.id, interaction.user.id)

    {msg, flags} =
      case result do
        :timeout ->
          {"Lobby no longer exists: it may have closed or timed out.", message_flags(:ephemeral)}

        :cannot_leave ->
          {"As you created this game, you cannot leave this game.", message_flags(:ephemeral)}

        {:left, id} ->
          {"**#{Format.uname(interaction.user)}** has left game \##{id}.", 0}

        :not_in_game ->
          {"You are not in this game.", message_flags(:ephemeral)}
      end

    Api.create_interaction_response!(interaction, %{
      type: interaction_callback_type(:channel_message_with_source),
      data: %{content: msg, flags: flags}
    })
  end

  defp handle_component("start", orig_int, interaction) do
    result = GameLobbies.start_game(orig_int.id, interaction.user.id)

    {msg, flags} =
      case result do
        :timeout ->
          {"Lobby no longer exists: it may have closed or timed out.", message_flags(:ephemeral)}

        :cannot_start ->
          {"Only the person who created the game can start it.", message_flags(:ephemeral)}

        {:started, lobby, game} ->
          {start_game(lobby, game), 0}

        :player_count_invalid ->
          {"The game was not able to start because the amount of players was invalid.", 0}
      end

    Api.create_interaction_response!(interaction, %{
      type: interaction_callback_type(:channel_message_with_source),
      data: %{content: msg, flags: flags}
    })
  end

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec prepare_app_commands() :: :ok
  def prepare_app_commands(), do: GenServer.call(__MODULE__, :prepare_app_commands)

  @spec handle(Interaction.t()) :: :ok | {:error, term()}
  def handle(interaction) do
    case GenServer.call(__MODULE__, {:handle, interaction}) do
      {:slash_command, fun} ->
        apply(__MODULE__, fun, [interaction])
        :ok

      {:handle_component, custom_id} ->
        handle_component(custom_id, interaction.message.interaction, interaction)
        :ok

      {:error, t} ->
        {:error, t}
    end
  end

  @impl true
  def init([]) do
    Process.flag(:trap_exit, true)
    {:ok, %{}}
  end

  @impl true
  # Handles slash commands
  def handle_call({:handle, %Interaction{type: 2} = interaction}, _from, cmds) do
    fun = cmds[interaction.data.id]

    if fun != nil do
      {:reply, {:slash_command, fun}, cmds}
    else
      {:reply, {:error, :not_found}, cmds}
    end
  end

  # Component responses
  def handle_call({:handle, %Interaction{type: 3} = interaction}, _from, cmds) do
    custom_id = interaction.data.custom_id
    {:reply, {:handle_component, custom_id}, cmds}
  end

  @impl true
  def handle_call({:handle, _interaction}, _from, cmds) do
    {:reply, {:error, :unknown_interaction}, cmds}
  end

  @impl true
  def handle_call(:prepare_app_commands, _from, _state) do
    {:ok, cmds_list} =
      case global_or_guild_cmds() do
        :global -> prepare_global_app_cmds()
        {:guild, guild} -> prepare_guild_app_cmds(guild)
      end

    cmds =
      for %{name: name, id: id} <- cmds_list, into: %{} do
        {String.to_integer(id), String.to_existing_atom(name)}
      end

    {:reply, :ok, cmds}
  end

  @impl true
  def terminate(reason, _state) do
    if reason == :shutdown or match?({:shutdown, _r}, reason) do
      case global_or_guild_cmds() do
        :global ->
          :noop

        {:guild, guild} ->
          Logger.info("Deregistering interactions for guild #{guild}...")
          {:ok, _} = Api.bulk_overwrite_guild_application_commands(guild, [])
      end
    end
  end

  @slash_commands Map.new(@slash_command)
  defp slash_commands(), do: @slash_commands

  defp start_game(lobby, game) do
    case FfcEx.GameResponder.start_game(game) do
      {:ok, response} ->
        Broadcaster.send_messages(response)
        "**Lobby \##{lobby.id}** was closed and the game is starting."

      {:cannot_dm, users} ->
        """
        Game \##{lobby.id} did not start because I couldn't DM these players:
        #{Enum.map_join(users, " ", &"<@#{&1}>")}
        Please change your privacy settings so I can send you direct messages.
        """
    end
  end

  defp house_rules(char) do
    case char do
      ?c -> :cumulative_draw
      _ -> nil
    end
  end

  defp global_or_guild_cmds() do
    dbg_guild = Application.fetch_env!(:ffc_ex, :debug_guild)

    case dbg_guild do
      nil -> :global
      x -> {:guild, x |> String.trim() |> String.to_integer()}
    end
  end

  defp prepare_guild_app_cmds(debug_guild) do
    Logger.info("Registering slash commands for guild #{debug_guild}")
    Api.bulk_overwrite_global_application_commands([])
    Api.bulk_overwrite_guild_application_commands(debug_guild, Map.values(slash_commands()))
  end

  defp prepare_global_app_cmds() do
    Logger.info("Registered slash commands globally")
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

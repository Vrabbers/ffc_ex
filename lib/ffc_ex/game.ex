defmodule FfcEx.Game do
  # Doesn't make much sense to try restarting a crashed game
  use GenServer, restart: :temporary
  alias Nostrum.Struct.Embed
  alias Nostrum.Struct.Embed.Thumbnail
  alias FfcEx.DmCache
  alias Nostrum.Api
  alias FfcEx.Lobby
  alias FfcEx.Game
  alias Nostrum.Struct.User
  require Logger

  @enforce_keys [:id, :players, :spectators]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{
          id: Lobby.id(),
          players: [User.id()],
          spectators: [User.id()]
        }

  @spec playercount_valid?(non_neg_integer()) :: boolean()
  def playercount_valid?(count) do
    count >= 2 && count <= 10
  end

  @spec start_game(pid()) :: :ok | {:cannot_dm, [User.id()]}
  def start_game(game) do
    GenServer.call(game, :start_game, :infinity)
  end

  def start_link(lobby) do
    GenServer.start_link(__MODULE__, lobby)
  end

  @impl true
  def init(lobby) do
    game = %Game{
      id: lobby.id,
      players: lobby.players,
      spectators: lobby.spectators
    }

    {:ok, game}
  end

  @impl true
  def handle_call(:start_game, _from, game) do
    responses =
      for user <- participants(game) do
        {:ok, dm_channel} = DmCache.create(user)
        {Api.create_message(dm_channel, "Starting game \##{game.id}..."), user}
      end

    if Enum.all?(responses, fn {{resp, _}, _} -> resp == :ok end) do
      embed =
        %Embed{
          title: "Final Fantastic Card",
          description: """
          Welcome to Final Fanstastic Card!
          """,
          color: Application.fetch_env!(:ffc_ex, :color),
          thumbnail: %Thumbnail{url: "attachment://draw.png"}
        }
        |> put_id_footer(game)

      broadcast(game, embeds: [embed], files: ["./img/draw.png"])
      {:reply, :ok, game}
    else
      {:stop, :error, {:cannot_dm, for({{:error, _}, user} <- responses, do: user)}, game}
    end
  end

  @spec participants(Game.t()) :: [User.id()]
  defp participants(game) do
    game.players ++ game.spectators
  end

  defp broadcast(game, message) do
    broadcast_to(participants(game), message)
  end

  defp broadcast_to(users, message) do
    for user <- users do
      tell(user, message)
    end

    :ok
  end

  defp tell(user, message) do
    {:ok, dm_channel} = DmCache.create(user)

    Task.start(fn ->
      case Api.create_message(dm_channel, message) do
        {:error, error} ->
          Logger.error(
            "Error telling #{inspect(user)} message: #{inspect(message)}: #{inspect(error)}"
          )

        {:ok, _} ->
          :noop
      end
    end)
  end

  defp put_id_footer(embed, game) do
    Embed.put_footer(embed, "Game \##{game.id}")
  end
end

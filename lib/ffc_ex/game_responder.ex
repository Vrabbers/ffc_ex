defmodule FfcEx.GameResponder do
  alias FfcEx.PrivDir
  alias FfcEx.Broadcaster
  alias FfcEx.Format
  alias Nostrum.Struct.Embed.Field
  alias Nostrum.Struct.User
  alias Nostrum.Api
  alias Nostrum.Struct.Embed.Thumbnail
  alias FfcEx.PlayerRouter
  alias Nostrum.Struct.Embed
  alias FfcEx.Game
  alias FfcEx.Game.Card

  use GenServer, restart: :temporary

  require Logger

  def start_game(pid) do
    GenServer.call(pid, :start_game, :infinity)
  end

  def command(pid, uid, command) do
    GenServer.call(pid, {:cmd, uid, command})
  end

  def part_of?(pid, uid) do
    GenServer.call(pid, {:part_of?, uid})
  end

  def start_link(lobby) do
    GenServer.start_link(__MODULE__, lobby,
      name: {:via, Registry, {FfcEx.GameRegistry, lobby.id}}
    )
  end

  @impl true
  def init(lobby) do
    Process.flag(:trap_exit, true)
    {:ok, game} = Game.start_link(lobby)
    {:ok, %{players: lobby.players, spectators: lobby.spectators, game: game, id: lobby.id}}
  end

  @impl true
  def terminate(reason, responder) do
    if reason != :normal do
      Task.Supervisor.start_child(FfcEx.TaskSupervisor, fn ->
        Broadcaster.broadcast_to(
          participants(responder),
          """
          🔴 Unfortunately, game \##{responder.id} has closed due to an error. \
          Use `/create` to start a new game.
          """
        )
      end)
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, responder) do
    if pid == responder.game do
      Logger.debug("Game \##{responder.id} exited for: #{inspect(reason)}. Responder exiting")
    end

    {:stop, reason, responder}
  end

  @impl true
  def handle_call(:start_game, _from, responder) do
    responses =
      for user <- participants(responder) do
        {:ok, dm_channel} = FfcEx.DmCache.create(user)
        {Nostrum.Api.create_message(dm_channel, "Starting game \##{responder.id}..."), user}
      end

    if Enum.all?(responses, fn {{resp, _}, _} -> resp == :ok end) do
      PlayerRouter.add_all_to(participants(responder), responder.id)
      {:reply, {:ok, respond(Game.start_game(responder.game), responder)}, responder}
    else
      Process.exit(responder.game, :kill)
      {:stop, :normal, {:cannot_dm, for({{:error, _}, user} <- responses, do: user)}, responder}
    end
  end

  @impl true
  def handle_call({:cmd, uid, :hand}, _from, responder) do
    if uid in responder.players do
      current_card = Game.current_card(responder.game)
      hand = Game.hand(responder.game, uid)

      embed =
        %Embed{
          title: "Your hand",
          description: formatted_hand(hand, current_card)
        }
        |> footer_color(responder)

      {:reply, tell(uid, embeds: [embed]), responder}
    else
      {:reply, tell(uid, "You don't have a hand!"), responder}
    end
  end

  @impl true
  def handle_call({:cmd, uid, {:chat, message}}, _from, responder) do
    str =
      if uid in responder.players do
        "*\##{responder.id}* **#{Format.uname(uid)}:** #{message}"
      else
        "*\##{responder.id} Spectator #{Format.uname(uid)}:* #{message}"
      end

    {:reply, {:send_chat_message, broadcast_except(responder, [uid], str)}, responder}
  end

  @impl true
  def handle_call({:cmd, uid, :status}, _from, responder) do
    {[current | others], card} = Game.status(responder.game)

    field_text =
      "**#{format_player_cards(current)}\n**" <>
        (others |> Enum.map_join("\n", &format_player_cards/1))

    embed =
      %Embed{
        title: "Game status",
        fields: [
          %Field{name: "Current card", value: Card.to_string(card)},
          %Field{name: "Players", value: field_text <> "\n*Play continues downwards*"}
        ],
        color: Application.fetch_env!(:ffc_ex, :color)
      }
      |> footer_color(responder)

    {:reply, tell(uid, embeds: [embed]), responder}
  end

  @impl true
  def handle_call({:cmd, uid, {:play, card_str}}, _from, responder) do
    case Card.parse(card_str) do
      :error ->
        {:reply, tell(uid, "Invalid card."), responder}

      {:ok, {_, nil}} ->
        {:reply, tell(uid, "Please specify a wildcard color!"), responder}

      {:ok, card} ->
        resp = GenServer.call(responder.game, {uid, {:play, card}})

        if is_list(resp) and Enum.any?(resp, fn r -> match?({:end, {:win, _}}, r) end) do
          # Victory!
          {:stop, :normal, respond(resp, responder), responder}
        else
          {:reply, respond(resp, responder), responder}
        end
    end
  end

  @impl true
  def handle_call({:cmd, uid, command}, _from, responder) do
    resp = GenServer.call(responder.game, {uid, command})
    {:reply, respond(resp, responder), responder}
  end

  @impl true
  def handle_call({:part_of?, uid}, _from, responder) do
    {:reply, uid in participants(responder), responder}
  end

  defp respond(terms, responder) when is_list(terms) do
    terms |> Enum.reverse() |> Enum.map(&respond(&1, responder))
  end

  defp respond(:welcome, responder) do
    embed =
      %Embed{
        title: "Final Fantastic Card",
        description: """
        Welcome to Final Fantastic Card!

        [Click here to view game instructions!](https://vrabbers.github.io/ffc_ex/index.html)
        """,
        thumbnail: %Thumbnail{url: User.avatar_url(Api.get_current_user!(), "png")}
      }
      |> footer_color(responder)

    broadcast(responder, embeds: [embed])
  end

  defp respond({:normal_turn, turns_uid, turns_hand, card, conditions}, responder) do
    embed =
      %Embed{
        title: "Your turn!",
        fields: [
          %Field{name: "Current card", value: Card.to_string(card)}
        ]
      }
      |> footer_color(responder)
      |> put_cond_fields(conditions, turns_hand, card)

    [
      tell(turns_uid, embeds: [embed]),
      broadcast_except(
        responder,
        [turns_uid],
        "*##{responder.id} – #{Format.uname(turns_uid)}'s turn*"
      )
    ]
  end

  defp respond({:play_card, player, card}, responder) do
    broadcast(responder,
      embeds: [
        %Embed{
          title: "Card played!",
          description: "#{Format.uname(player)} has played a **#{Card.to_string(card)}**"
        }
        |> footer_color(responder)
      ]
    )
  end

  defp respond({:drew_card, card, player, can_play}, responder) do
    personal_message =
      case can_play do
        :can_play_drawn ->
          "Use `play #{Card.to_string(card)}` to play this card now or use `pass`."

        :cant_play_drawn ->
          "Since you can't play this card, use `pass`."
      end

    author_message =
      tell(player,
        embeds: [
          %Embed{
            title: "Card drawn",
            description: "You have drawn **#{Card.to_string(card)}**.\n" <> personal_message,
            thumbnail: %Thumbnail{url: "attachment://draw.png"}
          }
          |> footer_color(responder)
        ],
        files: [PrivDir.file("draw.png")]
      )

    everyone_message =
      broadcast_except(responder, [player],
        embeds: [
          %Embed{
            title: "Card drawn",
            description: "#{Format.uname(player)} has drawn a card from the deck.",
            thumbnail: %Thumbnail{url: "attachment://draw.png"}
          }
          |> footer_color(responder)
        ],
        files: [PrivDir.file("draw.png")]
      )

    [author_message, everyone_message]
  end

  defp respond(term, responder) do
    Logger.warning("Unknown term #{inspect(term)} in game #{responder.id} to respond to.")
    broadcast(responder, "#{responder.id}: #{inspect(term)}")
  end

  defp put_cond_fields(embed, conditions, hand, current_card) do
    conditions
    |> Enum.reduce(embed, fn cnd, embed ->
      case cnd do
        :must_draw ->
          Embed.put_field(
            embed,
            "Draw",
            "You can't play any of your cards. Use `draw` to draw one."
          )

        {:forgot_ffc, who} ->
          Embed.put_field(
            embed,
            "Forgot FFC",
            "#{Format.uname(who)} forgot to call FFC. Use `!` to challenge them!"
          )

        _ ->
          embed
      end
    end)
    |> Embed.put_field(
      "Your hand",
      formatted_hand(hand, current_card)
    )
  end

  defp formatted_hand(hand, current_card) do
    hand
    |> Enum.map(fn card -> {Card.to_string(card), Card.can_play_on?(current_card, card)} end)
    |> Enum.sort_by(fn {card, _} -> card end, :asc)
    |> Enum.map_join(
      " ",
      fn
        {card, true} -> "**__#{card}__**"
        {card, false} -> card
      end
    )
  end

  defp format_player_cards({player, card_amt}) do
    card_plural = if card_amt == 1, do: "card", else: "cards"
    "#{Format.uname(player)} – #{card_amt} #{card_plural}"
  end

  defp participants(responder) do
    responder.players ++ responder.spectators
  end

  defp broadcast(responder, message) do
    broadcast_to(participants(responder), message)
  end

  defp broadcast_except(responder, except_users, message) do
    broadcast_to(participants(responder) -- except_users, message)
  end

  defp broadcast_to(users, message) do
    {:broadcast_to, users, message}
  end

  defp tell(user, message) do
    {:tell, user, message}
  end

  defp footer_color(embed, responder) do
    embed = Embed.put_footer(embed, "Game \##{responder.id}")

    if embed.color == nil do
      Embed.put_color(embed, Application.fetch_env!(:ffc_ex, :color))
    else
      embed
    end
  end
end

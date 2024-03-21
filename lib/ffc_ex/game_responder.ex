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
    game = Game.init(lobby)
    {:ok, %{spectators: lobby.spectators, game: game, id: lobby.id}}
  end

  @impl true
  def terminate(reason, responder) do
    # Although :shutdown and {:shutdown, _} are also 'normal' reasons, they indicate that this
    # decision to end the process did not arrive from myself, so we still inform the participants
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
  def handle_call(:start_game, _from, responder) do
    responses =
      for user <- participants(responder) do
        {:ok, dm_channel} = FfcEx.DmCache.create(user)
        {Nostrum.Api.create_message(dm_channel, "Starting game \##{responder.id}..."), user}
      end

    if Enum.all?(responses, fn {{resp, _}, _} -> resp == :ok end) do
      PlayerRouter.add_all_to(participants(responder), responder.id)
      {resp, game} = Game.start_game(responder.game)
      responder = %{responder | game: game}
      {:reply, {:ok, respond(resp, responder)}, responder}
    else
      {:stop, :cannot_dm, {:cannot_dm, for({{:error, _}, user} <- responses, do: user)},
       responder}
    end
  end

  @impl true
  def handle_call({:cmd, uid, {:chat, message}}, _from, responder) do
    str =
      if uid in responder.game.players do
        "*\##{responder.id}* **#{Format.uname(uid)}:** #{message}"
      else
        "*\##{responder.id} Spectator #{Format.uname(uid)}:* #{message}"
      end

    {:reply, {:green_check, broadcast_except(responder, [uid], str)}, responder}
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
  def handle_call({:cmd, uid, :hand}, _from, responder) do
    if uid in responder.game.players do
      current_card = responder.game.current_card
      hand = responder.game.hand[uid]

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
  def handle_call({:cmd, uid, {:play, card_str}}, _from, responder) do
    if uid in responder.game.players do
      case Card.parse(card_str) do
        :error ->
          {:reply, tell(uid, "Invalid card."), responder}

        {:ok, {_, nil}} ->
          {:reply, tell(uid, "Please specify a wildcard color!"), responder}

        {:ok, card} ->
          do_play_card(responder, uid, card)
      end
    else
      {:reply, tell(uid, "You are not playing in this game."), responder}
    end
  end

  @impl true
  def handle_call({:cmd, uid, :nudge}, _from, responder) do
    [current_player | _] = responder.game.players

    if current_player == uid do
      {:reply, tell(uid, "It's your turn right now! Go nudge yourself!"), responder}
    else
      response =
        tell(
          current_player,
          """
          #{Format.uname(uid)} wished to remind you it's your turn to play by giving you a gentle \
          nudge. *Nudge!*
          """
        )

      {:reply, {:green_check, response}, responder}
    end
  end

  @impl true
  def handle_call({:cmd, uid, :help}, _from, responder) do
    embed =
      %Embed{
        title: "Help",
        description:
          "[Click here to view game instructions!](https://vrabbers.github.io/ffc_ex/index.html)"
      }
      |> footer_color(responder)

    {:reply, tell(uid, embeds: embed), responder}
  end

  @impl true
  def handle_call({:cmd, uid, :drop}, _from, responder) do
    if uid in responder.game.players do
      do_drop_player(responder, uid)
    else
      {:reply, tell(uid, "You have stopped spectating the game."),
       %{responder | spectators: responder.spectators -- [uid]}}
    end
  end

  @impl true
  def handle_call({:cmd, uid, :spectate}, _from, responder) do
    if uid in responder.game.players do
      responder = %{responder | spectators: [uid | responder.spectators]}
      do_drop_player(responder, uid)
    else
      {:reply, tell(uid, "You are already spectating the game."), responder}
    end
  end

  @impl true
  def handle_call({:cmd, uid, :draw}, _from, responder) do
    do_player_command(responder, uid, &Game.draw/2)
  end

  @impl true
  def handle_call({:cmd, uid, :pass}, _from, responder) do
    do_player_command(responder, uid, &Game.pass/2)
  end

  @impl true
  def handle_call({:cmd, uid, :challenge}, _from, responder) do
    do_player_command(responder, uid, &Game.challenge/2)
  end

  @impl true
  def handle_call({:cmd, uid, :ffc}, _from, responder) do
    do_player_command(responder, uid, &Game.call_ffc/2)
  end

  @impl true
  def handle_call({:part_of?, uid}, _from, responder) do
    {:reply, uid in participants(responder), responder}
  end

  defp do_player_command(responder, uid, fun) do
    if uid in responder.game.players do
      {resp, game} = fun.(responder.game, uid)
      responder = %{responder | game: game}
      {:reply, respond(resp, responder), responder}
    else
      {:reply, tell(uid, "You are not playing in this game."), responder}
    end
  end

  defp do_play_card(responder, uid, card) do
    {resp, game} = Game.play(responder.game, uid, card)
    responder = %{responder | game: game}

    if is_list(resp) and Enum.any?(resp, fn r -> match?({:end, _}, r) end) do
      # Victory!
      {:stop, :normal, respond(resp, responder), responder}
    else
      {:reply, respond(resp, responder), responder}
    end
  end

  defp do_drop_player(responder, uid) do
    {resp, game} = Game.drop_player(responder.game, uid)
    responder = %{responder | game: game}

    if is_list(resp) and Enum.any?(resp, fn r -> match?({:end, _}, r) end) do
      # Stop game, not enough players.
      {:stop, :normal, respond(resp, responder), responder}
    else
      {:reply, respond(resp, responder), responder}
    end
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

  defp respond({:normal_turn, uid, hand, card, conditions}, responder) do
    embed =
      %Embed{
        title: "Your turn!",
        fields: [
          %Field{name: "Current card", value: Card.to_string(card)}
        ]
      }
      |> footer_color(responder)
      |> put_cond_fields(conditions, hand, card)

    [
      tell(uid, embeds: [embed]),
      global_turn_msg(responder, uid)
    ]
  end

  defp respond({{:wild4_challenge_turn, challenged}, uid, _hand, _card, _cond}, responder) do
    embed =
      %Embed{
        title: "Wild Draw 4 challenge",
        description: """
        #{Format.uname(challenged)} has played a Wild Draw 4. If you think it was played \
        illegally, use `!` to challenge their decision. Use `draw` to accept and draw 4 cards.
        *If you lose the challenge, you draw 6 cards. If you win, they draw 4 cards.*
        """
      }
      |> footer_color(responder)

    [
      tell(uid, embeds: [embed]),
      global_turn_msg(responder, uid)
    ]
  end

  defp respond({{:cml_draw_turn, cml_draw}, uid, hand, card, conditions}, responder) do
    draw2_cards =
      hand
      |> Enum.filter(fn {_, el} -> el == :draw2 end)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map_join(", ", &"`play #{Card.to_string(&1)}`")

    desc =
      if draw2_cards == "" do
        """
        Because you have no Draw 2 cards, you have to draw the #{cml_draw} \
        accumulated cards with `draw`.
        """
      else
        """
        This turn, you must play a Draw 2 card with #{draw2_cards} or draw the \
        #{cml_draw} accumulated cards with `draw`
        """
      end

    embed =
      %Embed{
        title: "Your turn!",
        description: desc
      }
      |> footer_color(responder)
      |> put_cond_fields(conditions, hand, card)

    [
      tell(uid, embeds: [embed]),
      global_turn_msg(responder, uid)
    ]
  end

  defp respond({:play_card, player, card}, responder) do
    broadcast(responder,
      embeds: [
        %Embed{
          title: "Card played!",
          description: "#{Format.uname(player)} has played **#{Card.to_string(card)}**"
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

  defp respond({:skip, uid}, responder) do
    broadcast(responder,
      embeds: [
        %Embed{
          title: "Turn skipped!",
          description: "#{Format.uname(uid)}'s turn has been skipped!",
          thumbnail: %Thumbnail{url: "attachment://skip.png"}
        }
        |> footer_color(responder)
      ],
      files: [PrivDir.file("skip.png")]
    )
  end

  defp respond(:play_reversed, responder) do
    broadcast(responder,
      embeds: [
        %Embed{
          title: "Play reversed!",
          description: "The direction of play has been reversed.",
          thumbnail: %Thumbnail{url: "attachment://reverse.png"}
        }
        |> footer_color(responder)
      ],
      files: [PrivDir.file("reverse.png")]
    )
  end

  defp respond({:color_changed, color}, responder) do
    broadcast(responder,
      embeds: [
        %Embed{
          title: "Color changed!",
          description: "The color has changed to **#{color}**.",
          thumbnail: %Thumbnail{url: "attachment://#{color}.png"}
        }
        |> footer_color(responder)
      ],
      files: [PrivDir.file("#{color}.png")]
    )
  end

  defp respond({:force_draw, uid, amt}, responder) do
    file =
      case amt do
        2 -> "draw2.png"
        4 -> "draw4.png"
        6 -> "draw6.png"
        _ -> "draw.png"
      end

    broadcast(responder,
      embeds: [
        %Embed{
          title: "Drawn cards",
          description: "#{Format.uname(uid)} has been forced to draw #{amt} cards!",
          thumbnail: %Thumbnail{url: "attachment://#{file}"}
        }
        |> footer_color(responder)
      ],
      files: [PrivDir.file(file)]
    )
  end

  defp respond({:called_ffc, uid}, responder) do
    broadcast(responder,
      embeds: [
        %Embed{
          title: "FFC",
          description: "**#{Format.uname(uid)} has called FFC!**"
        }
        |> footer_color(responder)
      ]
    )
  end

  defp respond({:forgot_ffc_challenge, forgot, challenger}, responder) do
    broadcast(responder,
      embeds: [
        %Embed{
          title: "FFC challenged!",
          description:
            "#{Format.uname(forgot)} forgot to call FFC and #{Format.uname(challenger)} has challenged them!"
        }
        |> footer_color(responder)
      ]
    )
  end

  defp respond({:drop, uid}, responder) do
    broadcast(responder, "*\##{responder.id}* - #{Format.uname(uid)} has dropped from the game.")
  end

  defp respond({:end, {:win, uid}}, responder) do
    author_img_url = User.avatar_url(Api.get_user!(uid))

    broadcast(
      responder,
      embeds: [
        %Embed{
          title: "Victory!",
          description: "#{Format.uname(uid)} has won the game!",
          thumbnail: %Thumbnail{url: author_img_url}
        }
        |> footer_color(responder)
      ]
    )
  end

  defp respond({:wild4_challenge, challenged, challenger, won?}, responder) do
    broadcast(responder,
      embeds: [
        %Embed{
          title: "Wild Draw 4 challenge",
          description: """
          #{Format.uname(challenger)} has challenged the Wild Draw Four played \
          by #{Format.uname(challenged)}, and has #{if won?, do: "won", else: "lost"} \
          the challenge.
          """
        }
        |> footer_color(responder)
      ]
    )
  end

  defp respond({:end, :not_enough_players}, responder) do
    broadcast(
      responder,
      "Game \##{responder.id} has ended as there weren't enough players to continue."
    )
  end

  defp respond(:not_players_turn, _responder) do
    tell(:author, "You can't do this when it's not your turn!")
  end

  defp respond(:dont_have_card, _responder) do
    tell(:author, "You don't have that card.")
  end

  defp respond(:resolve_wild4_challenge, _responder) do
    tell(:author, "You must resolve the Wild Draw 4 challenge.")
  end

  defp respond(:must_play_drawn_card, _responder) do
    tell(:author, "You must play the card you have drawn!")
  end

  defp respond(:cannot_play_card, _responder) do
    tell(:author, "You can't play that card now. Cards you can play are marked in **bold**.")
  end

  defp respond(:cml_draw_must_draw, _responder) do
    tell(:author, "You must draw or play a Draw 2 card.")
  end

  defp respond(:cannot_ffc_challenge, _responder) do
    tell(:author, "There is nothing to challenge right now!")
  end

  defp respond(:cannot_pass, _responder) do
    tell(:author, "You can't pass if you haven't drawn a card from the deck first.")
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

  defp global_turn_msg(responder, uid) do
    broadcast_except(
      responder,
      [uid],
      "*##{responder.id} – #{Format.uname(uid)}'s turn*"
    )
  end

  defp format_player_cards({player, card_amt}) do
    card_plural = if card_amt == 1, do: "card", else: "cards"
    "#{Format.uname(player)} – #{card_amt} #{card_plural}"
  end

  defp participants(responder) do
    responder.game.players ++ responder.spectators
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

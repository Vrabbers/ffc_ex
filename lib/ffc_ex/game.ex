defmodule FfcEx.Game do
  # Doesn't make much sense to try restarting a crashed game
  use GenServer, restart: :temporary

  alias FfcEx.{DmCache, Game, Game.Card, Game.Deck, Lobby, PlayerRouter, PrivDir}
  alias Nostrum.Api
  alias Nostrum.Struct.{Embed, Embed.Field, Embed.Thumbnail, User}

  require Logger
  require Card

  @enforce_keys [
    :id,
    :players,
    :hands,
    :spectators,
    :deck,
    :current_card,
    :drawn_card,
    :called_ffc,
    :was_valid_wild4,
    :house_rules,
    :cml_draw
  ]
  defstruct @enforce_keys

  @opaque t() :: %__MODULE__{
            id: Lobby.id(),
            players: [User.id()],
            hands: %{required(User.id()) => {Deck.t()}},
            spectators: [User.id()],
            deck: Deck.t(),
            current_card: Card.t() | nil,
            drawn_card: Cart.t() | nil,
            called_ffc: {User.id(), boolean()} | nil,
            was_valid_wild4: {User.id(), boolean()} | nil,
            house_rules: [atom()],
            cml_draw: pos_integer() | nil
          }

  @spec playercount_valid?(non_neg_integer()) :: boolean()
  def playercount_valid?(count) do
    count in 2..10
  end

  @spec start_game(pid()) :: :ok | {:cannot_dm, [User.id()]}
  def start_game(game) do
    GenServer.call(game, :start_game, :infinity)
  end

  @spec part_of?(pid(), User.id()) :: boolean()
  def part_of?(game, user) do
    GenServer.call(game, {:is_part_of, user})
  end

  def do_cmd(game, user, cmd) do
    if part_of?(game, user) do
      GenServer.cast(game, {user, cmd})
      true
    else
      false
    end
  end

  def start_link(lobby) do
    GenServer.start_link(__MODULE__, lobby)
  end

  @impl true
  def init(lobby) do
    deck = Deck.new()
    {last, deck} = Deck.get_matching(deck, &Card.is_valid_first_card?/1)
    {groups, deck} = Deck.get_many_groups(deck, 7, length(lobby.players))
    hands = Enum.zip(lobby.players, groups) |> Map.new()

    game = %Game{
      id: lobby.id,
      players: lobby.players,
      hands: hands,
      spectators: lobby.spectators,
      deck: deck,
      current_card: last,
      drawn_card: nil,
      called_ffc: nil,
      was_valid_wild4: nil,
      house_rules: lobby.house_rules,
      cml_draw: nil
    }

    # Use this to tell participants if I have crashed
    Process.flag(:trap_exit, true)

    {:ok, game}
  end

  @impl true
  def handle_call({:is_part_of, user_id}, _from, game) do
    {:reply, user_id in participants(game), game}
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
          Welcome to Final Fantastic Card!
 
          [Click here to view game instructions!](https://vrabbers.github.io/ffc_ex/index.html)
          """,
          thumbnail: %Thumbnail{url: User.avatar_url(Api.get_current_user!(), "png")}
        }
        |> put_id_footer(game)

      broadcast(game, embeds: [embed])
      PlayerRouter.add_all_to(participants(game), game.id)

      do_turn(game)

      {:reply, :ok, game}
    else
      {:stop, :error, {:cannot_dm, for({{:error, _}, user} <- responses, do: user)}, game}
    end
  end

  @impl true
  def handle_cast({user_id, {:play, card_str}}, game) do
    cond do
      current_player(game) != user_id ->
        tell(user_id, "You can't play when it's not your turn!")
        {:noreply, game}

      game.was_valid_wild4 != nil ->
        tell(user_id, "You must resolve the Wildcard Draw 4 challenge!")
        {:noreply, game}

      game.was_valid_wild4 == nil ->
        case Card.parse(card_str) do
          {:ok, {_, nil}} ->
            tell(user_id, "Please specify wildcard color!")
            {:noreply, game}

          {:ok, card} ->
            game = do_play_card(game, user_id, card)
            {:noreply, game}

          :error ->
            tell(user_id, "Invalid card!")
            {:noreply, game}
        end
    end
  end

  @impl true
  def handle_cast({user_id, :draw}, game) do
    cond do
      current_player(game) != user_id ->
        tell(user_id, "You can't use this when it's not your turn!")
        {:noreply, game}

      game.drawn_card != nil ->
        tell(user_id, "You can't `draw` twice! You must play the card you've drawn!")
        {:noreply, game}

      game.called_ffc == {user_id, true} ->
        tell(user_id, "You can't draw a card after you've called FFC!")
        {:noreply, game}

      game.was_valid_wild4 != nil ->
        game =
          %Game{game | was_valid_wild4: nil}
          |> force_draw(user_id, 4)
          |> advance_player()
          |> do_turn()

        {:noreply, game}

      game.cml_draw != nil ->
        game =
          %Game{game | cml_draw: nil}
          |> force_draw(user_id, game.cml_draw)
          |> advance_player()
          |> do_turn()

        {:noreply, game}

      game.cml_draw == nil and game.drawn_card == nil and game.was_valid_wild4 == nil ->
        {:noreply, do_draw_self(game, user_id)}
    end
  end

  @impl true
  def handle_cast({user_id, :pass}, game) do
    cond do
      current_player(game) != user_id ->
        tell(user_id, "You can't use this when it's not your turn!")
        {:noreply, game}

      game.drawn_card == nil ->
        tell(user_id, "You can only pass if you've drawn a card.")
        {:noreply, game}

      game.drawn_card != nil ->
        {:noreply, %Game{game | drawn_card: nil} |> advance_player() |> do_turn()}
    end
  end

  @impl true
  def handle_cast({user_id, :status}, game) do
    [current | others] = game.players

    field_text =
      "**#{format_user(game, current)}\n**" <>
        (others |> Enum.map_join("\n", &format_user(game, &1)))

    embed =
      %Embed{
        title: "Game status",
        fields: [
          %Field{name: "Current card", value: Card.to_string(game.current_card)},
          %Field{name: "Players", value: field_text <> "\n*Play continues downwards*"}
        ],
        color: Application.fetch_env!(:ffc_ex, :color)
      }
      |> put_id_footer(game)

    tell(user_id, embeds: [embed])

    {:noreply, game}
  end

  @impl true
  def handle_cast({user_id, :hand}, game) do
    if user_id in game.players do
      embed =
        %Embed{
          title: "Your hand",
          description: formatted_hand(game.hands[user_id], game.current_card)
        }
        |> put_id_footer(game)

      tell(user_id, embeds: [embed])
    else
      tell(user_id, "You do not have a hand!")
    end

    {:noreply, game}
  end

  @impl true
  def handle_cast({user_id, {:chat, chat_msg}}, game) do
    str =
      if user_id in game.players do
        "*\##{game.id}* **#{uname_discrim(user_id)}:** #{chat_msg}"
      else
        "*\##{game.id} Spectator #{uname_discrim(user_id)}:* #{chat_msg}"
      end

    broadcast_except(game, [user_id], str)

    {:noreply, game}
  end

  @impl true
  def handle_cast({user_id, :nudge}, game) do
    if current_player(game) == user_id do
      tell(user_id, "It's your turn right now. Go nudge yourself!")
      {:noreply, game}
    else
      tell(
        current_player(game),
        """
        #{username(user_id)} wished to remind you it's your turn to play by giving you a gentle \
        nudge. *Nudge!*
        """
      )

      tell(user_id, "I've nudged #{username(current_player(game))}.")
      {:noreply, game}
    end
  end

  @impl true
  def handle_cast({user_id, :ffc}, game) do
    hand = game.hands[user_id]
    can_play_a_card = Enum.any?(hand, &Card.can_play_on?(game.current_card, &1))

    cond do
      current_player(game) != user_id ->
        tell(user_id, "You can't do this!")
        {:noreply, game}

      length(hand) != 2 or not can_play_a_card ->
        tell(user_id, "You can't call FFC right now!")
        {:noreply, game}

      length(hand) == 2 and can_play_a_card ->
        broadcast(game,
          embeds: [
            %Embed{
              title: "FFC",
              description: "**#{username(user_id)} has called FFC!**"
            }
            |> put_id_footer(game)
          ]
        )

        {:noreply, %Game{game | called_ffc: {user_id, true}}}
    end
  end

  @impl true
  def handle_cast({user_id, :challenge}, game) do
    cond do
      current_player(game) != user_id ->
        tell(user_id, "You can't do this!")
        {:noreply, game}

      game.was_valid_wild4 != nil ->
        {:noreply, do_wild4_challenge(game, user_id)}

      match?({_, false}, game.called_ffc) ->
        {forgot_ffc, false} = game.called_ffc

        if forgot_ffc != user_id do
          broadcast(game,
            embeds: [
              %Embed{
                title: "FFC challenged!",
                description:
                  "#{username(forgot_ffc)} forgot to call FFC and #{username(user_id)} has challenged them!"
              }
              |> put_id_footer(game)
            ]
          )

          {:noreply, game |> force_draw(forgot_ffc, 2)}
        else
          tell(user_id, "There is nothing to challenge right now!")
          {:noreply, game}
        end

      true ->
        tell(user_id, "There is nothing to challenge right now!")
        {:noreply, game}
    end
  end

  @impl true
  def handle_cast({user_id, :help}, game) do
    tell(user_id,
      embeds: [
        %Embed{
          title: "Help",
          description:
            "[Click here to view game instructions!](https://vrabbers.github.io/ffc_ex/index.html)"
        }
        |> put_id_footer(game)
      ]
    )
  end

  @impl true
  def handle_cast({user_id, :spectate}, game) do
    game = game |> do_drop_player(user_id)
    tell(user_id, "You are now spectating the game.")
    {:noreply, %Game{game | spectators: game.spectators ++ [user_id]}}
  end

  @impl true
  def handle_cast({user_id, :drop}, game) do
    {:noreply, game |> do_drop_player(user_id)}
  end

  @impl true
  def terminate(reason, game) do
    if reason != :normal do
      Logger.error("Game \##{game.id} exited for abnormal reason: #{inspect(reason)}")

      broadcast(
        game,
        """
        🔴 Unfortunately, game \##{game.id} closed due to an error. \
        Use `ffc:join` in the original channel to start a new game.
        """
      )
    end
  end

  defp do_turn(game) do
    current_player = current_player(game)

    cond do
      game.was_valid_wild4 != nil -> wild4_challenge_turn(game)
      game.cml_draw != nil -> cml_draw_turn(game)
      game.was_valid_wild4 == nil and game.cml_draw == nil -> normal_turn(game)
    end

    broadcast_except(
      game,
      [current_player],
      "*\##{game.id} - #{username(current_player)}'s turn.*"
    )

    game
  end

  defp normal_turn(game) do
    current_player = current_player(game)

    embed =
      %Embed{
        title: "Your turn!",
        fields: [
          %Field{name: "Current card", value: Card.to_string(game.current_card)}
        ]
      }
      |> put_id_footer(game)
      |> put_cond_fields(game)

    tell(current_player, embeds: [embed])
  end

  defp wild4_challenge_turn(game) do
    current_player = current_player(game)
    {challenged_player, _} = game.was_valid_wild4

    tell(current_player,
      embeds: [
        %Embed{
          title: "Wild Draw 4 challenge",
          description: """
          #{username(challenged_player)} has played a Wild Draw 4. If you think it was played \
          illegally, use `!` to challenge their decision. Use `draw` to accept and draw 4 cards.
          *If you lose the challenge, you draw 6 cards. If you win, they draw 4 cards.*
          """
        }
        |> put_id_footer(game)
      ]
    )
  end

  defp cml_draw_turn(game) do
    current_player = current_player(game)

    draw2_cards =
      game.hands[current_player]
      |> Enum.filter(fn {_, el} -> el == :draw2 end)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map_join(", ", &"`play #{Card.to_string(&1)}`")

    tell(current_player,
      embeds: [
        %Embed{
          title: "Your turn!",
          description:
            if draw2_cards == "" do
              """
              Because you have no Draw 2 cards, you have to draw the #{game.cml_draw} \
              accumulated cards with `draw`.
              """
            else
              """
              This turn, you must play a Draw 2 card with #{draw2_cards} or draw the \
              #{game.cml_draw} accumulated cards with `draw`
              """
            end
        }
        |> put_cond_fields(game)
        |> put_id_footer(game)
      ]
    )
  end

  defp put_cond_fields(embed, game) do
    current_player = current_player(game)
    must_draw = !Enum.any?(game.hands[current_player], &Card.can_play_on?(game.current_card, &1))

    embed =
      embed
      |> Embed.put_field(
        "Your hand",
        formatted_hand(game.hands[current_player], game.current_card)
      )
      |> put_field_if(
        must_draw and game.cml_draw == nil,
        "Draw",
        "You can't play any of your cards. Use `draw` to draw one from the deck."
      )

    case game.called_ffc do
      {forgot_ffc, false} ->
        put_field_if(
          embed,
          forgot_ffc != current_player,
          "FFC challenge",
          "#{username(forgot_ffc)} forgot to call FFC. Use `!` to challenge them!"
        )

      _ ->
        embed
    end
  end

  defp do_play_card(game, player_id, {_, card_type} = card) do
    player_hand = game.hands[player_id]

    cond do
      !Deck.has_card?(player_hand, card) ->
        tell(player_id, "You don't have this card!")
        game

      game.drawn_card != nil and !Card.equal_nw?(game.drawn_card, card) ->
        tell(player_id, "You must play the card you've drawn!")
        game

      !Card.can_play_on?(game.current_card, card) ->
        tell(player_id, "This card can't be played! Cards that can be played are **__bold__**.")
        game

      game.cml_draw != nil and card_type != :draw2 ->
        tell(player_id, "You must play a Draw 2 card or `draw` the cards.")
        game

      (Card.can_play_on?(game.current_card, card) and game.cml_draw == nil) or
          (game.cml_draw != nil and card_type == :draw2) ->
        play_card_do_turn(game, card, player_id)
    end
  end

  defp play_card_do_turn(game, card, player_id) do
    broadcast(game,
      embeds: [
        %Embed{
          title: "Card played!",
          description: "#{username(player_id)} has played a **#{Card.to_string(card)}**"
        }
        |> put_id_footer(game)
      ]
    )

    new_deck = Deck.put_back(game.deck, game.current_card)
    {_, new_hand} = Deck.remove(game.hands[player_id], card)

    if Enum.empty?(new_hand) do
      # Victory condition
      author_img_url = User.avatar_url(Api.get_user!(player_id), "png")

      end_game(game,
        embeds: [
          %Embed{
            title: "Victory!",
            description: "#{username(player_id)} has won the game!",
            thumbnail: %Thumbnail{url: author_img_url}
          }
          |> put_id_footer(game)
        ]
      )
    else
      card_special_message(game, card)

      game =
        with {:wildcard_draw4, _} <- card do
          # except other wild draw 4s!
          can_play_other_cards =
            new_hand
            |> Enum.reject(&Card.equal_nw?(&1, {:wildcard_draw4, nil}))
            |> Enum.any?(&Card.can_play_on?(game.current_card, &1))

          %Game{game | was_valid_wild4: {player_id, !can_play_other_cards}}
        else
          _ -> %Game{game | was_valid_wild4: nil}
        end

      new_hands = Map.put(game.hands, player_id, new_hand)

      game = %Game{game | deck: new_deck, hands: new_hands, current_card: card}
      game = do_card_effect(game, card)

      game =
        if length(new_hand) == 1 and !match?({^player_id, true}, game.called_ffc) do
          %Game{game | called_ffc: {player_id, false}}
        else
          %Game{game | called_ffc: nil}
        end

      do_turn(game)
    end
  end

  defp do_draw_self(game, player_id) do
    player_hand = game.hands[player_id]
    {drawn_card, deck} = Deck.get_random(game.deck)

    broadcast_except(game, [player_id],
      embeds: [
        %Embed{
          title: "Card drawn",
          description: "#{username(player_id)} has drawn a card from the deck.",
          thumbnail: %Thumbnail{url: "attachment://draw.png"}
        }
        |> put_id_footer(game)
      ],
      files: [PrivDir.file("draw.png")]
    )

    new_hand = Deck.put_back(player_hand, drawn_card)
    new_hands = Map.put(game.hands, player_id, new_hand)
    game = %Game{game | hands: new_hands, deck: deck, called_ffc: nil}

    tell(player_id,
      embeds: [
        %Embed{
          title: "Card drawn",
          description:
            "You have drawn a **#{Card.to_string(drawn_card)}**.\n" <>
              if Card.can_play_on?(game.current_card, drawn_card) do
                "Use `play #{Card.to_string(drawn_card)}` to play this card now or use `pass`."
              else
                "Since you can't play this card, use `pass`."
              end,
          thumbnail: %Thumbnail{url: "attachment://draw.png"}
        }
        |> put_id_footer(game)
      ],
      files: [PrivDir.file("draw.png")]
    )

    %Game{game | drawn_card: drawn_card}
  end

  defp do_wild4_challenge(game, challenging_player) do
    {challenged_player, was_valid?} = game.was_valid_wild4

    broadcast(game,
      embeds: [
        %Embed{
          title: "Wild Draw 4 challenge",
          description: """
          #{username(challenging_player)} has challenged the Wild Draw Four played \
          by #{username(challenged_player)}, and has #{if was_valid?, do: "lost", else: "won"} \
          the challenge.
          """
        }
        |> put_id_footer(game)
      ]
    )

    if was_valid? do
      game |> force_draw(challenging_player, 6) |> advance_player()
    else
      game |> force_draw(challenged_player, 4)
    end
    |> Map.put(:was_valid_wild4, nil)
    |> do_turn()
  end

  defp card_special_message(game, card) do
    case card do
      {x, :skip} when Card.is_color(x) ->
        broadcast(game,
          embeds: [
            %Embed{
              title: "Turn skipped!",
              description: "#{game |> next_player() |> username()}'s turn has been skipped!",
              thumbnail: %Thumbnail{url: "attachment://skip.png"}
            }
            |> put_id_footer(game)
          ],
          files: [PrivDir.file("skip.png")]
        )

      {x, :reverse} when Card.is_color(x) ->
        broadcast(game,
          embeds: [
            %Embed{
              title: "Play reversed!",
              description: "The direction of play has been reversed.",
              thumbnail: %Thumbnail{url: "attachment://reverse.png"}
            }
            |> put_id_footer(game)
          ],
          files: [PrivDir.file("reverse.png")]
        )

      {x, col} when Card.is_wildcard(x) and Card.is_color(col) ->
        broadcast(game,
          embeds: [
            %Embed{
              title: "Color changed!",
              description: "The color has changed to **#{col}**.",
              thumbnail: %Thumbnail{url: "attachment://#{col}.png"}
            }
            |> put_id_footer(game)
          ],
          files: [PrivDir.file("#{col}.png")]
        )

      _ ->
        :noop
    end
  end

  defp do_card_effect(game, card) do
    case card do
      {x, no} when Card.is_cardno(no) or Card.is_wildcard(x) ->
        advance_player(game)

      {_, :skip} ->
        advance_twice(game)

      {_, :reverse} ->
        if length(game.players) == 2 do
          game |> reverse_playing_order() |> advance_player()
        else
          game |> reverse_playing_order()
        end

      {_, :draw2} ->
        if :cumulative_draw in game.house_rules do
          cml_draw = if game.cml_draw == nil, do: 2, else: game.cml_draw + 2
          advance_player(%Game{game | cml_draw: cml_draw})
        else
          game |> draw_next(2) |> advance_twice()
        end
    end
  end

  defp draw_next(game, amt) do
    next_player = next_player(game)
    force_draw(game, next_player, amt)
  end

  defp force_draw(game, player, amt) do
    file =
      case amt do
        2 -> "draw2.png"
        4 -> "draw4.png"
        6 -> "draw6.png"
        _ -> "draw.png"
      end

    broadcast(game,
      embeds: [
        %Embed{
          title: "Drawn cards",
          description: "#{username(player)} has been forced to draw #{amt} cards!",
          thumbnail: %Thumbnail{url: "attachment://#{file}"}
        }
        |> put_id_footer(game)
      ],
      files: [PrivDir.file(file)]
    )

    {drawn, deck} = Deck.get_many(game.deck, amt)
    hands = Map.update!(game.hands, player, &(drawn ++ &1))
    %Game{game | deck: deck, hands: hands}
  end

  @spec participants(Game.t()) :: [User.id()]
  defp participants(game) do
    game.players ++ game.spectators
  end

  defp broadcast(game, message) do
    broadcast_to(participants(game), message)
  end

  defp broadcast_except(game, except_users, message) do
    broadcast_to(participants(game) -- except_users, message)
  end

  defp broadcast_to(users, message) do
    Game.MessageQueue.broadcast_to(users, message)
  end

  defp tell(user, message) do
    Game.MessageQueue.tell(user, message)
  end

  defp put_id_footer(embed, game) do
    embed = Embed.put_footer(embed, "Game \##{game.id}")

    if embed.color == nil do
      Embed.put_color(embed, Application.fetch_env!(:ffc_ex, :color))
    else
      embed
    end
  end

  defp do_drop_player(game, player) do
    if player in game.players do
      broadcast(game, "*\##{game.id}* - #{username(player)} has dropped from the game.")

      if Game.playercount_valid?(length(game.players) - 1) do
        was_current_player = current_player(game) == player
        players = game.players -- [player]
        {hand, hands} = Map.pop(game.hands, player)
        deck = Deck.put_back(game.deck, hand)
        game = %Game{game | players: players, hands: hands, deck: deck, drawn_card: nil}
        if was_current_player, do: do_turn(game), else: game
      else
        end_game(game, "Game \##{game.id} has ended as there weren't enough players to continue.")
      end
    else
      tell(player, "You have stopped spectating the game.")
      %Game{game | spectators: game.spectators -- [player]}
    end
  end

  defp end_game(game, message) do
    broadcast(game, message)
    exit(:normal)
  end

  defp next_player(game) do
    Enum.at(game.players, 1)
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

  defp current_player(game) do
    hd(game.players)
  end

  defp advance_player(game) do
    [first | others] = game.players
    players = others ++ [first]
    %Game{game | players: players, drawn_card: nil}
  end

  defp advance_twice(game) do
    game |> advance_player() |> advance_player()
  end

  defp reverse_playing_order(game) do
    %Game{game | players: Enum.reverse(game.players)}
  end

  defp uname_discrim(user_id) do
    {:ok, user} = Api.get_user(user_id)
    "#{user.username}\##{user.discriminator}"
  end

  defp username(user_id) do
    {:ok, user} = Api.get_user(user_id)
    user.username
  end

  defp format_user(game, user_id) do
    card_amt = length(game.hands[user_id])
    card_plural = if card_amt == 1, do: "card", else: "cards"
    "#{username(user_id)} – #{card_amt} #{card_plural}"
  end

  defp put_field_if(embed, condition, title, value, inline \\ nil) do
    if condition do
      Embed.put_field(embed, title, value, inline)
    else
      embed
    end
  end
end

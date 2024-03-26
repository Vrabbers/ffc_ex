defmodule FfcEx.Game do
  alias FfcEx.{Game, Game.Card, Game.Deck, Lobby}

  require Card
  require Logger

  @enforce_keys [
    :id,
    :players,
    :hands,
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

  def init(lobby) do
    deck = Deck.new()
    {last, deck} = Deck.get_matching(deck, &Card.valid_first_card?/1)
    {groups, deck} = Deck.get_many_groups(deck, 7, length(lobby.players))
    hands = Enum.zip(lobby.players, groups) |> Map.new()

    game = %Game{
      id: lobby.id,
      players: lobby.players,
      hands: hands,
      deck: deck,
      current_card: last,
      drawn_card: nil,
      called_ffc: nil,
      was_valid_wild4: nil,
      house_rules: lobby.house_rules,
      cml_draw: nil
    }

    game
  end

  def status(game) do
    players_cards =
      game.players |> Enum.map(fn player -> {player, length(game.hands[player])} end)

    {players_cards, game.current_card}
  end

  def start_game(game) do
    turn_messages({[:welcome], game})
  end

  def play(game, player, card) do
    cond do
      current_player(game) != player ->
        {:not_players_turn, game}

      game.was_valid_wild4 != nil ->
        {:resolve_wild4_challenge, game}

      game.was_valid_wild4 == nil ->
        play_card(game, player, card)
    end
  end

  def draw(game, player) do
    cond do
      current_player(game) != player ->
        {:not_players_turn, game}

      game.drawn_card != nil ->
        {:must_play_drawn_card, game}

      game.called_ffc == {player, true} ->
        {:called_ffc_before, game}

      game.was_valid_wild4 != nil ->
        {[], %Game{game | was_valid_wild4: nil}}
        |> force_draw(player, 4)
        |> advance_player()
        |> turn_messages()

      game.cml_draw != nil ->
        {[], %Game{game | cml_draw: nil}}
        |> force_draw(player, game.cml_draw)
        |> advance_player()
        |> turn_messages()

      game.cml_draw == nil and game.drawn_card == nil and game.was_valid_wild4 == nil ->
        do_draw_self(game, player)
    end
  end

  def pass(game, player) do
    cond do
      current_player(game) != player ->
        {:not_players_turn, game}

      game.drawn_card == nil ->
        {:cannot_pass, game}

      game.drawn_card != nil ->
        {[], %Game{game | drawn_card: nil}} |> advance_player() |> turn_messages()
    end
  end

  def call_ffc(game, player) do
    hand = game.hands[player]
    can_play_a_card = Enum.any?(hand, &Card.can_play_on?(game.current_card, &1))

    cond do
      current_player(game) != player ->
        {:not_players_turn, game}

      length(hand) != 2 or not can_play_a_card ->
        {:cannot_call_ffc, game}

      length(hand) == 2 and can_play_a_card ->
        {{:called_ffc, player}, %Game{game | called_ffc: {player, true}}}
    end
  end

  def challenge(game, player) do
    cond do
      match?({_, false}, game.called_ffc) and game.called_ffc != {player, false} ->
        {forgot_ffc, false} = game.called_ffc
        message = {:forgot_ffc_challenge, forgot_ffc, player}
        game = %Game{game | called_ffc: nil}
        force_draw({[message], game}, forgot_ffc, 2)

      current_player(game) == player and game.was_valid_wild4 != nil ->
        wild4_challenge(game, player)

      true ->
        {:cannot_ffc_challenge, game}
    end
  end

  def drop_player(game, player) do
    if player in game.players do
      resp = [{:drop, player}]

      if Game.playercount_valid?(length(game.players) - 1) do
        was_current_player = current_player(game) == player
        players = game.players -- [player]
        {hand, hands} = Map.pop(game.hands, player)
        deck = Deck.put_back(game.deck, hand)
        game = %Game{game | players: players, hands: hands, deck: deck, drawn_card: nil}
        if was_current_player, do: turn_messages({resp, game}), else: {resp, game}
      else
        {[{:end, :not_enough_players} | resp], game}
      end
    end
  end

  defp turn_messages({resps, game}) do
    current_player = current_player(game)

    resp_msg =
      cond do
        game.was_valid_wild4 != nil ->
          {challenged_player, _} = game.was_valid_wild4
          {:wild4_challenge_turn, challenged_player}

        game.cml_draw != nil ->
          {:cml_draw_turn, game.cml_draw}

        game.was_valid_wild4 == nil and game.cml_draw == nil ->
          :normal_turn
      end

    must_draw = !Enum.any?(game.hands[current_player], &Card.can_play_on?(game.current_card, &1))

    conditions =
      [
        if game.cml_draw != nil do
          {:cml_draw, game.cml_draw}
        else
          nil
        end,
        if must_draw and game.cml_draw == nil do
          :must_draw
        else
          nil
        end,
        case game.called_ffc do
          {forgot_ffc, false} when forgot_ffc != current_player ->
            {:forgot_ffc, forgot_ffc}

          _ ->
            nil
        end
      ]
      |> Enum.filter(&Function.identity/1)

    {[
       {resp_msg, current_player, game.hands[current_player], game.current_card, conditions}
       | resps
     ], game}
  end

  defp play_card(game, player, {_, card_type} = card) do
    player_hand = game.hands[player]

    cond do
      !Deck.has_card?(player_hand, card) ->
        {:dont_have_card, game}

      game.drawn_card != nil and !Card.equal_nw?(game.drawn_card, card) ->
        {:must_play_drawn_card, game}

      !Card.can_play_on?(game.current_card, card) ->
        {:cannot_play_card, game}

      game.cml_draw != nil and card_type != :draw2 ->
        {:cml_draw_must_draw, game}

      valid_to_play_card?(game, card) ->
        play_card_turn_messages(game, card, player)
    end
  end

  defp valid_to_play_card?(game, card) do
    {_, card_type} = card
    no_cml_draw_condition = Card.can_play_on?(game.current_card, card) and game.cml_draw == nil
    cml_drawing_condition = game.cml_draw != nil and card_type == :draw2
    no_cml_draw_condition or cml_drawing_condition
  end

  defp play_card_turn_messages(game, card, player) do
    resp = [{:play_card, player, card}]

    new_deck = Deck.put_back(game.deck, game.current_card)
    {_, new_hand} = Deck.remove(game.hands[player], card)

    if Enum.empty?(new_hand) do
      # Victory condition
      {[{:end, {:win, player}} | resp], game}
    else
      resp =
        case card_special_message(game, card) do
          nil -> resp
          x -> [x | resp]
        end

      called_ffc =
        if length(new_hand) == 1 and !match?({^player, true}, game.called_ffc) do
          {player, false}
        else
          nil
        end

      game = check_valid_wild4(game, player, new_hand, card)

      new_hands = Map.put(game.hands, player, new_hand)

      game =
        %Game{game | deck: new_deck, hands: new_hands, current_card: card, called_ffc: called_ffc}

      {resp, game} |> do_card_effect(card) |> turn_messages()
    end
  end

  defp check_valid_wild4(game, player, hand, card) do
    case card do
      {:wildcard_draw4, _} ->
        # except other wild draw 4s!
        can_play_other_cards =
          hand
          |> Enum.reject(&Card.equal_nw?(&1, {:wildcard_draw4, nil}))
          |> Enum.any?(&Card.can_play_on?(game.current_card, &1))

        %Game{game | was_valid_wild4: {player, !can_play_other_cards}}

      _ ->
        %Game{game | was_valid_wild4: nil}
    end
  end

  defp do_draw_self(game, player) do
    player_hand = game.hands[player]
    {drawn_card, deck} = Deck.get_random(game.deck)

    new_hand = Deck.put_back(player_hand, drawn_card)
    new_hands = Map.put(game.hands, player, new_hand)
    game = %Game{game | hands: new_hands, deck: deck, called_ffc: nil, drawn_card: drawn_card}

    can_play_drawn =
      if Card.can_play_on?(game.current_card, drawn_card) do
        :can_play_drawn
      else
        :cant_play_drawn
      end

    resp = [{:drew_card, drawn_card, player, can_play_drawn}]

    {resp, game}
  end

  defp wild4_challenge(game, challenging_player) do
    {challenged_player, was_valid?} = game.was_valid_wild4
    resp = [{:wild4_challenge, challenging_player, challenged_player, !was_valid?}]

    game = %Game{game | was_valid_wild4: nil}

    if was_valid? do
      {resp, game} |> force_draw(challenging_player, 6) |> advance_player()
    else
      {resp, game} |> force_draw(challenged_player, 4)
    end
    |> turn_messages()
  end

  defp card_special_message(game, card) do
    case card do
      {x, :skip} when Card.is_color(x) ->
        {:skip, game |> next_player()}

      {x, :reverse} when Card.is_color(x) ->
        :play_reversed

      {x, col} when Card.is_wildcard(x) and Card.is_color(col) ->
        {:color_changed, col}

      _ ->
        nil
    end
  end

  defp do_card_effect({resp, game}, card) do
    case card do
      {x, no} when Card.is_cardno(no) or Card.is_wildcard(x) ->
        advance_player({resp, game})

      {_, :skip} ->
        advance_twice({resp, game})

      {_, :reverse} ->
        if length(game.players) == 2 do
          {resp, game} |> reverse_playing_order() |> advance_player()
        else
          {resp, game} |> reverse_playing_order()
        end

      {_, :draw2} ->
        if :cumulative_draw in game.house_rules do
          cml_draw = inc_cml_draw(game.cml_draw)
          advance_player({resp, %Game{game | cml_draw: cml_draw}})
        else
          {resp, game} |> draw_next(2) |> advance_twice()
        end
    end
  end

  defp inc_cml_draw(cml_draw) do
    case cml_draw do
      nil -> 2
      x -> x + 2
    end
  end

  defp draw_next({resp, game}, amt) do
    next_player = next_player(game)
    force_draw({resp, game}, next_player, amt)
  end

  defp force_draw({resp, game}, player, amt) do
    resp = [{:force_draw, player, amt} | resp]
    {drawn, deck} = Deck.get_many(game.deck, amt)
    hands = Map.update!(game.hands, player, &(drawn ++ &1))
    {resp, %Game{game | deck: deck, hands: hands}}
  end

  defp next_player(game) do
    Enum.at(game.players, 1)
  end

  defp current_player(game) do
    hd(game.players)
  end

  defp advance_player({resp, game}) do
    [first | others] = game.players
    players = others ++ [first]
    {resp, %Game{game | players: players, drawn_card: nil}}
  end

  defp advance_twice(game_resp) do
    game_resp |> advance_player() |> advance_player()
  end

  defp reverse_playing_order({resp, game}) do
    {resp, %Game{game | players: Enum.reverse(game.players)}}
  end
end

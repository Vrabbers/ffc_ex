defmodule FfcEx.Game do
  # Doesn't make much sense to try restarting a crashed game
  use GenServer, restart: :temporary

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

  def start_game(game) do
    GenServer.call(game, :start_game)
  end

  def start_link(lobby) do
    GenServer.start_link(__MODULE__, lobby,
      name: {:via, Registry, {FfcEx.GameRegistry, {:game, lobby.id}}}
    )
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
      deck: deck,
      current_card: last,
      drawn_card: nil,
      called_ffc: nil,
      was_valid_wild4: nil,
      house_rules: lobby.house_rules,
      cml_draw: nil
    }

    {:ok, game}
  end

  def current_card(game) do
    GenServer.call(game, :current_card)
  end

  def hand(game, player) do
    GenServer.call(game, {player, :hand})
  end

  @impl true
  def handle_call(:current_card, _from, game) do
    {:reply, game.current_card, game}
  end

  @impl true
  def handle_call({player, :hand}, _from, game) do
    {:reply, game.hands[player], game}
  end

  @impl true
  def handle_call({player, {:play, card}}, _from, game) do
    cond do
      current_player(game) != player ->
        {:reply, :not_players_turn, game}

      game.was_valid_wild4 != nil ->
        {:reply, :resolve_wild4_challenge, game}

      game.was_valid_wild4 == nil ->
        {game, resp} = do_play_card(game, player, card)
        {:reply, resp, game}
    end
  end

  @impl true
  def handle_call({player, :draw}, _from, game) do
    cond do
      current_player(game) != player ->
        {:reply, :not_players_turn, game}

      game.drawn_card != nil ->
        {:reply, :must_play_drawn_card, game}

      game.called_ffc == {player, true} ->
        {:reply, :called_ffc_before, game}

      game.was_valid_wild4 != nil ->
        {game, resp} =
          {%Game{game | was_valid_wild4: nil}, []}
          |> force_draw(player, 4)
          |> advance_player()
          |> turn_messages()

        {:reply, resp, game}

      game.cml_draw != nil ->
        {game, resp} =
          {%Game{game | cml_draw: nil}, []}
          |> force_draw(player, game.cml_draw)
          |> advance_player()
          |> turn_messages()

        {:reply, resp, game}

      game.cml_draw == nil and game.drawn_card == nil and game.was_valid_wild4 == nil ->
        {game, resp} = do_draw_self(game, player)
        {:reply, resp, game}
    end
  end

  @impl true
  def handle_call({player, :pass}, _from, game) do
    cond do
      current_player(game) != player ->
        {:reply, :not_players_turn, game}

      game.drawn_card == nil ->
        {:reply, :cannot_pass, game}

      game.drawn_card != nil ->
        {game, resp} = {%Game{game | drawn_card: nil}, []} |> advance_player() |> turn_messages()
        {:reply, resp, game}
    end
  end

  @impl true
  def handle_call({player, :ffc}, _from, game) do
    hand = game.hands[player]
    can_play_a_card = Enum.any?(hand, &Card.can_play_on?(game.current_card, &1))

    cond do
      current_player(game) != player ->
        {:reply, :not_players_turn, game}

      length(hand) != 2 or not can_play_a_card ->
        {:reply, :cannot_call_ffc, game}

      length(hand) == 2 and can_play_a_card ->
        {:reply, {:called_ffc, player}, %Game{game | called_ffc: {player, true}}}
    end
  end

  @impl true
  def handle_call({player, :challenge}, _from, game) do
    cond do
      current_player(game) != player ->
        {:reply, :not_players_turn, game}

      game.was_valid_wild4 != nil ->
        {game, resp} = wild4_challenge(game, player)
        {:reply, resp, game}

      match?({_, false}, game.called_ffc) and game.called_ffc != {player, false} ->
        {forgot_ffc, false} = game.called_ffc
        {game, resp} = force_draw({game, []}, forgot_ffc, 2)
        {:reply, resp, game}

      true ->
        {:reply, :cannot_ffc_challenge, game}
    end
  end

  @impl true
  def handle_call(:start_game, _from, game) do
    {game, resp} = turn_messages({game, [:welcome]})
    {:reply, resp, game}
  end

  @impl true
  def handle_call({player, :drop}, _from, game) do
    {game, resp} = do_drop_player({game, []}, player)
    {:reply, resp, game}
  end

  @spec do_drop_player({Game.t(), list() | atom()}, User.id()) :: {Game.t(), list()}
  defp do_drop_player({game, resp}, player) do
    if player in game.players do
      resp = [{:drop, player} | resp]

      if Game.playercount_valid?(length(game.players) - 1) do
        was_current_player = current_player(game) == player
        players = game.players -- [player]
        {hand, hands} = Map.pop(game.hands, player)
        deck = Deck.put_back(game.deck, hand)
        game = %Game{game | players: players, hands: hands, deck: deck, drawn_card: nil}
        if was_current_player, do: turn_messages({game, resp}), else: {game, resp}
      else
        {game, [{:end, :not_enough_players} | resp]}
      end
    end
  end

  defp turn_messages({game, resps}) do
    current_player = current_player(game)

    resp_msg =
      cond do
        game.was_valid_wild4 != nil -> :wild4_challenge_turn
        game.cml_draw != nil -> :cml_draw_turn
        game.was_valid_wild4 == nil and game.cml_draw == nil -> :normal_turn
      end

    {game, [{resp_msg, current_player, game.current_card} | resps]}
  end

  defp do_play_card(game, player, {_, card_type} = card) do
    player_hand = game.hands[player]

    cond do
      !Deck.has_card?(player_hand, card) ->
        {game, :dont_have_card}

      game.drawn_card != nil and !Card.equal_nw?(game.drawn_card, card) ->
        {game, :must_play_drawn_card}

      !Card.can_play_on?(game.current_card, card) ->
        {game, :cannot_play_card}

      game.cml_draw != nil and card_type != :draw2 ->
        {game, :cml_draw_must_draw}

      (Card.can_play_on?(game.current_card, card) and game.cml_draw == nil) or
          (game.cml_draw != nil and card_type == :draw2) ->
        play_card_turn_messages(game, card, player)
    end
  end

  defp play_card_turn_messages(game, card, player) do
    resp = [{:play_card, card}]

    new_deck = Deck.put_back(game.deck, game.current_card)
    {_, new_hand} = Deck.remove(game.hands[player], card)

    if Enum.empty?(new_hand) do
      # Victory condition
      {game, [{:end, {:win, player}} | resp]}
    else
      resp = [card_special_message(game, card) | resp]

      game =
        with {:wildcard_draw4, _} <- card do
          # except other wild draw 4s!
          can_play_other_cards =
            new_hand
            |> Enum.reject(&Card.equal_nw?(&1, {:wildcard_draw4, nil}))
            |> Enum.any?(&Card.can_play_on?(game.current_card, &1))

          %Game{game | was_valid_wild4: {player, !can_play_other_cards}}
        else
          _ -> %Game{game | was_valid_wild4: nil}
        end

      new_hands = Map.put(game.hands, player, new_hand)

      game = %Game{game | deck: new_deck, hands: new_hands, current_card: card}
      {game, resp} = do_card_effect({game, resp}, card)

      game =
        if length(new_hand) == 1 and !match?({^player, true}, game.called_ffc) do
          %Game{game | called_ffc: {player, false}}
        else
          %Game{game | called_ffc: nil}
        end

      turn_messages({game, resp})
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

    resp = [{:drew_card, player, can_play_drawn}]

    {game, resp}
  end

  defp wild4_challenge(game, challenging_player) do
    {challenged_player, was_valid?} = game.was_valid_wild4
    resp = [{:wild4_challenge, challenging_player, challenged_player, !was_valid?}]

    game = %Game{game | was_valid_wild4: nil}

    if was_valid? do
      {game, resp} |> force_draw(challenging_player, 6) |> advance_player()
    else
      {game, resp} |> force_draw(challenged_player, 4)
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
        :no_special_effect_message
    end
  end

  defp do_card_effect({game, resp}, card) do
    case card do
      {x, no} when Card.is_cardno(no) or Card.is_wildcard(x) ->
        advance_player({game, resp})

      {_, :skip} ->
        advance_twice({game, resp})

      {_, :reverse} ->
        if length(game.players) == 2 do
          {game, resp} |> reverse_playing_order() |> advance_player()
        else
          {game, resp} |> reverse_playing_order()
        end

      {_, :draw2} ->
        if :cumulative_draw in game.house_rules do
          cml_draw = if game.cml_draw == nil, do: 2, else: game.cml_draw + 2
          advance_player({%Game{game | cml_draw: cml_draw}, resp})
        else
          {game, resp} |> draw_next(2) |> advance_twice()
        end
    end
  end

  defp draw_next({game, resp}, amt) do
    next_player = next_player(game)
    force_draw({game, resp}, next_player, amt)
  end

  defp force_draw({game, resp}, player, amt) do
    resp = [{:force_draw, player, amt} | resp]
    {drawn, deck} = Deck.get_many(game.deck, amt)
    hands = Map.update!(game.hands, player, &(drawn ++ &1))
    {%Game{game | deck: deck, hands: hands}, resp}
  end

  defp next_player(game) do
    Enum.at(game.players, 1)
  end

  defp current_player(game) do
    hd(game.players)
  end

  defp advance_player({game, resp}) do
    [first | others] = game.players
    players = others ++ [first]
    {%Game{game | players: players, drawn_card: nil}, resp}
  end

  defp advance_twice(game_resp) do
    game_resp |> advance_player() |> advance_player()
  end

  defp reverse_playing_order({game, resp}) do
    {%Game{game | players: Enum.reverse(game.players)}, resp}
  end
end

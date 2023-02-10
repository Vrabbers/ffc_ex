defmodule FfcEx.Game.Deck do
  alias FfcEx.Game.Card
  require Card

  @type t() :: [Card.t()]

  @spec get_random(t()) :: {Card.t(), t()}
  def get_random(deck) do
    idx = Enum.random(1..length(deck)) - 1
    List.pop_at(deck, idx)
  end

  @spec get_matching(t(), (Card.t() -> as_boolean(any))) :: {Card.t(), t()}
  def get_matching(deck, fun) do
    {card, deck} = get_random(deck)

    if fun.(card) do
      {card, deck}
    else
      get_matching(deck, fun)
    end
  end

  @spec get_many(t(), pos_integer()) :: {[Card.t()], t()}
  def get_many(deck, amt) when length(deck) >= amt do
    els = Enum.take_random(deck, amt)
    {els, deck -- els}
  end

  @spec get_many_groups(t(), pos_integer(), pos_integer()) :: {[[Card.t()]], t()}
  def get_many_groups(deck, amt, groups) when length(deck) >= amt * groups do
    Enum.reduce(1..groups, {[], deck}, fn _, {groups, deck} ->
      {group, deck} = get_many(deck, amt)
      {[group | groups], deck}
    end)
  end

  @spec put_back(t(), Card.t()) :: t()
  def put_back(deck, card) do
    case card do
      {x, _} when x in [:wildcard, :wildcard_draw4] -> [{x, nil} | deck]
      _ -> [card | deck]
    end
  end

  @spec has_card?(t(), Card.t()) :: boolean()
  def has_card?(deck, card) do
    Enum.any?(deck, fn card_from_deck ->
      case card do
        {wild, _} when wild in [:wildcard, :wildcard_draw4] -> {wild, nil} == card_from_deck
        _ -> card == card_from_deck
      end
    end)
  end

  @spec remove(t(), Card.t()) :: {Card.t(), t()} | :error
  def remove(deck, card) do
    card = case card do
      {wild, _} when Card.is_wildcard(wild) -> {wild, nil}
      _ -> card
    end |> IO.inspect()
    if card in deck do
      {card, deck -- [card]}
    else
      :error
    end
  end

  @spec new() :: t()
  def new() do
    [
      {:red, 0},
      {:yellow, 0},
      {:green, 0},
      {:blue, 0},
      {:red, 1},
      {:red, 2},
      {:red, 3},
      {:red, 4},
      {:red, 5},
      {:red, 6},
      {:red, 7},
      {:red, 8},
      {:red, 9},
      {:red, :reverse},
      {:red, :skip},
      {:red, :draw2},
      {:red, 1},
      {:red, 2},
      {:red, 3},
      {:red, 4},
      {:red, 5},
      {:red, 6},
      {:red, 7},
      {:red, 8},
      {:red, 9},
      {:red, :reverse},
      {:red, :skip},
      {:red, :draw2},
      {:yellow, 1},
      {:yellow, 2},
      {:yellow, 3},
      {:yellow, 4},
      {:yellow, 5},
      {:yellow, 6},
      {:yellow, 7},
      {:yellow, 8},
      {:yellow, 9},
      {:yellow, :reverse},
      {:yellow, :skip},
      {:yellow, :draw2},
      {:yellow, 1},
      {:yellow, 2},
      {:yellow, 3},
      {:yellow, 4},
      {:yellow, 5},
      {:yellow, 6},
      {:yellow, 7},
      {:yellow, 8},
      {:yellow, 9},
      {:yellow, :reverse},
      {:yellow, :skip},
      {:yellow, :draw2},
      {:green, 1},
      {:green, 2},
      {:green, 3},
      {:green, 4},
      {:green, 5},
      {:green, 6},
      {:green, 7},
      {:green, 8},
      {:green, 9},
      {:green, :reverse},
      {:green, :skip},
      {:green, :draw2},
      {:green, 1},
      {:green, 2},
      {:green, 3},
      {:green, 4},
      {:green, 5},
      {:green, 6},
      {:green, 7},
      {:green, 8},
      {:green, 9},
      {:green, :reverse},
      {:green, :skip},
      {:green, :draw2},
      {:blue, 1},
      {:blue, 2},
      {:blue, 3},
      {:blue, 4},
      {:blue, 5},
      {:blue, 6},
      {:blue, 7},
      {:blue, 8},
      {:blue, 9},
      {:blue, :reverse},
      {:blue, :skip},
      {:blue, :draw2},
      {:blue, 1},
      {:blue, 2},
      {:blue, 3},
      {:blue, 4},
      {:blue, 5},
      {:blue, 6},
      {:blue, 7},
      {:blue, 8},
      {:blue, 9},
      {:blue, :reverse},
      {:blue, :skip},
      {:blue, :draw2},
      {:wildcard, nil},
      {:wildcard, nil},
      {:wildcard, nil},
      {:wildcard, nil},
      {:wildcard_draw4, nil},
      {:wildcard_draw4, nil},
      {:wildcard_draw4, nil},
      {:wildcard_draw4, nil}
    ]
  end
end

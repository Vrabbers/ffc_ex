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

  @spec put_back(t(), Card.t() | [Card.t()]) :: t()
  def put_back(deck, [card | others]) do
    deck |> put_back(card) |> put_back(others)
  end

  def put_back(deck, []) do
    deck
  end

  def put_back(deck, card) when is_tuple(card) do
    case card do
      {x, _} when x in [:wildcard, :wildcard_draw4] -> [{x, nil} | deck]
      _ -> [card | deck]
    end
  end

  @spec has_card?(t(), Card.t()) :: boolean()
  def has_card?(deck, card) do
    Enum.any?(deck, fn card_from_deck ->
      case card do
        {wild, _} when Card.is_wildcard(wild) -> {wild, nil} == card_from_deck
        _ -> card == card_from_deck
      end
    end)
  end

  @spec remove(t(), Card.t()) :: {Card.t(), t()} | :error
  def remove(deck, card) do
    card =
      case card do
        {wild, _} when Card.is_wildcard(wild) -> {wild, nil}
        _ -> card
      end

    if card in deck do
      {card, deck -- [card]}
    else
      :error
    end
  end

  @spec new() :: t()
  def new() do
    zero_cards =
      for col <- [:red, :green, :yellow, :blue] do
        {col, 0}
      end

    col_cards =
      for _i <- 1..2,
          col <- [:red, :green, :yellow, :blue],
          num <- Enum.to_list(1..9) ++ [:reverse, :skip, :draw2] do
        {col, num}
      end

    wildcards =
      for _i <- 1..4,
          wild <- [:wildcard, :wildcard_draw4] do
        {wild, nil}
      end

    Enum.shuffle(zero_cards ++ col_cards ++ wildcards)
  end
end

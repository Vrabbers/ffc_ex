defmodule FfcEx.Game.Deck do
  alias FfcEx.Game.Card

  @type t() :: [Card.t()]

  @spec new() :: t()
  def new() do
    [
      "R0",
      "Y0",
      "G0",
      "B0",
      "R1",
      "R2",
      "R3",
      "R4",
      "R5",
      "R6",
      "R7",
      "R8",
      "R9",
      "RR",
      "RS",
      "R+",
      "R1",
      "R2",
      "R3",
      "R4",
      "R5",
      "R6",
      "R7",
      "R8",
      "R9",
      "RR",
      "RS",
      "R+",
      "Y1",
      "Y2",
      "Y3",
      "Y4",
      "Y5",
      "Y6",
      "Y7",
      "Y8",
      "Y9",
      "YR",
      "YS",
      "Y+",
      "Y1",
      "Y2",
      "Y3",
      "Y4",
      "Y5",
      "Y6",
      "Y7",
      "Y8",
      "Y9",
      "YR",
      "YS",
      "Y+",
      "G1",
      "G2",
      "G3",
      "G4",
      "G5",
      "G6",
      "G7",
      "G8",
      "G9",
      "GR",
      "GS",
      "G+",
      "G1",
      "G2",
      "G3",
      "G4",
      "G5",
      "G6",
      "G7",
      "G8",
      "G9",
      "GR",
      "GS",
      "G+",
      "B1",
      "B2",
      "B3",
      "B4",
      "B5",
      "B6",
      "B7",
      "B8",
      "B9",
      "BR",
      "BS",
      "B+",
      "B1",
      "B2",
      "B3",
      "B4",
      "B5",
      "B6",
      "B7",
      "B8",
      "B9",
      "BR",
      "BS",
      "B+",
      "+W",
      "+W",
      "+W",
      "+W",
      "+4",
      "+4",
      "+4",
      "+4"
    ]
    |> Enum.map(&Card.parse/1)
  end

  @spec get_random(t()) :: {Card.t(), t()}
  def get_random(deck) do
    idx = Enum.random(1..length(deck)) - 1
    List.pop_at(deck, idx)
  end

  @spec get_matching(t(), (Card.t() -> as_boolean(any))) :: {Card.t(), t()}
  def get_matching(deck, fun) do
    deck |> Enum.filter(fun) |> get_random()
  end

  @spec get_many(t(), pos_integer()) :: {[Card.t()], t()}
  def get_many(deck, amt) when length(deck) >= amt do
    els = Enum.take_random(deck, amt)
    {els, deck -- els}
  end

  @spec get_many_groups(list, pos_integer(), pos_integer()) :: {[[Card.t()]], t()}
  def get_many_groups(deck, amt, groups) when length(deck) >= amt * groups do
    Enum.reduce(1..groups, {[], deck}, fn _, {groups, deck} ->
      {group, deck} = get_many(deck, amt)
      {[group | groups], deck}
    end)
  end

  @spec put_back(t(), Card.t()) :: t()
  def put_back(deck, card) do
    [card | deck]
  end

  @spec remove(t(), Card.t()) :: {Card.t(), t()} | :error
  def remove(deck, card) do
    if card in deck do
      {card, deck -- [card]}
    else
      :error
    end
  end
end

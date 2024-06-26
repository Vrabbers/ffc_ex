defmodule FfcEx.Game.Card do
  @type color() :: :red | :green | :yellow | :blue
  @type complement() :: 0..9 | :reverse | :skip | :draw2
  @type t() ::
          {color(), complement()} | {:wildcard, color() | nil} | {:wildcard_draw4, color() | nil}

  defguardp is_colchar(char) when char in [?r, ?g, ?b, ?y]
  defguardp is_wchar(char) when char in [?w, ?4]
  defguard is_cardno(no) when no in 0..9
  defguard is_color(col) when col in [:red, :green, :yellow, :blue]
  defguard is_wildcard(wild) when wild in [:wildcard, :wildcard_draw4]

  @spec valid_first_card?(t()) :: boolean()
  def valid_first_card?(card) do
    case card do
      {_first, second} when is_cardno(second) -> true
      _ -> false
    end
  end

  @spec can_play_on?(t(), t()) :: boolean
  def can_play_on?(card_down, card_to_play) do
    case {card_down, card_to_play} do
      {nil, _} -> false
      {_, {w, _}} when is_wildcard(w) -> true
      {{w, c}, {c, _}} when is_wildcard(w) -> true
      {{a1, a2}, {b1, b2}} when a1 == b1 or a2 == b2 -> true
      _ -> false
    end
  end

  @spec can_play_on_cml_draw?(t(), t()) :: boolean
  def can_play_on_cml_draw?(card_down, card_to_play) do
    case {card_down, card_to_play} do
      {{:draw2, _}, {:draw2, _}} -> true
      _ -> false
    end
  end

  def equal_nw?(card1, card2) do
    strip_wild(card1) == strip_wild(card2)
  end

  defp strip_wild(card) do
    case card do
      {wild, _} when is_wildcard(wild) -> {wild, nil}
      _ -> card
    end
  end

  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(str) when is_binary(str) do
    lower = str |> String.downcase() |> String.trim()
    <<prefix::utf8, rest::binary>> = lower

    case prefix do
      x when is_colchar(x) -> parse_color_number(x, rest)
      ?+ -> parse_wildcard(rest)
      _ -> :error
    end
  end

  @spec to_string(t()) :: String.t()
  def to_string(card) do
    case card do
      {:wildcard, color} -> "+W" <> color_to_string(color)
      {:wildcard_draw4, color} -> "+4" <> color_to_string(color)
      {color, complement} -> color_to_string(color) <> complement_to_string(complement)
    end
  end

  defp color_to_string(color) do
    case color do
      :red -> "R"
      :green -> "G"
      :yellow -> "Y"
      :blue -> "B"
      nil -> ""
    end
  end

  defp complement_to_string(complement) do
    case complement do
      :reverse -> "R"
      :skip -> "S"
      :draw2 -> "+"
      x when is_cardno(x) -> Integer.to_string(x)
    end
  end

  defp parse_wildcard(rest) do
    case rest do
      <<first::utf8, second::utf8>> when is_wchar(first) and is_colchar(second) ->
        {:ok, {parse_wildcard_modif(first), parse_color(second)}}

      <<first::utf8>> when is_wchar(first) ->
        {:ok, {parse_wildcard_modif(first), nil}}

      _ ->
        :error
    end
  end

  defp parse_wildcard_modif(char) do
    case char do
      ?w -> :wildcard
      ?4 -> :wildcard_draw4
    end
  end

  defp parse_color(color) do
    case color do
      ?r -> :red
      ?g -> :green
      ?y -> :yellow
      ?b -> :blue
    end
  end

  defp parse_color_number(prefix, rest) do
    color = parse_color(prefix)

    complement =
      case rest do
        "s" ->
          :skip

        "r" ->
          :reverse

        "+" ->
          :draw2

        x ->
          case Integer.parse(x) do
            {int, ""} when is_cardno(int) -> int
            _ -> :error
          end
      end

    if complement == :error do
      :error
    else
      {:ok, {color, complement}}
    end
  end
end

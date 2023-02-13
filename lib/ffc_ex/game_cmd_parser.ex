defmodule FfcEx.GameCmdParser do
  def parse(string) do
    case string |> String.trim() |> Integer.parse() do
      {int, rest} -> do_parse(int, String.trim(rest))
      :error -> do_parse(nil, string)
    end
  end

  defp do_parse(game_id, rest) do
    split = String.split(rest, ~r{\s}, parts: 2) |> List.to_tuple()

    result = case split do
      {"hand"} -> :hand
      {"state"} -> :state
      {"status"} -> :status
      {"draw"} -> :draw
      {"nudge"} -> :nudge
      {"chat", arg} -> {:chat, arg}
      {"play", card} -> {:play, card}
      _ -> {:chat, rest}
      end
    {game_id, result}
  end
end

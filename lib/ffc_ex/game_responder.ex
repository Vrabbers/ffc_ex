defmodule FfcEx.GameResponder do
  alias Nostrum.Struct.Embed
  alias FfcEx.PlayerRouter
  alias FfcEx.Game
  alias FfcEx.Game.Card

  use GenServer, restart: :transient

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

  @impl true
  def init({lobby, game}) do
    Process.monitor(game)
    {:ok, %{players: lobby.players, spectators: lobby.spectators, game: game, id: lobby.id}}
  end

  def start_link({lobby, game}) do
    GenServer.start_link(__MODULE__, {lobby, game},
      name: {:via, Registry, {FfcEx.GameRegistry, {:resp, lobby.id}}}
    )
  end

  @impl true
  def handle_call(:start_game, _from, responder) do
    broadcast("start #{responder.id}", responder)
    PlayerRouter.add_all_to(participants(responder), responder.id)
    resp = Game.start_game(responder.game)
    respond(resp, responder)
    {:reply, :ok, responder}
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
        |> put_id_footer(responder)

      tell(uid, embeds: [embed])
    else
      tell("You don't have a hand!", uid)
    end

    {:reply, :ok, responder}
  end

  @impl true
  def handle_call({:cmd, uid, command}, _from, responder) do
    resp = GenServer.call(responder.game, {uid, command})
    respond(resp, responder)
    {:reply, resp, responder}
  end

  @impl true
  def handle_call({:part_of?, uid}, _from, responder) do
    {:reply, uid in participants(responder), responder}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, game, reason}, responder)
      when reason != :normal do
    Logger.notice(
      "Game \##{responder.id}, PID: #{inspect(game)} closed (reason: #{inspect(reason)})"
    )

    exit(:normal)
  end

  @impl true
  def handle_info(msg, responder) do
    Logger.debug("Unknown message received by GameResponder #{inspect(self())}: #{inspect(msg)}")
    {:noreply, responder}
  end

  defp respond(terms, responder) when is_list(terms) do
    terms |> Enum.reverse() |> Enum.each(&respond(&1, responder))
  end

  defp respond(term, responder) do
    broadcast("#{responder.id}: #{inspect(term)}", responder)
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

  defp participants(responder) do
    responder.players ++ responder.spectators
  end

  defp broadcast(message, responder) do
    broadcast_to(message, participants(responder))
  end

  defp broadcast_except(except_users, message, responder) do
    broadcast_to(participants(responder) -- except_users, message)
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
end

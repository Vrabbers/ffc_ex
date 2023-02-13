defmodule FfcEx.Game do
  # Doesn't make much sense to try restarting a crashed game
  use GenServer, restart: :temporary
  alias FfcEx.{DmCache, Game, Game.Card, Game.Deck, Lobby, PlayerRouter}
  alias Nostrum.Struct.{Embed, Embed.Field, Embed.Thumbnail, User}
  alias Nostrum.Api
  require Logger
  require Card

  @enforce_keys [:id, :players, :hands, :spectators, :deck, :current_card, :drawn_card]
  defstruct @enforce_keys

  @type t() :: %__MODULE__{
          id: Lobby.id(),
          players: [User.id()],
          hands: %{required(User.id()) => {Deck.t()}},
          spectators: [User.id()],
          deck: Deck.t(),
          current_card: Card.t() | nil,
          drawn_card: Cart.t() | nil
        }

  @spec playercount_valid?(non_neg_integer()) :: boolean()
  def playercount_valid?(count) do
    count in 2..10
  end

  @spec start_game(pid()) :: :ok | {:cannot_dm, [User.id()]}
  def start_game(game) do
    GenServer.call(game, :start_game, :infinity)
  end

  @spec is_part_of?(pid(), User.id()) :: boolean()
  def is_part_of?(game, user) do
    GenServer.call(game, {:is_part_of, user})
  end

  def do_cmd(game, user, cmd) do
    if is_part_of?(game, user) do
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
      drawn_card: nil
    }

    {:ok, game}
  end

  @impl true
  def handle_cast({user_id, :state}, game) do
    # TODO: Debug command!
    tell(user_id, "```elixir\n#{inspect(game, pretty: true, limit: 10, width: 120)}```")
    {:noreply, game}
  end

  @impl true
  def handle_cast({user_id, {:play, card_str}}, game) do
    if current_player(game) != user_id do
      tell(user_id, "You can't use this when it's not your turn!")
      {:noreply, game}
    else
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

      true ->
        {:noreply, do_draw(game, user_id)}
    end
  end

  @impl true
  def handle_cast({user_id, :status}, game) do
    field_text =
      game.players
      |> Enum.map(fn user_id -> {username(user_id), length(game.hands[user_id])} end)
      |> Enum.map(fn {uname, cards} -> "#{uname} - #{cards} cards" end)
      |> Enum.join("\n")

    embed =
      %Embed{
        title: "Game status",
        fields: [
          %Field{name: "Current card", value: Card.to_string(game.current_card)},
          %Field{name: "Players", value: field_text <> "\n**Play continues downwards**"}
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
    broadcast_except(game, [user_id], "*\##{game.id}* **#{uname_discrim(user_id)}:** #{chat_msg}")
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
        "#{username(user_id)} wished to remind you it's your turn to play by giving you a gentle" <>
          " nudge. *Nudge!*"
      )

      tell(user_id, "I've nudged #{username(current_player(game))}.")
      {:noreply, game}
    end
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
          Welcome to Final Fanstastic Card!

          [Click here to view game instructions!](https://vrabbers.github.io/ffc_ex/game_instructions.html)
          """,
          thumbnail: %Thumbnail{url: "attachment://draw.png"}
        }
        |> put_id_footer(game)

      broadcast(game, embeds: [embed], files: ["./img/draw.png"])
      PlayerRouter.add_all_to(participants(game), game.id)

      do_turn(game)

      {:reply, :ok, game}
    else
      {:stop, :error, {:cannot_dm, for({{:error, _}, user} <- responses, do: user)}, game}
    end
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
    for user <- users do
      tell(user, message)
    end

    :ok
  end

  defp tell(user, message) do
    {:ok, dm_channel} = DmCache.create(user)

    case Api.create_message(dm_channel, message) do
      {:error, error} ->
        Logger.error(
          "Error telling #{inspect(user)} message: #{inspect(message)}: #{inspect(error)}"
        )

      {:ok, _} ->
        :noop
    end
  end

  defp put_id_footer(embed, game) do
    embed = Embed.put_footer(embed, "Game \##{game.id}")

    unless embed.color do
      Embed.put_color(embed, Application.fetch_env!(:ffc_ex, :color))
    else
      embed
    end
  end

  defp do_turn(game) do
    current_player = current_player(game)

    embed =
      %Embed{
        title: "Your turn!",
        fields: [
          %Field{name: "Current card", value: Card.to_string(game.current_card)},
          %Field{
            name: "Your hand",
            value: formatted_hand(game.hands[current_player], game.current_card)
          }
        ]
      }
      |> put_id_footer(game)

    embed =
      if !Enum.any?(game.hands[current_player], &Card.can_play_on?(game.current_card, &1)) do
        Embed.put_field(
          embed,
          "Draw",
          "You cannot play any of your cards. As such, use `draw` to draw a card from the deck",
          false
        )
      else
        embed
      end

    tell(current_player, embeds: [embed])
    game
  end

  defp do_play_card(game, player_id, card) do
    player_hand = game.hands[player_id]

    cond do
      !Deck.has_card?(player_hand, card) ->
        tell(player_id, "You don't have this card!")
        game

      game.drawn_card != nil && !Card.equal_nw?(game.drawn_card, card) ->
        tell(player_id, "You must play the card you've drawn!")
        game

      !Card.can_play_on?(game.current_card, card) ->
        tell(player_id, "This card can't be played! Cards that can be played are in **bold**.")
        game

      true ->
        broadcast(game,
          embeds: [
            %Embed{
              title: "Card played!",
              description: "#{username(player_id)} has played a **#{Card.to_string(card)}**"
            }
            |> put_id_footer(game)
          ]
        )

        card_special_message(game, card)

        new_deck = Deck.put_back(game.deck, game.current_card)
        {_, new_hand} = Deck.remove(player_hand, card)
        new_hands = Map.put(game.hands, player_id, new_hand)

        game = %Game{game | deck: new_deck, hands: new_hands, current_card: card}

        game = do_card_effect(game, card)

        do_turn(game)
        game
    end
  end

  defp do_draw(game, player_id) do
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
      files: ["./img/draw.png"]
    )

    new_hand = Deck.put_back(player_hand, drawn_card)
    new_hands = Map.put(game.hands, player_id, new_hand)
    game = %Game{game | hands: new_hands, deck: deck}

    if Card.can_play_on?(game.current_card, drawn_card) do
      tell(player_id,
        embeds: [
          %Embed{
            title: "Card drawn",
            description:
              "You have drawn a **#{Card.to_string(drawn_card)}**. As you may play this card, " <>
                "use `play #{Card.to_string(drawn_card)}` to play it.",
            thumbnail: %Thumbnail{url: "attachment://draw.png"}
          }
          |> put_id_footer(game)
        ],
        files: ["./img/draw.png"]
      )

      %Game{game | drawn_card: drawn_card}
    else
      tell(player_id,
        embeds: [
          %Embed{
            title: "Card drawn",
            description: "You have drawn a **#{Card.to_string(drawn_card)}**.",
            thumbnail: %Thumbnail{url: "attachment://draw.png"}
          }
          |> put_id_footer(game)
        ],
        files: ["./img/draw.png"]
      )

      game |> advance_player() |> do_turn()
    end
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
          files: ["./img/skip.png"]
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
          files: ["./img/reverse.png"]
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
          files: ["./img/#{col}.png"]
        )

      _ ->
        :noop
    end
  end

  defp do_card_effect(game, card) do
    case card do
      {x, no} when Card.is_cardno(no) or x == :wildcard ->
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
        game |> draw_next(2) |> advance_twice()

      {:wildcard_draw4, _} ->
        game |> draw_next(4) |> advance_twice()
    end
  end

  defp draw_next(game, amt) do
    draw_str =
      case amt do
        2 -> "draw2.png"
        4 -> "draw4.png"
        6 -> "draw6.png"
        _ -> "draw.png"
      end

    next_player = next_player(game)

    broadcast(game,
      embeds: [
        %Embed{
          title: "Drawn cards",
          description: "#{uname_discrim(next_player)} has been forced to draw #{amt} cards!",
          thumbnail: %Thumbnail{url: "attachment://#{draw_str}"}
        }
        |> put_id_footer(game)
      ],
      files: ["./img/#{draw_str}"]
    )

    {drawn, deck} = Deck.get_many(game.deck, amt)
    hands = Map.update!(game.hands, next_player, &(drawn ++ &1))
    %Game{game | deck: deck, hands: hands}
  end

  defp next_player(game) do
    Enum.at(game.players, 1)
  end

  defp formatted_hand(hand, current_card) do
    hand
    |> Enum.map(fn card -> {Card.to_string(card), Card.can_play_on?(current_card, card)} end)
    |> Enum.sort_by(fn {card, _} -> card end, :asc)
    |> Enum.map(fn
      {card, true} -> "**#{card}**"
      {card, false} -> card
    end)
    |> Enum.join(" ")
  end

  defp current_player(game) do
    List.first(game.players)
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
end

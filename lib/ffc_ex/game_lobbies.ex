defmodule FfcEx.GameLobbies do
  use Agent

  def start_link([]) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  defmodule Lobby do
    @enforce_keys [:id, :channel, :starting_user]
    defstruct id: nil, channel: nil, starting_user: nil, players: [], spectators: []

    @type t() :: %__MODULE__{
            channel: Nostrum.Struct.Channel.id(),
            starting_user: Nostrum.Snowflake.t(),
            players: [Nostrum.Snowflake.t()],
            spectators: [Nostrum.Snowflake.t()]
          }
  end
end

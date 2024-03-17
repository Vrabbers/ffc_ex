defmodule FfcEx.Lobby do
  alias Nostrum.Struct.User

  @type id() :: non_neg_integer()
  @enforce_keys [:id, :starting_user]
  defstruct id: nil, starting_user: nil, players: [], spectators: [], house_rules: []

  @type t() :: %__MODULE__{
          id: id(),
          starting_user: User.id(),
          players: [User.id()],
          spectators: [User.id()],
          house_rules: [atom()]
        }
end

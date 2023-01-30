defmodule FfcEx.GameLobbiesTest do
  use ExUnit.Case, async: true

  alias FfcEx.GameLobbies

  test "Joining lobby" do
    {:new, x, _timeout} = GameLobbies.join(1, 1)
    {:joined, y} = GameLobbies.join(1, 2)
    assert x == y
    {:already_joined, _} = GameLobbies.join(1, 1)
    {:already_joined, _} = GameLobbies.join(1, 2)
    {:new, z, _timeout} = GameLobbies.join(2, 1)
    assert z > y
  end

  test "Spectate lobby" do
    assert GameLobbies.spectate(1, 1) == :cannot_spectate
    {:new, x, _timeout} = GameLobbies.join(1, 1)
    assert GameLobbies.spectate(1, 1) == :cannot_spectate
    {:spectating, y} = GameLobbies.spectate(1, 2)
    assert x == y
    assert GameLobbies.spectate(1, 2) == :cannot_spectate
  end

  test "Close lobby" do
    assert GameLobbies.close(1, 1) == :cannot_close
    {:new, x, _timeout} = GameLobbies.join(1, 1)
    assert GameLobbies.close(1, 1) == :player_count_invalid
    {:joined, ^x} = GameLobbies.join(1, 2)
    assert GameLobbies.close(1, 2) == :cannot_close
    {:closed, _} = GameLobbies.close(1, 1)
  end
end

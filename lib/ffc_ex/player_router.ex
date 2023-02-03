defmodule FfcEx.PlayerRouter do
  use Agent

  def start_link([]) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def lookup(user) do
    Agent.get(__MODULE__, fn map -> map[user] end)
  end

  def add_all_to(users, id) do
    Agent.update(__MODULE__, fn map -> Map.merge(map, Map.from_keys(users, id)) end)
  end

  def set_for(user, id) do
    Agent.update(__MODULE__, &Map.put(&1, user, id))
  end
end

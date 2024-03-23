defmodule FfcEx.DmCache do
  use GenServer

  alias Nostrum.{Api, Struct.Channel, Struct.User}

  @spec start_link([]) :: {:ok, pid}
  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec create(User.id()) :: {:ok, Channel.id()} | :error
  def create(user) do
    case :ets.lookup(__MODULE__, user) do
      [{^user, channel}] -> {:ok, channel}
      [] -> GenServer.call(__MODULE__, {:create, user})
    end
  end

  @impl true
  def init([]) do
    table = :ets.new(__MODULE__, [:named_table])
    {:ok, table}
  end

  @impl true
  def handle_call({:create, user}, _from, table) do
    case Api.create_dm(user) do
      {:ok, channel} ->
        :ets.insert(table, {user, channel.id})
        Process.send_after(self(), {:invalidate, user}, :timer.hours(1))
        {:reply, {:ok, channel.id}, table}

      {:error, _} ->
        {:reply, :error, table}
    end
  end

  @impl true
  def handle_info({:invalidate, user}, table) do
    :ets.delete(table, user)
    {:noreply, table}
  end
end

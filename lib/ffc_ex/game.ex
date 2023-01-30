defmodule FfcEx.Game do
  use GenServer

  @spec playercount_valid?(non_neg_integer()) :: boolean()
  def playercount_valid?(count) do
    count >= 2 && count <= 10
  end

  def start_link([]) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init([]) do
    {:ok, {}}
  end
end

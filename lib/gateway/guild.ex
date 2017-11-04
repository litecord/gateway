defmodule Guild do
  use GenServer

  def start() do
    GenServer.start(__MODULE__, :ok, [name: :guilds])
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def all_guilds(user_id) do
  end
end

defmodule GenGuild do
  use GenServer
end

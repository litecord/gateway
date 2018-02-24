defmodule Guild.Registry do
  @moduledoc """
  Guild Registry GenServer.

  This handles a mapping between guild IDs
  and GenGuilds which are tied in to those IDs.

  If a guild doesn't have a related GenGuild,
  one is created automatically.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    Logger.info "starting guild registry"
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## client api
  @doc """
  Get a GenGuild process, given its ID.

  This will always work.
  """
  @spec get(String.t) :: pid()
  def get(guild_id) do
    GenServer.call(__MODULE__, {:get, guild_id})
  end
  
  ## server callbacks
  def init(opts) do
    {:ok, %{}}
  end

  def handle_call({:get, guild_id}, _from, state) do
    Logger.info "getting genguild for #{inspect guild_id}"
    case Map.get(state, guild_id) do
      nil ->
        # create new GenGuild
        {:ok, pid} = GenGuild.start(guild_id)
        {:reply, pid, Map.put(state, guild_id, pid)}
      g ->
        # return what we have available
        {:reply, g, state}
    end
  end
end


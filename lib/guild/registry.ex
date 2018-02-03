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

  def start_link(state) do
    Logger.info "starting guild registry"
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  ## client api
  @doc """
  Get a GenGuild process, given
  its ID.
  """
  @spec get(String.t) :: pid()
  def get(guild_id) do
    GenServer.call(__MODULE__, {:get, guild_id})
  end
  
  ## server callbacks
  def init(state) do
    {:ok, state}
  end

  def handle_call({:get, guild_id}, state) do
    case Map.get(state, guild_id) do
      nil ->
        # create new GenGuild
        Logger.info "Creating new GenGuild for #{guild_id}"
        {:ok, pid} = GenGuild.start_link(guild_id)
        {:reply, pid, Map.put(state, guild_id, pid)}
      g ->
        # return what we have available
        {:reply, g, state}
    end
  end
end


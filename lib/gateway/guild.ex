defmodule Guild do
  @moduledoc """
  General functions for fetching guild data.
  """
  import Ecto.Query, only: [from: 2]
  
  @spec get_guilds(String.t) :: [String.t]
  def get_guilds(user_id) do
    query = from m in "members",
      where: m.user_id == ^user_id,
      select: m.guild_id

    Gateway.Repo.all(query)
  end
end

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
  @spec get(String.t) :: GenGuild
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

defmodule GenGuild do
  @moduledoc """
  Generic Guild GenServer (GenGuild)

  This holds generic information about a specific guild,
  like which users are subscribed to the guild's events.
  """
  use GenServer
  require Logger
  
  def start_link(guild_id) do
    Logger.info "starting GenGuild with guild_id #{guild_id}"
    GenServer.start_link(__MODULE__, guild_id, name: __MODULE__)
  end

  # client api
  @spec subscribe(pid(), String.t) :: :ok
  def subscribe(pid, uid) do
    GenServer.cast(pid, {:sub, uid})
  end

  @spec unsubscribe(pid(), String.t) :: :ok
  def unsubscribe(pid, uid) do
    GenServer.cast(pid, {:unsub, uid})
  end

  @doc """
  Get all users subscribed to a guild's events
  """
  @spec get_subs(pid()) :: [integer()]
  def get_subs(pid) do
    GenServer.call(pid, {:get_subs})
  end

  ## server callbacks
  def init(guild_id) do
    {:ok, %{
        id: guild_id,
        subscribed: []
     }}
  end

  ## calls
  def handle_call({:get_subs}, _from, state) do
    {:reply, state.subscribed, state}
  end

  ## casts
  def handle_cast({:sub, user_id}, state) do
    uids = state.subscribed
    {:noreply, %{state |
                 subscribed: [user_id | uids]
                }
    }
  end

  def handle_cast({:unsub, user_id}, state) do
    uids = state.subscribed
    {:noreply, %{state |
                 subscribed: List.delete(uids, user_id)
                }
    }
  end

end

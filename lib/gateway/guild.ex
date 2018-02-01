defmodule Guild do
  @moduledoc """
  General functions for fetching guild data.
  """
  import Ecto.Query, only: [from: 2]
  alias Gateway.Repo

  @doc """
  Convert a guild struct to a guild map
  """
  @spec from_struct(Ecto.Struct.t()) :: Map.t
  def from_struct(struct) do
    struct
    |> Map.from_struct
    |> Map.delete(:__meta__)
  end

  @doc """
  Query one guild, based on its ID.
  """
  @spec get_guild(String.t) :: Ecto.Struct.t() | nil
  def get_guild(guild_id) do
    query = from g in Gateway.Guild,
      where: g.id == ^guild_id

    Repo.one(query)
  end
  
  @doc """
  Get all guild IDs a user is on, given its ID.
  """
  @spec get_guilds(String.t) :: [String.t]
  def get_guilds(user_id) when is_binary(user_id) do
    query = from m in "members",
      where: m.user_id == ^user_id,
      select: m.guild_id

    Gateway.Repo.all(query)
  end
  
  @doc """
  Get all the guilds that are tied to a websocket connection
  (shard).
  """
  def get_guilds(pid) when is_pid(pid) do
    user_id = State.get(pid, :user_id)
    shard_id = State.get(pid, :shard_id)
    shard_total = State.get(pid, :shard_total)

    user_id
    |> get_guilds
    |> Enum.filter(fn guild_id ->
      {guild_id_int, _} = guild_id |> Integer.parse
      State.Registry.get_shard(guild_id, shard_total) == shard_id
    end)
  end

  @doc """
  Map a list of gulid IDs to maps that have its data.

  Commonly used across the websocket.
  """
  @spec map_guild_data([String.t]) :: [Map.t]
  def map_guild_data(guild_ids) do
    guild_ids
    |> Enum.map(fn guild_id ->
      struct = guild_id
               |> Guild.get_guild

      case struct do
        nil -> nil
        s -> s |> Guild.from_struct
      end
    end)
    |> Enum.filter(fn el ->
      el != nil
    end)
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

  The general idea is that a GenGuild is implementing the
  sub part of pub/sub.
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
  @spec get_subs(pid()) :: [String.t]
  def get_subs(pid) do
    GenServer.call(pid, {:get_subs})
  end

  @spec get_presences(pid()) :: [Presence.Struct.t]
  def get_presences(pid) do
    GenServer.call(pid, {:get_presences})
  end

  ## server callbacks
  def init(guild_id) do
    {:ok, %{
      id: guild_id, # String.t
      subscribed: [], # [String.t]
      status: %{} # %{String.t => Presence.Status.t}
      presences: %{} # %{String.t => [Presence.Struct.t]}
    }}
  end

  ## calls
  def handle_call({:get_subs}, _from, state) do
    {:reply, state.subscribed, state}
  end

  def handle_call({:get_presences}, _from, state) do
    {:reply, state.presences, state}
  end

  ## casts
  @doc """
  Subscribe a user to the guild.
  """
  def handle_cast({:sub, user_id}, state) do
    uids = state.subscribed
    {:noreply, %{state |
                 subscribed: [user_id | uids]
                }
    }
  end

  @doc """
  Unsubscribe a user from the guild.
  """
  def handle_cast({:unsub, user_id}, state) do
    uids = state.subscribed
    {:noreply, %{state |
                 subscribed: List.delete(uids, user_id)
                }
    }
  end

end

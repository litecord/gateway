defmodule Guild do
  @moduledoc """
  General functions for guilds
  """
  import Ecto.Query, only: [from: 2]
  
  @spec all_guilds(String.t) :: [String.t]
  def all_guilds(user_id) do
    query = from m in "members",
      where: m.user_id == ^user_id,
      select: m.guild_id

    Gateway.Repo.all(query)
  end
end

defmodule Guild.Registry do
  use GenServer
  require Logger

  def start_link(state) do
    Logger.info "starting guild registry"
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  ## client api
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
  use GenServer
  require Logger
  
  def start_link(guild_id) do
    Logger.info "starting GenGuild with guild_id #{guild_id}"
    GenServer.start_link(__MODULE__, guild_id, name: __MODULE__)
  end

  # client api
  def subscribe(pid, uid) do
    GenServer.cast(pid, {:sub, uid})
  end

  def unsubscribe(pid, uid) do
    GenServer.cast(pid, {:unsub, uid})
  end

  @doc """
  Get all users subscribed to a guild
  """
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

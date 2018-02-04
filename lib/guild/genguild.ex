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
  
  def start(guild_id) do
    Logger.info "starting GenGuild with guild_id #{inspect guild_id}"
    GenServer.start(__MODULE__, guild_id)
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

  @spec add_presence(pid(), Types.state_pid) :: :ok
  def add_presence(pid, state_pid) do
    GenServer.call(pid, {:add_presence, state_pid})
  end

  @doc """
  Get a user's presence.

  This works by selecting the oldest (lowest timestamp) out
  from all PIDs that were added to the guild (and hence
  are tied in to the user)
  """
  @spec get_presence(pid(), String.t) :: {:ok, Presence.Struct} | {:error, String.t}
  def get_presence(pid, user_id) do
    GenServer.call(pid, {:get_presence, user_id})
  end

  @spec remove_presence(pid(), pid()) :: :ok | {:error, String.t}
  def remove_presence(pid, state_pid) do
    GenServer.call(pid, {:drop_presence, state_pid})
  end

  ## server callbacks
  def init(guild_id) do
    {:ok, %{
      id: guild_id, # String.t
      subscribed: [], # [String.t]

      status: %{}, # %{String.t => Presence.Status.t}
      presences: %{} # %{String.t => {pid(), Integer.t}}
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

  def handle_call({:add_presence, pid}, _from, state) do
    user_id = State.get(pid, :user_id)
    data = Map.get(state.presences, user_id, [])

    timestamp_pid = {
      pid,
      :erlang.unique_integer([:monotonic])
    }

    new_data = [timestamp_pid | data]

    {:reply, :ok, %{state |
      presences: Map.put(state.presences, user_id, new_data)
    }}
  end

  def handle_call({:get_presence, user_id}, _from, state) do
    presences = state.presences
    data = Map.get(presences, user_id)
    if data == nil do
      {:reply, {:error, "user not found"}, state}
    else
      oldest = Enum.min_by(data, fn tup ->
        elem tup, 1
      end)

      {pid, timestamp} = oldest
      presence = State.get(pid, :presence)
      {:reply, presence, state}
    end
  end

end

defmodule Presence do
  use GenServer

  def start() do
    GenServer.start(__MODULE__, :ok, [name: :presence])
  end
  
  def default_presence() do
    default_presence("online")
  end

  def default_presence(status) do
    %{status: status,
      type: 0,
      name: nil,
      url: nil
    }
  end

  # client API
  def dispatch_users(state_pid, presence) do
    GenServer.cast(:presence, {:dispatch_users, state_pid, presence})
  end

  def subscribe(state_pid, guild_id) do
    GenServer.cast(:presence, {:sub, state_pid, guild_id})
  end

  def unsubscribe(state_pid, guild_id) do
    GenServer.cast(:presence, {:unsub, state_pid, guild_id})
  end

  # Server callbacks
  def init(:ok) do
    {:ok, %{}}
  end

  @doc """
  Dispatch a presence object to all subscribed users
  that share mutual servers with another user
  """
  def handle_cast({:dispatch_users, state_pid, presence}, state) do
    Guild.mutual_users_sub(state_pid)
    |> Enum.each(fn other_pid ->
      Gateway.State.send_ws(other_pid,
	{:text, Gateway.Websocket.encode(presence, state_pid)}
      )
    end)

    {:noreply, state}
  end

  # Subscribe and unsubscribe from all guilds
  def handle_cast({:subscribe, state_pid, :all}, state) do
    user_id = Gateway.State.get(state_pid, :user_id)
    Enum.each(Guild.all_guilds(user_id), fn guild ->
      GenServer.cast(:presence, {:subscribe, state_pid, guild.id})
    end)
    {:noreply, state}
  end

  def handle_cast({:unsubscribe, state_pid, :all}, state) do
    user_id = Gateway.State.get(state_pid, :user_id)

    Enum.each(Guild.all_guilds(user_id), fn guild ->
      GenServer.cast(:presence, {:unsubscribe, state_pid, guild.id})
    end)
    {:noreply, state}
  end

  # Subscribe and unsubscribe to a specific guild
  def handle_cast({:sub, state_pid, guild_id}, state) do
    # First, get the guild genserver which
    # handles the subsribed state to the guild

    # Guild.Registry.get should spin a new
    # GenGuild GenServer if it isn't found
    guild_pid = Guild.Registry.get(guild_id)

    # Signal the guild we have this user to be in its
    # subscribed state
    user_id = Gateway.State.get(state_pid, :user_id)

    GenGuild.subscribe(guild_pid, user_id)
    {:noreply, state}
  end

  def handle_cast({:unsub, state_pid, guild_id}, state) do
    # Follow the same strategy, but unsubscribe
    guild_pid = Guild.Registry.get(guild_id)
    uid = Gateway.State.get(state_pid, :user_id)

    GenGuild.unsubscribe(guild_pid, uid)
    {:noreply, state}
  end
end

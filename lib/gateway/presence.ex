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

  # Things that use GenServer
  def dispatch_users(state_pid, presence) do
    GenServer.cast(:presence, {:dispatch_users, state_pid, presence})
  end

  def subscribe(state_pid, guild_id) do
    GenServer.cast(:presence, {:subscribe, state_pid, guild_id})
  end

  def unsubscribe(state_pid, guild_id) do
    GenServer.cast(:presence, {:subscribe, state_pid, guild_id})
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
  def handle_cast({:subscribe, state_pid, guild_id}, state) do
    guild_pid = GuildRegistry.get(guild_id)
    uid = Gateway.State.get(state_pid, :user_id)

    GenGuild.subscribe(guild_pid, uid)
    {:noreply, state}
  end

  def handle_cast({:unsubscribe, state_pid, guild_id}, state) do
    guild_pid = GuildRegistry.get(guild_id)
    uid = Gateway.State.get(state_pid, :user_id)

    GenGuild.unsubscribe(guild_pid, uid)
    {:noreply, state}
  end
end

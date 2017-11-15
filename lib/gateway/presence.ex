defmodule Presence do
  use GenServer
  require Logger

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

  @spec all_guilds(pid(), :subscribe | :unsubscribe) :: nil
  @doc """
  Send an sub/unsub message to all guilds
  a user is in.
  """
  defp all_guilds(state_pid, atom) do
    user_id = State.get(state_pid, :user_id)

    Guild.get_guilds(user_id)
    |> Enum.each(fn guild_id ->
      # send to myself
      GenServer.cast(:presence, {atom, user_id, guild_id})
    end)
  end

  @doc """
  Dispatch a presence object to all subscribed users
  that share mutual servers with another user
  """
  def handle_cast({:dispatch_users, state_pid, presence}, state) do
    # First, fetch all the guilds the user is in
    user_id = State.get(state_pid, :user_id)
    guilds = Guild.get_guilds(user_id)

    # Now, with a list of guild structs, we can
    # ask the guild registry to fetch all
    # subscribed users in the guild

    guilds
    |> Enum.each(fn guild_id ->
      guild_pid = Guild.Registry.get(guild_id)
      user_ids = GenGuild.get_subs(guild_pid)

      # For each subscribed user in the guild,
      # get the state object that links to them
      # and send the presence data to it
      # (via websocket)
      Enum.each(user_ids, fn user_id ->
	case State.Registry.get(user_id) do
	  {:ok, state_pid} ->
	    State.send_ws(state_pid,
	      {:text, Gateway.Websocket.encode(presence, state_pid)}
	    )
	  {:error, err} ->
	    Logger.warn "Failed to dispatch to #{user_id}: #{err}"
	end

      end)
    end)
    
    {:noreply, state}
  end

  # Subscribe and unsubscribe from all guilds

  def handle_cast({:subscribe, state_pid, :all}, state) do
    all_guilds(state_pid, :subscribe)
    {:noreply, state}
  end

  def handle_cast({:unsubscribe, state_pid, :all}, state) do
    all_guilds(state_pid, :unsubscribe)
    {:noreply, state}
  end

  # Subscribe and unsubscribe to a specific guild
  def handle_cast({:sub, user_id, guild_id}, state) do
    # First, get the guild genserver which
    # handles the subsribed state to the guild

    # Guild.Registry.get should spin a new
    # GenGuild GenServer if it isn't found
    guild_pid = Guild.Registry.get(guild_id)

    # Signal the guild we have this user to be in its
    # subscribed state
    GenGuild.subscribe(guild_pid, user_id)
    {:noreply, state}
  end

  def handle_cast({:unsub, user_id, guild_id}, state) do
    # Follow the same strategy, but unsubscribe
    guild_pid = Guild.Registry.get(guild_id)
    GenGuild.unsubscribe(guild_pid, user_id)
    {:noreply, state}
  end
end

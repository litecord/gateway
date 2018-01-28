defmodule Presence do
  @moduledoc """
  Presence GenServer.

  This module manages presence information
  for all users currently connected and identified
  to the websocket.

  This also manages dispatching of the `PRESENCE_UPDATE`
  event to other clients which are subscribed to the
  guilds they share with other users.
  """
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


  # client api
  @doc """
  Subscribe to guilds.
  """
  @spec subscribe(pid(), [String.t]) :: nil
  def subscribe(state_pid, guild_ids) do
    user_id = State.get(state_pid, :user_id)

    Enum.each(guild_ids, fn guild_id ->
      # for each guild, contact guild registry
      guild_pid = Guild.Registry.get(guild_id)

      GenGuild.subscribe(guild_pid, user_id)
    end)
  end

  @doc """
  Unsubscribe to guilds.
  """
  @spec unsubscribe(pid(), [String.t]) :: nil
  def unsubscribe(state_pid, guild_ids) do
    user_id = State.get(state_pid, :user_id)

    Enum.each(guild_ids, fn guild_id ->
      # for each guild, contact guild registry
      guild_pid = Guild.Registry.get(guild_id)

      GenGuild.unsubscribe(guild_pid, user_id)
    end)
  end

  @doc """
  Dispatch a presence object to a single user.
  """
  @spec dispatch_user(Map.t, String.t) :: nil
  def dispatch_user(presence, user_id) do
    case State.Registry.get(user_id) do
      {:ok, state_pid} ->
        State.send_ws(state_pid,
                      {:text, Gateway.Websocket.encode(presence, state_pid)}
        )
      {:error, err} ->
        Logger.warn fn -> 
          "Failed to dispatch to #{user_id}: #{err}"
        end
    end
  end

  # Server callbacks
  def init(_) do
    {:ok, %{}}
  end

  @doc """
  Dispatch a presence object to all subscribed users
  that share mutual servers with another user
  """
  def handle_cast({:dispatch_users, state_pid, presence}, state) do
    # First, fetch all the guilds the user is in
    user_id = State.get(state_pid, :user_id)
    guild_ids = Guild.get_guilds(user_id)

    guild_ids
    |> Enum.each(fn guild_id ->
      guild_pid = Guild.Registry.get(guild_id)
      GenGuild.dispatch(guild_pid, presence)

      user_ids = GenGuild.get_subs(guild_pid)

      # For each subscribed user in the guild,
      # get the state object that links to them
      # and send the presence data to it
      # (via websocket)
      Enum.each(user_ids, fn user_id ->
        dispatch_user(presence, user_id)
      end)
    end)
    
    {:noreply, state}
  end

end

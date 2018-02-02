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

  defmodule Struct do
    defstruct [:ws_pid, :user_id, :game]
  end

  defmodule Status do
    defstruct [:ws_pid, :status]
  end

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
      GenGuild.add_presence(guild_pid, state_pid)
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
  Dispatch data to a guild.

  The generator function receives the guild pid and the user shard state pid
  """
  @spec dispatch(String.t, ((pid(), pid()) -> Map.t)) :: nil
  def dispatch(guild_id, generator) do
    guild_pid = Guild.Registry.get(guild_id)

    if guild_pid != nil do
      # get all guild subscribed users (list of user ids)
      # then get the pids of the shards for each user
      # then flatten it all
      user_pids = guild_pid
                  |> GenGuild.get_subs
                  |> Enum.map(&(State.Registry.get(&1, guild_id)))
                  |> Enum.flatten

      Enum.each(user_pids, fn state_pid ->
        data = generator(guild_pid, state_pid)
        State.ws_send(pid, {:send_map, data})
      end)
    end

    nil
  end

  # Server callbacks
  def init(_) do
    {:ok, %{}}
  end
end

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
    # TODO: finish struct
    defstruct [:user_id, :shard_id, :shard_total,
               :status, ]
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
  """
  @spec dispatch(String.t, pid(), Map.t, :guild) :: nil
  def dispatch(guild_id, pid, data, :guild) do
    guild_pid = Guild.Registry.get(guild_id)

    if guild_pid != nil do
      # TODO: add a special function specially for presence updates
      # presence_packet = Gateway.Websocket.payload(:presence_update, pid, presence)

      user_ids = GenGuild.get_subs(guild_pid)

      user_pids = user_ids
                  |> Enum.map(fn user_id ->
                    State.Registry.get(user_id, guild_id)
                  end)
                  |> Enum.flatten

      Enum.each(user_pids, fn pid ->
        State.ws_send(pid, {:send_map, data})
      end)
    end
  end

  # Server callbacks
  def init(_) do
    {:ok, %{}}
  end
end

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
  alias Gateway.Ready

  defmodule Activity do
    @moduledoc """
    Describes an activity struct.
    """
    @enforce_keys [:name]
    defstruct name: "",
      type: 0,
      url: nil
  end

  defmodule Status do
    @enforce_keys [:ws_pid]
    defstruct ws_pid: nil,
      status: "online"
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
  @spec subscribe(pid(), [String.t]) :: :ok
  def subscribe(state_pid, guild_ids) do
    user_id = State.get(state_pid, :user_id)

    # guild_ids = ["1"]

    Enum.each(guild_ids, fn guild_id ->
      # for each guild, contact guild registry
      guild_pid = Guild.Registry.get(guild_id)

      GenGuild.subscribe(guild_pid, user_id)
      GenGuild.add_presence(guild_pid, state_pid)

      # yes, this is very innefficient
      # sending a presence update on every
      # guild subscribe for any shard.
      dispatch(guild_id, fn guild_pid, state_pid ->
        user_id = State.get(state_pid, :user_id)
        Logger.debug "uid #{inspect user_id}"
        userdata = user_id
                   |> Ready.user_info
                   |> User.from_struct

        state_presence = State.get(state_pid, :presence)

        {"PRESENCE_UPDATE" ,%{
          user: userdata,
          roles: [],
          guild_id: guild_id,
          game: state_presence["game"] |> Map.from_struct,
          status: state_presence["status"].status,
        }}
      end)
    end)
  end

  @doc """
  Unsubscribe to guilds.
  """
  @spec unsubscribe(pid(), [String.t]) :: :ok
  def unsubscribe(state_pid, guild_ids) do
    user_id = State.get(state_pid, :user_id)

    Enum.each(guild_ids, fn guild_id ->
      guild_pid = Guild.Registry.get(guild_id)

      GenGuild.unsubscribe(guild_pid, user_id)
      GenGuild.remove_presence(guild_pid, state_pid)
    end)
  end

  @doc """
  Dispatch data to a guild.

  The generator function receives the guild pid and the user shard state pid
  """
  @spec dispatch(String.t, ((pid(), pid()) -> {String.t, Map.t})) :: :ok
  def dispatch(guild_id, generator) do
    guild_pid = Guild.Registry.get(guild_id)

    if guild_pid != nil do
      # get all guild subscribed users (list of user ids)
      # then get the pids of the shards for each user
      # then flatten it all
      user_pids = guild_pid
                  |> GenGuild.get_subs
                  |> Enum.map(&(State.Registry.get(&1, guild_id)))
                  |> List.flatten

      Logger.debug fn ->
        "Dispatching to #{Enum.count(user_pids)} user pids"
      end

      Enum.each(user_pids, fn state_pid ->
        data = generator.(guild_pid, state_pid)
        State.ws_send(state_pid, {:send_event, data})
      end)
    end

    :ok
  end

  # Server callbacks
  def init(_) do
    {:ok, %{}}
  end
end

defmodule Gateway.SharedState do
  @moduledoc """
  This module defines a way
  for different parts of the gateway
  to request information about others.
  """
  require Logger

  def start_link() do
    :ets.new(:gs_state, [:set, :named_table, :protected])
  end

  @doc """
  Insert something into the shared state.
  """
  def set(key, value) do
    Logger.debug "gw_state set: #{inspect key} -> #{inspect value}"
    :ets.insert(:gs_state, {key, value})
  end

  @doc """
  Get a value from an unique key.
  """
  def simple_get(key) do
    :ets.lookup(:gs_state, key)
  end

  @doc """
  More complex version of simple_get\1.
  """
  def all_keys(user_id) do
    :ets.match(:gs_state, {"_", %{user_id: user_id}})
  end

  @doc """
  Get all PIDs of gateway connections tied to a user
  """
  def get_conns(state) do
    Stream.map(all_keys(state.user_id), fn {pid, _state} ->
      pid
    end)
  end
end

defmodule Gateway.State do
  use GenServer
  require Logger
  
  defmodule StateStruct do
    defstruct [:session_id, :token, :user_id, :events,
	       :recv_seq, :sent_seq, :heartbeat,
	       :encoding, :compress, :shard_id, :sharded,
	       :properties, :large]
  end
  
  def start_link() do
    GenServer.start_link(__MODULE__, %StateStruct{events: [],
						  recv_seq: 0,
						  sent_seq: 0,
						  heartbeat: false,
						  encoding: "json",
						  compress: false,
						  sharded: false})
  end

  def get(pid, key) do
    GenServer.call(pid, {:get, key})
  end

  def put(pid, key, value) do
    GenServer.call(:put, pid, {key, value})
  end

  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end

  def handle_call({:put, key, value}, _from, state) do
    {:noreply, Map.put(state, key, value)}
  end
end

defmodule State do
  use GenServer
  require Logger
  
  defmodule StateStruct do
    defstruct [:session_id, :token, :user_id, :events,
	       :recv_seq, :sent_seq, :heartbeat,
	       :encoding, :compress, :shard_id, :sharded,
	       :properties, :large, :parent]
  end
  
  def start(parent) do
    Logger.info "Spinning up state GenServer"
    GenServer.start(__MODULE__, %StateStruct{parent: parent,
					     events: [],
					     recv_seq: 0,
					     sent_seq: 0,
					     heartbeat: false,
					     encoding: "json",
					     compress: false,
					     sharded: false})
  end

  # Client api
  def get(pid, key) do
    # Logger.info "state get: #{inspect pid} -> #{inspect key}"
    GenServer.call(pid, {:get, key})
  end

  def put(pid, key, value) do
    # Logger.info "state put #{inspect pid} -> #{inspect key} : #{inspect value}"
    GenServer.cast(pid, {:put, key, value})
  end

  def send_ws(pid, frame) do
    GenServer.cast(pid, {:send, frame})
  end

  # Server callbacks
  def init(state) do
    {:ok, state}
  end

  def handle_call({:get, key}, _from, state) do
    Logger.info "HANDLING state get: #{inspect key}"
    {:reply, Map.get(state, key), state}
  end

  def handle_cast({:put, key, value}, state) do
    Logger.info "HANDLING state put #{inspect key} : #{inspect value}"
    new_state = Map.put(state, key, value)
    {:noreply, new_state}
  end

  def handle_cast(dispatch, state) do
    send state.parent, dispatch
  end
end

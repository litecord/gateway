defmodule State.Registry do
  @moduledoc """
  State Registry

  This relates a tuple of user and guild IDs to a state PID.
  """
  use GenServer
  require Logger

  def start_link(_) do
    Logger.info "starting state registry"
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  ## client api
  @spec get(String.t) :: pid() | nil
  def get(user_id) do
    GenServer.call(__MODULE__, {:get, user_id})
  end

  @spec set(String.t, pid()) :: :ok
  def set(user_id, state_pid) do
    GenServer.call(__MODULE__, {:set, user_id, state_pid})
  end

  @spec delete(pid()) :: :ok
  def delete(state_pid) do
    GenServer.call(__MODULE__, {:delete, state_pid})
  end

  ## server callbacks
  def init(:ok) do
    {:ok, %{}}
  end

  # TODO: add another key to user_id, guild_id
  # since we have sharding stuff
  def handle_call({:get, user_id}, _from, state) do
    Logger.debug fn ->
      "getting state for #{user_id}"
    end
    {:reply, Map.get(state, user_id), state}
  end

  def handle_call({:set, user_id, state_pid}, _from, state) do
    Logger.debug fn ->
      "setting state for #{user_id} => #{inspect state_pid}"
    end
    {:reply, :ok, Map.put(state, user_id, state_pid)}
  end

  def handle_call({:delete, state_pid}, _from, state) do
    user_id = State.get(state_pid, :user_id)
    Logger.debug fn ->
      "deleting state for uid #{user_id}"
    end
    {:reply, :ok, Map.delete(state, user_id)}
  end
end

defmodule State do
  @moduledoc """
  Represents a single state, for one user.

  Used throughout the websocket connection for
  data about the user like session IDs and tokens.

  This also provides an interface for other modules
  to get data from a single state.
  """

  use GenServer
  require Logger
  
  defmodule StateStruct do
    @moduledoc """
    Defines a stucture of data to be hold to a state
    object.
    """
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
    Logger.info "state get: #{inspect pid} -> #{inspect key}"
    GenServer.call(pid, {:get, key})
  end

  def put(pid, key, value) do
    Logger.info "state put #{inspect pid} -> #{inspect key} : #{inspect value}"
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
    res = Map.get(state, key)
    Logger.info "HANDLING state get: #{inspect key} : #{inspect res}"
    {:reply, res, state}
  end

  def handle_cast({:put, key, value}, state) do
    Logger.info "HANDLING state put #{inspect key} : #{inspect value}"
    new_state = Map.put(state, key, value)
    {:noreply, new_state}
  end

  def handle_cast(dispatch, state) do
    Logger.debug fn ->
      "dispatching to #{inspect state.parent}, #{inspect dispatch}"
    end
    send state.parent, dispatch
    {:noreply, state}
  end
end


defmodule State.Registry do
  @moduledoc """
  The State Registry

  This GenServer manages all connections' states,
  including shard filtering
  """
  use GenServer
  require Logger

  def start_link(_) do
    Logger.info "starting state registry"
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  ## client api
  @spec get(String.t, String.t) :: [pid()]
  def get(user_id, guild_id) do
    GenServer.call(__MODULE__, {:get, user_id, guild_id})
  end

  @spec put(pid()) :: nil
  def put(state_pid) do
    GenServer.cast(__MODULE__, {:put, state_pid})
  end

  @spec delete(pid()) :: nil
  def delete(state_pid) do
    GenServer.cast(__MODULE__, {:delete, state_pid})
  end

  @doc """
  Get all the shard IDs that are currently tied
  to a specific user ID.
  """
  @spec get_user_shards(String.t) :: [Integer.t]
  def get_user_shards(user_id) do
    GenServer.call(__MODULE__, {:get_shards, user_id})
  end

  @doc """
  Get a shard ID, given a guild ID and the
  total number of shards for a client.
  """
  @spec get_shard(Integer.t, Integer.t) :: Integer.t
  def get_shard(guild_id, shard_total) do
    use Bitwise
    val = guild_id >>> 22
    rem(val, shard_total)
  end

  ## server callbacks
  def init(:ok) do
    {:ok, 
      # map user id to a list of shards.
      %{}}
  end

  def handle_call({:get, user_id, guild_id}, _from, state) do
    Logger.debug fn ->
      "state registry: getting shards for #{inspect user_id} #{inspect guild_id}"
    end

    {guild_id_int, _} = guild_id |> Integer.parse
    case Map.get(state, user_id) do
      nil ->
        {:reply, {:error, "user not connected"}, state}
      shards ->
        applicable_shards = Enum.filter(shards, fn state_pid ->
          shard_id = State.get(state_pid, :shard_id)
          shard_count = State.get(state_pid, :shard_count)

          shard_id == get_shard(guild_id_int, shard_count)
        end)

        {:reply, applicable_shards, state}
    end
  end

  def handle_cast({:put, state_pid}, state) do
    user_id = State.get(state_pid, :user_id)
    new_shard_list = [state_pid | state[user_id]]
    {:noreply, Map.put(state, user_id, new_shard_list)}
  end

  def handle_cast({:delete, state_pid}, state) do
    user_id = State.get(state_pid, :user_id)
    new_shard_list = List.delete(state[user_id], state_pid)
    {:noreply, Map.put(state, user_id, new_shard_list)}
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
               :encoding, :compress, :shard_id, :shard_total,
               :properties, :large, :ws_pid]
  end

  def start(ws_pid, encoding) do
    Logger.info "Spinning up state GenServer"
    GenServer.start(__MODULE__, %StateStruct{
      ws_pid: ws_pid,
      events: [],
      recv_seq: 0,
      sent_seq: 0,
      heartbeat: false,
      encoding: encoding,
      compress: false,
    })
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

  @doc """
  Send an Erlang message to the state's
  linked websocket process
  """
  def ws_send(pid, message) do
    GenServer.cast(pid, {:ws_send, message})
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

  def handle_cast({:ws_send, message}, state) do
    # {:ws, term()} makes it a specific litecord internal message
    send state[:ws_pid], {:ws, message}
    {:noreply, state}
  end

end


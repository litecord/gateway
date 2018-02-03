defmodule Litebridge do
  @moduledoc """
  This module handles requests and responses to the other
  side of litebridge.

  Calls to this module *will* block, because of the blocking/waiting
  nature of the websocket to process a request.
  """
  use GenServer
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [name: :litebridge])
  end

  @doc """
  Add a litebridge websocket process
  as one of the process we can send requests to.
  """
  def register(pid) do
    GenServer.cast(:litebridge, {:add_ws, pid})
  end

  @doc """
  Remove a litebridge websocket process pid
  from the client list
  """
  def remove(pid) do
    GenServer.cast(:litebridge, {:remove_ws, pid})
  end

  @doc """
  Request something from the client.

  This call will block the process waiting for the message
  from the client, with a timeout for a reply of 5 seconds.
  """
  @spec request(String.t, [any()]) :: any() | :timeout
  def request(r_type, r_args) do
    GenServer.call(:litebridge, {:request, r_type, r_args})
  end

  @doc """
  Process a received response from one of the websockets.
  """
  def process_response(nonce, response) do
    Logger.info "[litebridge client] n=#{nonce} r=#{response}"
    GenServer.cast(:litebridge, {:response, nonce, response})
  end

  @doc """
  Generate a random nonce for our requests.
  """
  defp gen_nonce() do
    data = for _ <- 1..15, do: Enum.random(0..255)

    cap = &(:crypto.hash(:md5, &1))

    data
    |> cap.()
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  # server callbacks

  def init(args) do
    {:ok, %{
      clients: []
    }}
  end

  def handle_cast({:add_ws, pid}, state) do
    Logger.debug fn ->
      "Adding #{inspect pid} as litebridge"
    end
    new_clients = [pid | state[:clients]]
    {:noreply, Map.put(state, :clients, new_clients)}
  end

  def handle_cast({:remove_ws, pid}, state) do
    Logger.debug fn ->
      "Removing #{inspect pid} as litebridge"
    end
    new_clients = List.delete(state[:clients], pid)
    {:noreply, Map.put(state, :clients, new_clients)}
  end

  def handle_call({:request, r_type, r_args}, from, state) do
    random_nonce = gen_nonce()

    # choose a random client to handle our request
    case state[:clients] do
      [] ->
        {:reply, {:error, "no clients available"}, state}
      clients ->
        ws_pid = Enum.random(state[:clients])
        send ws_pid, {:send, %{
          op: 4,
          w: r_type,
          a: r_args,
          n: random_nonce
        }}

        # Prepare ourselves the 5 second timeout
        # from the client
        Process.send_after(self(), {:call_timeout, from}, 5000)

        # this will block the call, read the GenServer docs
        # to know more
        {:noreply, Map.put(state, random_nonce, from)}
    end
  end

  def handle_info({:call_timeout, from}, state) do
    Logger.debug fn ->
      "Sending a timeout reply to #{inspect from}"
    end

    GenServer.reply(from, :request_timeout)
    {:noreply, state}
  end

  def handle_cast({:response, nonce, data}, state) do
    Logger.debug fn -> 
      "Litebridge: recv #{nonce} #{inspect data}"
    end

    from = state[nonce]
    case state[nonce] do
      nil ->
        Logger.debug fn ->
          "got a response to unknown nonce"
        end
        {:noreply, state}
      from ->
        Logger.debug fn ->
          "Litebridge: replying #{inspect data} to #{inspect from}"
        end

        GenServer.reply(from, data)
        {:noreply, Map.delete(state, nonce)}
    end
  end
end

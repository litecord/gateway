defmodule Gateway.Bridge do
  @moduledoc """
  Implements the Litebridge protocol as a server.

  Litebridge is a protocol running over websockets
  that uses the gateway as a server and the rest
  component as a client to share information between.
  """

  require Logger
  @behaviour :cowboy_websocket

  defmodule State do
    @moduledoc false
    defstruct [:heartbeat, :identify, :encoding, :compress]
  end
  
  def hb_interval() do
    20_000
  end

  def encode(map, state) do
    encoded = case state.encoding do
                "json" ->
                  Poison.encode!(map)
              end

    if state.compress do
      ""
    else
      encoded
    end
  end

  def decode(data, state) do
    case state.encoding do
      "json" ->
        Poison.decode!(data)
    end
  end
  
  def init(req, _state) do
    {peer_ip, peer_port} = :cowboy_req.peer(req)
    Logger.info "litebridge: new #{inspect peer_ip}:#{inspect peer_port}"
    {:cowboy_websocket, req, %State{heartbeat: false,
                                    identify: false,
                                    encoding: "json",
                                    compress: false}}
  end

  def terminate(reason, _req, _state) do
    Logger.info "Terminated from #{inspect reason}"
    Litebridge.remove self()
    :ok
  end

  def hb_timer() do
    interv = hb_interval()

    # The world is really bad.
    :erlang.start_timer(interv + 1000, self(), :req_heartbeat)
  end
  
  def websocket_init(state) do
    hb_timer()
    hello = encode(%{op: 0,
                     hb_interval: hb_interval()}, state)

    Litebridge.register self()
    {:reply, {:text, hello}, state}
  end

  # payload handlers
  def websocket_handle({:text, frame}, state) do
    payload = decode(frame, state)
    %{"op" => opcode} = payload
    handle_payload(opcode, payload, state)
  end

  def websocket_handle(_any_frame, state) do
    {:ok, state}
  end

  # erlang timer handlers
  def websocket_info({:timeout, _ref, :req_heartbeat}, state) do
    case state.heartbeat do
      true ->
        hb_timer()
        {:ok, Map.put(state, :heartbeat, false)}
      false ->
        {:reply, {:close, 4003, "Heartbeat timeout"}, state}
    end
  end

  def websocket_info({:send, packet}, state) do
    {:reply, {:text, encode(packet, state)}, state}
  end

  # specific payload handlers

  @doc """
  Handle OP 1 Hello ACK.

  Checks in application data if the
  provided password is correct
  """
  def handle_payload(1, payload, state) do
    correct = Application.fetch_env!(:gateway, :bridge_password)
    given = payload["password"]
    if correct == given do
      {:ok, Map.put(state, :identify, true)}
    else
      {:reply, {:close, 4001, "Authentication failed"}, state}
    end
  end

  @doc """
  Handle OP 2 Heartbeat

  If the client is not properly identified through
  OP 1 Hello ACK, it is disconnected.
  """
  def handle_payload(2, _payload, state) do
    case state.identify do
      true ->
        hb_ack = encode(%{op: 3}, state)
        {:reply, {:text, hb_ack}, Map.put(state, :heartbeat, true)}
      false ->
        {:reply, {:close, 4002, "Not Authenticated"}, state}
    end
  end

  @doc """
  Handle OP 4 Request

  Handle a specific request from the client.
  Sends OP 5 Response.
  """
  def handle_payload(4, payload, state) do
    %{"n" => nonce,
      "w" => request,
      "a" => args} = decode(payload, state)

    response_payload = encode(%{op: 5,
                                n: nonce,
                                #r: response
                               }, state)

    {:reply, {:text, response_payload}, state}
  end

  @doc """
  Handle OP 5 Response.
  """
  def handle_payload(5, payload, state) do
    %{"n" => nonce,
      "r" => response} = payload

    Logger.debug fn ->
      "Got a response for #{nonce}, #{inspect response}"
    end

    Litebridge.process_response(nonce, response)
    {:ok, state}
  end
  
  @doc """
  Handle OP 6 Dispatch.

  Do a request that won't have any response back.
  """
  def handle_payload(6, _payload, state) do
    {:ok, state}
  end

end


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
  @spec request(atom(), [any()]) :: any() | :timeout
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

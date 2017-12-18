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
    Logger.info "New client at #{inspect peer_ip}:#{inspect peer_port}"
    {:cowboy_websocket, req, %State{heartbeat: false,
                                    identify: false,
                                    encoding: "json",
                                    compress: false}}
  end

  def terminate(reason, _req, _state) do
    Logger.info "Terminated from #{inspect reason}"
    :ok
  end

  def hb_timer() do
    hb_interval()
    |> :erlang.start_timer(self(), :req_heartbeat)
  end
  
  def websocket_init(state) do
    hb_timer()
    hello = encode(%{op: 0,
                     hb_interval: hb_interval()}, state)

    Litebridge.start_link self()
    {:reply, {:text, hello}, state}
  end

  # payload handlers
  def websocket_handle({:text, frame}, state) do
    payload = decode(frame, state)
    IO.puts "recv payload: #{inspect payload}"
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
    #%{"" => nonce,
    #  "" => q} = decode(payload, state)
    %{"n" => nonce,
      "w" => request,
      "a" => args} = decode(payload, state)
    #response = request_call(w, args)
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
    send state.bridge_pid, {:response, payload["n"], payload["d"]}
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

  def start_link(parent) do
    GenServer.start_link(__MODULE__, parent, [name: :litebridge])
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

  # server callbacks

  def init(parent) do
    {:ok, %{parent: parent}}
  end

  def gen_nonce() do
    data = for _ <- 1..15, do: Enum.random(0..255)

    data
    |> &(:crypto.hash(:md5, &1)).()
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  def handle_call({:request, r_type, r_args}, from, state) do
    random_nonce = gen_nonce()

    send state.ws_pid, {:send, %{
                           op: 4,
                           w: r_type,
                           a: r_args,
                           n: random_nonce
                        }}

    # Prepare ourselves the 5 second timeout
    # from the client
    GenServer.cast(:litebridge, {:call_timeout, from})

    # This makes the "blocking" part of request()
    # since handle_call needs to reply something
    # to the requesting process, replying nothing
    # will make it wait for something.
    #
    # That something will be later received
    # by the GenServer as {:response, nonce, data}
    # and can be properly replied to the client
    # at a later time, since the GenServer
    # has a map from nonce's to PIDs.
    {:noreply, %{state | random_nonce => from}}
  end

  def handle_cast({:call_timeout, pid}, state) do
    Process.sleep(5000)
    GenServer.reply(pid, :timeout)
    {:noreply, state}
  end

  def handle_info({:response, nonce, data}, _from, state) do
    pid = state[nonce]
    GenServer.reply(pid, data)
    {:noreply, Map.delete(state, nonce)}
  end
end

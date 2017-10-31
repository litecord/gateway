defmodule Gateway.Bridge do
  @moduledoc """
  Implements the Litebridge protocol as a server.
  """

  require Logger
  @behaviour :cowboy_websocket

  defmodule State do
    @moduledoc false
    defstruct [:heartbeat, :identify, :encoding, :compress]
  end
  
  def hb_interval() do
    5000
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
    {:reply, {:text, hello}, state}
  end

  # payload handlers
  def websocket_handle({:text, frame}, state) do
    payload = decode(frame, state)
    IO.puts "recv payload: #{inspect payload}"
    %{"op" => opcode} = payload

    # TODO: Update the state in Gateway.SharedSession
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
  def handle_payload(4, _payload, state) do
    #%{"" => nonce,
    #  "" => q} = decode(payload, state)
    %{"n" => nonce,
      "w" => request,
      "a" => args} = decode(payload, state)
    response = request_call(w, a)
    response_payload = encode(%{op: 5,
				n: nonce,
				r: response
			       }, state)

    {:reply, {:text, response_payload}, state}
  end

  @doc """
  Handle OP 6 Dispatch.

  Do a request that won't have any response back.
  """
  def handle_payload(6, _payload, state) do
    {:ok, state}
  end

end

defmodule Gateway.Bridge do
  @moduledoc """
  Implements the Litebridge protocol as a server.
  """

  require Logger
  @behaviour :cowboy_websocket

  def hb_interval() do
    10000
  end

  def encode(map, state) do
    case state[:compress] do
      _ ->
	JSEX.encode(map)
    end
  end

  def decode(data, state) do
    case state[:compress] do
      _ ->
	JSEX.decode(data)
    end
  end
  
  def init(req, state) do
    {peer_ip, peer_port} = :cowboy_req.peer(req)
    Logger.info "New client at #{peer_ip}:#{peer_port}"
    {:cowboy_websocket, req, state}
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
    %{"op" => opcode} = payload
    handle_payload(opcode, payload, state)
  end

  def websocket_handle(_any_frame, state) do
    {:ok, state}
  end

  @doc """
  Handle OP 1 Hello ACK.

  Checks in application data if the
  provided password is correct
  """
  def handle_payload(1, payload, state) do
    correct = Application.fetch_env!(:gateway, :password)
    given = payload["password"]
    if correct == given do
      {:ok, Map.put(state, :identify, true)}
    else
      {:stop, state}
    end
  end

  @doc """
  Handle OP 2 Heartbeat

  If the client is not properly identified through
  OP 1 Hello ACK, it is disconnected.
  """
  def handle_payload(2, _payload, state) do
    case Map.get(state, :identify) do
      true ->
	hb_ack = encode(%{op: 3}, state)
	{:reply, hb_ack, Map.put(state, :heartbeat, true)}
      false ->
	{:stop, state}
    end
  end

  @doc """
  Handle OP 4 Request

  Handle a specific request from the client.
  Sends OP 5 Response.
  """
  def handle_payload(4, payload, state) do
    %{"" => nonce,
      "" => q} = decode(payload, state)
    {:ok, state}
  end

  @doc """
  Handle OP 6 Dispatch.

  Do a request that won't have any response back.
  """
  def handle_payload(6, _payload, state) do
    {:ok, state}
  end

  # erlang timer handlers
  def websocket_info({:timeout, _ref, :req_heartbeat}, state) do
    case state[:heartbeat] do
      true ->
	hb_timer()
	{:ok, Map.put(state, :heartbeat, false)}
      false ->
	{:stop, state}
    end
  end
end

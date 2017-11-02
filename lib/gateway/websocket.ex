defmodule Gateway.Websocket do
  @moduledoc """
  Main websocket
  """

  require Logger
  @behaviour :cowboy_websocket

  defmodule State do
    @moduledoc false
    defstruct [:session_id, :token, :user_id, :events,
	       :recv_seq, :sent_seq, :heartbeat,
	       :encoding, :compress]
  end
  
  def hb_interval() do
    41250
  end

  def hb_timer() do
    Logger.info "start timer"
    :erlang.send_after(hb_interval(), self(), [:heartbeat])
  end
  
  def init(req, _state) do
    Logger.info "New client: #{inspect req}"

    # TODO: parse querystring here

    {:cowboy_websocket, req, %State{recv_seq: 0,
				    sent_seq: 0,
				    heartbeat: false,
				    events: [],
				    session_id: nil,
				    compress: false,
				    encoding: "json"}}
  end

  def terminate(reason, _request, state) do
    Logger.info "Terminating, #{inspect reason}, #{inspect state}"
    :ok
  end

  defp get_name() do
    ["litecord-gateway-prd-0"]
  end

  def opcode(op) do
    %{dispatch: 0,
      heartbeat: 1,
      identify: 2,
      status_update: 3,
      voice_update: 4,
      voice_ping: 5,
      resume: 6,
      reconnect: 7,
      req_guild_members: 8,
      invalid: 9,
      hello: 10,
      ack: 11,
      guild_sync: 12}[op]
  end

  def opcode_atom(opcode) do
    %{0 => :dispatch,
      1 => :heartbeat,
      2 => :identify,
      3 => :status_update,
      4 => :voice_update,
      5 => :voice_ping,
      6 => :resume,
      7 => :reconnect,
      8 => :req_guild_members,
      9 => :invalid,
      10 => :hello,
      11 => :ack,
      12 => :guild_sync}[opcode]
  end

  def encode(map, state) do
    encoded = case state.encoding do
		"etf" -> :erlang.term_to_binary(map)
		_ ->
		  Poison.encode!(map)
	      end

    case state.compress do
      _ ->
	:erlang.binary_to_list(encoded)
    end
  end

  def decode(raw, state) do
    case state.encoding do
      "etf" ->
	:erlang.binary_to_term(raw, [:safe])
      _ ->
	Poison.decode!(raw)
    end
  end

  def payload(:ack, state) do
    %{
      op: opcode(:ack),
      d: nil
    }
    |> encode(state)
  end

  # The logic is that the client
  # will send an IDENTIFY packet soon
  # after receiving this HELLO.
  def websocket_init(state) do
    Logger.info "Sending a hello packet"
    hello = %{
      op: opcode(:hello),
      d: %{
	heartbeat_interval: hb_interval(),
	_trace: get_name()
      }
    }
    hb_timer()
    {:reply, {:text, encode(hello, state)}, state}
  end
  
  # Handle client frames
  def websocket_handle({:text, content}, state) do
    payload = decode(content, state)
    IO.puts "Received payload: #{inspect payload}"
    as_atom = opcode_atom(payload["op"])
    IO.inspect as_atom
    gateway_handle(as_atom, payload, state)
  end

  def websocket_handle(_any_frame, state) do
    {:ok, state}
  end

  def websocket_info([:heartbeat], state) do
    Logger.info "Checking heartbeat state"
    case state.heartbeat do
      true ->
	Logger.info "all good"
	hb_timer()
	{:ok, Map.put(state, :heartbeat, false)}
      false ->
	Logger.info "all bad"
	{:reply, {:close, 4009, "Session timeout"}, state}
    end
  end

  def websocket_info(data, state) do
    Logger.info "w_info = #{inspect data}"
    {:ok, state}
  end
    
  #def websocket_info(any, _state) do
  #  Logger.info "recv info: #{any}"
  #end

  @doc """
  Handle HEARTBEAT packets by the client.
  Send HEARTBEAT ACK packets
  """
  def gateway_handle(:heartbeat, %{d: seq}, state) do
    case state.identified do
      true ->
	{:reply, payload(:ack, state),
	 Map.put(state, :recv_seq, seq)}
      _ ->
	{:reply, {:close, 4003, "Not authenticated"}, state}
    end
  end

  @doc """
  Handle IDENTIFY packet.
  Dispatches the READY event.
  """
  def gateway_handle(:identify, payload, state) do
    # {:reply, payload(:ack), Map.put(state, :seq, seq)}
    {:ok, state}
  end

  def gateway_handle(atomp, _payload, state) do
    Logger.info "Handling nothing, #{inspect atomp}"
    {:ok, state}
  end

  # TODO: insert rest
end

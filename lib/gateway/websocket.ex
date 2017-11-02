defmodule Gateway.Websocket do
  @moduledoc """
  Main websocket
  """

  require Logger
  @behaviour :cowboy_websocket

  defmodule State do
    @moduledoc """
    Represents a connection state
    In litecord.
    """
  end

  @doc """
  Default heartbeating interval to the client.
  """
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

    # Spin up a Gateway.State GenServer
    {:ok, state_pid} = Gateway.State.start_link()
    {:cowbot_websocket, req, state_pid}
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

  def encode(map, pid) do
    encoded = case Gateway.State.get(pid, :encoding) do
		"etf" -> :erlang.term_to_binary(map)
		_ ->
		  Poison.encode!(map)
	      end

    case Gateway.State.get(pid, :compress) do
      _ ->
	:erlang.binary_to_list(encoded)
    end
  end

  def decode(raw, pid) do
    case Gateway.State.get(pid, :encoding)
      "etf" ->
	:erlang.binary_to_term(raw, [:safe])
      _ ->
	Poison.decode!(raw)
    end
  end

  def enclose(state, ev_type, data) do
    %{
      op: 0,
      t: ev_type,
      d: data,
      seq: state.sent_seq,
    }
  end
  
  def payload(:ack, pid) do
    %{
      op: opcode(:ack),
      d: nil
    }
    |> encode(pid)
  end

  def dispatch(pid, :ready) do
    ready = enclose(state, "READY", %{
	  v: 6,
	  #user: get_user(state.user_id),
	  user: %{
	    id: 1,
	    discriminator: "1111",
	    username: "gay",
	    avatar: "",
	    bot: false,
	    mfa_enabled: false,
	    flags: 0,
	    verified: true
	  },
	  private_channels: [],
	  guilds: [],
	  session_id: Gateway.State.get(pid, :session_id)
	  _trace: get_name()
		    })
    {:reply, encode(ready, state), state}
  end

  def dispatch(pid, :resumed) do
    {:reply,
     encode(enclose(pid, "RESUMED",
	   %{_trace: get_name()}), pid),
     pid}
  end
  
  def dispatch(_state, _) do
    {:error, 4000, "Unkown atom"}
  end

  # The logic is that the client
  # will send an IDENTIFY packet soon
  # after receiving this HELLO.
  def websocket_init(pid) do
    Logger.info "Sending a hello packet"
    hello = %{
      op: opcode(:hello),
      d: %{
	heartbeat_interval: hb_interval(),
	_trace: get_name()
      }
    }
    hb_timer()
    {:reply, {:text, encode(hello, pid)}, pid}
  end
  
  # Handle client frames
  def websocket_handle({:text, content}, pid) do
    payload = decode(content, pid)
    IO.puts "Received payload: #{inspect payload}"
    as_atom = opcode_atom(payload["op"])
    IO.inspect as_atom
    gateway_handle(as_atom, payload, pid)
  end

  def websocket_handle(_any_frame, state) do
    {:ok, state}
  end

  def websocket_info([:heartbeat], pid) do
    Logger.info "Checking heartbeat state"
    case Gateway.State.get(pid, :heartbeat) do
      true ->
	Logger.info "all good"
	hb_timer()
	Gateway.State.put(pid, :heartbeat, false)
	{:ok, pid}
      false ->
	Logger.info "all bad"
	{:reply, {:close, 4009, "Session timeout"}, pid}
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
  def gateway_handle(:heartbeat, %{"d" => seq}, pid) do
    case Gateway.State.get(pid, :session_id) do
      nil ->
	{:reply, {:close, 4003, "Not authenticated"}, pid}
      _ ->
	Gateway.State.put(pid, :recv_seq, seq)
	{:reply, payload(:ack, pid), pid}
    end
  end

  @doc """
  Handle IDENTIFY packet.
  Dispatches the READY event.
  """
  def gateway_handle(:identify, payload, pid) do
    case Gateway.State.get(pid, :session_id) do
      nil ->
	%{"token" => token,
	  "properties" => prop,
	  "compress" => compress,
	  "large_threshold" => large,
	  # "presence" => initial_presence
	 } = payload["d"]

	shard = Map.get(payload, "shard", [0, 1])

	Gateway.Ready.check_token(pid, token)
	Gateway.Ready.check_shard(pid, shard)
	Gateway.Ready.fill_session(pid, prop, compress, large)

	Presence.guild_sub(pid, :all)
	
	case state do
	  {:error, errcode, errmessage} ->
	    {:reply, {:error, errcode, errmessage}, state}
	  _ ->
	    presence = Map.get(payload, "presence", Presence.default_presence())
	    Presence.dispatch(pid, presence)
	    {:reply, dispatch(pid, :ready), state}
	end
      _ ->
	{:reply, {:close, 4005, "Already authenticated"}, pid}
     end
  end

  def gateway_handle(atomp, _payload, state) do
    Logger.info "Handling nothing, #{inspect atomp}"
    {:ok, state}
  end

  # TODO: insert rest
end

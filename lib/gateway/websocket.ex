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
 
    # We add 1 second more because the world is bad
    :erlang.send_after(hb_interval() + 1000, self(), [:heartbeat])
  end
  
  def init(req, _state) do
    Logger.info "New client: #{inspect req}"

    # TODO: parse querystring here

    {:cowboy_websocket, req, nil}
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
    case Gateway.State.get(pid, :encoding) do
      "etf" ->
	:erlang.binary_to_term(raw, [:safe])
      _ ->
	Poison.decode!(raw)
    end
  end

  def enclose(pid, ev_type, data) do
    %{op: 0,
      s: Gateway.State.get(pid, :sent_seq),
      t: ev_type,
      d: data,
    }
  end
  
  def payload(:ack, pid) do
    %{
      op: opcode(:ack),
      d: nil,
    }
    |> encode(pid)
  end

  def dispatch(pid, :ready) do
    ready = enclose(pid, "READY", %{
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
	  session_id: Gateway.State.get(pid, :session_id),
	  _trace: get_name()
		    })
    Logger.debug "Ready packet: #{inspect ready}"
    {:text, encode(ready, pid)}
  end

  def dispatch(pid, :resumed) do
    resumed = enclose(pid, "RESUMED", %{
	  _trace: get_name()
		      })
    {:reply, {:text, encode(resumed, pid)}, pid}
  end
  
  def dispatch(_state, _) do
    {:error, 4000, "Unkown atom"}
  end

  # The logic is that the client
  # will send an IDENTIFY packet soon
  # after receiving this HELLO.
  def websocket_init(_pid) do
    Logger.info "Sending a hello packet"

    # Spin up a Gateway.State GenServer
    {:ok, pid} = Gateway.State.start(self())

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
    Logger.debug "Received payload: #{inspect payload}"
    as_atom = opcode_atom(payload["op"])
    gateway_handle(as_atom, payload, pid)
  end

  def websocket_handle(_any_frame, state) do
    {:ok, state}
  end

  # handle incoming messages

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
	{:reply, {:close, 4009, "Heartbeat timeout"}, pid}
    end
  end

  def websocket_info({:send, dispatch}, pid) do
    {:reply, dispatch, pid}
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
	Gateway.State.put(pid, :heartbeat, true)
	{:reply, {:text, payload(:ack, pid)}, pid}
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

	Presence.subscribe(pid, :all)
	
	presence = Map.get(payload, "presence", Presence.default_presence())
	Presence.dispatch_users(pid, presence)

	{:reply, dispatch(pid, :ready), pid}
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

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

    {response, new_state} = bridge_request(request, args, state)

    response_payload = encode(%{op: 5,
                                n: nonce,
                                r: response
                               }, new_state)

    {:reply, {:text, response_payload}, new_state}
  end

  @doc """
  Request all subscribers that are in a guild.
  """
  def bridge_request("GET_SUBSCRIBERS", [guild_id], state) do
    guild_pid = Guild.Registry.get(guild_id)
    {GenGuild.get_subs(guild_pid), state}
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
  def handle_payload(6, payload, state) do
    %{
      "w" => request,
      "a" => args
    } = decode(payload, state)

    new_state = bridge_dispatch(request, args, state)
    {:ok, new_state}
  end

  def bridge_dispatch("NEW_GUILD", [guild_id, owner_id], state) do
    # get GenGuild
    guild_pid = Guild.Registry.get(guild_id)
    state_pids = State.Registry.get(owner_id, guild_id)

    # ???
    GenGuild.subscribe(guild_pid, owner_id)

    Enum.each(state_pids, fn state_pid ->
      GenGuild.add_presence(guild_pid, state_pid)
    end)

    Presence.dispatch(guild_id, fn guild_pid, state_pid ->
      # We need to fill an entire guild payload here.
      # Fuck.
      {"GUILD_CREATE", Guild.guild_dump(guild_pid, state_pid)}
    end)


    state
  end

  def bridge_dispatch("DISPATCH", %{
    "guild" => guild_id,
    "event" => [event_name, event_data]
  }, state) do
    # dispatch to all members of a guild
    guild_pid = Guild.Registry.get(guild_id)

    Presence.dispatch(guild_id, fn ->
      {event_name, event_data}
    end)

    state
  end

  def bridge_request("DISPATCH", %{"user" => user_id}, state) do
    # dispatch to one user (all of the user's shards will receive)
    state
  end

  def bridge_dispatch("DISPATCH_MEMBER", [guild_id, user_id], state) do
    # dispatch to a *single* user in a gulid
    state
  end

  def bridge_dispatch("DISPATCH_CHANNEL", [guild_id, channel_id], state) do
    # dispatch to all users in a channel
    state
  end

end


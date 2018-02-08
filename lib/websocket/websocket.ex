defmodule Gateway.Websocket do
  @moduledoc """
  Main websocket handler.
  """

  alias Gateway.Ready
  require Logger
  @behaviour :cowboy_websocket

  @doc """
  Default heartbeating interval to the client.
  """
  def hb_interval() do
    41_250
  end

  def hb_timer() do
    # We add 1 second more because the world is bad
    :erlang.send_after(hb_interval() + 1000, self(), [:heartbeat])
  end

  def init(req, _state) do
    Logger.info "New client: #{inspect req}"

    {:cowboy_websocket, req, req}
  end

  def terminate(reason, _request, pid) do
    Logger.info "Terminating, #{inspect reason}, #{inspect pid}"
    # State.Registry.delete(pid)
    :ok
  end

  defp get_name() do
    ["litecord-gateway-prd-0"]
  end

  defp get_name(:ready) do
    ["litecord-ready-prd-0"]
  end

  @doc """
  get an op code from an atom
  """
  @spec atom_opcode(atom()) :: integer()
  def atom_opcode(atom) do
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
      guild_sync: 12}[atom]
  end

  @doc """
  get an atom from an opcode
  """
  @spec opcode_atom(integer()) :: atom()
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

  @doc """
  Encode a map based on the encoding
  of the connection.
  """
  def encode(map, pid) do
    encoded = case State.get(pid, :encoding) do
      "etf" ->
        :erlang.term_to_binary(map)
      _ ->
        Poison.encode!(map)
    end

    case State.get(pid, :compress) do
      _ ->
        :erlang.binary_to_list(encoded)
    end
  end

  @doc """
  Decode any data from the websocket.
  """
  def decode(raw, pid) do
    case State.get(pid, :encoding) do
      "etf" ->
        :erlang.binary_to_term(raw, [:safe])
      _ ->
        Poison.decode!(raw)
    end
  end

  @doc """
  Enclose a OP 0 Dispatch packet outside
  of a payload
  """
  @spec enclose(pid(), String.t, any()) :: Map.t
  def enclose(pid, ev_type, data) do
    sent_seq = State.get(pid, :sent_seq)

    State.put(pid, :sent_seq, sent_seq + 1)
    %{
      op: 0,
      s: sent_seq + 1,
      t: ev_type,
      d: data,
    }
  end

  @doc """
  Get the payload, as a string,
  of the OP 11 Heartbeat ACK
  """
  def payload(:ack, pid) do
    {:text, %{
      op: atom_opcode(:ack),
      d: nil,
    }
    |> encode(pid)}
  end

  def payload(:invalid_session, pid, resumable \\ false) do
    case resumable do
      false ->
        State.Registry.delete(pid)
    end
    res = %{
      op: atom_opcode(:invalid_session),
      d: resumable,
    }
    |> encode(pid)

    {:text, res}
  end

  def dispatch(pid, :ready) do
    uid = State.get(pid, :user_id)
    case uid do
      nil ->
        # not auth
        {:close, 4001, "Not Authenticated for READY"}
      user_id ->
        user_data = user_id |> User.get_user |> User.from_struct

        # we get a list of guilds with get_guilds
        # then proceed to get a fuckton of data with
        # map_guild_data

        guild_ids = Guild.get_guilds(pid)

        Presence.subscribe(pid, guild_ids)
        guilds = guild_ids |> Guild.map_guild_data

        ready = enclose(pid, "READY", %{
          v: 6,
          user: user_data,
          private_channels: [],
          guilds: guilds,
          session_id: State.get(pid, :session_id),
          relationships: [],
          _trace: get_name(:ready),
        })

      Logger.debug fn ->
        "Ready packet: #{inspect ready}"
      end

      {:text, encode(ready, pid)}
    end
  end

  def dispatch(pid, :resumed) do
    resumed = enclose(pid, "RESUMED", %{
      _trace: get_name()
    })
    {:text, encode(resumed, pid)}
  end

  @spec dispatch(pid(), atom(), pid()) :: {:text, String.t}
  def dispatch(pid, :guild_sync, {guild_id, guild_pid}) do

    # fetch presences from the guild
    presences = guild_pid
                |> GenGuild.get_subs
                |> Enum.map(fn user_id ->
                  case GenGuild.get_presence(guild_pid, user_id) do
                    {:error, err} ->
                      Logger.warn "error getting pres #{guild_id} #{user_id}: #{inspect err}"
                      nil
                    {:ok, presence} ->
                      presence
                  end
                end)
                |> Enum.filter(fn el ->
                  el != nil
                end)

    members = guild_id
              |> Guild.get_member_data
              |> Enum.map(fn member ->
                Member.get_member_map(member)
              end)

    data = enclose(pid, "GUILD_SYNC", %{
      id: guild_id,
      presences: presences,
      members: members
    })

    {:text, encode(data, pid)}
  end

  def dispatch(_state, _) do
    {:error, 4000, "unknown atom to dispatch"}
  end

  def websocket_init(req) do
    Logger.info "Sending a hello packet"

    %{
      v: gw_version,
      encoding: gw_encoding,
    } = :cowboy_req.match_qs([:v, :encoding], req)

    # Spin up a State GenServer
    Logger.info "v=#{gw_version}, encoding=#{gw_encoding}"
    if gw_version == "6" or gw_version == "7" do
      {:ok, pid} = State.start(self(), gw_encoding)

      hello = %{
        op: atom_opcode(:hello),
        d: %{
          heartbeat_interval: hb_interval(),
          _trace: get_name()
        }
      }
      hb_timer()
      {:reply, {:text, encode(hello, pid)}, pid}
    else
      {:reply, {:close, 4000, "Gateway version not supported"}, nil}
    end
  end

  # Handle sent client frames
  defp dispatch_ghandle(opatom, payload, pid) do
    sid = State.get(pid, :session_id)
    Logger.debug fn ->
      "sid=#{inspect sid}, opcode=#{inspect opatom}"
    end
    case {State.get(pid, :session_id), opatom} do
      {nil, :identify} ->
        gateway_handle(opatom, payload, pid)
      {nil, :heartbeat} ->
        gateway_handle(opatom, payload, pid)
      {nil, _} ->
        {:reply, {:close, 4003, "Unauthenticated"}, pid}
      {_, _} ->
        gateway_handle(opatom, payload, pid)
    end
  end

  def websocket_handle({:text, content}, pid) do
    payload = decode(content, pid)
    Logger.debug fn ->
      "Received payload: #{inspect payload}"
    end

    case Map.get(payload, "op") do
      nil -> 
        {:reply, {:close, 4000, "Bad packet"}, pid}
      as_op ->
        as_atom = as_op |> opcode_atom
        dispatch_ghandle(as_atom, payload, pid)
    end
 end

  def websocket_handle(_any_frame, state) do
    {:ok, state}
  end

  # handle incoming erlang payloads

  @doc """
  This function is usually called every
  heartbeat_period seconds, this checks
  if the client already heartbeated at that time,
  if not, we close it, because they're
  probably in a bad connection, and should resume
  ASAP.
  """
  def websocket_info([:heartbeat], pid) do
    Logger.info "Checking heartbeat state"

    case State.get(pid, :heartbeat) do
      true ->
        hb_timer()
        State.put(pid, :heartbeat, false)
        {:ok, pid}
      false ->
        Logger.info "heartbeat timeout, closing"
        {:reply, {:close, 4009, "Heartbeat timeout"}, pid}
    end
  end

  def websocket_info({:ws, message}, pid) do
    # our special litecord-specific messages
    litecord_handle(message, pid)
  end

  # handler for any message
  def websocket_info(data, state) do
    Logger.info "websocket_info, got #{inspect data}"
    {:ok, state}
  end

  # litecord-specific message handlers
  @doc """
  Send raw data over the websocket.
  """
  def litecord_handle({:send_raw, data}, pid) do
    {:reply, {:text, data}, pid}
  end

  @doc """
  Send a map over the websocket.
  """
  def litecord_handle({:send_map, map}, pid) do
    {:reply, {:text, encode(map, pid)}, pid}
  end

  @doc """
  Send a payload to an event over the websocket
  """
  def litecord_handle({:send_event, {ev_str, payload}}, pid) do
    Logger.info "dispatching #{inspect ev_str}"
    map = enclose(pid, ev_str, payload)
    {:reply, {:text, map |> encode(pid)}, pid}
  end

  @doc """
  Close the websocket.
  """
  def litecord_handle({:close, code, reason}, pid) do
    Logger.info "closing #{inspect code} #{inspect reason}"
    {:reply, {:close, code, reason}, pid}
  end


  @doc """
  Insert a presence payload
  into the state.
  """
  @spec insert_presence(Map.t, pid()) :: :ok
  def insert_presence(presence, pid) do
    # we don't get "since" because
    # we don't have any push notification thing
    activity = presence
    pre_status = Map.get(presence, "status")

    status = case pre_status do
      "invisible" -> "offline"
      any -> any
    end

    State.put(pid, :presence, %{
      "game" => %Presence.Activity{
        name: activity["name"],
        type: activity["type"],
        url: activity["url"]
      },

      "status" => %Presence.Status{
        ws_pid: pid,
        status: status
      }
    })

    :ok
  end


  @doc """
  Handle HEARTBEAT packets by the client.
  Send HEARTBEAT ACK packets
  """
  def gateway_handle(:heartbeat, %{"d" => seq}, pid) do
    case State.get(pid, :session_id) do
      nil ->
        {:reply, {:close, 4003, "Not authenticated to heartbeat"}, pid}
      _ ->
        State.put(pid, :recv_seq, seq)
        State.put(pid, :heartbeat, true)
        {:reply, payload(:ack, pid), pid}
    end
  end

  @doc """
  Handle IDENTIFY packet.
  Dispatches the READY event.
  """
  def gateway_handle(:identify, payload, pid) do
    case State.get(pid, :session_id) do
      nil ->
        %{"token" => token,
          "properties" => prop,
        } = payload["d"]

        compress = Map.get(payload, "compress", false)
        large = Map.get(payload, "large_threshold", 50)
        shard = Map.get(payload, "shard", [0, 1])
        presence = Map.get(payload, "presence", Presence.default_presence())

        # checking given user data
        # and filling the state genserver
        Ready.check_token(pid, token)
        Ready.check_shard(pid, shard)
        Ready.fill_session(pid, shard, prop, compress, large)

        insert_presence(presence, pid)

        # good stuff
        {:reply, dispatch(pid, :ready), pid}
      _ ->
        {:reply, {:close, 4005, "Already authenticated"}, pid}
    end
  end

  def gateway_handle(:status_update, payload, pid) do
    insert_presence(payload, pid)
    guild_ids = Guild.get_guilds(pid)

    # Presence.subscribe/2 will call
    # GenGuild.add_presence which manages our stuff.
    Presence.subscribe(pid, guild_ids)
    {:ok, pid}
  end

  def gateway_handle(:resume, payload, pid) do
    # Catch the state genserver which manages
    # the given session ID.
    %{
      "d" => %{
        "token" => token,
        "session_id" => session_id,
        "seq" => seq,
      }
    } = payload
    Ready.check_token(pid, token)

    user_id = State.get(pid, :user_id)
    pids = user_id
           |> State.Registry.get_user_shards
           |> Enum.filter(fn pid ->
             state_sessid = State.get(pid, :session_id)
             state_sessid == session_id
           end)

    case Enum.count(pids) do
      0 ->
        # session id not found
        {:reply, payload(:invalid_session, pid), pid}
      any ->
        old_state_pid = Enum.at(pids, 0)

        # replay events
        Enum.each(State.get(old_state_pid, :events), fn event ->
          send self(), {:send_map, event}
        end)

        # overwrite the old ws pid (which is dead)
        # to self()
        State.put(old_state_pid, :ws_pid, self())

        {:reply, dispatch(pid, :resumed), old_state_pid}
    end
  end

  def gateway_handle(:req_guild_members, %{
    "guild_id" => guild_id, "query" => query, "limit" => limit,
  }, pid) do
    # Idea is we get the GenServer for what we want,
    # from there we pass the query and the limit
    guild_pid = Guild.Registry.get(guild_id)

    if String.length(query) > 0 do
      GenGuild.request_guild_members(guild_pid, query, limit, pid)
    end

    {:noreply, pid}
  end

  def gateway_handle(:guild_sync, guild_ids, pid) do
    uid = State.get(pid, :user_id)

    Enum.each(guild_ids, fn guild_id ->
      guild_pid = Guild.Registry.get(guild_id)

      # TODO: checks if the user is in the guild
      # before subscribing, maybe delegate
      # the job to the actual GenGuild.subcribe?
      GenGuild.subscribe(guild_pid, uid)

      send self(), {:send, dispatch(pid, :guild_sync, {guild_id, guild_pid})}
    end)

    {:noreply, pid}
  end

  def gateway_handle(atomp, _payload, pid) do
    Logger.info fn ->
      "Client gave an invalid OP code to us: #{inspect atomp}"
    end
    {:reply, {:close, 4001, "Invalid OP code"}, pid}
  end
end

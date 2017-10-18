defmodule Gateway.Websocket do
  @moduledoc """Main websocket"""

  require Logger
  @behavior :cowboy_websocket

  def hb_interval() do
    41250
  end
  
  def init(request, state) do
    Logger.info "New client: #{request}"
    hb_interval()
    |> :erlang.start_timer(self(), [:heartbeat])

    {:cowboy_websocket, req, state}
  end

  def terminate(_reason, _request, _state) do
    Logger.info "Terminating, #{inspect reason}"
    :ok
  end

  defp get_name() do
    "litecord-gateway-prd-0"
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

  def payload(:ack, state) do
    %{
      op: opcode(:ack),
      d: nil
    }
    |> encode(state)
  end

  def encode(map, state) do
    JSEX.encode(map)
  end

  def decode(raw, state) do
    JSEX.decode(raw)
  end
  
  # The logic is that the client
  # will send an IDENTIFY packet soon
  # after receiving this HELLO.
  def websocket_init(state) do
    hello = %{
      op: opcode(:hello),
      d: %{
	heartbeat_interval: hb_interval(),
	"_trace" => get_name()
      }
    }
    {:reply, {:text, encode(hello)}, state}
  end
  
  # Handle client frames
  def websocket_handle({:text, content}, req, state) do
    {:ok, payload} = decode(content, state)
    IO.puts "#{inspect payload}"
    gateway_handle(payload, req, state)
  end

  def websocket_handle(_any_frame, _req, state) do
    {:ok, state}
  end

  def websocket_info({_timeout, _ref, [:heartbeat]}, req, state) do
    case state[:heartbeat] do
      true ->
	hb_interval()
	|> :erlang.start_timer(self(), [:heartbeat])

	# something something I AM NOT GOOD WITH STATE
	{:ok, Map.put(state, :heartbeat, false)}
      false ->
	{:stop, state}
    end
  end

  @doc """
  Handle HEARTBEAT packets by the client.
  Send HEARTBEAT ACK packets
  """
  def gateway_handle(%{op: opcode(:heartbeat), d: seq}, req, state) do
    {:reply, payload(:ack), Map.put(state, :seq, seq)}
  end

  @doc """
  Handle IDENTIFY packet.
  Dispatches the READY event.
  """
  def gateway_handle(%{op: opcode(:identify),
		      token: token,}, req, state) do
    # {:reply, payload(:ack), Map.put(state, :seq, seq)}
  end

  # TODO: insert rest
end

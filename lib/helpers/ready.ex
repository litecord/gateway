defmodule Gateway.Ready do
  @moduledoc """
  Helper functions to validate
  the Identify->Ready part of the
  websocket connection
  """
  require Logger
  alias Gateway.Repo
  import Ecto.Query, only: [from: 2]

  @doc """
  Check if a token is valid, and if it
  is, set the state's user_id field to it.

  if not, this will close the websocket connection
  with authentication failed reason.
  """
  @spec check_token(pid(), String.t) :: boolean()
  def check_token(pid, token) do
    [encoded_uid, _, _] = String.split token, "."
    {:ok, user_id} = encoded_uid |> Base.url_decode64

    Logger.info "Querying ID #{user_id}"
    query = from u in "users",
      where: u.id == ^user_id,
      select: u.password_salt

    Repo.one(query)

    # Offload that to bridge
    res = Litebridge.request("TOKEN_VALIDATE", [token])
    Logger.debug fn -> 
      "res from litebridge request: #{inspect res}"
    end

    case res do
      :request_timeout ->
        Logger.warn fn ->
          "Request timeout"
        end

        State.ws_close(pid, 4001, "Authentication failed (timeout)")
        false
      [false, err] ->
        Logger.info fn ->
          "auth failed: #{err}"
        end
        State.ws_close(pid, 4001, "Authentication failed")
        false
      true ->
        Logger.info "IDENTIFIED"
        State.put(pid, :user_id, user_id)
        true
    end
  end

  def check_shard(pid, shard) do
    if Enum.count(shard) != 2 do
      Logger.info "Invalid shard"
      State.ws_close(pid, 4010, "Invalid shard (payload length)")
    end

    # we accept shards 0 to shard_count - 1
    [shard_id, shard_count] = shard
    if shard_count < 0 do
      Logger.info "Invalid shard from count"
      State.ws_close(pid, 4010, "Invalid shard (count < 0)")
    end

    if shard_id > shard_count do
      Logger.info "Invalid shard from id"
      State.ws_close(pid, 4010, "Invalid shard (id > count)")
    end
  end

  def generate_session_id() do
    # how to make session IDs not collide
    # with one another?
    # SOLUTION: don't care about it

    random_data = for _ <- 1..30, do: Enum.random(0..255)

    cap = &(:crypto.hash(:md5, &1))
    random_data
    |> cap.()
    |> Base.encode16(case: :lower)
  end
 
  def fill_session(pid, shard, properties, compress, large) do
    session_id = generate_session_id()
    State.put(pid, :session_id, session_id)

    # your usual connection properties
    State.put(pid, :shard, shard)
    State.put(pid, :properties, properties)
    State.put(pid, :compress, compress)
    State.put(pid, :large, large)

    State.Registry.put(pid)
  end
end

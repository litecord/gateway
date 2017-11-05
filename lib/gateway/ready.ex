defmodule Gateway.Ready do
  @moduledoc """
  Helper functions to validate
  the Identify->Ready part of the
  websocket connection
  """
  require Logger
  import Ecto.Query, only: [from: 2]

  def check_token(pid, token) do
    [encoded_uid, _, _] = String.split token, "."
    {:ok, user_id} = encoded_uid |> Base.url_decode64

    Logger.info "Querying ID #{user_id}"
    query = from u in "users",
      where: u.id == ^user_id,
      select: u.password_salt

    Gateway.Repo.one(query)

    # Offload that to bridge
    case Litebridge.request("TOKEN_VALIDATE", [token]) do
      [false, err] ->
	Logger.info "auth failed: #{err}"
	Gateway.State.send_ws(pid, {:error, 4001, "Authentication Failed"})
      any -> any
    end
  end

  def check_shard(pid, shard) do
    if Enum.count(shard) != 2 do
      Logger.info "Invalid shard"
      Gateway.State.send_ws(pid, {:error, 4010, "Invalid shard (len)"})
    end

    [shard_id, shard_count] = shard
    if shard_count < 1 do
      Logger.info "Invalid shard from count"
      Gateway.State.send_ws(pid, {:error, 4010, "Invalid shard (count < 1)"})
    end

    if shard_id > shard_count do
      Logger.info "Invalid shard from id"
      Gateway.State.send_ws(pid, {:error, 4010, "Invalid shard (id > count)"})
    end
  end

  def generate_session_id() do
    # TODO: how to make session IDs not collide
    # with one another?
    random_data = for _ <- 1..30, do: Enum.random(0..255)
    :crypto.hash(:md5, random_data) |> Base.encode16(case: :lower)
  end
 
  def fill_session(pid, properties, compress, large) do
    # TODO: generate session_id
    Gateway.State.put(pid, :session_id, generate_session_id())

    # your usual connection properties
    Gateway.State.put(pid, :properties, properties)
    Gateway.State.put(pid, :compress, compress)
    Gateway.State.put(pid, :large, large)
  end
end

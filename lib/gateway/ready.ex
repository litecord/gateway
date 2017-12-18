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
        State.send_ws(pid, {:error, 4001, "Authentication Failed"})
      true ->
        State.put(pid, :user_id, user_id)
    end
  end

  def check_shard(pid, shard) do
    if Enum.count(shard) != 2 do
      Logger.info "Invalid shard"
      State.send_ws(pid, {:error, 4010, "Invalid shard (len)"})
    end

    [shard_id, shard_count] = shard
    if shard_count < 1 do
      Logger.info "Invalid shard from count"
      State.send_ws(pid, {:error, 4010, "Invalid shard (count < 1)"})
    end

    if shard_id > shard_count do
      Logger.info "Invalid shard from id"
      State.send_ws(pid, {:error, 4010, "Invalid shard (id > count)"})
    end
  end

  def generate_session_id() do
    # TODO: how to make session IDs not collide
    # with one another?

    # SOLUTION: don't care about it
    random_data = for _ <- 1..30, do: Enum.random(0..255)

    random_data
    |> &(:crypto.hash(:md5, &1)).()
    |> Base.encode16(case: :lower)
  end
 
  def fill_session(pid, properties, compress, large) do
    State.put(pid, :session_id, generate_session_id())

    # your usual connection properties
    State.put(pid, :properties, properties)
    State.put(pid, :compress, compress)
    State.put(pid, :large, large)
  end
end

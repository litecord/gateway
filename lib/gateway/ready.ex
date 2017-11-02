defmodule Gateway.Ready do
  @moduledoc false

  def check_token(pid, _token) do
    # Query user ID in the token
  end

  def check_shard(pid, shard) do
    # TODO: add shard sanity checking
    if Enum.length(shard) != 2 do
      send self(), {:ready_error, {:error, 4010, "Invalid shard (len)"}}
    end

    [shard_id, shard_count] = shard
    if shard_count < 1 do
      send self(), {:ready_error, {:error, 4010, "Invalid shard (count < 1)"}}
    end

    if shard_id > shard_count do
      send self(), {:ready_error, {:error, 4010, "Invalid shard (id > count)"}}
    end
  end
  
  def fill_session(pid, properties, compress, large) do
    # TODO: generate session_id
    Gateway.State.put(pid, :session_id, "gay")

    # your usual connection properties
    Gateway.State.put(pid, :properties, properties)
    Gateway.State.put(pid, :compress, compress)
    Gateway.State.put(pid, :large, large)
  end
end

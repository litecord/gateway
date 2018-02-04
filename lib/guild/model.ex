defmodule Guild do
  @moduledoc """
  General functions for fetching guild data.
  """
  import Ecto.Query, only: [from: 2]
  alias Gateway.Repo

  @doc """
  Convert a guild struct to a guild map
  """
  @spec from_struct(Ecto.Struct.t()) :: Map.t
  def from_struct(struct) do
    struct
    |> Map.from_struct
    |> Map.delete(:__meta__)
  end

  @doc """
  Query one guild, based on its ID.
  """
  @spec get_guild(String.t) :: Ecto.Struct.t() | nil
  def get_guild(guild_id) do
    query = from g in Gateway.Guild,
      where: g.id == ^guild_id

    Repo.one(query)
  end
  
  @doc """
  Get all guild IDs a user is on, given its ID.
  """
  @spec get_guilds(String.t) :: [String.t]
  def get_guilds(user_id) when is_binary(user_id) do
    query = from m in "members",
      where: m.user_id == ^user_id,
      select: m.guild_id

    Repo.all(query)
  end
  
  @doc """
  Get all the guilds that are tied to a websocket connection
  (shard).
  """
  @spec get_guilds(pid()) :: [String.t]
  def get_guilds(pid) when is_pid(pid) do
    user_id = State.get(pid, :user_id)
    shard_id = State.get(pid, :shard_id)
    shard_total = State.get(pid, :shard_total)

    user_id
    |> get_guilds
    |> Enum.filter(fn guild_id ->
      {guild_id_int, _} = guild_id |> Integer.parse
      State.Registry.get_shard(guild_id_int, shard_total) == shard_id
    end)
  end

  @doc """
  Map a list of gulid IDs to maps that have its data.

  Commonly used across the websocket.
  """
  @spec map_guild_data([String.t]) :: [Map.t]
  def map_guild_data(guild_ids) do
    guild_ids
    |> Enum.map(fn guild_id ->
      struct = guild_id
               |> Guild.get_guild

      case struct do
        nil -> nil
        s -> s |> Guild.from_struct
      end
    end)
    |> Enum.filter(fn el ->
      el != nil
    end)
  end

end


defmodule User do
  @moduledoc """
  Helper functions for user information
  """
  import Ecto.Query, only: [from: 2]
  alias Gateway.Repo
  require Logger

  @doc """
  Query user information.
  """
  @spec get_user(String.t) :: Ecto.Sctruct.t() | nil
  def get_user(user_id) do
    Logger.debug fn ->
      "Querying user #{inspect user_id}"
    end

    query = from u in Gateway.User,
      where: u.id == ^user_id

    Repo.one(query)
  end

  @doc """
  Convert from a user struct to a user map.
  """
  @spec from_struct(Ecto.Struct.t()) :: Map.t
  def from_struct(struct) do
    struct
    |> Map.from_struct
    |> Map.delete(:__meta__)
    |> Map.delete(:password_hash)
    |> Map.delete(:password_salt)
  end

  @doc """
  Convert from a user struct to a user map,
  but keeping private information in the map.
  """
  @spec from_struct(struct(), :private) :: Map.t
  def from_struct(struct, :private) do
    struct
    |> Map.from_struct
  end
end

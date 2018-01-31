defmodule User do
  @moduledoc """
  Helper functions for user information
  """

  @doc """
  Convert from a user struct to a user map.
  """
  @spec from_struct(struct()) :: Map.t
  def from_struct(struct) do
    map = struct
    |> Map.from_struct
    |> Map.delete(:__meta__)
    |> Map.delete(:password_hash)
    |> Map.delete(:password_salt)
  end

  @doc """
  Convert from a user struct to a user map,
  but keeping private information in the map.
  """
  @spec from_struct(struct()) :: Map.t
  def from_struct(struct, :private) do
    struct
    |> Map.from_struct
  end
end

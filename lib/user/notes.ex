defmodule Notes do
  @moduledoc """
  Manage user-defined notes.

  This merely serves as an interface
  to the postgres table that stores the notes.
  """

  @spec get(String.t) :: Map.t
  @doc """
  Get all available notes coming from 1 user.
  """
  def get(user_id) do
    %{}
  end

  @spec get(string(), string()) :: String.t | nil
  @doc """
  Get a note.
  """
  def get(user_id, target_id) do
    ""
  end

  @spec set(string(), string(), string()) :: :ok
  @doc """
  Set a note.
  """
  def set(user_id, target_id, note) do
    :ok
  end
end

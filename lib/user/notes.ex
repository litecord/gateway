defmodule Notes do
  @moduledoc """
  Manage user-defined notes.

  This merely serves as an interface
  to the postgres table that stores the notes.
  """

  @spec get(user_id)
  @doc """
  Get all available notes coming from 1 user.
  """
  def get(user_id) do
    %{}
  end

  @spec get(string(), string())
  @doc """
  Get a note.
  """
  def get(user_id, target_id) do
  end

  @spec set(string(), string(), string())
  @doc """
  Set a note.
  """
  def set(user_id, target_id, note) do
  end
end

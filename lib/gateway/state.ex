defmodule Gateway.State do
  @moduledoc """
  This module defines a way
  for different parts of the gateway
  to request information about others.
  """

  def start_link() do
    :ets.new(:gs_state, [:set, :named_table, :protected])
  end

  @doc """
  Insert something into the shared state.
  """
  def set(key, value) do
    :ets.insert(:gs_state, {key, value})
  end

  @doc """
  Get a value from an unique key.
  """
  def simple_get(key) do
    :ets.lookup(:gs_state, key)
  end

  @doc """
  More complex version of simple_get\1.
  """
  def all_keys(user_id) do
    :ets.match(:gs_state, %{})
  end
end

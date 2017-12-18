defmodule Gateway do
  @moduledoc """
  Entry point for the main application.
  """
  import Application

  def start(_type, _args) do
    Gateway.Supervisor.start_link(name: Gateway.Supervisor)
  end
end

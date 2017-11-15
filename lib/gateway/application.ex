defmodule Gateway.Supervisor do
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    opts = [strategy: :one_for_one, name: Gateway.Supervisor]
    Logger.info "Starting gateway"
    Supervisor.init([
      Gateway.Repo,
      Guild.Registry,
      State.Registry,
      %{
	id: Gateway.Cowboy,
	start: {Gateway.Cowboy, :start_link, []}
      },
    ], opts)
  end
end

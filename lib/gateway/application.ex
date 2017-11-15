defmodule Gateway.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    opts = [strategy: :one_for_one, name: Gateway.Supervisor]
    Supervisor.init([
      Gateway.Repo,
      Guild.Registry,
      %{
	id: Gateway.Cowboy,
	start: {Gateway.Cowboy, :start_link, []}
      },
    ], opts)
  end
end

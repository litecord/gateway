defmodule Gateway.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    import Supervisor.Spec

    children = [
	supervisor(Gateway.Cowboy, []),
	supervisor(Gateway.Repo, [])
    ]

    opts = [strategy: :one_for_one, name: Gateway.Supervisor]
    Supervisor.init(children, opts)
  end
end

defmodule Gateway.Mixfile do
  use Mix.Project

  def project do
    [
      app: :gateway,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Gateway, []},
      applications: [:cowboy, :ranch, :ecto, :postgrex],
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cowboy, "~> 2.0.0"},
      {:poison, "~> 3.1"},
      {:postgrex, ">= 0.0.0"},
      {:ecto, "~> 2.1"},
      {:credo, "~> 0.8", only: [:dev, :test], runtime: false},
    ]
  end
end

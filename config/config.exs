use Mix.Config

config :gateway,
  adapter: Ecto.Adapters.Postgres,
  ecto_repos: [Gateway.Repo]

config :gateway, Gateway.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "litecord",
  username: "litecord",
  password: "assass6969",
  hostname: "localhost",
  port: "5432"

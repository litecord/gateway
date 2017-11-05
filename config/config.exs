use Mix.Config

config :gateway, Gateway.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "litecord",
  username: "litecord",
  password: "123",
  hostname: "localhost"


config :gateway,
  bridge_password: "123"

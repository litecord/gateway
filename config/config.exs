use Mix.Config

config :gateway, Gateway.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "litecord",
  username: "litecord",
  password: "123",
  hostname: "localhost"


config :gateway,
  mode: :http,
  http_port: 8081,
  https_port: 8443,
  bridge_port: 10_101,
  bridge_password: "123"

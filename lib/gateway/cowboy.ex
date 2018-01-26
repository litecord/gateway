defmodule Gateway.Cowboy do
  @moduledoc """
  Entry point for the webserver and websocket servers.
  """
  require Logger

  def start_link() do
    dispatch_config = build_dispatch_config()

    Logger.info "Starting cowboy at :8080"
    {:ok, _} = :cowboy.start_clear(:http,
      [{:port, 8081}],
      %{env: %{dispatch: dispatch_config}}
    )
  end

  # If we get HTTPS working, rename
  # this function to start_link
  def start_link_https() do
    dispatch_config = build_dispatch_config()

    {:ok, _} = :cowboy.start_tls(:litecord_http,
      [
        {:port, 8443},
        {:certfile, ""},
        {:keyfile, ""}
      ], %{env: %{dispatch: dispatch_config}})
  end
  
  def build_dispatch_config do
    :cowboy_router.compile([
      {:_, [
          {"/", Gateway.DefaultHandler, []},
          {"/gw", Gateway.Websocket, %{}},
          {"/bridge", Gateway.Bridge, %{}}
        ]}
    ])
  end
end

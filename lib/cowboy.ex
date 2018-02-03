defmodule Gateway.DefaultHandler do
  @moduledoc """
  Just a default handler for /
  """
  require Logger

  def init(req0, state) do
    Logger.info "giving a hello"
    req = :cowboy_req.reply(200,
      %{"content-type" => "text/plain"},
      "helo",
      req0
    )
    {:ok, req, state}
  end
end

defmodule Gateway.Cowboy do
  @moduledoc """
  Entry point for the webserver and websocket servers.
  """
  require Logger

  def start_link() do
    dispatch_config = build_dispatch_config()

    port = case Application.fetch_env(:gateway, :http_port) do
      {:ok, http_port} ->
        http_port
      :error ->
        8081
    end

    Logger.info "Starting http at :#{port}"
    {:ok, _} = :cowboy.start_clear(:litecord_http,
      [{:port, port}],
      %{env: %{dispatch: dispatch_config}}
    )
  end

  # If we get HTTPS working, rename
  # this function to start_link
  def start_link_https() do
    dispatch_config = build_dispatch_config()

    port = case Application.fetch_env(:gateway, :http_port) do
      {:ok, http_port} ->
        http_port
      :error ->
        8443
    end

    Logger.info "Starting https at :#{port}"

    {:ok, _} = :cowboy.start_tls(:litecord_https,
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

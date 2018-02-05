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
    mode = Application.fetch_env!(:gateway, :mode)

    start_link_bridge

    case mode do
      :http -> start_link_http
      :https -> start_link_https
    end
  end

  def start_link_bridge do
    dispatch_config = bridge_dispatch_config()

    port = Application.fetch_env!(:gateway, :bridge_port)
    Logger.info "Starting bridge at :#{port}"
    {:ok, _} = :cowboy.start_clear(
      :litecord_bridge,
      [port: port],
      %{env: %{dispatch: dispatch_config}}
    )
  end

  def start_link_http do
    dispatch_config = build_dispatch_config()
    port = Application.fetch_env!(:gateway, :http_port)

    Logger.info "Starting http at :#{port}"
    {:ok, _} = :cowboy.start_clear(
      :litecord_http,
      [{:port, port}],
      %{env: %{dispatch: dispatch_config}}
    )
  end

  def start_link_https() do
    dispatch_config = build_dispatch_config()
    port = Application.fetch_env(:gateway, :https_port)

    Logger.info "Starting https at :#{port}"
    {:ok, _} = :cowboy.start_tls(
      :litecord_https,
      [
        {:port, port},
        {:certfile, ""},
        {:keyfile, ""}
      ], %{env: %{dispatch: dispatch_config}})
  end

  def bridge_dispatch_config do
    :cowboy_router.compile([
      {:_, [
        {"/", Gateway.Bridge, %{}}
      ]}
    ])
  end
  
  def build_dispatch_config do
    :cowboy_router.compile([
      {:_, [
          {"/", Gateway.DefaultHandler, []},
          {"/gw", Gateway.Websocket, %{}},
        ]}
    ])
  end
end

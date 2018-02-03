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

    # TODO: use port from Application.fetch_env!()

    Logger.info "Starting cowboy at :8081"
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

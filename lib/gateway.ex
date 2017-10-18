defmodule Gateway do
  def start(_type, _args) do
    dispatch_config = build_dispatch_config()

    {:ok, _} = :cowboy.start_http(:http,
      100,
      [{:port, 8080}],
      [{:env, [{:dispatch, dispatch_config}]}])
  end

  def build_dispatch_config do
    :cowboy_router.compile([
      {:_, [
	  {"/gw", Gateway.Websocket, []}
	]}
    ])
  end
end

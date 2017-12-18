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

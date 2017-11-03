defmodule GatewayTest do
  use ExUnit.Case
  doctest Gateway

  test "testing hmac" do
    key = "good key"
    enc = HMAC.encode(key, "mydata")
    assert HMAC.valid?(key, enc)
    assert not HMAC.valid?(key, enc + "something else")
  end
end

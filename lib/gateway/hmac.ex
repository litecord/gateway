defmodule HMAC do
  def encode(key, data) do
    encoded = :crypto.hmac(:sha256, key, data)
    |> Base.url_encode64

    "#{data}.#{encoded}"
  end

  def valid?(key, encoded) do
    s = String.split(encoded, ".")

    data = Enum.at(s, 0)
    correct_hmac = encode(key, data)
    correct_hmac == encoded
  end
end

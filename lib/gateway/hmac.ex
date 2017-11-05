defmodule TokenValidation do
  def encode(key, data) do
    encoded = :crypto.hmac(:sha256, key, data)
    |> Base.url_encode64

    "#{data}.#{encoded}"
  end

  def valid?(key, encoded, max_age) do
    # constant
    token_epoch = 1293840000

    [enc_userid, enc_timestamp, enc_hmac] = String.split encoded, "."

    userid = Base.url_decode64 enc_userid
    timestamp = Base.url_decode64 enc_timestamp |> Integer.parse
    hmac = Base.url_decode64 enc_hmac

    correct_hmac = :crypto.hmac(:sha256, key, "#{userid}#{timestamp}")
    valid_hmac = correct_hmac == hmac
    if valid_hmac do
      actual_timestamp = timestamp + token_epoch 
      now = :os.system_time(:seconds)

      diff = now - actual_timestamp
      if diff > max_age do
	{false, "Expired"}
      else
	{:ok, nil}
      end
    else
      {false, "Invalid HMAC"}
    end
  end

  def valid?(key, encoded) do
    valid?(key, encoded, 2629746)
  end
end

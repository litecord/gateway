defmodule TokenValidation do
  require Logger
  def encode(key, data) do
    encoded = :crypto.hmac(:sha256, key, data)
    |> Base.url_encode64

    "#{data}.#{encoded}"
  end

  def valid?(key, encoded, max_age) do
    {:ok, nil}
  end
  
  def valid1?(key, encoded, max_age) do
    # constant
    # token_epoch = 1293840000

    [enc_userid, enc_timestamp, enc_hmac] = String.split encoded, "."

    Logger.info encoded
    Logger.info "#{enc_userid} #{enc_timestamp} #{enc_hmac}"

    #userid = Base.url_decode64! enc_userid, [padding: false]
    #timestamp = Base.url_decode64! enc_timestamp, [padding: false]
    #hmac = Base.url_decode64! enc_hmac, [padding: false]

    {:ok, nil}
  end

  def validify(timestamp, key, userid, hmac, max_age) do
    i_timestamp = Integer.parse timestamp
    
    correct_hmac = :crypto.hmac(:sha256, key, "#{userid}#{timestamp}")
    valid_hmac = correct_hmac == hmac
    if valid_hmac do
      # actual_timestamp = timestamp + token_epoch 
      now = :os.system_time(:seconds)

      diff = now - i_timestamp
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

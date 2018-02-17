defmodule Snowflake do

  @spec parse_snowflake(String.t) :: integer()
  def parse_snowflake(snowflake) do
    {parsed, _} = Integer.parse snowflake
    parsed
  end

  @spec snowflake_time(String.t) :: DateTime.t
  def snowflake_time(snowflake) do
    use Bitwise

    snowflake
    |> parse_snowflake
    |> (fn sflake ->
      # extract timestamp (milliseconds)
      (sflake >>> 22) + 1_420_070_400_000
    end).()
    |> DateTime.from_unix!(:millisecond)
  end

  @spec time_timestamp(DateTime.t) :: String.t
  def time_timestamp(datetime) do
    datetime |> DateTime.to_iso8601
  end

  def time_snowflake(datetime) do
    # TODO: we'd need to make our own snowflake library.
    :not_implemented
  end
end

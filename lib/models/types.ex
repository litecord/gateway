defmodule Types do
  @type state_pid() :: pid()
  @type state_type() :: boolean() | integer() | pid() | String.t | List.t 

  @type snowflake() :: String.t

  @type user_id() :: snowflake()
  @type guild_id() :: snowflake()
  @type channel_id() :: snowflake()

end

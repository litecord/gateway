defmodule Presence do
  def default_presence() do
    default_presence("online")
  end

  def default_presence(status) do
    %{status: status,
      type: 0,
      name: nil,
      url: nil
    }
  end

  def dispatch(_state, _presence) do
    #Enum.each(Gateway.State.get_conns(state), fn pid ->
    #  send pid, {:dispatch, presence}
    #end)
  end

  def guild_sub(_state, :all) do
    # Get all guilds a user is in
    # Subscribe in all of them
  end
end

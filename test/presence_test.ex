defmodule PresenceTest do
  use ExUnit.Case
  doctest Presence

  setup do
    {:ok, pid} = Presence.start
    %{pid: pid}
  end

  test "sub and unsub to guild", %{pid: pid} do
    # just a random user with ID 1
    Presence.subscribe(pid, "1", "1")
    Presence.unsubscribe(pid, "1", "1")
  end

  test "dispatch to unknown user", %{pid: pid} do
    IO.puts "test"
    dp = Presence.default_presence()
    Presence.dispatch_user dp, "1"
  end
end

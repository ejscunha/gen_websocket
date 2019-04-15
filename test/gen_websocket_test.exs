defmodule GenWebsocketTest do
  use ExUnit.Case
  doctest GenWebsocket

  test "greets the world" do
    assert GenWebsocket.hello() == :world
  end
end

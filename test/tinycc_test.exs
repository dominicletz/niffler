defmodule TinyccTest do
  use ExUnit.Case
  doctest Tinycc

  test "greets the world" do
    assert Tinycc.hello() == :world
  end
end

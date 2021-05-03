defmodule StdlibTest do
  use ExUnit.Case
  use Niffler
  doctest Niffler

  defnif :reverse, [input: :binary], ret: :binary do
    """
    $ret.data = $alloc($input.size);
    $ret.size = $input.size;
    for (int i = 0; i < $input.size; i++)
      $ret.data[i] = $input.data[$input.size-(i+1)];
    """
  end

  test "test reverse" do
    assert {:ok, [<<1, 2, 3>>]} = reverse(<<3, 2, 1>>)
  end

  defnif :sprintf, [], ret: :binary do
    """
    static char lol[16];
    $ret.data = lol;
    $ret.size = snprintf(lol, sizeof(lol), "%d", 28);
    """
  end

  test "test sprintf" do
    assert {:ok, ["28"]} = sprintf()
  end
end

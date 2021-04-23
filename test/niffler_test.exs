defmodule NifflerTest do
  use ExUnit.Case
  use Niffler
  doctest Niffler

  defnif :count_zeros, [str: :binary], ret: :int do
    """
    while($str.size--) {
      if (*$str.data++ == 0) $ret++;
    }
    """
  end

  test "test count zeros" do
    assert {:ok, [2]} = count_zeros(<<0, 11, 0>>)
    assert {:ok, [1]} = count_zeros(<<0>>)
    assert {:ok, [0]} = count_zeros(<<13>>)
    assert {:ok, [0]} = count_zeros(<<>>)
    assert {:error, "parameter should be binary"} = count_zeros([])
  end

  defnif :fib, [a: :int], ret: :int do
    """
    int64_t fib(int64_t f) {
      if (f < 2) return 1;
      return fib(f-1) + fib(f-2);
    }

    DO_RUN
      $ret = fib($a);
    END_RUN
    """
  end

  test "test fib" do
    assert {:ok, [8]} = fib(5)
  end

  defnif :counter, [], ret: :int do
    """
    static uint64_t counter = 0;
    $ret = counter++;
    """
  end

  test "test counter" do
    assert {:ok, [0]} = counter()
    assert {:ok, [1]} = counter()
    assert {:ok, [2]} = counter()
    assert {:ok, [3]} = counter()
  end

  defnif :make_binary, [], ret: :binary do
    """
    static char lol[16];
    for (int i = 0; i < sizeof(lol); i++) lol[i] = i;
    $ret.size = sizeof(lol);
    $ret.data = lol;
    """
  end

  test "test binary" do
    assert {:ok, [<<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>]} = make_binary()
  end
end

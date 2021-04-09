defmodule TinyccTest do
  use ExUnit.Case
  use Tinycc
  doctest Tinycc

  defc :count_zeros, [str: :binary], ret: :int do
    """
    ret = 0;
    while(str->size--) {
      if (*str->data++ == 0) ret++;
    }
    """
  end

  test "test count zeros" do
    assert {:ok, [2]} = count_zeros([<<0,11,0>>])
  end


  defc :fib, [a: :int], ret: :int do
    """
    int64_t fib(int64_t f) {
      if (f < 2) return 1;
      return fib(f-1) + fib(f-2);
    }

    void run() {
      ret = fib(a);
    }
    """
  end

  test "test fib" do
    assert {:ok, [8]} = fib([5])
  end
end

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
end

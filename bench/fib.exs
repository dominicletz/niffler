
defmodule Fib do
  use Niffler

  def fib_elixir(f) when f < 2, do: 1
  def fib_elixir(f), do: fib_elixir(f-1) + fib_elixir(f-2)

  def fib_nif!(bin) do
    {:ok, [ret]} = fib_nif(bin)
    ret
  end

  defnif :fib_nif, [a: :int], ret: :int do
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

end

input = 17

result = Fib.fib_elixir(input)
^result = Fib.fib_nif!(input)

Benchee.run(
  %{
    "fib_elixir" => fn -> Fib.fib_elixir(input) end,
    "fib_nif" => fn -> Fib.fib_nif!(input) end
  }
)


defmodule Noop do
  use Niffler

  def noop_elixir(bin), do: bin

  def noop_nif!(bin) do
    {:ok, [ret]} = noop_nif([bin])
    ret
  end

  defnif :noop_nif, [a: :int], ret: :int do
    "ret = a;"
  end
end

0 = Noop.noop_elixir(0)
0 = Noop.noop_nif!(0)
{:ok, [0]} = Noop.noop_nif([0])

Benchee.run(
  %{
    "noop_nif!" => fn -> Noop.noop_nif!(0) end,
    "noop_nif" => fn -> Noop.noop_nif([0]) end,
    "noop_elixir" => fn -> Noop.noop_elixir(0) end
  }
)

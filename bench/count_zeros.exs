
defmodule CountZeros do
  use Niffler

  def count_zeros_elixir(bytes) do
    length(for <<byte::8 <- bytes>>, byte == 0, do: byte)
  end

  def count_zeros_nif!(bin) do
    {:ok, [ret]} = count_zeros_nif(bin)
    ret
  end

  defnif :count_zeros_nif, [str: :binary], ret: :int do
    "ret = 0; while(str.size--) if (*str.data++ == 0) ret++;"
  end

end

bin = :crypto.strong_rand_bytes(64_000)

result = CountZeros.count_zeros_elixir(bin)
^result = CountZeros.count_zeros_nif!(bin)

Benchee.run(
  %{
    "count_zeros_elixir" => fn -> CountZeros.count_zeros_elixir(bin) end,
    "count_zeros_nif" => fn -> CountZeros.count_zeros_nif!(bin) end
  }
)

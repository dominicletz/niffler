defmodule Reverse do
  use Niffler

  def elixir(bytes) do
    :binary.bin_to_list(bytes)
    |> Enum.reverse()
    |> :binary.list_to_bin()
  end

  def nif!(bin) do
    {:ok, [ret]} = nif(bin)
    ret
  end

  defnif :nif, [input: :binary], ret: :binary do
    """
    $ret.data = $alloc($input.size);
    $ret.size = $input.size;
    for (int i = 0; i < $input.size; i++)
      $ret.data[i] = $input.data[$input.size-(i+1)];
    """
  end
end

bin = :crypto.strong_rand_bytes(64_000)

result = Reverse.elixir(bin)
^result = Reverse.nif!(bin)

Benchee.run(
  %{
    "Reverse.elixir" => fn -> Reverse.elixir(bin) end,
    "Reverse.nif" => fn -> Reverse.nif!(bin) end
  }
)

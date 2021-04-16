defmodule ConcurrencyTest do
  use ExUnit.Case
  use Niffler
  doctest Niffler

  defnif :count_zeros, [str: :binary], ret: :int do
    """
    ret = 0;
    while(str.size--) {
      if (*str.data++ == 0) ret++;
    }
    """
  end

  test "test parallel counts" do
    sizes = [64_000, 32_000, 1_000]
    tests = Enum.map(sizes, &testdata/1)
    rounds = 1000
    workers = 100

    spawn_workers(workers, fn ->
      for _ <- 1..rounds do
        for {data, answer} <- tests do
          ^answer = count_zeros([data])
        end
      end
    end)
  end

  defp testdata(size) do
    data = :crypto.strong_rand_bytes(size)
    answer = count_zeros([data])
    {data, answer}
  end

  defp spawn_workers(n, fun, pids \\ [])

  defp spawn_workers(0, _fun, pids) do
    Enum.map(pids, fn pid ->
      receive do
        {:done, ^pid, ret} -> ret
      end
    end)
  end

  defp spawn_workers(n, fun, pids) do
    me = self()
    pid = spawn_link(fn -> send(me, {:done, self(), fun.()}) end)
    spawn_workers(n - 1, fun, [pid | pids])
  end
end

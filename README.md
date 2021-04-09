# Tinycc [![Build Status](https://travis-ci.com/dominicletz/tinycc.svg?branch=main)](https://travis-ci.com/dominicletz/tinycc)

Tinycc is a C-JIT implemented is nif binding to (libtcc)[https://bellard.org/tcc/]. Tinycc allows converting small c fragments into nif backed functions *AT RUNTIME*

# Module Example:

```
defmodule Example do
  use Tinycc

  defc :count_zeros, [str: :binary], ret: :int do
    """
    ret = 0;
    while(str->size--) {
      if (*str->data++ == 0) ret++;
    }
    """
  end
end

{:ok, [2]} = Example.count_zeros([<<0,11,0>>])
```

# Shell Example:

```
  iex> {:ok, prog} = Tinycc.compile("ret = a * b;", [a: :int, b: :int], [ret: :int])
  iex> Tinycc.run(prog, [3, 4])
  {:ok, [12]}

```

# Benchmarks

```
> mix run bench/count_zeros.exs
...
Benchmarking count_zeros_elixir...
Benchmarking count_zeros_nif...

Name                         ips        average  deviation         median         99th %
count_zeros_nif           6.87 K      145.47 μs    ±15.18%      141.22 μs      223.31 μs
count_zeros_elixir        3.54 K      282.68 μs    ±12.06%      271.96 μs      404.90 μs

Comparison: 
count_zeros_nif           6.87 K
count_zeros_elixir        3.54 K - 1.94x slower +137.22 μs
```

# Todos

This library is work in progress. Feel free to open a PR to any of these:

* Test on windows
* Integrate with CI
* Add more tests for string/binary types
* Compile functions on module load not on first call
* Use async thread to avoid blocking in long-running nifs
* Better documentation
* Include c-standard library libtcc1.a 

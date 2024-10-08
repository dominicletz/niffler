![Niffler](https://github.com/dominicletz/niffler/blob/main/img/niffler.png?raw=true)

# Niffler ![Build](https://github.com/dominicletz/niffler/actions/workflows/test.yml/badge.svg)

Niffler is a C-JIT implemented is nif binding to [libtcc](https://bellard.org/tcc/). Niffler allows converting small c fragments into nif backed functions *AT RUNTIME*.

*Warning:* Even though cute, the Niffler is very dangerous creature that when treated without enough attention can quickly cause havoc accross your whole BEAM.

# Use Cases

* Call your .dll / .so / .dylib dynamic library code from Elixir.
* Make things faster (most binary/math code is ~3x faster with the niffler)
* Create chaos in memory (seriously be careful with c-fragments)

# Module Example:

```
defmodule Example do
  use Niffler

  # Binaries (strings) have .data and .size
  defnif :count_zeros, [str: :binary], ret: :int do
    """
    while($str.size--) {
      if (*$str.data++ == 0) $ret++;
    }
    """
  end

  # If binaries return size is 0, strlen() is used to get the size
  defnif :hello, [], ret: :binary do
    """
    $ret.data = "Hello from C";
    """
  end
end

{:ok, [2]} = Example.count_zeros(<<0,11,0>>)
{:ok, ["Hello from C"]} = Example.hello()
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

# Windows

I've only tried compiling & running this under windows with the [msys2](https://www.msys2.org/) toolchain. For that you need to install dlfcn and export the rebar variables:

```
msys2-64 $> pacman -S mingw-w64-x86_64-dlfcn
# and for the libgmp test:
msys2-64 $> pacman -S mingw-w64-x86_64-gmp-6.2.0-3 

msys2-64 $> export REBAR_TARGET_ARCH_WORDSIZE=64
msys2-64 $> export REBAR_TARGET_ARCH=x86_64-w64-mingw32
msys2-64 $> mix deps.get
msys2-64 $> mix test
```

# Todos

This library is work in progress. Feel free to open a PR to any of these:

* Add nif options to:
  * Use async thread to avoid blocking in long-running nifs
  * Use mutex locks for non-thread-safe code
* Add access to useful erlang enif_* functions

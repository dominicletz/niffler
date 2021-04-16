# Introduction

If installing from Hex, use the latest version from there:

```elixir
def deps do
  [
    {:niffler, "~> 0.1"}
  ]
end
```

If you want the latest features, install from GitHub:

```elixir
def deps do
  [
    {:phoenix_live_view, github: "dominicletz/niffler"}
  ]
```

Once installed, you can use the Niffler to define new nif modules using embedded C fragments:

```
defmodule Example do
  use Niffler

  defnif :count_zeros, [str: :binary], ret: :int do
    """
    ret = 0;
    while(str.size--) {
      if (*str.data++ == 0) ret++;
    }
    """
  end
end
```

## Warnings

As long as you keep good track of the Niffler he going to server you well, but left alone on his
own he quickly becomes are nightmare to take care of. Null pointer exceptions, segmentations faults
and memory leaks are all common ways a Niffler can cause havoc.

## Concurrency

Each generated Niffler function is a small c program in it's own dedicated memory space. Multiple 
runs of the same program are all executed in the same context. This allows to keep state in 
c programs when needed but also increases the chances for concurrency issues. 

For simple programs the niffler protects against concurrency issues by creating all input and output
variables on the call stack. So two functions calls at the same time do never interefere on the input
and output parameters.


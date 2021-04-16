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
    while(str->size--) {
      if (*str->data++ == 0) ret++;
    }
    """
  end
end
```


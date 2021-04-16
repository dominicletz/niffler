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
    {:niffler, github: "dominicletz/niffler"}
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

## Working with binaries

When using binaries as input or output they are returned as as a struct with two members:

```C
  typedef struct {
    uint64_t size;
    unsigned char* data;
  } Binary;
```

The size and data fields can be used to reads from inputs and write to outputs.

*Warning:* __NEVER__ write to input binaries. These are pointers into the BEAM VM, changing
their values will have unknown but likely horrible consequences. 

Output binaries can be constructed and returned at the moment only from static variables. On stack
variables don't work as they are being destroyed as the Niffler program returns. An example that is 
possible from the tests here:

```
  defnif :make_binary, [], ret: :binary do
    """
    static char str[16];
    for (int i = 0; i < sizeof(str); i++) str[i] = i;
    ret.size = sizeof(str);
    ret.data = str;
    """
  end

  test "test binary" do
    assert {:ok, [<<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>]} = make_binary([])
  end
```

## Concurrency

Each generated Niffler function is a small c program in it's own dedicated memory space. Multiple 
runs of the same program are all executed in the same context. This allows to keep state in 
c programs when needed but also increases the chances for concurrency issues. 

Let's take for example this stateful counter:

```
  defnif :counter, [], ret: :int do
    """
    static uint64_t counter = 0;
    ret = counter++;
    """
  end
```

The niffler protects against concurrency issues by creating all input and output variables
on the call stack. So two functions calls at the same time do never interefere on the input
and output parameters. 

But as this example is using a static counter variable, this variable will be the same instance. So
with high concurrency these things could happen:

* counter returns the same value for two concurrent calls.
* counter skips a value for two concurrent calls.



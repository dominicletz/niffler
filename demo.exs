#!/usr/bin/env elixir
Mix.install([
  :niffler,
  :phoenix_playground
])

defmodule Demo.Niffler do
  use Niffler

  defnif :hello, [], ret: :binary do
    """
    $ret.data = "Hello from C";
    """
  end
end

defmodule Demo do
  use Phoenix.LiveView

  def mount(_, _, socket) do
    {:ok, hello_from_c} = Demo.Niffler.hello()
    {:ok, assign(socket, hello_from_c: hello_from_c)}
  end

  def render(assigns) do
    ~H"""
    <p><%= @hello_from_c %></p>
    """
  end
end

PhoenixPlayground.start(live: Demo)

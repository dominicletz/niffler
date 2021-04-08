defmodule Tinycc do
  @on_load :init

  @moduledoc """
  Documentation for `Tinycc`.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Tinycc
      @tinycc_module __MODULE__
    end
  end

  defmacro defc(name, inputs, outputs, do: source) do
    quote do
      def unquote(name)(args) do
        key = {@tinycc_module, unquote(name)}

        :persistent_term.get(key, nil)
        |> case do
          nil ->
            prog = Tinycc.compile!(unquote(source), unquote(inputs), unquote(outputs))
            :persistent_term.put(key, prog)
            prog

          prog ->
            prog
        end
        |> Tinycc.run(args)
      end
    end
  end

  @doc false
  def gen!(key, source, inputs, outputs) do
    :persistent_term.put(key, Tinycc.compile!(source, inputs, outputs))
  end

  @doc false
  def init do
    :ok =
      case :code.priv_dir(:tinycc) do
        {:error, :bad_name} ->
          if File.dir?(Path.join("..", "priv")) do
            Path.join("..", "priv")
          else
            "priv"
          end

        path ->
          path
      end
      |> Path.join("tinycc.nif")
      |> String.to_charlist()
      |> :erlang.load_nif(0)
  end

  @doc """
  Hello world.

  ## Examples

      iex> {:ok, prog} = Tinycc.compile("ret = a * b;", [a: :int, b: :int], [ret: :int])
      iex> Tinycc.run(prog, [3, 4])
      {:ok, [12]}

      iex> code = "ret = 0; for (int i = 0; i < str->size; i++) if (str->data[i] == 0) ret++;"
      iex> {:ok, prog} = Tinycc.compile(code, [str: :binary], [ret: :int])
      iex> Tinycc.run(prog, [<<0,1,1,0,1,5,0>>])
      {:ok, [3]}

  """
  def compile(code, inputs, outputs)
      when is_binary(code) and is_list(inputs) and is_list(outputs) do
    type_defs =
      [
        Enum.map(inputs, fn {name, type} -> "extern #{type_name(type)} #{name};" end),
        Enum.map(outputs, fn {name, type} -> "#{type_name(type)} #{name};" end)
      ]
      |> Enum.concat()
      |> Enum.join("\n")

    code = """
      #{header()}
      #{type_defs}
      void run() {
        #{code}
      }
    """

    case nif_compile(code <> <<0>>, inputs, outputs) do
      {:error, message} ->
        IO.puts(code)
        {:error, message <> " in '#{code}'"}

      other ->
        other
    end
  end

  def compile!(code, inputs, outputs) do
    {:ok, prog} = compile(code, inputs, outputs)
    prog
  end

  defp nif_compile(_code, _inputs, _outputs) do
    exit(:nif_library_not_loaded)
  end

  @doc """
  Hello world.

  ## Examples

      iex> Tinycc.hello()
      :world

  """
  def run(prog, args) do
    nif_run(prog, args)
  end

  def run!(prog, args) do
    {:ok, ret} = run(prog, args)
    ret
  end

  defp nif_run(_state, _args) do
    exit(:nif_library_not_loaded)
  end

  defp type_name(:int), do: "int64_t"
  defp type_name(:int64), do: "int64_t"
  defp type_name(:uint64), do: "uint64_t"
  defp type_name(:double), do: "double"
  defp type_name(:binary), do: "struct Binary*"

  defp header() do
    """
      typedef signed char int8_t;
      typedef unsigned char   uint8_t;
      typedef short  int16_t;
      typedef unsigned short  uint16_t;
      typedef int  int32_t;
      typedef unsigned   uint32_t;
      typedef long long  int64_t;
      typedef unsigned long long   uint64_t;

      struct Binary {
        uint64_t size;
        unsigned char* data;
      };
    """
  end
end

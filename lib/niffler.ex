defmodule Niffler do
  @on_load :init

  @moduledoc """
  Documentation for `Niffler`.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Niffler
      @niffler_module __MODULE__
    end
  end

  defmacro defnif(name, inputs, outputs, do: source) do
    keys = Keyword.keys(inputs) |> Enum.map(fn n -> Macro.var(n, __MODULE__) end)

    quote do
      def unquote(name)(unquote_splicing(keys)) do
        key = {@niffler_module, unquote(name)}

        :persistent_term.get(key, nil)
        |> case do
          nil ->
            prog = Niffler.compile!(unquote(source), unquote(inputs), unquote(outputs))
            :persistent_term.put(key, prog)
            prog

          prog ->
            prog
        end
        |> Niffler.run([unquote_splicing(keys)])
      end
    end
  end

  @doc false
  def gen!(key, source, inputs, outputs) do
    :persistent_term.put(key, Niffler.compile!(source, inputs, outputs))
  end

  @doc false
  def init do
    :ok =
      case :code.priv_dir(:niffler) do
        {:error, :bad_name} ->
          if File.dir?(Path.join("..", "priv")) do
            Path.join("..", "priv")
          else
            "priv"
          end

        path ->
          path
      end
      |> Path.join("niffler.nif")
      |> String.to_charlist()
      |> :erlang.load_nif(0)
  end

  @doc """
  Compile takes a string as input and compiles it into a nif program. Returning the program
  reference.any()

  ## Examples

      iex> {:ok, prog} = Niffler.compile("$ret = $a * $b;", [a: :int, b: :int], [ret: :int])
      iex> Niffler.run(prog, [3, 4])
      {:ok, [12]}

      iex> code = "for (int i = 0; i < $str.size; i++) if ($str.data[i] == 0) $ret++;"
      iex> {:ok, prog} = Niffler.compile(code, [str: :binary], [ret: :int])
      iex> Niffler.run(prog, [<<0,1,1,0,1,5,0>>])
      {:ok, [3]}

  """
  def compile(code, inputs, outputs)
      when is_binary(code) and is_list(inputs) and is_list(outputs) do
    code =
      if String.contains?(code, "DO_RUN") do
        """
        #{type_defs(inputs, outputs)}
        #{code}
        #{type_undefs(inputs, outputs)}
        """
      else
        """
        DO_RUN
          #{type_defs(inputs, outputs)}
          #{code}
          #{type_undefs(inputs, outputs)}
        END_RUN
        """
      end

    compile(code, [{inputs, outputs}])
  end

  def compile!(code, inputs, outputs) do
    {:ok, prog} = compile(code, inputs, outputs)
    prog
  end

  def compile(code, params) do
    code =
      """
        #{header()}

        #define DO_RUN #{method_name("run")} {
        #define END_RUN return 0; }

        #{code}
      """ <> <<0>>

    case nif_compile(code, params) do
      {:error, message} ->
        message =
          if message == "compilation error" do
            lines =
              String.split(code, "\n")
              |> Enum.with_index(1)
              |> Enum.map(fn {line, num} -> String.pad_leading("#{num}: ", 4) <> line end)
              # |> Enum.drop(110)
              |> Enum.join("\n")

            IO.puts(lines)
            message <> " in '#{code}'"
          else
            message
          end

        {:error, message}

      other ->
        other
    end
  end

  def compile!(code, params) do
    {:ok, prog} = compile(code, params)
    prog
  end

  defp nif_compile(_code, _params) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @doc """
  Executes the given Niffler program and return any output values

  ## Examples

      iex> {:ok, prog} = Niffler.compile("$ret = $a << 2;", [a: :int], [ret: :int])
      iex> Niffler.run(prog, [5])
      {:ok, [20]}

  """
  def run(prog, method \\ 0, args) do
    nif_run(prog, method, args)
  end

  def run!(prog, method \\ 0, args) do
    {:ok, ret} = run(prog, method, args)
    ret
  end

  defp nif_run(_state, _method, _args) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  defp value_name(:int), do: "integer64"
  defp value_name(:int64), do: "integer64"
  defp value_name(:uint64), do: "uinteger64"
  defp value_name(:double), do: "doubleval"
  defp value_name(:binary), do: "binary"

  defp header() do
    """
      typedef signed char         int8_t;
      typedef unsigned char       uint8_t;
      typedef short               int16_t;
      typedef unsigned short      uint16_t;
      typedef int                 int32_t;
      typedef unsigned            uint32_t;
      typedef long long           int64_t;
      typedef unsigned long long  uint64_t;

      typedef struct
      {
        uint64_t method;
        void *head;
      } Env;

      typedef struct {
        uint64_t size;
        unsigned char* data;
      } Binary;

      typedef union {
        Binary binary;
        int64_t integer64;
        uint64_t uinteger64;
        double doubleval;
      } Param;

      #{Niffler.Stdlib.include()}
    """
    |> String.trim()
  end

  def type_defs(inputs, outputs) do
    [
      Enum.with_index(inputs)
      |> Enum.map(fn {{name, type}, idx} ->
        "#define $#{name} (niffler_input[#{idx}].#{value_name(type)})"
      end),
      Enum.with_index(outputs)
      |> Enum.map(fn {{name, type}, idx} ->
        "#define $#{name} (niffler_output[#{idx}].#{value_name(type)})"
      end)
    ]
    |> Enum.concat()
    |> Enum.join("\n  ")
  end

  def type_undefs(inputs, outputs) do
    (inputs ++ outputs) |> Enum.map(fn {name, _} -> "#undef $#{name}" end) |> Enum.join("\n  ")
  end

  def method_name(name) do
    "const char *#{name}(Env *niffler_env, Param *niffler_input, Param *niffler_output)"
  end
end

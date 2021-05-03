defmodule Niffler.Library do
  @moduledoc """
  Documentation for `Niffler`.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      @module __MODULE__
      @nifs :niffler_nifs
      @on_load :pre_compile
      @behaviour Niffler.Library

      def pre_compile() do
        program = Niffler.Library.compile(@module, header(), on_load())
        :persistent_term.put({@module, :niffler_program}, program)
        :ok
      end

      import Niffler.Library
    end
  end

  defmacro defnif(name, inputs, outputs, do: source) do
    keys = Keyword.keys(inputs) |> Enum.map(fn n -> Macro.var(n, __MODULE__) end)
    key = {name, length(inputs)}

    quote do
      nifs = Module.get_attribute(@module, @nifs, [])
      Module.put_attribute(@module, unquote(name), length(nifs))
      @idx length(nifs)

      Module.put_attribute(
        @module,
        @nifs,
        nifs ++ [{unquote(key), unquote(inputs), unquote(outputs), unquote(source)}]
      )

      def unquote(name)(unquote_splicing(keys)) do
        :persistent_term.get({@module, :niffler_program})
        |> Niffler.run(@idx, [unquote_splicing(keys)])
      end
    end
  end

  def library_suffix() do
    case :os.type() do
      {:unix, :darwin} -> "dylib"
      {:unix, _} -> "so"
      {:win32, _} -> "dll"
    end
  end

  @nifs :niffler_nifs
  def compile(module, header, on_load) do
    funs = Module.get_attribute(module, @nifs, [])

    cases =
      Enum.with_index(funs)
      |> Enum.map(fn {{_, inputs, outputs, source}, idx} ->
        """
        case #{idx}: {
            #{Niffler.type_defs(inputs, outputs)}
            #{source}
            #{Niffler.type_undefs(inputs, outputs)}
            break;
        }
        """
      end)
      |> Enum.join("\n  ")

    params = Enum.map(funs, fn {_key, inputs, outputs, _source} -> {inputs, outputs} end)

    Niffler.compile!(
      """
        #{header}

        DO_RUN
          static int niffler_initialized = 0;
          if (!niffler_initialized) {
            #{on_load}
            niffler_initialized = 1;
          }

          switch (niffler_env->method) {
            #{cases}
            default:
              return "failed fo fetch requested method";
          }
        END_RUN
      """,
      params
    )
  end

  @callback header() :: binary
  @callback on_load() :: binary
  @callback on_destroy() :: binary
end

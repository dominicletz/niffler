defmodule Niffler.Library do
  @moduledoc """
  `Niffler.Library` allows to wrap dynamically loaded libraries. And create foreign
  function interfaces (FFI) for them. This usually requires:

  * Shared headers such for type definitions
  * Some init code involving `dlopen()`
  * Static variables/state that is part of the library
  * Potential deinit code involving `dlclose()`

  `Niffler.Library` allows to produce modules at runtime doing all these
  things and exposing access to the c-functions of a dynamic library.

  ```
  defmodule Gmp do
    use Niffler.Library, thread_safe: false

    @impl true
    def header() do
      \"""
      // library handle
      void *gmp;

      // types
      typedef struct
      {
        int _mp_alloc;
        int _mp_size;
        void *_mp_d;
      } __mpz_struct;

      typedef __mpz_struct mpz_t[1];
      void (*mpz_init)(mpz_t);
      // ...
      \"""
    end

    @impl true
    def on_load() do
      \"""
      // loading the library with dlopen()
      gmp = dlopen("libgmp.\#{library_suffix()}", RTLD_LAZY);
      if (!gmp) {
        return "could not load libgmp";
      }
      // loading symbols:
      dlerror();
      if (!(mpz_init = dlsym(gmp, "__gmpz_init"))) {
        return dlerror();
      }
      // other symbols ...
      \"""
    end

    @impl true
    def on_destroy() do
      \"""
      if (!gmp) {
        return;
      }
      // unloading
      dlclose(gmp);
      \"""
    end

    # definining one or more operations here...
    defnif :mul, [a: :int, b: :int], ret: :int do
      \"""
      mpz_set_si(ma, $a);
      mpz_set_si(mb, $b);
      mpz_mul(mc, ma, mb);
      $ret = mpz_get_si(mc);
      \"""
    end
  end
  ```

  Once defined the module functions can be used via:

  ```
    {ok, [result]} = Gmp.mul(4, 5)
  ```

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

  @doc """
    Return a c-fragement of a common header for type definitions,
    static variables and other neccesary c code.

    Example:

    ```
    @impl true
    def header() do
      \"""
      // library handle
      void *gmp;
      \"""
    end
    ```
  """
  @callback header() :: binary

  @doc """
    Return a c-fragement that is called on the first call to the module.
    Typicall this fragment would contain a call to `dlopen()` when loading
    a dynamic library.

    This c-fragment should return a char* (a common string in c) when any
    error has occured.

    Example:

    ```
    @impl true
    def on_load() do
      \"""
      // loading the library with dlopen()
      gmp = dlopen("libgmp.\#{library_suffix()}", RTLD_LAZY);
      if (!gmp) {
        return "could not load libgmp";
      }
      \"""
    end
    ```
  """
  @callback on_load() :: binary

  @doc """
    Return a c-fragement that is called when the module is unloaded.
    Typicallly this fragment would contain a call to `dlclose()` for
    a dynamic library.

    Example:

    ```
    @impl true
    def on_destroy() do
      \"""
      if (!gmp) {
        return;
      }
      // unloading
      dlclose(gmp);
      \"""
    end
    ```
  """
  @callback on_destroy() :: binary

  @spec defnif(atom(), keyword, keyword, [{:do, binary()}]) ::
          {:__block__, [], [{any, any, any}, ...]}
  @doc """
    Defines a new nif function in the current module.

    Same as `Niffler.defnif/4` but with access to the current module context.
  """
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

  @doc """
    Returns the current platforms default library suffix:

    * `dll` on windows
    * `dylib` on mac
    * `so` on linux

    Useful for dlopen() code to load the correct library:

    ```
    @impl true
    def on_load() do
      \"""
      // loading the library with dlopen()
      gmp = dlopen("libgmp.\#{library_suffix()}", RTLD_LAZY);
      if (!gmp) {
        return "could not load libgmp";
      }
      \"""
    end
    ```

  """
  def library_suffix() do
    case :os.type() do
      {:unix, :darwin} -> "dylib"
      {:unix, _} -> "so"
      {:win32, _} -> "dll"
    end
  end

  @nifs :niffler_nifs
  @doc false
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
end

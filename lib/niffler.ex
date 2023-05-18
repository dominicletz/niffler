defmodule Niffler do
  @moduledoc """
  Just-In-Time nif generator, FFI generator, C-compiler based on TinyCC.
  For Linux, MacOS, Windows (msys2)

  # Using Niffler

  Once installed, you can use the Niffler to define new nif modules using embedded C fragments:

  ```
  defmodule Example do
    use Niffler

    defnif :count_zeros, [str: :binary], [ret: :int] do
      \"""
      while($str.size--) {
        if (*$str.data++ == 0) $ret++;
      }
      \"""
    end
  end

  {:ok, [2]} = Example.count_zeros(<<0,1,0>>)
  ```

  See `Niffler.defnif/4` for a full explanation of the parameters passed.

  ## Variable binding in C fragments

  Each c fragment is wrapped in shortcut macros to receive direct access to the defined parameters. So when  defining a nif:

  ```
    defnif :count_zeros, [str: :binary], [ret: :int] do
    #       ^name         ^input          ^output
  ```

  There will be macros defined for each defined input and output variable. Each macro is prefixed with a dollar sign `$` to highlight the fact that it's a macro and not real variable:

  In the exampe above:

  * `$str` will be defined as a macro alias pointing to a binary type
  * `$ret` will be defined as a macro alias to an integer

  Input and output variables are allocated on the stack of the nif function call making them thread-safe and isolated.

  ## Working with binaries

  When using binaries as input or output they are returned as as a struct with two members:

  ```c++
    typedef struct {
      uint64_t size;
      unsigned char* data;
    } Binary;
  ```

  The size and data fields can be used to read from inputs and write to outputs.

  *Warning:* __NEVER__ write to input binaries. These are pointers into the BEAM VM, changing their values will have unknown but likely horrible consequences.

  Constructing output binaries requires care. The easiest way is to use the built-in macro function `$alloc(size_t)` which allows to allocate memory temporary during the runtime of the nif, that will be automatically freed. Other possibilities are to use the system `malloc()` directly but then `free()` needs to be called at a later point in time, or to use static memory in the module. Stack variables (or from `alloca`) don't work as they are being destroyed before the Niffler program returns and the result values are beeing read. Two examples that are possible here:

  ```
  defmodule BinaryExample
    use Niffler

    defnif :static, [], [ret: :binary] do
      \"""
      static char str[10];
      $ret.size = sizeof(str);
      $ret.data = str;
      for (int i = 0; i < sizeof(str); i++) str[i] = i;
      \"""
    end

    defnif :reverse, [input: :binary], [ret: :binary] do
      \"""
      $ret.data = $alloc($input.size);
      $ret.size = $input.size;
      for (int i = 0; i < $input.size; i++)
        $ret.data[i] = $input.data[$input.size-(i+1)];
      \"""
    end
  end

  {:ok, [<<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>]} = BinaryExample.static()

  {:ok, [<<3, 2, 1>>]} = BinaryExample.reverse(<<1, 2, 3>>)
  ```

  ## Concurrency

  Each generated Niffler function is a small c program in its own call stack. Multiple
  runs of the same program are all executed in the same context. This allows to keep state in
  c programs when needed but also increases the chances for concurrency issues.

  Lets take this stateful counter:

  ```
    defnif :counter, [], [ret: :int] do
      \"""
      static uint64_t counter = 0;
      $ret = counter++;
      \"""
    end
  ```

  The niffler protects against certain types concurrency issues by creating all input and output variables on the call stack. Two functions calls at the same time do never interefere on the input and output parameters.

  But this protection is not true for static and global variables. The above counter example is using a static counter variable, this variable will be the same instance on each call. So with high concurrency these things could happen:

  * counter returns the same value for two concurrent calls.
  * counter skips a value for two concurrent calls.

  The same problem affects the static binary example above. When called multiple times concurrently it will overwrite the static variable multiple times return undefined results.

  ## Defining helper functions

  When using `Niffler.defnif/4` you sometimes might want to create helper functions
  or defines outside the function body. For short fragements it's possible to use the
  `DO_RUN` and `END_RUN` macros to separate the function body from global helpers:

  Here an example defining a recursive fibonacci function. In order to refer to the
  function name `fib()` recursively in c it needs to be defined. So we define it globally
  outside of an explicity `DO_RUN` / `END_RUN` block:

  ```
    defnif :fib, [a: :int], ret: :int do
    \"""
    int64_t fib(int64_t f) {
      if (f < 2) return 1;
      return fib(f-1) + fib(f-2);
    }

    DO_RUN
      $ret = fib($a);
    END_RUN
    \"""
  end
  ```

  Interally `DO_RUN` and `END_RUN` are c-macros that will be converted to the correct
  niffler wrapping to execute the code, while anything outside the `DO_RUN` / `END_RUN`
  block will be copied into the c code without modification.

  For larger blocks it might though be better to use `Niffler.Library` and override the
  `Niffler.Library.c:header/0` callback.

  ## Using shared libraries (.dll, .so, .dylib)

  For working with shared library and create foreign function interfaces (FFI) for those
  please look at `Niffler.Library`

  ## Standard library

  Niffler comes with a minimal c standard library. Please check standard c
  documentation for reference. This is just a list of defined functions and types:

  ```
    /* types */
    typedef signed char         int8_t;
    typedef unsigned char       uint8_t;
    typedef short               int16_t;
    typedef unsigned short      uint16_t;
    typedef int                 int32_t;
    typedef unsigned            uint32_t;
    typedef long long           int64_t;
    typedef unsigned long long  uint64_t;

    typedef struct {
      uint64_t size;
      unsigned char* data;
    } Binary;

    /* niffler helper */
    void *$alloc(size_t size);

    /* stdarg.h */
    typedef __builtin_va_list va_list;

    /* stddef.h */
    typedef __SIZE_TYPE__ size_t;
    typedef __PTRDIFF_TYPE__ ssize_t;
    typedef __WCHAR_TYPE__ wchar_t;
    typedef __PTRDIFF_TYPE__ ptrdiff_t;
    typedef __PTRDIFF_TYPE__ intptr_t;
    typedef __SIZE_TYPE__ uintptr_t;
    void *alloca(size_t size);

    /* stdlib.h */
    void *calloc(size_t nmemb, size_t size);
    void *malloc(size_t size);
    void free(void *ptr);
    void *realloc(void *ptr, size_t size);
    int atoi(const char *nptr);
    long int strtol(const char *nptr, char **endptr, int base);
    unsigned long int strtoul(const char *nptr, char **endptr, int base);
    void exit(int);

    /* stdio.h */
    extern FILE *stdin;
    extern FILE *stdout;
    extern FILE *stderr;
    FILE *fopen(const char *path, const char *mode);
    FILE *fdopen(int fildes, const char *mode);
    FILE *freopen(const  char *path, const char *mode, FILE *stream);
    int fclose(FILE *stream);
    size_t  fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
    size_t  fwrite(void *ptr, size_t size, size_t nmemb, FILE *stream);
    int fgetc(FILE *stream);
    int fputs(const char *s, FILE *stream);
    char *fgets(char *s, int size, FILE *stream);
    int getc(FILE *stream);
    int getchar(void);
    char *gets(char *s);
    int ungetc(int c, FILE *stream);
    int fflush(FILE *stream);
    int putchar(int c);

    int printf(const char *format, ...);
    int fprintf(FILE *stream, const char *format, ...);
    int sprintf(char *str, const char *format, ...);
    int snprintf(char *str, size_t size, const  char  *format, ...);
    int asprintf(char **strp, const char *format, ...);
    int vprintf(const char *format, va_list ap);
    int vfprintf(FILE  *stream,  const  char *format, va_list ap);
    int vsprintf(char *str, const char *format, va_list ap);
    int vsnprintf(char *str, size_t size, const char  *format, va_list ap);
    int vasprintf(char  **strp,  const  char *format, va_list ap);

    void perror(const char *s);

    /* string.h */
    char *strcat(char *dest, const char *src);
    char *strchr(const char *s, int c);
    char *strrchr(const char *s, int c);
    char *strcpy(char *dest, const char *src);
    void *memcpy(void *dest, const void *src, size_t n);
    void *memmove(void *dest, const void *src, size_t n);
    void *memset(void *s, int c, size_t n);
    char *strdup(const char *s);
    size_t strlen(const char *s);

    /* dlfcn.h */
    void *dlopen(const char *filename, int flag);
    const char *dlerror(void);
    void *dlsym(void *handle, char *symbol);
    int dlclose(void *handle);
  ```


  """

  @on_load :init
  @doc false
  defmacro __using__(_opts) do
    quote do
      import Niffler
      @niffler_module __MODULE__
    end
  end

  @doc """
  Defines a new nif member method. To use defnif() import Niffler into
  your module with `use Niffler`.

  defnif takes three parameters and a c-fragment function body:

  * `name` - an atom, the name of the to be defined nif function
  * `inputs` - a keyword list of the format `[name: type]`
  * `outputs` - a keyword list of the format `[name: type]`

  The `inputs` and `outputs` keyword lists take atom() as names and types.
  The parameter names can be freely choosen* the currently supported
  types are:

  * `int` or `int64` - a signed 64-bit integer
  * `uint64` - an unsigned 64-bit integer
  * `double` - a double (floating point number)
  * `binary` - an Elixir binary/string

  ```
  defmodule Example do
    use Niffler

    defnif :count_zeros, [str: :binary], [ret: :int] do
      \"""
      while($str.size--) {
        if (*$str.data++ == 0) $ret++;
      }
      \"""
    end
  end

  {:ok, [2]} = Example.count_zeros(<<0,1,0>>)
  ```
  """
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
  Low level function takes a string as input and compiles it into a nif program. Returning the program
  reference. Prefer using the high-level function `Niffler.defnif/4` or `Niffler.Library` instead.

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

  @doc false
  def compile!(code, inputs, outputs) do
    {:ok, prog} = compile(code, inputs, outputs)
    prog
  end

  @doc false
  def compile(code, params) do
    code =
      """
        #{header()}
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
              |> Enum.drop(length(String.split(header(), "\n")))
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

  @doc false
  def compile!(code, params) do
    {:ok, prog} = compile(code, params)
    prog
  end

  defp nif_compile(_code, _params) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  @doc """
  Low level function that executes the given Niffler program and
  returns any output values. Prefer using the high-level function
  `Niffler.defnif/4` or `Niffler.Library` instead.

  ## Examples

      iex> {:ok, prog} = Niffler.compile("$ret = $a << 2;", [a: :int], [ret: :int])
      iex> Niffler.run(prog, [5])
      {:ok, [20]}

  """
  def run(prog, method \\ 0, args) do
    nif_run(prog, method, args)
  end

  defp nif_run(_state, _method, _args) do
    :erlang.nif_error(:nif_library_not_loaded)
  end

  defp value_name(:int), do: "integer64"
  defp value_name(:int64), do: "integer64"
  defp value_name(:uint64), do: "uinteger64"
  defp value_name(:double), do: "doubleval"
  defp value_name(:binary), do: "binary"
  defp value_name(other), do: raise "Unknown type #{other} in defnif"

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

      #define DO_RUN #{method_name("run")} {
      #define END_RUN return 0; }

      #{Niffler.Stdlib.include()}
    """
    |> String.trim()
  end

  @doc false
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

  @doc false
  def type_undefs(inputs, outputs) do
    (inputs ++ outputs) |> Enum.map(fn {name, _} -> "#undef $#{name}" end) |> Enum.join("\n  ")
  end

  @doc false
  def method_name(name) do
    "const char *#{name}(Env *niffler_env, Param *niffler_input, Param *niffler_output)"
  end
end

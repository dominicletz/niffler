defmodule LibraryTest do
  use ExUnit.Case

  defmodule Gmp do
    use Niffler.Library, thread_safe: false

    @impl true
    def header() do
      """
      typedef struct
      {
        int _mp_alloc;
        int _mp_size;
        void *_mp_d;
      } __mpz_struct;

      typedef __mpz_struct mpz_t[1];
      void (*mpz_init)(mpz_t);
      void (*mpz_clear)(mpz_t);
      void (*mpz_mul)(mpz_t, mpz_t, mpz_t);
      void (*mpz_add)(mpz_t, mpz_t, mpz_t);
      void (*mpz_set_si)(mpz_t, signed long int);
      signed long int (*mpz_get_si)(const mpz_t);
      void *gmp;

      mpz_t ma;
      mpz_t mb;
      mpz_t mc;
      """
    end

    @impl true
    def on_load() do
      symbols =
        Enum.map(~w(init clear mul add set_si get_si), fn name ->
          """
          dlerror();
          if (!(mpz_#{name} = dlsym(gmp, "__gmpz_#{name}"))) {
            return dlerror();
          }
          """
        end)

      """
      gmp = dlopen("libgmp.#{library_suffix()}", RTLD_LAZY);
      if (!gmp) {
        return "could not load libgmp";
      }
      #{Enum.join(symbols)}
      mpz_init(ma);
      mpz_init(mb);
      mpz_init(mc);
      """
    end

    @impl true
    def on_destroy() do
      """
      if (!gmp) {
        return;
      }
      mpz_clear(ma);
      mpz_clear(mb);
      mpz_clear(mc);
      dlclose(gmp);
      """
    end

    defnif :mul, [a: :int, b: :int], ret: :int do
      """
      mpz_set_si(ma, $a);
      mpz_set_si(mb, $b);
      mpz_mul(mc, ma, mb);
      $ret = mpz_get_si(mc);
      """
    end

    defnif :add, [a: :int, b: :int], ret: :int do
      """
      mpz_set_si(ma, $a);
      mpz_set_si(mb, $b);
      mpz_add(mc, ma, mb);
      $ret = mpz_get_si(mc);
      """
    end
  end

  test "gmp tests" do
    assert {:ok, [12]} = Gmp.mul(3, 4)
    assert {:ok, [2]} = Gmp.add(1, 1)
  end
end

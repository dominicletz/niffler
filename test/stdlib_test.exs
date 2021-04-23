defmodule StdlibTest do
  use ExUnit.Case
  use Niffler
  doctest Niffler

  defnif :reverse, [input: :binary], ret: :binary do
    """
    $ret.data = $alloc($input.size);
    $ret.size = $input.size;
    for (int i = 0; i < $input.size; i++)
      $ret.data[i] = $input.data[$input.size-(i+1)];
    """
  end

  test "test reverse" do
    assert {:ok, [<<1, 2, 3>>]} = reverse(<<3, 2, 1>>)
  end

  defnif :sprintf, [], ret: :binary do
    """
    static char lol[16];
    $ret.data = lol;
    $ret.size = snprintf(lol, sizeof(lol), "%d", 28);
    """
  end

  test "test sprintf" do
    assert {:ok, ["28"]} = sprintf()
  end

  defnif :gmp_mul, [a: :int, b: :int], ret: :int do
    """
    typedef struct
    {
      int _mp_alloc;
      int _mp_size;
      void *_mp_d;
    } __mpz_struct;

    typedef __mpz_struct mpz_t[1];
    void (*mpz_init)(mpz_t);
    void (*mpz_mul)(mpz_t, mpz_t, mpz_t);
    void (*mpz_set_si)(mpz_t, signed long int);
    signed long int (*mpz_get_si)(const mpz_t);

    mpz_t ma;
    mpz_t mb;
    mpz_t mc;
    void *gmp;

    DO_RUN
      static int initialized = 0;
      if (!initialized) {
        gmp = dlopen("libgmp.so", RTLD_LAZY);
        if (!gmp) {
          return "could not load libgmp";
        }

        dlerror();
        if (!(mpz_init = dlsym(gmp, "__gmpz_init"))) {
          return dlerror();
        }
        dlerror();
        if (!(mpz_mul = dlsym(gmp, "__gmpz_mul"))) {
          return dlerror();
        }
        dlerror();
        if (!(mpz_set_si = dlsym(gmp, "__gmpz_set_si"))) {
          return dlerror();
        }
        dlerror();
        if (!(mpz_get_si = dlsym(gmp, "__gmpz_get_si"))) {
          return dlerror();
        }

        mpz_init(ma);
        mpz_init(mb);
        mpz_init(mc);
        initialized = 1;
      }

      mpz_set_si(ma, $a);
      mpz_set_si(mb, $b);
      mpz_mul(mc, ma, mb);
      $ret = mpz_get_si(mc);
    END_RUN
    """
  end

  test "gmp multiplication" do
    assert {:ok, [12]} = gmp_mul(3, 4)
  end
end

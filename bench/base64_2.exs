
defmodule Base64 do
  use Niffler

  def encode(bin) do
    {:ok, [ret]} = encode_nif(bin)
    ret
  end

  defnif :encode_nif, [input: :binary], ret: :binary do
    ~S"""
    static const unsigned char base64_table[65] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

      unsigned char *src = $input.data;
      size_t len = $input.size;

      unsigned char *out, *pos;
      const unsigned char *end, *in;
      size_t olen;

      olen = len * 4 / 3 + 4; /* 3-byte blocks to 4-byte */
      olen += olen / 72; /* line feeds */
      olen++; /* nul termination */
      if (olen < len)
        return "olen < len";
      out = $alloc(olen);

      end = src + len;
      in = src;
      pos = out;
      while (end - in >= 3) {
        *pos++ = base64_table[in[0] >> 2];
        *pos++ = base64_table[((in[0] & 0x03) << 4) | (in[1] >> 4)];
        *pos++ = base64_table[((in[1] & 0x0f) << 2) | (in[2] >> 6)];
        *pos++ = base64_table[in[2] & 0x3f];
        in += 3;
      }

      if (end - in) {
        *pos++ = base64_table[in[0] >> 2];
        if (end - in == 1) {
          *pos++ = base64_table[(in[0] & 0x03) << 4];
          *pos++ = '=';
        } else {
          *pos++ = base64_table[((in[0] & 0x03) << 4) |
                    (in[1] >> 4)];
          *pos++ = base64_table[(in[1] & 0x0f) << 2];
        }
        *pos++ = '=';
      }

      *pos = '\0';

      $ret.data = out;
      $ret.size = pos - out;
    """
  end
end

# file = "this is a really small string that we are going to encode to base 64"
file = :rand.bytes(1024 * 1024)


result = Base64.encode(file)
result2 = Base.encode64(file)

if result != result2 do
  IO.inspect({result, result2})
  raise "implementations are not matching"
end

Benchee.run(
  %{
    "elixir_base64" => fn -> Base.encode64(file) end,
    "niffler_base64" => fn -> Base64.encode(file) end
  }
)

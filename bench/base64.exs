
defmodule Base64 do
  use Niffler

  def encode(bin) do
    {:ok, [ret]} = encode_nif(bin)
    ret
  end

  defnif :encode_nif, [input: :binary], ret: :binary do
    """
    static char encoding_table[] = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
    'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
    'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
    'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
    'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
    'w', 'x', 'y', 'z', '0', '1', '2', '3',
    '4', '5', '6', '7', '8', '9', '+', '/'};
    static int mod_table[] = {0, 2, 1};

    size_t output_length = 4 * (($input.size + 2) / 3);
    $ret.data = $alloc(output_length);
    $ret.size = output_length;
    size_t input_length = $input.size;
    unsigned char* data = $input.data;
    char* encoded_data = $ret.data;
    for (int i = 0; i < $input.size;) {
      uint32_t octet_a = i < input_length ? data[i++] : 0;
      uint32_t octet_b = i < input_length ? data[i++] : 0;
      uint32_t octet_c = i < input_length ? data[i++] : 0;

      uint32_t triple = (octet_a << 0x10) + (octet_b << 0x08) + octet_c;

      *encoded_data++ = encoding_table[(triple >> 3 * 6) & 0x3F];
      *encoded_data++ = encoding_table[(triple >> 2 * 6) & 0x3F];
      *encoded_data++ = encoding_table[(triple >> 1 * 6) & 0x3F];
      *encoded_data++ = encoding_table[(triple >> 0 * 6) & 0x3F];
    }

    for (int i = 0; i < mod_table[$input.size % 3]; i++)
      $ret.data[output_length - 1 - i] = '=';
    """
  end
end

# file = "this is a really small string that we are going to encode to base 64"
file = :rand.bytes(300_000)

result = Base64.encode(file)
^result = Base.encode64(file)

Benchee.run(
  %{
    "elixir_base64" => fn -> Base.encode64(file) end,
    "niffler_base64" => fn -> Base64.encode(file) end
  }
)

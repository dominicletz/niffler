defmodule NifflerLru do
  defmodule Nif do
    use Niffler.Library, thread_safe: false

    @impl true
    def header() do
      """
        typedef struct {
          int   capacity;
          int   size;
          char* data;
        } Item;

        static Item**  lru_head;
        static int     lru_size;
      """
    end

    @impl true
    def on_load() do
      """
        lru_size = 2000;
        lru_head = calloc(lru_size, sizeof(lru_head[0]));
      """
    end

    @impl true
    def on_destroy() do
      :ok
    end

    defnif :nif_put, [hash: :int, kv: :binary], ret: :int do
      """
        int pos = $hash % lru_size;
        if (lru_head[pos] && lru_head[pos]->capacity < $kv.size) {
          free(lru_head[pos]);
          lru_head[pos] = 0;
        }
        if (!lru_head[pos]) {
          lru_head[pos] = malloc(sizeof(Item) + $kv.size);
          lru_head[pos]->capacity = $kv.size;
        }
        memcpy(lru_head[pos]->data, $kv.data, $kv.size);
        lru_head[pos]->size = $kv.size;
      """
    end

    defnif :nif_get, [hash: :int], ok: :int, ret: :binary do
      """
        int pos = $hash % lru_size;
        if (!lru_head[pos]) {
          $ok = 0;
          return 0;
        } else {
          $ret.data = $alloc(lru_head[pos]->size);
          $ret.size = lru_head[pos]->size;
          memcpy($ret.data, lru_head[pos]->data, lru_head[pos]->size);
          $ok = 1;
        }
      """
    end
  end

  def put(_name, key, value) when is_binary(key) and is_binary(value) do
    Nif.nif_put(hash(key), key <> value)
    value
  end

  def get(_name, key, default) when is_binary(key) do
    case Nif.nif_get(hash(key)) do
      [0, _] ->
        default

      [1, key_value] ->
        if String.starts_with?(key_value, key) do
          :binary.part(key_value, byte_size(key), byte_size(key_value) - byte_size(key))
        else
          default
        end
    end
  end

  def fetch(_name, key, fun) when is_binary(key) do
    hash = hash(key)

    case Nif.nif_get(hash) do
      [0, _] ->
        Nif.nif_put(hash(key), fun.())

      [1, key_value] ->
        if String.starts_with?(key_value, key) do
          :binary.part(key_value, byte_size(key), byte_size(key_value) - byte_size(key))
        else
          Nif.nif_put(hash(key), fun.())
        end
    end
  end

  defp hash(key) do
    :erlang.phash2(key)
  end
end

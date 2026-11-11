module CacheKeysHelper
  def get_prefixed_cache_key(account_id, key)
    "idb-cache-key-account-#{account_id}-#{key}"
  end

  def fetch_value_for_key(account_id, key)
    prefixed_cache_key = get_prefixed_cache_key(account_id, key)
    value_from_cache = Redis::Alfred.get(prefixed_cache_key)

    return value_from_cache if value_from_cache.present?

    # ramon: chave vencida (72h) ganha valor novo em vez do zero fixo do Chatwoot. Com o zero fixo, o navegador que
    # guardou a lista sob '0000000000' antes de uma mudança voltava a achá-la válida quando a chave vencia, e a caixa,
    # o time ou a etiqueta nova nunca aparecia ali. Custo: cada navegador rebusca as três listas uma vez a cada 72h.
    # O sufixo impede a chave de coincidir com a de uma mudança real feita no mesmo segundo (update_cache_key grava só
    # o horário). nx: quem gravou primeiro vale, e todos devolvem o que ficou gravado.
    fresh_key = "#{Time.now.utc.to_i}-#{SecureRandom.hex(2)}"
    Redis::Alfred.set(prefixed_cache_key, fresh_key, nx: true, ex: CacheKeys::CACHE_KEYS_EXPIRY.to_i)
    Redis::Alfred.get(prefixed_cache_key) || fresh_key
  end
end

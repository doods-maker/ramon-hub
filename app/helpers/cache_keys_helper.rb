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
    # nx: quem gravou primeiro vale; perder a corrida só custa uma rebusca a mais.
    nova = Time.now.utc.to_i.to_s
    Redis::Alfred.set(prefixed_cache_key, nova, nx: true, ex: CacheKeys::CACHE_KEYS_EXPIRY.to_i)
    nova
  end
end

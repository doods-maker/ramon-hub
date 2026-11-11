require 'rails_helper'

RSpec.describe CacheKeysHelper do
  let(:account_id) { 1 }
  let(:key) { 'example_key' }

  describe '#get_prefixed_cache_key' do
    it 'returns a string with the correct prefix, account ID, and key' do
      expected_key = "idb-cache-key-account-#{account_id}-#{key}"
      result = helper.get_prefixed_cache_key(account_id, key)

      expect(result).to eq(expected_key)
    end
  end

  describe '#fetch_value_for_key' do
    # ramon: a chave vence em 72h. Se a vencida voltasse sempre ao mesmo valor fixo, o navegador que guardou a lista
    # sob esse valor antes de uma mudança (caixa Equipe criada) acharia a lista velha ainda válida, para sempre.
    it 'gives a fresh key, never the fixed zero epoch, when no value is cached' do
      travel_to(Time.utc(2026, 11, 11, 12, 0, 0)) do
        result = helper.fetch_value_for_key(account_id, 'chave-vencida')

        expect(result).to eq('1794398400')
      end
    end

    it 'keeps the same key on the next reads until something changes' do
      first = travel_to(Time.utc(2026, 11, 11, 12, 0, 0)) { helper.fetch_value_for_key(account_id, 'chave-estavel') }
      second = travel_to(Time.utc(2026, 11, 11, 13, 0, 0)) { helper.fetch_value_for_key(account_id, 'chave-estavel') }

      expect(second).to eq(first)
    end

    it 'gives a different key after the stored one expires' do
      first = travel_to(Time.utc(2026, 11, 11, 12, 0, 0)) { helper.fetch_value_for_key(account_id, 'chave-que-vence') }
      Redis::Alfred.delete(helper.get_prefixed_cache_key(account_id, 'chave-que-vence'))
      second = travel_to(Time.utc(2026, 11, 15, 12, 0, 0)) { helper.fetch_value_for_key(account_id, 'chave-que-vence') }

      expect(second).not_to eq(first)
    end

    it 'returns a cached value if it exists' do
      value = Time.now.to_i
      prefixed_cache_key = helper.get_prefixed_cache_key(account_id, key)

      Redis::Alfred.set(prefixed_cache_key, value)

      result = helper.fetch_value_for_key(account_id, key)

      expect(result).to eq(value.to_s)
    end
  end
end

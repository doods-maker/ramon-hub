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
    context 'when no value is cached' do
      let(:expired_key) { helper.get_prefixed_cache_key(account_id, 'chave-vencida') }
      let(:noon) { Time.utc(2026, 11, 11, 12, 0, 0) }

      # O Redis dos specs é real e não é zerado entre execuções.
      before { Redis::Alfred.delete(expired_key) }
      after { Redis::Alfred.delete(expired_key) }

      it 'gives a fresh key, never the fixed zero epoch' do
        result = travel_to(noon) { helper.fetch_value_for_key(account_id, 'chave-vencida') }

        expect(result).to start_with('1794398400-')
      end

      # update_cache_key grava só o horário: a chave gerada na leitura não pode coincidir com a de uma mudança real.
      it 'never matches the key of a real change made in the same second' do
        result = travel_to(noon) { helper.fetch_value_for_key(account_id, 'chave-vencida') }

        expect(result).not_to eq('1794398400')
      end

      it 'keeps the same key on the next reads' do
        first = travel_to(noon) { helper.fetch_value_for_key(account_id, 'chave-vencida') }
        second = travel_to(noon + 1.hour) { helper.fetch_value_for_key(account_id, 'chave-vencida') }

        expect(second).to eq(first)
      end

      it 'gives a different key after the stored one expires' do
        first = travel_to(noon) { helper.fetch_value_for_key(account_id, 'chave-vencida') }
        Redis::Alfred.delete(expired_key)
        second = travel_to(noon + 4.days) { helper.fetch_value_for_key(account_id, 'chave-vencida') }

        expect(second).not_to eq(first)
      end

      it 'returns the key another process stored first' do
        allow(Redis::Alfred).to receive(:get).with(expired_key).and_return(nil, 'gravada-por-outro')

        expect(helper.fetch_value_for_key(account_id, 'chave-vencida')).to eq('gravada-por-outro')
      end
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

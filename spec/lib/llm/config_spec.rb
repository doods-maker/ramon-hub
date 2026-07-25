require 'rails_helper'

RSpec.describe Llm::Config do
  describe '.initialize!' do
    before { described_class.reset! }

    after { described_class.reset! }

    it 'configura a credencial do deepseek a partir da env' do
      with_modified_env DEEPSEEK_API_KEY: 'chave-de-teste' do
        described_class.initialize!

        expect(RubyLLM.config.deepseek_api_key).to eq('chave-de-teste')
      end
    end

    it 'nao quebra quando a env do deepseek esta ausente' do
      with_modified_env DEEPSEEK_API_KEY: nil do
        expect { described_class.initialize! }.not_to raise_error
      end
    end
  end
end

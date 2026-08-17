require 'rails_helper'

RSpec.describe 'Ramon::CopilotoModo default por env', if: ChatwootApp.enterprise? do
  let(:conversation) { create(:conversation) }

  it 'usa rascunho sem env' do
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: nil do
      expect(Ramon::CopilotoModo.of(conversation)).to eq('rascunho')
    end
  end

  it 'usa a env quando valida e ignora quando invalida' do
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
      expect(Ramon::CopilotoModo.of(conversation)).to eq('piloto_limitado')
    end
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'xablau' do
      expect(Ramon::CopilotoModo.of(conversation)).to eq('rascunho')
    end
  end

  it 'atributo da conversa vence a env' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'manual' })
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
      expect(Ramon::CopilotoModo.of(conversation)).to eq('manual')
    end
  end
end

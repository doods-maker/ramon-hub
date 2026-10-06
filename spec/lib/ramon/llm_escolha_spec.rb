require 'rails_helper'

RSpec.describe Ramon::LlmEscolha do
  let(:account) { create(:account) }

  describe '.para' do
    it 'sem escolha na tela, cai no env de antes (reserva)' do
      with_modified_env RAMON_COPILOT_MODEL: 'deepseek-v4-flash', RAMON_CAPTAIN_MODEL: 'deepseek-v4-pro' do
        expect(described_class.para(account, 'copiloto')).to eq(provider: 'deepseek', model: 'deepseek-v4-flash')
        expect(described_class.para(account, 'atendimento')).to eq(provider: 'deepseek', model: 'deepseek-v4-pro')
        expect(described_class.fonte(account, 'copiloto')).to eq('reserva')
      end
    end

    it 'sem conta (job sem contexto) também cai na reserva' do
      with_modified_env RAMON_COPILOT_MODEL: nil do
        expect(described_class.para(nil, 'copiloto')).to eq(provider: 'deepseek', model: 'deepseek-chat')
      end
    end

    it 'a escolha salva vence quando o provedor tem chave no servidor', :aggregate_failures do
      account.update!(captain_models: { 'copilot' => 'claude-haiku-4-5', 'documentos' => 'gpt-4.1-mini' })

      with_modified_env ANTHROPIC_API_KEY: 'k', OPENAI_API_KEY: 'k' do
        expect(described_class.para(account, 'copiloto')).to eq(provider: 'anthropic', model: 'claude-haiku-4-5')
        expect(described_class.para(account, 'documentos')).to eq(provider: 'openai', model: 'gpt-4.1-mini')
        expect(described_class.fonte(account, 'copiloto')).to eq('tela')
      end
    end

    it 'escolha de provedor sem chave volta para a reserva' do
      account.update!(captain_models: { 'copilot' => 'claude-haiku-4-5' })

      with_modified_env ANTHROPIC_API_KEY: nil, RAMON_COPILOT_MODEL: nil do
        expect(described_class.para(account, 'copiloto')).to eq(provider: 'deepseek', model: 'deepseek-chat')
      end
    end

    it 'o agente @claude é sempre a assinatura da VPS' do
      expect(described_class.para(account, 'agente')).to eq(provider: 'claude_vps', model: 'claude-vps')
    end
  end

  describe 'trava da assinatura do Claude (termos de uso)' do
    it 'o Account recusa a assinatura em atendimento, copiloto ou documentos', :aggregate_failures do
      %w[assistant copilot documentos].each do |feature|
        account.captain_models = { feature => 'claude-vps' }
        expect(account).not_to be_valid
        expect(account.errors[:captain_models].join).to include('uso interno do gestor')
      end
    end

    it 'mesmo gravada à força, a assinatura nunca vira o LLM do copiloto' do
      account.update_column(:settings, { 'captain_models' => { 'copilot' => 'claude-vps' } }) # rubocop:disable Rails/SkipsModelValidations
      stub_const('Llm::Models::CONFIG', Llm::Models::CONFIG.deep_merge('features' => { 'copilot' => { 'models' => ['claude-vps'] } }))

      with_modified_env RAMON_AGENTE_TOKEN: 'tok', RAMON_COPILOT_MODEL: nil do
        expect(described_class.para(account.reload, 'copiloto')).to eq(provider: 'deepseek', model: 'deepseek-chat')
      end
    end
  end

  it 'informa quais chaves estão no servidor sem expor o valor' do
    with_modified_env DEEPSEEK_API_KEY: 'segredo', OPENAI_API_KEY: nil, ANTHROPIC_API_KEY: nil, RAMON_AGENTE_TOKEN: 'tok' do
      expect(described_class.chaves).to eq('deepseek' => true, 'openai' => false, 'anthropic' => false, 'claude_vps' => true)
    end
  end
end

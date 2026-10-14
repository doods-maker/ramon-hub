require 'rails_helper'

RSpec.describe Ramon::CopilotoModo do
  let(:inbox) { create(:inbox) }
  let(:conversation) { create(:conversation, account: inbox.account, inbox: inbox) }

  it 'sem atributo nem padrão da caixa: env válida, senão rascunho' do
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: nil do
      expect(described_class.of(conversation)).to eq('rascunho')
    end
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
      expect(described_class.of(conversation)).to eq('piloto_limitado')
    end
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'xablau' do
      expect(described_class.of(conversation)).to eq('rascunho')
    end
  end

  # Review Focus 1: a 1ª resposta é agendada antes do ouvinte carimbar — vale o padrão da caixa, lido ao vivo.
  it 'padrão da caixa vence a env; atributo da conversa vence a caixa' do
    inbox.update!(ramon_copiloto_modo: 'piloto_ate_reuniao')
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
      expect(described_class.of(conversation.reload)).to eq('piloto_ate_reuniao')
      conversation.update!(custom_attributes: { 'copiloto_modo' => 'manual' })
      expect(described_class.of(conversation)).to eq('manual')
    end
  end

  it 'caixa recusa modo inválido e vazio vira nil' do
    expect(inbox.update(ramon_copiloto_modo: 'xablau')).to be(false)
    inbox.reload.update!(ramon_copiloto_modo: '')
    expect(inbox.reload.ramon_copiloto_modo).to be_nil
  end

  it 'os modos "sozinha até…" enviam e aplicam direto, como o piloto total' do
    described_class::LIMITES.each_key do |modo|
      expect(described_class.envia?(modo, handoff: false, logistica_ok: nil)).to be(true)
      expect(described_class.direto?(modo)).to be(true)
    end
    expect(described_class.direto?('piloto_total')).to be(true)
    expect(described_class.direto?('piloto_limitado')).to be(false)
    expect(described_class.direto?('rascunho')).to be(false)
  end

  it 'carimbar_padrao grava o modo da caixa na conversa nova sem passar por cima de escolha' do
    inbox.update!(ramon_copiloto_modo: 'piloto_ate_qualificacao')
    described_class.carimbar_padrao(conversation)
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_ate_qualificacao')

    escolhida = create(:conversation, account: inbox.account, inbox: inbox, custom_attributes: { 'copiloto_modo' => 'manual' })
    described_class.carimbar_padrao(escolhida)
    expect(escolhida.reload.custom_attributes['copiloto_modo']).to eq('manual')
  end

  it 'o roteiro aplica direto nos modos "sozinha até…", inclusive pelo padrão da caixa; lead sem conversa nunca' do
    lead = create(:lead, account: inbox.account, conversation: conversation)
    expect(Ramon::Roteiro::Efeitos.direto?(lead)).to be(false)

    inbox.update!(ramon_copiloto_modo: 'piloto_ate_contrato')
    expect(Ramon::Roteiro::Efeitos.direto?(lead.reload)).to be(true)
    expect(Ramon::Roteiro::Efeitos.direto?(create(:lead, account: inbox.account))).to be(false)
  end
end

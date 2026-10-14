require 'rails_helper'

# Leituras do roteiro e do modo da IA no lead (F5, revisão integrada item 13).
RSpec.describe LeadRoteiro do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:lead) { create(:lead, account: account, conversation: conversation) }

  it 'copiloto_modo: o modo efetivo da conversa (atributo → caixa → env); sem conversa, nil' do
    conversation.update!(custom_attributes: {})
    inbox.update!(ramon_copiloto_modo: 'piloto_ate_reuniao')
    expect(lead.reload.copiloto_modo).to eq('piloto_ate_reuniao')

    conversation.update!(custom_attributes: { 'copiloto_modo' => 'manual' })
    expect(lead.reload.copiloto_modo).to eq('manual')
    expect(create(:lead, account: account).copiloto_modo).to be_nil
  end

  it 'contrato_enviado? e desfecho_roteiro leem o estado gravado no lead' do
    expect([lead.contrato_enviado?, lead.desfecho_roteiro]).to eq([false, nil])

    lead.update!(custom_attributes: { 'zapsign' => { 'sign_url' => 'https://zap/x' }, 'roteiro' => { 'desfecho' => 'humano' } })
    expect([lead.reload.contrato_enviado?, lead.desfecho_roteiro]).to eq([true, 'humano'])
  end

  it 'nome_completo?: o nome do contato (senão o do lead) com 2 palavras ou mais' do
    lead.update!(name: 'Maria')
    expect(lead.nome_completo?).to be(false)

    lead.update!(contact: create(:contact, account: account, name: 'Maria Souza'))
    expect(lead.reload.nome_completo?).to be(true)
  end
end

require 'rails_helper'

RSpec.describe Ramon::Hoje::Prazo do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true, first_response_sla_minutes: 5) }

  def lead_com_conversa(criada_ha:, respondida: false)
    conversation = create(:conversation, account: account, inbox: inbox, created_at: criada_ha.ago)
    conversation.update!(first_reply_created_at: Time.current) if respondida
    create(:lead, account: account, conversation: conversation)
  end

  it 'sem_resposta pega só quem não teve 1ª resposta nas últimas 48 h' do
    pendente = lead_com_conversa(criada_ha: 2.minutes)
    lead_com_conversa(criada_ha: 2.minutes, respondida: true)
    lead_com_conversa(criada_ha: 3.days)
    expect(described_class.sem_resposta(account.leads)).to contain_exactly(pendente)
  end

  it 'estourados = sem resposta além do SLA da inbox' do
    lead_com_conversa(criada_ha: 2.minutes)
    atrasado = lead_com_conversa(criada_ha: 10.minutes)
    expect(described_class.estourados(account.leads)).to contain_exactly(atrasado)
  end

  it 'lead sem conversa ou em inbox que não é de lead fica de fora' do
    create(:lead, account: account)
    create(:lead, account: account, conversation: create(:conversation, account: account))
    expect(described_class.sem_resposta(account.leads)).to be_empty
  end

  it 'linha traz o prazo = criação + SLA da inbox, e o display_id da conversa' do
    lead = lead_com_conversa(criada_ha: 2.minutes)
    linha = described_class.linha(lead)
    expect(Time.zone.parse(linha[:prazo_em])).to be_within(1.second).of(lead.conversation.created_at + 5.minutes)
    expect(linha[:conversa_id]).to eq(lead.conversation.display_id)
    expect(linha[:canal]).to eq('Outro')
  end
end

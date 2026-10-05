require 'rails_helper'

RSpec.describe RamonFluxoListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversa) }

  def evento(nome, dados) = Events::Base.new(nome, Time.zone.now, dados)

  it 'mensagem recebida dispara com o texto; nota privada não' do
    msg = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming, content: 'oi')
    expect(Ramon::Fluxos::Disparo).to receive(:call)
      .with('mensagem_recebida', conversa, hash_including('texto' => 'oi', 'caixa_id' => conversa.inbox_id), origem: nil)
    listener.message_created(evento('message.created', message: msg))

    nota = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :outgoing, private: true)
    expect(Ramon::Fluxos::Disparo).not_to receive(:call)
    listener.message_created(evento('message.created', message: nota))
  end

  it 'etapa mudou dispara etapa + ganho, com a execução autora como origem' do
    ganho = create(:lead_stage, account: account, is_won: true, position: 9)
    de = lead.lead_stage_id
    lead.update!(lead_stage: ganho)
    autora = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })).execucoes.create!(account: account, alvo: lead)
    dados = { 'de_etapa_id' => de, 'para_etapa_id' => ganho.id }
    expect(Ramon::Fluxos::Disparo).to receive(:call).with('lead_mudou_etapa', lead, dados, origem: autora)
    expect(Ramon::Fluxos::Disparo).to receive(:call).with('lead_ganho', lead, dados, origem: autora)
    listener.lead_updated(evento('lead.updated', lead: lead, changed_attributes: { 'lead_stage_id' => [de, ganho.id] },
                                                 performed_by: autora))
  end

  it 'lead atualizado sem troca de etapa não dispara' do
    expect(Ramon::Fluxos::Disparo).not_to receive(:call)
    listener.lead_updated(evento('lead.updated', lead: lead, changed_attributes: {}))
  end

  it 'o modelo Lead manda a troca de etapa no evento' do
    nova = create(:lead_stage, account: account, position: 3)
    lead
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    lead.update!(lead_stage: nova)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::LEAD_UPDATED, anything, hash_including(changed_attributes: { 'lead_stage_id' => [anything, nova.id] }))
  end
end

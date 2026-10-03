require 'rails_helper'

RSpec.describe RamonConversa do
  let(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account) }
  let(:gabriela) { create(:user, account: account, name: 'Gabriela') }
  let(:tamires) { create(:user, account: account) }

  after { Current.reset }

  it 'grava quem atribuiu e quando' do
    Current.user = gabriela
    conversation.update!(assignee: tamires)
    registro = conversation.reload.additional_attributes['ramon_atribuicao']
    expect(registro).to include('por_id' => gabriela.id, 'por_nome' => 'Gabriela')
    expect(Time.zone.parse(registro['em'])).to be_within(5.seconds).of(Time.current)
  end

  it 'pegar a conversa pra si não conta como atribuída por alguém' do
    Current.user = tamires
    conversation.update!(assignee: tamires)
    expect(conversation.reload.additional_attributes['ramon_atribuicao']).to be_nil
  end

  it 'grava também quando muda o time' do
    Current.user = gabriela
    conversation.update!(team: create(:team, account: account))
    expect(conversation.reload.additional_attributes['ramon_atribuicao']).to include('por_nome' => 'Gabriela')
  end

  it 'sem usuário (automação) não grava' do
    conversation.update!(assignee: tamires)
    expect(conversation.reload.additional_attributes['ramon_atribuicao']).to be_nil
  end

  it 'devolver (tirar responsável e time) não sobrescreve o registro' do
    Current.user = gabriela
    conversation.update!(assignee: tamires)
    Current.user = tamires
    conversation.update!(assignee: nil)
    expect(conversation.reload.additional_attributes['ramon_atribuicao']).to include('por_nome' => 'Gabriela')
  end

  it 'devolver conversa com time (time e agente em duas requisições) não altera o registro' do
    registro = { 'ramon_atribuicao' => { 'por_id' => gabriela.id, 'por_nome' => 'Gabriela', 'em' => 1.hour.ago.iso8601 } }
    team = create(:team, account: account)
    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_columns(team_id: team.id, assignee_id: tamires.id, additional_attributes: registro)
    # rubocop:enable Rails/SkipsModelValidations
    Current.user = tamires
    conversation.update!(team: nil)
    conversation.update!(assignee: nil)
    expect(conversation.reload.additional_attributes).to eq(registro)
  end

  it 'expõe o lead da conversa, também no payload do websocket' do
    stage = create(:lead_stage, account: account, name: 'Etapa da etiqueta', color: '#475569')
    lead = create(:lead, account: account, conversation: conversation, lead_stage: stage)
    expect(conversation.reload.ramon_lead).to eq(lead)
    expect(conversation.push_event_data[:ramon_lead]).to eq(id: lead.id, stage_name: 'Etapa da etiqueta', stage_color: '#475569', thesis_name: nil)
  end
end

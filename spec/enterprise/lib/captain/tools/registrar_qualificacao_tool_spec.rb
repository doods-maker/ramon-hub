require 'rails_helper'

RSpec.describe Captain::Tools::RegistrarQualificacaoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:thesis) { create(:thesis, account: account, name: 'Auxilio-acidente') }
  let(:lead) { create(:lead, account: account, thesis: thesis, name: 'Maria') }
  let!(:item) { create(:thesis_item, thesis: thesis, section: 'qualificacao', title: 'Sequela permanente') }
  let!(:outro) { create(:thesis_item, thesis: thesis, section: 'qualificacao', title: 'Trabalhava com carteira') }

  it 'marca o criterio pelo texto e devolve o placar' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s, criterio: 'sequela', status: 'ok')

    expect(lead.reload.custom_attributes['qualificacao_status']).to eq(item.id.to_s => 'ok')
    expect(out).to include('Sequela permanente').and include('1 ok').and include('1 sem resposta')
  end

  it 'preserva o que ja estava marcado' do
    lead.update!(custom_attributes: { 'qualificacao_status' => { outro.id.to_s => 'falta' }, 'x' => 1 })
    tool.perform(tool_context, lead_id: lead.id.to_s, criterio: 'Sequela permanente', status: 'ok')

    expect(lead.reload.custom_attributes).to include('x' => 1,
                                                     'qualificacao_status' => { outro.id.to_s => 'falta', item.id.to_s => 'ok' })
  end

  it 'lista os criterios quando nao acha' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s, criterio: 'xablau', status: 'ok')
    expect(out).to include('Sequela permanente').and include('Trabalhava com carteira')
    expect(lead.reload.custom_attributes['qualificacao_status']).to be_blank
  end

  it 'recusa status invalido e caso sem tese' do
    expect(tool.perform(tool_context, lead_id: lead.id.to_s, criterio: 'sequela', status: 'talvez')).to include('ok, falta ou limpar')
    sem_tese = create(:lead, account: account, thesis: nil)
    expect(tool.perform(tool_context, lead_id: sem_tese.id.to_s, criterio: 'sequela', status: 'ok')).to include('sem tese')
    expect(tool.perform(tool_context, lead_id: '999999', criterio: 'a', status: 'ok')).to eq(described_class::SEM_LEAD)
  end
end

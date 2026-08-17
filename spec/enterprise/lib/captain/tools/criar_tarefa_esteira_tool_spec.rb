require 'rails_helper'

RSpec.describe Captain::Tools::CriarTarefaEsteiraTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, name: 'Joao') }

  it 'cria a tarefa follow_up com data e hora' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s, titulo: 'Cobrar CNIS', quando: '2030-01-10 09:00')
    task = lead.lead_tasks.last

    expect(task).to have_attributes(kind: 'follow_up', title: 'Cobrar CNIS', user_id: nil)
    expect(task.due_at.in_time_zone('America/Sao_Paulo').strftime('%Y-%m-%d %H:%M')).to eq('2030-01-10 09:00')
    expect(out).to include('Cobrar CNIS').and include('10/01/2030')
  end

  it 'aceita so a data (assume 09:00) e o tipo document' do
    tool.perform(tool_context, lead_id: lead.id.to_s, titulo: 'Receber laudo', quando: '2030-01-10', tipo: 'document')
    expect(lead.lead_tasks.last).to have_attributes(kind: 'document')
    expect(lead.lead_tasks.last.due_at.in_time_zone('America/Sao_Paulo').hour).to eq(9)
  end

  it 'nao duplica tarefa aberta com o mesmo titulo' do
    2.times { tool.perform(tool_context, lead_id: lead.id.to_s, titulo: 'Cobrar CNIS', quando: '2030-01-10') }
    expect(lead.lead_tasks.count).to eq(1)
  end

  it 'recusa data passada, tipo invalido e caso inexistente' do
    expect(tool.perform(tool_context, lead_id: lead.id.to_s, titulo: 'x', quando: '2000-01-01')).to include('ja passou')
    expect(tool.perform(tool_context, lead_id: lead.id.to_s, titulo: 'x', quando: '2030-01-01', tipo: 'festa')).to include('follow_up')
    expect(tool.perform(tool_context, lead_id: '999999', titulo: 'x', quando: '2030-01-01')).to eq(described_class::SEM_LEAD)
    expect(lead.lead_tasks.count).to eq(0)
  end
end

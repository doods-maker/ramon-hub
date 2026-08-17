require 'rails_helper'

RSpec.describe Captain::Tools::MarcarPerdidoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, name: 'Ana') }

  before { account.lost_reasons.create!(name: 'Sem direito', position: 1); account.lost_reasons.create!(name: 'Sem retorno', position: 2) }

  it 'cria a sugestao pendente com o motivo do catalogo, sem mover o caso' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s, motivo: 'sem retorno')
    s = account.copilot_suggestions.pending.last

    expect(s.payload).to include('acao' => 'perdido', 'lost_reason' => 'Sem retorno')
    expect(lead.reload.lost_at).to be_nil
    expect(out).to include('pendente')
  end

  it 'lista os motivos quando nao casa e nao duplica pendente' do
    expect(tool.perform(tool_context, lead_id: lead.id.to_s, motivo: 'mudou de ideia')).to include('Sem direito').and include('Sem retorno')
    2.times { tool.perform(tool_context, lead_id: lead.id.to_s, motivo: 'Sem direito') }
    expect(account.copilot_suggestions.pending.count).to eq(1)
  end

  it 'recusa caso ganho' do
    lead.update!(won_at: Time.current)
    expect(tool.perform(tool_context, lead_id: lead.id.to_s, motivo: 'Sem direito')).to include('ganho')
    expect(account.copilot_suggestions.count).to eq(0)
  end
end

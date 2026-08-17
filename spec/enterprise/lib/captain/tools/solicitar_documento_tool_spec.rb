require 'rails_helper'

RSpec.describe Captain::Tools::SolicitarDocumentoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:thesis) { create(:thesis, account: account) }
  let(:lead) { create(:lead, account: account, thesis: thesis, name: 'Maria das Dores') }

  before do
    create(:thesis_item, thesis: thesis, section: 'documento', title: 'CNIS')
    create(:thesis_item, thesis: thesis, section: 'documento', title: 'Laudo medico')
    create(:thesis_item, thesis: thesis, section: 'documento', title: 'RG').tap do |rg|
      lead.update!(custom_attributes: { 'doc_status' => { rg.id.to_s => 'recebido' } })
    end
  end

  it 'monta o pedido com os documentos pendentes da tese' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s)
    expect(out).to include('Maria').and include('• CNIS').and include('• Laudo medico')
    expect(out).not_to include('RG')
  end

  it 'usa a lista informada quando vier' do
    out = tool.perform(tool_context, lead_id: lead.id.to_s, documentos: 'carteira de trabalho, comprovante de residencia')
    expect(out).to include('• carteira de trabalho').and include('• comprovante de residencia')
    expect(out).not_to include('CNIS')
  end

  it 'avisa quando nao ha pendencia' do
    lead.update!(custom_attributes: { 'doc_status' => thesis.thesis_items.to_h { |i| [i.id.to_s, 'recebido'] } })
    expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('nenhum documento pendente')
  end
end

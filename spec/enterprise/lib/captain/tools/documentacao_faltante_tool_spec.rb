require 'rails_helper'

RSpec.describe Captain::Tools::DocumentacaoFaltanteTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:thesis) { create(:thesis, account: account) }

  describe '#perform' do
    it 'lista documento pendente da tese, lacuna da colheita e tarefa aberta' do
      item = create(:thesis_item, thesis: thesis, section: 'documento', title: 'CNIS atualizado')
      lead = create(:lead, account: account, thesis: thesis,
                           custom_attributes: { 'colheita' => { 'lacunas' => [{ 'campo' => 'beneficios[0].dcb',
                                                                                'como_obter' => 'Meu INSS' }] } })
      create(:lead_task, account: account, lead: lead, title: 'Pedir CNIS', due_at: 1.day.from_now)

      resultado = JSON.parse(tool.perform(tool_context, lead_id: lead.id.to_s))

      expect(resultado['documentos_pendentes'].first['title']).to eq(item.title)
      expect(resultado['lacunas_da_colheita'].first['campo']).to eq('beneficios[0].dcb')
      expect(resultado['tarefas_abertas'].first['title']).to eq('Pedir CNIS')
    end

    it 'nao lista documento ja recebido' do
      item = create(:thesis_item, thesis: thesis, section: 'documento', content: 'RG')
      lead = create(:lead, account: account, thesis: thesis,
                           custom_attributes: { 'doc_status' => { item.id.to_s => 'recebido' } })

      expect(JSON.parse(tool.perform(tool_context, lead_id: lead.id.to_s))['documentos_pendentes']).to be_empty
    end

    it 'avisa o agente que o CNIS recebido é o resumido, enquanto o CNIS seguir pendente' do
      create(:thesis_item, thesis: thesis, section: 'documento', title: 'CNIS')
      lead = create(:lead, account: account, thesis: thesis,
                           custom_attributes: { 'doc_alertas' => { 'cnis_resumido' => Time.zone.now.iso8601 } })

      resultado = JSON.parse(tool.perform(tool_context, lead_id: lead.id.to_s))

      expect(resultado['alertas']).to contain_exactly(a_string_including('resumido', 'remunerações'))
    end

    it 'pede o caso quando nao consegue resolver' do
      expect(tool.perform(tool_context)).to eq(described_class::SEM_LEAD)
    end
  end
end

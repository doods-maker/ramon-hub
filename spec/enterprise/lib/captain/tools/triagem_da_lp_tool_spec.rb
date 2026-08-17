require 'rails_helper'

RSpec.describe Captain::Tools::TriagemDaLpTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }

  describe '#perform' do
    it 'devolve veredito, respostas e duvidas do quiz da LP' do
      lead = create(:lead, account: account, name: 'Maria', source: 'auxilio-acidente', custom_attributes: {
                      'quiz' => {
                        'qualificado' => true,
                        'em' => '2026-08-10T14:00:00-03:00',
                        'duvidas' => ['Ainda posso pedir mesmo trabalhando?'],
                        'respostas' => [
                          { 'id' => 'sequela', 'pergunta' => 'Ficou sequela', 'resposta' => 'Sim, permanente' },
                          { 'id' => 'trabalha', 'pergunta' => 'Ainda trabalha', 'resposta' => 'Sim', 'duvida' => true }
                        ]
                      }
                    })

      texto = tool.perform(tool_context, lead_id: lead.id.to_s)

      expect(texto).to include("caso ##{lead.id} (Maria): QUALIFICADO pelo quiz", 'campanha: auxilio-acidente', 'em 10/08/2026',
                               '- Ficou sequela: Sim, permanente', '- Ainda trabalha: Sim [DUVIDA]',
                               'Ainda posso pedir mesmo trabalhando?')
    end

    it 'diz quando o caso nao passou pelo quiz' do
      lead = create(:lead, account: account)

      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('sem triagem da landing page')
    end

    it 'pede o caso quando nao consegue resolver' do
      expect(tool.perform(tool_context)).to eq(described_class::SEM_LEAD)
    end
  end
end

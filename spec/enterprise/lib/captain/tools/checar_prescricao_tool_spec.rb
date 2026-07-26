require 'rails_helper'

RSpec.describe Captain::Tools::ChecarPrescricaoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }

  describe '#perform' do
    it 'devolve o relogio da prescricao do caso' do
      lead = create(:lead, account: account, dcb_em: 6.years.ago.to_date, benefit_monthly_value: 1000)

      resultado = JSON.parse(tool.perform(tool_context, lead_id: lead.id.to_s))

      expect(resultado['parcelas_prescritas']).to eq(12)
      expect(resultado['valor_ja_prescrito']).to eq(12_000.0)
      expect(resultado['meses_ate_o_corte']).to eq(0)
    end

    it 'avisa quando o caso nao tem dcb' do
      lead = create(:lead, account: account, name: 'Joana')

      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('nao tem DCB registrada')
    end

    it 'acha o caso pela conversa quando nao recebe lead_id' do
      conversation = create(:conversation, account: account)
      lead = create(:lead, account: account, conversation: conversation, dcb_em: 1.year.ago.to_date)
      contexto = Struct.new(:state).new({ conversation: { id: conversation.id } })

      expect(JSON.parse(tool.perform(contexto))['lead_id']).to eq(lead.id)
    end

    it 'nao encontra caso de outra conta' do
      alheio = create(:lead, dcb_em: 1.year.ago.to_date)

      expect(tool.perform(tool_context, lead_id: alheio.id.to_s)).to eq(described_class::SEM_LEAD)
    end
  end
end

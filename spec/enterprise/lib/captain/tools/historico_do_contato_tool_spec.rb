require 'rails_helper'

RSpec.describe Captain::Tools::HistoricoDoContatoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }

  describe '#perform' do
    it 'devolve casos, conversas e notas da pessoa' do
      thesis = create(:thesis, account: account, name: 'BPC')
      # track_stage_cycle zera lost_at/lost_reason fora de etapa is_lost — precisa da etapa perdida.
      perdido = create(:lead_stage, account: account, name: 'Perdido', is_lost: true)
      lead = create(:lead, account: account, contact: contact, name: 'Caso BPC', thesis: thesis, lead_stage: perdido,
                           lost_at: Time.zone.parse('2026-01-10 12:00'), lost_reason: 'sem interesse')
      conversation = create(:conversation, account: account, contact: contact)
      create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'Oi, tenho direito ao BPC?')
      lead.lead_notes.create!(account: account, body: 'Ligou pedindo retorno')

      texto = tool.perform(tool_context, contact_id: contact.id.to_s)

      expect(texto).to include('Pessoa: Maria', "##{lead.id} Caso BPC | tese: BPC", 'PERDIDO em 10/01/2026 (sem interesse)',
                               conversation.inbox.name, 'Oi, tenho direito ao BPC?', 'Ligou pedindo retorno')
    end

    it 'chega na pessoa pelo lead_id' do
      lead = create(:lead, account: account, contact: contact)

      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include("contact_id #{contact.id}")
    end

    it 'diz quando nao ha nada' do
      texto = tool.perform(tool_context, contact_id: contact.id.to_s)

      expect(texto).to include('Casos: nenhum.', 'Conversas: nenhuma.', 'Notas: nenhuma.')
    end

    it 'pede a pessoa quando nao consegue resolver' do
      expect(tool.perform(tool_context)).to include('Nao encontrei a pessoa')
    end
  end
end

require 'rails_helper'

RSpec.describe Captain::Tools::AgendarReuniaoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, name: 'Maria das Dores') }

  describe '#perform' do
    it 'guarda o horario proposto na sugestao, sem criar tarefa' do
      tool.perform(tool_context, lead_id: lead.id.to_s, quando: '2027-03-10 14:30', assunto: 'Fechamento')

      sugestao = account.copilot_suggestions.pending.last
      expect(sugestao.payload['acao']).to eq('reuniao')
      expect(sugestao.payload['titulo']).to eq('Fechamento')
      expect(Time.zone.parse(sugestao.payload['quando']).hour).to eq(14)
      expect(lead.lead_tasks.count).to eq(0)
    end

    it 'recusa data no passado' do
      expect(tool.perform(tool_context, lead_id: lead.id.to_s, quando: '2020-01-01 10:00')).to include('ja passou')
    end

    it 'recusa data que nao entende' do
      expect(tool.perform(tool_context, lead_id: lead.id.to_s, quando: 'semana que vem')).to include('Nao entendi a data')
    end

    context 'with a IA em modo de piloto' do
      let(:bia) { create(:user, account: account, name: 'Bia Closer') }
      let(:conversa) { create(:conversation, account: account, custom_attributes: { 'copiloto_modo' => modo }) }
      let(:lead) { create(:lead, account: account, name: 'Maria das Dores', conversation: conversa) }
      let(:disponibilidade) { instance_double(Ramon::Agenda::Disponibilidade) }
      let(:modo) { 'piloto_total' }

      before do
        create(:team_member, team: create(:team, account: account, name: 'closer'), user: bia)
        allow(Ramon::Agenda::Disponibilidade).to receive(:new).and_return(disponibilidade)
        allow(Ramon::ReuniaoAgendamento).to receive(:call)
      end

      it 'marca a reuniao quando o horario esta livre' do
        allow(disponibilidade).to receive(:livre?).and_return(true)

        resposta = travel_to(Time.zone.parse('2027-03-01 12:00')) do
          tool.perform(tool_context, lead_id: lead.id.to_s, quando: '2027-03-10 14:30', assunto: 'Fechamento')
        end

        inicio = Time.find_zone!('America/Sao_Paulo').parse('2027-03-10 14:30')
        expect(Ramon::ReuniaoAgendamento).to have_received(:call).with(lead: lead, starts_at: inicio, title: 'Fechamento')
        expect(resposta).to eq("Reuniao marcada para #{Ramon::ReuniaoAgendamento.quando(inicio)}.")
        expect(lead.reload.closer).to eq(bia)
        expect(account.copilot_suggestions.count).to eq(0)
      end

      it 'recusa o horario ocupado e nao marca nada' do
        allow(disponibilidade).to receive(:livre?).and_return(false)

        resposta = travel_to(Time.zone.parse('2027-03-01 12:00')) do
          tool.perform(tool_context, lead_id: lead.id.to_s, quando: '2027-03-10 14:30')
        end

        expect(resposta).to include('acabou de ser ocupado')
        expect(Ramon::ReuniaoAgendamento).not_to have_received(:call)
      end

      context 'when o modo e rascunho' do
        let(:modo) { 'rascunho' }

        it 'so sugere, como antes' do
          travel_to(Time.zone.parse('2027-03-01 12:00')) do
            tool.perform(tool_context, lead_id: lead.id.to_s, quando: '2027-03-10 14:30')
          end

          expect(Ramon::ReuniaoAgendamento).not_to have_received(:call)
          expect(account.copilot_suggestions.pending.last.payload['acao']).to eq('reuniao')
        end
      end
    end
  end
end

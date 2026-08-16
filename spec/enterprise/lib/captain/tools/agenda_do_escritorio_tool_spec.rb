require 'rails_helper'

RSpec.describe Captain::Tools::AgendaDoEscritorioTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  # Dia sempre no futuro: tarefa do dia nao pode virar 'atrasada' com o passar do calendario.
  let(:dia) { (Time.current.in_time_zone('America/Sao_Paulo') + 30.days).to_date }
  let(:meio_dia) { dia.in_time_zone('America/Sao_Paulo').change(hour: 12) }

  def envelope(itens)
    { 'offset' => 0, 'limit' => 50, 'totalCount' => itens.size, 'data' => itens, 'query' => {} }
  end

  before do
    allow(Ramon::AdvboxClient).to receive(:posts).and_return(envelope([]))
  end

  describe '#perform' do
    it 'lists meetings, tasks of the day and overdue tasks of the account' do
      lead = create(:lead, account: account, name: 'Maria')
      create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reuniao de fechamento', due_at: meio_dia)
      create(:lead_task, account: account, lead: lead, kind: 'follow_up', title: 'Cobrar CNIS', due_at: meio_dia + 2.hours)
      create(:lead_task, account: account, lead: lead, kind: 'document', title: 'Velha', due_at: 3.days.ago)
      outra_conta = create(:account)
      create(:lead_task, account: outra_conta, lead: create(:lead, account: outra_conta), kind: 'meeting', due_at: meio_dia)

      resultado = tool.perform(tool_context, data: dia.iso8601)

      expect(resultado).to include("Agenda de #{dia.strftime('%d/%m/%Y')}")
      expect(resultado).to include('12:00 Reuniao de fechamento — Maria')
      expect(resultado).to include('14:00 Cobrar CNIS')
      expect(resultado).to include('Velha')
      expect(resultado).to include('1 reunioes, 1 tarefas do hub no dia, 1 atrasadas')
    end

    it 'shows advbox deadlines of the day' do
      allow(Ramon::AdvboxClient).to receive(:posts)
        .with(deadline_start: dia.iso8601, deadline_end: dia.iso8601, limit: 50)
        .and_return(envelope([{ 'task' => 'ELABORAR PETICAO', 'lawsuits_id' => 9,
                                'lawsuit' => { 'customers' => [{ 'name' => 'JOAO' }] }, 'users' => [{ 'name' => 'TAMIRES' }] }]))

      expect(tool.perform(tool_context, data: dia.iso8601)).to include('ELABORAR PETICAO — JOAO (TAMIRES, processo 9)')
    end

    it 'keeps going when advbox is down' do
      allow(Ramon::AdvboxClient).to receive(:posts).and_raise(Ramon::AdvboxClient::UnavailableError)

      resultado = tool.perform(tool_context, data: dia.iso8601)

      expect(resultado).to include('AdvBox indisponivel agora.')
      expect(resultado).to include('Totais:')
    end

    it 'defaults to today when no date is given' do
      hoje = Time.current.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y')

      expect(tool.perform(tool_context)).to include("Agenda de #{hoje}")
    end

    it 'rejects an invalid date' do
      expect(tool.perform(tool_context, data: 'ontem')).to eq('Data invalida. Use o formato AAAA-MM-DD.')
    end
  end
end

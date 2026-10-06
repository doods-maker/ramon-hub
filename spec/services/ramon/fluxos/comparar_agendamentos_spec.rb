require 'rails_helper'

RSpec.describe Ramon::Fluxos::CompararAgendamentos do
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Carla Closer') }
  let(:lead) do
    create(:lead, account: account, lead_stage: account.lead_stages.order(:position).first, closer: closer, name: 'João Pereira')
  end
  let(:agora) { Time.zone.parse('2026-10-07T12:00:00Z') }
  let(:inicio) { agora + 10.hours }

  before do
    travel_to(agora - 1.day) { Ramon::Fluxos::Reunioes.semear(account) }
    travel_to(agora - 1.hour) { lead }
  end

  after { Redis::Alfred.delete(Ramon::Fluxos::Reunioes.chave_rastro(account)) }

  # O começo da janela depende do relógio (o rastro guarda 8 dias contados de agora): compara "1h depois".
  def comparar = travel_to(agora + 1.hour) { described_class.new(account, dias: 2) }

  def marcar = travel_to(agora) { Ramon::ReuniaoAgendamento.call(lead: lead, starts_at: inicio, title: 'Primeiro Atendimento') }

  it 'em sombra de verdade (código + ensaio), marcar, remarcar e cancelar batem' do
    marcar
    tarefa = lead.lead_tasks.find_by!(kind: 'meeting')
    travel_to(agora + 10.minutes) { Ramon::ReuniaoAgendamento.remarcar(task: tarefa, starts_at: inicio + 1.day) }
    travel_to(agora + 20.minutes) { Ramon::ReuniaoAgendamento.cancelar(task: tarefa.reload) }
    c = comparar
    expect(c.linhas.map { |l| [l[:evento], l[:situacao]] }).to eq([%w[marcada igual], %w[remarcada igual], %w[cancelada igual]])
    expect(c.relatorio).to include('Resultado: BATEU', '1 marcada(s) · 1 remarcada(s) · 1 cancelada(s)')
  end

  it 'o que só um dos lados fez aparece na linha (e não bate)' do
    marcar
    ensaio = FluxoExecucao.where(fluxo: Ramon::Fluxos::Reunioes.fluxo(account, 'reuniao_marcada')).last
    ensaio.update!(trilha: ensaio.trilha.reject { |t| t['tipo'] == 'rascunho_texto' })
    linha = comparar.linhas.first
    expect(linha[:situacao]).to eq('diferente')
    expect(linha[:so_no_codigo]).to contain_exactly(a_string_starting_with('rascunho "'))
    expect(comparar.relatorio).to include('Resultado: NÃO BATEU')
  end

  it 'evento que o fluxo não viu aparece como só no código' do
    travel_to(agora) { lead.lead_activities.create!(account: account, kind: 'meeting_cancelled', to_value: 'X em 07/10/2026 19:00') }
    expect(comparar.linhas.map { |l| [l[:evento], l[:situacao]] }).to eq([%w[cancelada so_codigo]])
  end
end

require 'rails_helper'

RSpec.describe Ramon::Fluxos::CompararLembretes do
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Carla Closer') }
  let(:sdr) { create(:user, account: account, name: 'Sérgio SDR') }
  let(:lead) { create(:lead, account: account, closer: closer, name: 'João Pereira') }
  let(:agora) { Time.zone.parse('2026-10-07T14:00:00Z') }

  before do
    travel_to(agora - 1.day) { Ramon::Fluxos::Reunioes.semear(account) }
    travel_to(agora - 2.hours) do
      lead.lead_activities.create!(account: account, kind: 'meeting_scheduled', to_value: 'Primeiro Atendimento em 07/10/2026 19:00')
    end
  end

  after { Redis::Alfred.delete(Ramon::Fluxos::Reunioes.chave_rastro(account)) }

  # O que o MeetingReminderJob grava: 1 rastro por lembrete, com quem recebeu o sino.
  def codigo_avisou(momento, pessoas, rotulo: '8h antes', alvo: lead)
    dados = { 'tipo' => 'lembrete', 'lead_id' => alvo.id, 'inicio' => '2026-10-07T22:00:00Z', 'rotulo' => rotulo,
              'user_ids' => pessoas.map(&:id) }
    travel_to(momento) { Ramon::Fluxos::Reunioes.rastro!(account, dados) }
  end

  # O que a sombra grava: a linha "faria: sino para …" do ciclo (execuções concluídas: fora do índice único).
  def fluxo_ensaiou(momento, pessoas, contexto: {})
    resumo = "faria: sino para #{pessoas.map(&:name).sort.join(', ')}: \"Reunião em 8h antes\""
    linha = { 'no' => 'n8', 'tipo' => 'avisar_sino', 'em' => momento.iso8601, 'saida' => 's', 'resumo' => resumo, 'erro' => false }
    travel_to(momento) do
      Ramon::Fluxos::Reunioes.fluxo(account, 'lembretes_reuniao').execucoes.create!(
        account: account, alvo: lead, ensaio: true, status: 'concluida', trilha: [linha],
        contexto: contexto.merge('gatilho' => { 'lead_id' => lead.id })
      )
    end
  end

  # O começo da janela depende do relógio (o rastro guarda 8 dias contados de agora): compara "6h depois".
  def comparar = travel_to(agora + 6.hours) { described_class.new(account, dias: 2) }

  it 'mesmo lead e mesmas pessoas, até 3 min de diferença: igual' do
    codigo_avisou(agora, [closer])
    fluxo_ensaiou(agora + 50.seconds, [closer])
    c = comparar
    expect([c.linhas.pluck(:situacao), c.divergencias]).to eq([['igual'], 0])
    expect(c.relatorio).to include('Resultado: BATEU', 'João Pereira', '8h antes', 'código: Carla Closer · fluxo: Carla Closer')
  end

  it 'pessoas diferentes, só no código e só no fluxo aparecem e não batem' do
    codigo_avisou(agora, [closer, sdr])
    fluxo_ensaiou(agora + 1.minute, [closer])
    codigo_avisou(agora + 2.hours, [closer], rotulo: '1h antes')
    fluxo_ensaiou(agora + 5.hours, [closer])
    c = comparar
    expect(c.linhas.pluck(:situacao)).to eq(%w[pessoas so_codigo so_fluxo])
    expect(c.relatorio).to include('Resultado: NÃO BATEU', 'código: Carla Closer, Sérgio SDR · fluxo: Carla Closer')
  end

  it 'deixa de fora o "Testar com um lead…" e a reunião marcada antes da sombra existir' do
    antigo = travel_to(agora - 3.days) { create(:lead, account: account, name: 'Antigo') }
    codigo_avisou(agora, [closer], alvo: antigo)
    fluxo_ensaiou(agora, [closer], contexto: { 'pular_esperas' => true })
    expect(comparar.linhas).to eq([])
    expect(comparar.relatorio).to include('nada para comparar')
  end

  it 'a janela não começa antes de 8 dias atrás (é o que o rastro do código guarda) e o relatório diz isso' do
    c = travel_to(agora + 10.days) { described_class.new(account, dias: 30) }
    expect(c.de).to eq(agora + 2.days)
    expect(c.relatorio).to include('no máximo 8 dias')
  end
end

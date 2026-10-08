require 'rails_helper'

RSpec.describe Ramon::Fluxos::HorarioConta do
  let(:account) { create(:account) }
  let(:push) { ['avisar_push', { 'texto' => 'oi' }] }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  # Fluxo que nasceu antes das datas do teste: o que nasce depois da hora de hoje só começa amanhã (T3).
  def fluxo_conta(gatilho, *passos)
    grafo = grafo_linear({ 'tipo' => 'horario_conta' }.merge(gatilho), *(passos.presence || [push]))
    fluxo_publicado(account, grafo).tap { |f| f.update_column(:created_at, sp('2026-10-01 00:00')) } # rubocop:disable Rails/SkipsModelValidations
  end

  def rodar(texto) = travel_to(sp(texto)) { described_class.disparar }

  def concluir(fluxo) = fluxo.execucoes.update_all(status: 'concluida') # rubocop:disable Rails/SkipsModelValidations

  it 'uma vez por dia a partir da hora, com a conta de alvo, e de novo no dia seguinte' do
    fluxo = fluxo_conta({ 'hora' => '08:00' })
    rodar('2026-10-06 07:59')
    expect(fluxo.execucoes.count).to eq(0)
    rodar('2026-10-06 08:00')
    rodar('2026-10-06 15:00')
    expect(fluxo.execucoes.pluck(:alvo_type, :alvo_id, :ensaio)).to eq([['Account', account.id, false]])
    concluir(fluxo)
    rodar('2026-10-07 08:01')
    expect(fluxo.execucoes.count).to eq(2)
  end

  it 'só nos dias marcados (0 = domingo)' do
    fluxo = fluxo_conta({ 'hora' => '08:00', 'dias' => [1, 2, 3, 4, 5] })
    rodar('2026-10-04 09:00') # domingo
    expect(fluxo.execucoes.count).to eq(0)
    rodar('2026-10-05 09:00') # segunda
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'a cada N minutos: 1 vez por bloco de N minutos' do
    fluxo = fluxo_conta({ 'a_cada_minutos' => 5 })
    %w[10:00:10 10:02:00 10:04:59 10:05:01 10:09:30].each do |hora|
      rodar("2026-10-06 #{hora}")
      concluir(fluxo)
    end
    expect(fluxo.execucoes.count).to eq(2)
  end

  it 'fluxo que nasce depois da hora começa amanhã (nunca repete a vez que o código já fez)' do
    grafo = grafo_linear({ 'tipo' => 'horario_conta', 'hora' => '08:00' }, push)
    fluxo = travel_to(sp('2026-10-06 10:00')) { fluxo_publicado(account, grafo) }
    rodar('2026-10-06 10:01')
    expect(fluxo.execucoes.count).to eq(0)
    rodar('2026-10-07 08:00')
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'roda sem lead: o push sai e a execução conclui' do
    fluxo = fluxo_conta({ 'hora' => '08:00' })
    rodar('2026-10-06 08:00')
    execucao = fluxo.execucoes.sole
    expect { Ramon::Fluxos::Executor.new(execucao).avancar! }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(execucao.reload.status).to eq('concluida')
    expect([execucao.lead, execucao.conversa]).to eq([nil, nil])
  end

  it 'erro num fluxo não derruba os outros' do
    quebrado = fluxo_conta({ 'hora' => '08:00' })
    bom = fluxo_conta({ 'hora' => '08:00' })
    allow(Ramon::Fluxos::Disparo).to receive(:new).and_call_original
    allow(Ramon::Fluxos::Disparo).to receive(:new).with(quebrado, account, {}, nil).and_raise(ActiveRecord::RecordInvalid)
    rodar('2026-10-06 08:00')
    expect([quebrado.execucoes.count, bom.execucoes.count]).to eq([0, 1])
  end
end

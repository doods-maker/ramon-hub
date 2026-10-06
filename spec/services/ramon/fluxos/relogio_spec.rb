require 'rails_helper'

RSpec.describe Ramon::Fluxos::Relogio do
  let(:account) { create(:account) }
  let(:etapa) { create(:lead_stage, account: account, stalled_after_days: 3) }
  let(:nota) { ['nota_privada', { 'texto' => 'oi' }] }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  it 'relógio: a partir da hora, 1 vez por dia (fuso SP), só no grupo filtrado' do
    alvo = create(:lead, account: account, lead_stage: etapa)
    create(:lead, account: account)
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'relogio', 'hora' => '22:00', 'etapa_ids' => [etapa.id] }, nota))
    travel_to(sp('2026-10-06 21:59')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(0)
    travel_to(sp('2026-10-06 22:30')) { described_class.disparar_do_dia } # 01:30 UTC do dia 7
    travel_to(sp('2026-10-06 23:59')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.pluck(:alvo_id)).to eq([alvo.id])
    fluxo.execucoes.update_all(status: 'concluida') # rubocop:disable Rails/SkipsModelValidations
    travel_to(sp('2026-10-07 22:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(2)
  end

  it 'relógio perdido no minuto exato dispara quando voltar, no mesmo dia' do
    create(:lead, account: account, lead_stage: etapa)
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'relogio', 'hora' => '09:00', 'etapa_ids' => [etapa.id] }, nota))
    travel_to(sp('2026-10-06 15:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'fluxo do sistema com relógio nunca dispara (o resumo do dia é do código)' do
    create(:lead, account: account, lead_stage: etapa)
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'relogio', 'hora' => '08:00', 'etapa_ids' => [etapa.id] }, nota),
                            origem: 'sistema')
    travel_to(sp('2026-10-06 09:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(0)
    expect(fluxo.reload.ultimo_disparo_em).to be_nil
  end

  it 'lead parado dispara 1 vez por parada (padrão 11:00, regra da etapa)' do
    parado = create(:lead, account: account, lead_stage: etapa)
    parado.update_columns(stage_entered_at: sp('2026-10-01 10:00')) # rubocop:disable Rails/SkipsModelValidations
    create(:lead, account: account, lead_stage: etapa).update_columns(stage_entered_at: sp('2026-10-05 10:00')) # rubocop:disable Rails/SkipsModelValidations
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado' }, nota))
    travel_to(sp('2026-10-06 10:59')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(0)
    travel_to(sp('2026-10-06 11:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.pluck(:alvo_id)).to eq([parado.id])
    fluxo.execucoes.update_all(status: 'concluida') # rubocop:disable Rails/SkipsModelValidations
    travel_to(sp('2026-10-07 11:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'lead parado com N dias ignora a regra da etapa' do
    lead = create(:lead, account: account, lead_stage: etapa)
    lead.update_columns(stage_entered_at: sp('2026-10-01 10:00')) # rubocop:disable Rails/SkipsModelValidations
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado', 'dias' => 10 }, nota))
    travel_to(sp('2026-10-06 11:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(0)
  end

  it 'respeita o limite do dia' do
    2.times { create(:lead, account: account, lead_stage: etapa) }
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'relogio', 'hora' => '09:00', 'etapa_ids' => [etapa.id] }, nota),
                            limite_dia: 1)
    travel_to(sp('2026-10-06 09:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'erro num lead não derruba os outros' do
    leads = Array.new(2) { create(:lead, account: account, lead_stage: etapa) }
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'relogio', 'hora' => '09:00', 'etapa_ids' => [etapa.id] }, nota))
    allow(Ramon::Fluxos::Disparo).to receive(:new).and_call_original
    allow(Ramon::Fluxos::Disparo).to receive(:new).with(fluxo, leads.first, {}, nil).and_raise(ActiveRecord::RecordInvalid)
    travel_to(sp('2026-10-06 09:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.pluck(:alvo_id)).to eq([leads.last.id])
  end
end

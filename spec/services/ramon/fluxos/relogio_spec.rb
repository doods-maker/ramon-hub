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

  describe 'lead parado com retomada (B4.3: a cadência)' do
    def parado_com_conversa(na_etapa = etapa)
      lead = create(:lead, account: account, lead_stage: na_etapa, conversation_id: create(:conversation, account: account).id)
      lead.update_columns(stage_entered_at: sp('2026-10-01 10:00')) # rubocop:disable Rails/SkipsModelValidations
      lead
    end

    it 'retomada: todo dia para quem segue parado e pode receber retomada (a regra do código, não 1 vez por parada)' do
      pode = parado_com_conversa
      create(:lead, account: account, lead_stage: etapa).update_columns(stage_entered_at: sp('2026-10-01 10:00')) # rubocop:disable Rails/SkipsModelValidations
      recente = parado_com_conversa
      recente.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1, 'ultima_em' => sp('2026-10-05 11:00').iso8601 } })
      fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado', 'retomada' => true }, nota))
      travel_to(sp('2026-10-07 11:00')) { described_class.disparar_do_dia }
      expect(fluxo.execucoes.pluck(:alvo_id)).to eq([pode.id]) # sem conversa e retomada há 2 dias ficam de fora
      fluxo.execucoes.update_all(status: 'concluida') # rubocop:disable Rails/SkipsModelValidations
      travel_to(sp('2026-10-10 11:00')) { described_class.disparar_do_dia }
      expect(fluxo.execucoes.where(alvo_id: pode.id).count).to eq(2) # segue parado (a nota não conta retomada) → de novo
      expect(fluxo.execucoes.where(alvo_id: recente.id).count).to eq(1) # 5 dias depois da última
    end

    it 'retomada: o limite do dia corta na ordem do funil (etapa, posição), como o radar do código' do
      cedo = etapa
      tarde = create(:lead_stage, account: account, stalled_after_days: 3, position: 1)
      parado_com_conversa(tarde) # lead de id menor, mas na etapa de id maior
      primeiro = parado_com_conversa(cedo)
      fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado', 'retomada' => true }, nota), limite_dia: 1)
      travel_to(sp('2026-10-07 11:00')) { described_class.disparar_do_dia }
      expect(fluxo.execucoes.pluck(:alvo_id)).to eq([primeiro.id])
    end

    it 'retomada: data envenenada no lead não derruba o relógio' do
      envenenado = parado_com_conversa
      envenenado.update!(custom_attributes: { 'follow_up' => { 'ultima_em' => 'não é data' } })
      fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado', 'retomada' => true }, nota))
      travel_to(sp('2026-10-07 11:00')) { described_class.disparar_do_dia }
      expect(fluxo.execucoes.pluck(:alvo_id)).to eq([envenenado.id])
    end

    it 'o fluxo da cadência (migrado) dispara assumido: execução de verdade, não ensaio' do
      parado_com_conversa
      fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_parado', 'retomada' => true }, nota), sistema_chave: 'cadencia')
      with_modified_env(RAMON_FLUXO_CADENCIA: 'on') do
        travel_to(sp('2026-10-07 11:00')) { described_class.disparar_do_dia }
      end
      expect(fluxo.execucoes.pluck(:ensaio)).to eq([false])
    end
  end
end

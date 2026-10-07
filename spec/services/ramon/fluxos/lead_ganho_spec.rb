require 'rails_helper'

RSpec.describe Ramon::Fluxos::LeadGanho do
  let(:account) { create(:account) }
  let(:ganho) { account.lead_stages.find_by!(is_won: true) }
  let(:lead) { create(:lead, account: account, name: 'João Pereira') }

  def dossies = lead.lead_notes.where('body LIKE ?', '📋 DOSSIÊ%').count
  def pesquisas = lead.lead_notes.where('body LIKE ?', '%pesquisa NPS%').count

  before do
    allow(Ramon::AdvboxClient).to receive_messages(create_customer: { 'customers_id' => 11 },
                                                    create_lawsuit: { 'lawsuits_id' => 22 }, create_post: { 'posts_id' => 33 })
  end

  describe 'o fluxo "Lead ganho" (semeado)' do
    it 'nasce 1 vez, em sombra, ligado e publicado: dossiê → NPS → ADVBOX (por último, para não segurar o resto)' do
      fluxos = Ramon::Fluxos::Migracao.semear(account, 'lead_ganho')
      expect(Ramon::Fluxos::Migracao.semear(account, 'lead_ganho')).to eq(fluxos)
      fluxo = fluxos.sole
      expect([fluxo.origem, fluxo.modo, fluxo.ativo, fluxo.gatilho_tipo]).to eq(['usuario', 'sombra', true, 'lead_ganho'])
      rotinas = fluxo.versao_publicada.grafo['nos'].filter_map { |n| n.dig('config', 'rotina') }
      expect(rotinas).to eq(%w[dossie_passagem pesquisa_nps abrir_caso_advbox])
    end
  end

  describe 'a decisão é do evento (lida uma vez no callback do Lead)' do
    it 'código no comando (padrão): dossiê na hora, ADVBOX e NPS na fila — como sempre; o fluxo só ensaia' do
      fluxo = Ramon::Fluxos::Migracao.semear(account, 'lead_ganho').first
      with_modified_env(ADVBOX_API_TOKEN: 'tok') do
        expect { lead.update!(lead_stage: ganho) }
          .to have_enqueued_job(Ramon::AdvboxClosingJob).with(lead.id).and have_enqueued_job(Ramon::NpsDraftJob).with(lead.id)
      end
      expect(dossies).to eq(1)
      expect(fluxo.execucoes.pluck(:ensaio)).to eq([true])
    end

    it 'fluxo no comando: o código não faz nada; o fluxo faz dossiê, NPS e abre o caso no ADVBOX, 1 vez cada' do
      with_modified_env(ADVBOX_API_TOKEN: 'tok', RAMON_FLUXO_LEAD_GANHO: 'on') do
        Ramon::Fluxos::Migracao.semear(account, 'lead_ganho')
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'lead_ganho', 'normal')
        expect { lead.update!(lead_stage: ganho) }.not_to have_enqueued_job(Ramon::NpsDraftJob)
        expect(dossies).to eq(0) # o fluxo roda no job, não dentro do update
        perform_enqueued_jobs
      end
      expect([dossies, pesquisas]).to eq([1, 1])
      expect(Ramon::AdvboxClient).to have_received(:create_customer).once
      expect(lead.reload.custom_attributes.dig('advbox', 'lawsuits_id')).to eq(22)
    end

    it 'um desligado na tela devolve ao código, sem ensaio' do
      with_modified_env(ADVBOX_API_TOKEN: 'tok', RAMON_FLUXO_LEAD_GANHO: 'on') do
        fluxo = Ramon::Fluxos::Migracao.semear(account, 'lead_ganho').first
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'lead_ganho', 'normal')
        fluxo.update!(ativo: false)
        expect { lead.update!(lead_stage: ganho) }.to have_enqueued_job(Ramon::AdvboxClosingJob).with(lead.id)
        expect(fluxo.execucoes.count).to eq(0)
      end
      expect(dossies).to eq(1)
    end

    it 'fluxo no comando mas ocupado com o mesmo lead: o código faz este ganho (reserva) — uma decisão só' do
      allow(described_class).to receive(:pelo_codigo).and_call_original
      with_modified_env(ADVBOX_API_TOKEN: 'tok', RAMON_FLUXO_LEAD_GANHO: 'on') do
        fluxo = Ramon::Fluxos::Migracao.semear(account, 'lead_ganho').first
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'lead_ganho', 'normal')
        fluxo.execucoes.create!(account: account, alvo: lead, status: 'esperando', retomar_em: 5.minutes.from_now)
        expect { lead.update!(lead_stage: ganho) }.to have_enqueued_job(Ramon::AdvboxClosingJob).with(lead.id)
        expect(fluxo.execucoes.count).to eq(1) # a viva; este evento não criou outra
      end
      expect(described_class).to have_received(:pelo_codigo).once
      expect(dossies).to eq(1)
    end

    it 'fluxo no comando mas o motor falhou antes de criar a execução: o código faz este ganho (reserva)' do
      allow(Ramon::Fluxos::Disparo).to receive(:call).and_raise(StandardError, 'motor')
      with_modified_env(ADVBOX_API_TOKEN: 'tok', RAMON_FLUXO_LEAD_GANHO: 'on') do
        Ramon::Fluxos::Migracao.semear(account, 'lead_ganho')
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'lead_ganho', 'normal')
        expect { lead.update!(lead_stage: ganho) }.to have_enqueued_job(Ramon::NpsDraftJob).with(lead.id)
      end
      expect(dossies).to eq(1)
    end
  end

  it 'pelo código: erro no dossiê não derruba o NPS nem o caso no ADVBOX (as filas vêm antes, como nos callbacks)' do
    allow(Leads::HandoffNoteService).to receive(:new).and_raise(StandardError, 'dossiê')
    with_modified_env(ADVBOX_API_TOKEN: 'tok') do
      expect { described_class.pelo_codigo(lead) }.to raise_error(StandardError, 'dossiê')
    end
    expect(Ramon::NpsDraftJob).to have_been_enqueued.with(lead.id)
    expect(Ramon::AdvboxClosingJob).to have_been_enqueued.with(lead.id)
  end
end

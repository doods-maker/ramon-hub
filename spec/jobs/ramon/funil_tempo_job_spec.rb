require 'rails_helper'

RSpec.describe Ramon::FunilTempoJob do
  let(:account) { create(:account) }
  let(:negociacao) { account.lead_stages.find_by(label: 'fase-negociacao') }
  let(:ultima_chance) { account.lead_stages.find_by(label: 'fase-ultima-chance') }
  let(:qualificacao) { account.lead_stages.find_by(label: 'fase-qualificacao') }

  def lead_parado(etapa, dias)
    create(:lead, account: account, lead_stage: etapa).tap do |lead|
      lead.update_columns(stage_entered_at: dias.days.ago) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  before do
    Ramon::FunilAutomatico.mudar!(account, 'tempo_ultima_chance', 'on')
    Ramon::FunilAutomatico.mudar!(account, 'tempo_perdido', 'on')
  end

  it 'Negociação parada vai para Última chance' do
    lead = lead_parado(negociacao, negociacao.stalled_after_days + 1)
    described_class.perform_now
    expect(lead.reload.lead_stage).to eq(ultima_chance)
    expect(FunilAcao.find_by(lead: lead, peca: 'tempo_ultima_chance').desfazer['etapa_id']).to eq(negociacao.id)
  end

  it 'Última chance parada vai para Perdido com o motivo do catálogo e desfazer' do
    lead = lead_parado(ultima_chance, ultima_chance.stalled_after_days + 1)
    described_class.perform_now
    lead.reload
    expect(lead.lead_stage).to be_is_lost
    expect(lead.lost_reason).to eq('Sumiu / não respondeu')
    expect(FunilAcao.find_by(lead: lead, peca: 'tempo_perdido').desfazer['etapa_id']).to eq(ultima_chance.id)
  end

  it 'não anda duas etapas no mesmo dia' do
    lead = lead_parado(negociacao, negociacao.stalled_after_days + 30)
    described_class.perform_now
    expect(lead.reload.lead_stage).to eq(ultima_chance)
  end

  it 'lead dentro do prazo e lead em Qualificação não são tocados' do
    recente = lead_parado(negociacao, 1)
    qualif = lead_parado(qualificacao, 60)
    described_class.perform_now
    expect(recente.reload.lead_stage).to eq(negociacao)
    expect(qualif.reload.lead_stage).to eq(qualificacao)
  end

  it 'chaves off: nada acontece' do
    Ramon::FunilAutomatico.mudar!(account, 'tempo_ultima_chance', 'off')
    Ramon::FunilAutomatico.mudar!(account, 'tempo_perdido', 'off')
    negoc = lead_parado(negociacao, negociacao.stalled_after_days + 1)
    ultima = lead_parado(ultima_chance, ultima_chance.stalled_after_days + 1)
    described_class.perform_now
    expect(negoc.reload.lead_stage).to eq(negociacao)
    expect(ultima.reload.lead_stage).to eq(ultima_chance)
    expect(FunilAcao.count).to eq(0)
  end

  it 'conta sem a etapa Última chance: o job termina sem erro e a Negociação fica onde está' do
    lead = lead_parado(negociacao, negociacao.stalled_after_days + 1)
    ultima_chance.destroy!
    expect { described_class.perform_now }.not_to raise_error
    expect(lead.reload.lead_stage).to eq(negociacao)
  end
end

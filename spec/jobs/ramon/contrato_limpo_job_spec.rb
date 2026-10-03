require 'rails_helper'

RSpec.describe Ramon::ContratoLimpoJob do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.order(:position).first }

  def lead_com(won_at:, docs_completos_em:)
    create(:lead, account: account, lead_stage: stage).tap do |lead|
      lead.update_columns(won_at: won_at, docs_completos_em: docs_completos_em) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  it 'carimba o momento exato: o mais tardio entre assinatura + 7 dias e docs completos', :aggregate_failures do
    assinado = Time.zone.parse('2026-11-01 12:00:00')
    docs_antes = lead_com(won_at: assinado, docs_completos_em: assinado - 1.day)
    docs_depois = lead_com(won_at: assinado, docs_completos_em: assinado + 9.days)

    travel_to(assinado + 10.days) { described_class.perform_now }

    expect(docs_antes.reload.contrato_limpo_em).to eq(assinado + 7.days)
    expect(docs_depois.reload.contrato_limpo_em).to eq(assinado + 9.days)
  end

  it 'não carimba antes dos 7 dias, sem docs completos ou sem assinatura', :aggregate_failures do
    leads = [
      lead_com(won_at: 3.days.ago, docs_completos_em: 3.days.ago),
      lead_com(won_at: 10.days.ago, docs_completos_em: nil),
      lead_com(won_at: nil, docs_completos_em: 10.days.ago)
    ]

    described_class.perform_now

    expect(leads.map { |l| l.reload.contrato_limpo_em }).to all(be_nil)
  end

  it 'carimbo já feito não muda' do
    lead = lead_com(won_at: 20.days.ago, docs_completos_em: 20.days.ago)
    lead.update_columns(contrato_limpo_em: 1.day.ago.change(usec: 0)) # rubocop:disable Rails/SkipsModelValidations

    expect { described_class.perform_now }.not_to(change { lead.reload.contrato_limpo_em })
  end
end

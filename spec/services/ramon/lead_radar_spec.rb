require 'rails_helper'

RSpec.describe Ramon::LeadRadar do
  let(:account) { create(:account) }

  describe '.closed_window' do
    it 'ganho antigo em Documentos ou Jurídico continua no Kanban; em Fechado, sai', :aggregate_failures do
      documentos = account.lead_stages.create!(name: 'Docs X', label: Ramon::EtapaDeGanho::DOCUMENTOS, is_won: true)
      juridico = account.lead_stages.create!(name: 'Jur X', label: Ramon::EtapaDeGanho::JURIDICO, is_won: true)
      fechado = account.lead_stages.find_by!(label: Ramon::EtapaDeGanho::FECHADO)
      em_docs, em_juridico, em_fechado = [documentos, juridico, fechado].map { |s| create(:lead, account: account, lead_stage: s) }
      account.leads.where(id: [em_docs, em_juridico, em_fechado].map(&:id)).update_all(won_at: 120.days.ago) # rubocop:disable Rails/SkipsModelValidations

      visiveis = described_class.closed_window(account, account.leads, {})

      expect(visiveis).to include(em_docs, em_juridico)
      expect(visiveis).not_to include(em_fechado)
    end
  end
end

require 'rails_helper'

RSpec.describe Ramon::LeadRadar do
  let(:account) { create(:account) }

  describe '.closed_window' do
    it 'ganho antigo em Documentos continua no Kanban; em Fechado, sai', :aggregate_failures do
      documentos = account.lead_stages.create!(name: 'Docs X', label: Ramon::EtapaDeGanho::DOCUMENTOS, is_won: true)
      fechado = account.lead_stages.find_by!(label: Ramon::EtapaDeGanho::FECHADO)
      em_docs = create(:lead, account: account, lead_stage: documentos)
      em_fechado = create(:lead, account: account, lead_stage: fechado)
      account.leads.where(id: [em_docs.id, em_fechado.id]).update_all(won_at: 120.days.ago) # rubocop:disable Rails/SkipsModelValidations

      visiveis = described_class.closed_window(account, account.leads, {})

      expect(visiveis).to include(em_docs)
      expect(visiveis).not_to include(em_fechado)
    end
  end
end

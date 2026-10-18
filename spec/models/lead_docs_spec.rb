require 'rails_helper'

RSpec.describe LeadDocs do
  let(:account) { create(:account) }

  describe 'desmarcar documento recebido' do
    it 'solta o anexo e o vínculo do Drive só do item desmarcado' do
      lead = create(:lead, account: account, custom_attributes: {
                      'doc_status' => { '4' => 'recebido', '5' => 'recebido' },
                      'doc_anexos' => { '4' => 77, '5' => 78 },
                      'drive' => { 'pasta_id' => 'p1', 'itens' => { '4' => 'f4', '5' => 'f5' } }
                    })

      # mesmo PATCH do front (ciclo recebido → pendente): o merge do controller manda o resto junto
      lead.update!(custom_attributes: lead.custom_attributes.deep_merge('doc_status' => { '4' => 'pendente' }))

      attrs = lead.reload.custom_attributes
      expect(attrs['doc_anexos']).to eq('5' => 78)
      expect(attrs['drive']).to eq('pasta_id' => 'p1', 'itens' => { '5' => 'f5' })
    end
  end
end

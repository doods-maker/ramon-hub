require 'rails_helper'

RSpec.describe LeadDocs do
  let(:account) { create(:account) }

  describe '#docs_pendentes' do
    it 'os itens de documento da tese que ainda não foram recebidos, com título e status' do
      tese = create(:thesis, account: account)
      rg = create(:thesis_item, thesis: tese, section: 'documento', content: 'RG')
      create(:thesis_item, thesis: tese, section: 'documento', title: 'CNIS completo')
      create(:thesis_item, thesis: tese, section: 'qualificacao', content: 'Não é documento')
      lead = create(:lead, account: account, thesis: tese, custom_attributes: { 'doc_status' => { rg.id.to_s => 'recebido' } })

      expect(lead.docs_pendentes.map { |doc| doc.slice(:title, :status) }).to eq([{ title: 'CNIS completo', status: 'pendente' }])
    end
  end

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

  # Relógio da cobrança de Documentos (spec §7, Review Focus 2): documento novo pela conversa, pelo Painel do Cliente ou por
  # uma pessoa passa pelo mesmo save do lead.
  describe 'documento novo na cobrança de Documentos' do
    def cobranca(lead) = lead.reload.custom_attributes['documentos_cobranca']

    it 'item que vira recebido marca ultimo_documento_em; desmarcar ou regravar o mesmo não marca', :aggregate_failures do
      lead = create(:lead, account: account, custom_attributes: { 'doc_status' => { '4' => 'recebido' },
                                                                  'documentos_cobranca' => { 'entrou_em' => 1.day.ago.iso8601 } })

      freeze_time do
        lead.update!(custom_attributes: lead.custom_attributes.deep_merge('doc_status' => { '5' => 'recebido' }))
        expect(cobranca(lead)['ultimo_documento_em']).to eq(Time.current.iso8601)
      end
      marca = cobranca(lead)['ultimo_documento_em']

      travel_to(1.hour.from_now) do
        lead.update!(custom_attributes: lead.custom_attributes.deep_merge('doc_status' => { '4' => 'pendente', '5' => 'recebido' }, 'outro' => 1))
        expect(cobranca(lead)['ultimo_documento_em']).to eq(marca)
      end
    end

    it 'lead fora da cobrança: nada marcado' do
      lead = create(:lead, account: account)
      lead.update!(custom_attributes: { 'doc_status' => { '5' => 'recebido' } })
      expect(cobranca(lead)).to be_nil
    end
  end
end

require 'rails_helper'

RSpec.describe Ramon::DriveExportService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Maria das Dores', cpf: '529.982.247-25') }
  let(:thesis) { create(:thesis, account: account) }
  let!(:item_a) { create(:thesis_item, thesis: thesis, section: 'documento', title: 'RG') }
  let!(:item_b) { create(:thesis_item, thesis: thesis, section: 'documento', title: 'CNIS') }

  def attachment_for(fixture, content_type, file_type: :file)
    message = create(:message, account: account, conversation: create(:conversation, account: account))
    message.attachments.create!(account_id: account.id, file_type: file_type,
                                file: fixture_file_upload(Rails.root.join("spec/assets/#{fixture}"), content_type))
  end

  def won_lead(custom_attributes: {})
    create(:lead, account: account, contact: contact, thesis: thesis, won_at: Time.zone.now,
                  custom_attributes: custom_attributes)
  end

  before do
    allow(Ramon::DriveClient).to receive(:root_id).and_return('root-id')
    allow(Ramon::DriveClient).to receive(:ensure_folder) { |name, _parent_id| "folder-#{name}" }
    allow(Ramon::DriveClient).to receive(:upload).and_return('file-id')
    allow(Ramon::DriveClient).to receive(:shortcut).and_return('shortcut-id')
    allow(Ramon::DriveClient).to receive(:rename)
  end

  # (a) sem env: perform retorna sem tocar o client
  it 'nao faz nada quando o DriveClient nao esta configurado' do
    allow(Ramon::DriveClient).to receive(:configured?).and_return(false)
    lead = won_lead
    expect(Ramon::DriveClient).not_to receive(:upload)
    described_class.new(lead).perform
  end

  context 'when configured' do
    before { allow(Ramon::DriveClient).to receive(:configured?).and_return(true) }

    # (b) item recebido com anexo vinculado e ainda nao exportado -> upload + shortcut + drive.itens
    it 'exporta um item recebido com anexo vinculado ainda nao exportado' do
      attachment = attachment_for('sample.pdf', 'application/pdf')
      lead = won_lead(custom_attributes: {
                        'doc_status' => { item_a.id.to_s => 'recebido', item_b.id.to_s => 'pendente' },
                        'doc_anexos' => { item_a.id.to_s => attachment.id }
                      })

      described_class.new(lead).perform

      expect(Ramon::DriveClient).to have_received(:upload).once
      expect(Ramon::DriveClient).to have_received(:shortcut).once
      lead.reload
      expect(lead.custom_attributes.dig('drive', 'itens', item_a.id.to_s)).to eq('file-id')
      expect(lead.custom_attributes.dig('drive', 'concluido_em')).to be_nil
    end

    # (c) item ja em drive.itens -> nao re-exporta
    it 'nao re-exporta item que ja esta em drive.itens' do
      attachment = attachment_for('sample.pdf', 'application/pdf')
      lead = won_lead(custom_attributes: {
                        'doc_status' => { item_a.id.to_s => 'recebido', item_b.id.to_s => 'pendente' },
                        'doc_anexos' => { item_a.id.to_s => attachment.id },
                        'drive' => { 'pasta_id' => 'folder-existente', 'itens' => { item_a.id.to_s => 'ja-exportado' } }
                      })

      described_class.new(lead).perform

      expect(Ramon::DriveClient).not_to have_received(:upload)
      expect(Ramon::DriveClient).not_to have_received(:shortcut)
    end

    # (d) checklist completo -> rename com "— COMPLETO" + concluido_em gravado
    it 'conclui a pasta quando o checklist ja esta 100% exportado' do
      lead = won_lead(custom_attributes: {
                        'doc_status' => { item_a.id.to_s => 'recebido', item_b.id.to_s => 'recebido' },
                        'drive' => { 'pasta_id' => 'folder-cliente',
                                    'itens' => { item_a.id.to_s => 'f1', item_b.id.to_s => 'f2' } }
                      })

      described_class.new(lead).perform

      expect(Ramon::DriveClient).to have_received(:rename).with('folder-cliente', 'Maria das Dores — 52998224725 — COMPLETO')
      lead.reload
      expect(lead.custom_attributes.dig('drive', 'concluido_em')).to be_present
    end

    it 'nao conclui de novo quando concluido_em ja esta gravado' do
      lead = won_lead(custom_attributes: {
                        'doc_status' => { item_a.id.to_s => 'recebido', item_b.id.to_s => 'recebido' },
                        'drive' => { 'pasta_id' => 'folder-cliente',
                                    'itens' => { item_a.id.to_s => 'f1', item_b.id.to_s => 'f2' },
                                    'concluido_em' => '2026-08-01T10:00:00Z' }
                      })

      described_class.new(lead).perform

      expect(Ramon::DriveClient).not_to have_received(:rename)
    end

    # (e) anexo png -> conteudo enviado vira PDF (nome termina em .pdf)
    it 'converte anexo png para PDF de 1 pagina antes de subir' do
      attachment = attachment_for('sample.png', 'image/png', file_type: :image)
      lead = won_lead(custom_attributes: {
                        'doc_status' => { item_a.id.to_s => 'recebido', item_b.id.to_s => 'pendente' },
                        'doc_anexos' => { item_a.id.to_s => attachment.id }
                      })

      expect(Ramon::DriveClient).to receive(:upload) do |name:, io:, content_type:, parent_id:|
        expect(name).to end_with('.pdf')
        expect(content_type).to eq('application/pdf')
        expect(io.read[0, 4]).to eq('%PDF')
        expect(parent_id).to eq('folder-Maria das Dores — 52998224725')
        'file-id'
      end

      described_class.new(lead).perform
    end
  end
end

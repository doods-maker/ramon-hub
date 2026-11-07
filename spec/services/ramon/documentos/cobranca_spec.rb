require 'rails_helper'

# Estado da cobrança de Documentos (custom_attributes['documentos_cobranca']): gravado só na sub-chave, num UPDATE atômico, e
# nenhum save comum do lead (DocMatch, Painel, tela) apaga uma marca gravada no meio do caminho.
RSpec.describe Ramon::Documentos::Cobranca do
  let(:account) { create(:account) }
  let(:documentos) { Ramon::EtapasPosVenda.criar!(account).first }
  let(:lead) { create(:lead, account: account) }

  before do
    lead.update_columns(lead_stage_id: documentos.id, # rubocop:disable Rails/SkipsModelValidations
                        custom_attributes: { 'documentos_cobranca' => { 'entrou_em' => '2026-10-05T10:00:00-03:00' }, 'outro' => 1 })
  end

  def cobranca = lead.reload.custom_attributes['documentos_cobranca']

  it 'marcar: soma e tira marcas só na sub-chave; o resto do custom_attributes fica', :aggregate_failures do
    described_class.marcar(lead, { 'lembrete_1_em' => 'x', 'lembrete_2_em' => 'y' })
    described_class.marcar(lead, { 'silencio_em' => 'z' }, remover: %w[lembrete_2_em])

    expect(cobranca).to eq('entrou_em' => '2026-10-05T10:00:00-03:00', 'lembrete_1_em' => 'x', 'silencio_em' => 'z')
    expect(lead.custom_attributes['outro']).to eq(1)
  end

  it 'ligar: o estado recomeça só com entrou_em' do
    described_class.marcar(lead, { 'abertura_em' => 'x' })
    freeze_time do
      described_class.ligar(lead)
      expect(cobranca).to eq('entrou_em' => Time.current.iso8601)
    end
  end

  it 'marca gravada entre o reload e o update! de quem salva o lead (DocMatch) sobrevive', :aggregate_failures do
    copia = Lead.find(lead.id) # o reload do DocMatchService#gravar
    described_class.marcar(lead, { 'lembrete_1_em' => 'x' })

    copia.update!(custom_attributes: copia.custom_attributes.deep_merge('doc_status' => { '9' => 'pendente' }))

    expect(cobranca).to include('entrou_em', 'lembrete_1_em')
    expect(lead.custom_attributes['doc_status']).to eq('9' => 'pendente')
  end
end

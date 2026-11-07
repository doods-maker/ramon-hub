require 'rails_helper'

# Imagem do passo a passo (spec §3; decisões de 07/11: UMA imagem por tema e UMA mensagem por resposta). A tool só prepara
# a imagem no estado do turno; ela sai anexada à resposta do agente (legenda = o texto), no envio da resposta
# (Ramon::RespostaIaAtrasadaJob). O núcleo fica aqui porque o CI roda sem enterprise/.
RSpec.describe Ramon::Documentos::PassoAPasso do
  let(:account) { create(:account) }
  let(:documentos) { Ramon::EtapasPosVenda.criar!(account).first }
  let(:caixa) do
    canal = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    create(:inbox, channel: canal, account: account)
  end
  let(:conversa) { create(:conversation, account: account, inbox: caixa, status: :pending) }
  let(:imagem) do
    ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'meu_inss_cnis.png',
                                           content_type: 'image/png')
  end
  let(:estado) { {} }

  before do
    lead = create(:lead, account: account, conversation: conversa)
    lead.update_columns(lead_stage_id: documentos.id) # rubocop:disable Rails/SkipsModelValidations
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming)
  end

  def preparar(tema, chave: 'on')
    with_modified_env(RAMON_ETAPA_DOCUMENTOS: chave) { described_class.preparar(conversa, tema, imagens: [imagem], estado: estado) }
  end

  def enviadas = conversa.messages.outgoing

  describe '.preparar' do
    it 'tema com imagem: guarda a imagem no turno e não manda nada ainda', :aggregate_failures do
      expect(preparar('meu_inss_cnis')).to eq(described_class::PREPARADA)
      expect(estado[described_class::ESTADO]).to eq(imagem.id)
      expect(enviadas).to be_empty
    end

    it 'uma imagem por turno: a segunda chamada é recusada' do
      preparar('meu_inss_cnis')
      expect(preparar('meu_inss_cnis')).to eq(described_class::JA_TEM)
    end

    it 'tema sem imagem: nada guardado, o agente explica em texto', :aggregate_failures do
      expect(preparar('meu_inss_cat')).to eq(described_class::SEM_IMAGEM)
      expect(estado).to be_empty
    end

    it 'tema fora da lista: nada guardado' do
      expect(preparar('xablau')).to include('govbr_criar_conta')
      expect(estado).to be_empty
    end

    it 'janela de 24 h fechada: nada guardado', :aggregate_failures do
      conversa.messages.incoming.update_all(created_at: 25.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      expect(preparar('meu_inss_cnis')).to eq(described_class::FORA_DA_JANELA)
      expect(estado).to be_empty
    end

    it 'upload do portal do cliente não abre a janela do WhatsApp' do
      conversa.messages.incoming.update_all(created_at: 25.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      create(:message, account: account, conversation: conversa, inbox: caixa, message_type: :incoming,
                       content_attributes: { 'ramon_origem' => 'portal' })
      expect(preparar('meu_inss_cnis')).to eq(described_class::FORA_DA_JANELA)
    end

    it 'chave desligada ou conversa já com uma pessoa: nada guardado', :aggregate_failures do
      expect(preparar('meu_inss_cnis', chave: nil)).to eq(described_class::NAO_SAI)
      conversa.update!(status: :open)
      expect(preparar('meu_inss_cnis')).to eq(described_class::NAO_SAI)
      expect(estado).to be_empty
    end
  end

  describe '.criar_mensagem' do
    let(:params) { { message_type: :outgoing, account_id: account.id, inbox_id: caixa.id, content: 'Olha o caminho na imagem.' } }

    it 'uma mensagem só: o texto do agente como legenda e uma cópia da imagem', :aggregate_failures do
      described_class.criar_mensagem(conversa, params, imagem.id)

      expect(enviadas.count).to eq(1)
      expect(enviadas.first.content).to eq('Olha o caminho na imagem.')
      anexo = enviadas.first.attachments.sole.file
      expect([anexo.filename.to_s, anexo.blob.id == imagem.id]).to eq(['meu_inss_cnis.png', false])
    end

    it 'imagem apagada no meio do caminho: o texto sai sozinho' do
      described_class.criar_mensagem(conversa, params, 0)
      expect(enviadas.sole.attachments).to be_empty
    end
  end
end

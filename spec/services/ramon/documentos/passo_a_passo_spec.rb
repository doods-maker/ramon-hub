require 'rails_helper'

# Imagem do passo a passo (spec §3; decisão 07/11: UMA imagem por tema, uma mensagem com um anexo). O núcleo fica aqui
# porque o CI roda sem enterprise/ (a tool enviar_passo_a_passo só repassa as imagens do assistente).
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

  before do
    lead = create(:lead, account: account, conversation: conversa)
    lead.update_columns(lead_stage_id: documentos.id) # rubocop:disable Rails/SkipsModelValidations
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming)
  end

  def enviar(tema, chave: 'on')
    with_modified_env(RAMON_ETAPA_DOCUMENTOS: chave) { described_class.enviar(conversa, tema, imagens: [imagem], remetente: nil) }
  end

  def enviadas = conversa.messages.outgoing

  it 'tema com imagem: uma mensagem com um anexo', :aggregate_failures do
    expect(enviar('meu_inss_cnis')).to eq(described_class::ENVIADA)
    expect(enviadas.count).to eq(1)
    expect(enviadas.first.attachments.map { |a| a.file.filename.to_s }).to eq(['meu_inss_cnis.png'])
  end

  it 'tema sem imagem: nada enviado, o agente explica em texto', :aggregate_failures do
    expect(enviar('meu_inss_cat')).to eq(described_class::SEM_IMAGEM)
    expect(enviadas).to be_empty
  end

  it 'tema fora da lista: nada enviado' do
    expect(enviar('xablau')).to include('govbr_criar_conta')
    expect(enviadas).to be_empty
  end

  it 'janela de 24 h fechada: nada enviado', :aggregate_failures do
    conversa.messages.incoming.update_all(created_at: 25.hours.ago) # rubocop:disable Rails/SkipsModelValidations
    expect(enviar('meu_inss_cnis')).to eq(described_class::FORA_DA_JANELA)
    expect(enviadas).to be_empty
  end

  it 'upload do portal do cliente não abre a janela do WhatsApp', :aggregate_failures do
    conversa.messages.incoming.update_all(created_at: 25.hours.ago) # rubocop:disable Rails/SkipsModelValidations
    create(:message, account: account, conversation: conversa, inbox: caixa, message_type: :incoming,
                     content_attributes: { 'ramon_origem' => 'portal' })
    expect(enviar('meu_inss_cnis')).to eq(described_class::FORA_DA_JANELA)
    expect(enviadas).to be_empty
  end

  it 'chave desligada ou conversa já com uma pessoa: nada enviado', :aggregate_failures do
    expect(enviar('meu_inss_cnis', chave: nil)).to eq(described_class::NAO_SAI)
    conversa.update!(status: :open)
    expect(enviar('meu_inss_cnis')).to eq(described_class::NAO_SAI)
    expect(enviadas).to be_empty
  end
end

require 'rails_helper'

RSpec.describe Ramon::DocMatchService do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let!(:rg) { create(:thesis_item, thesis: thesis, section: 'documento', content: 'RG') }
  let(:conversation) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, thesis: thesis, conversation: conversation) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming).tap do |m|
      m.attachments.create!(account_id: account.id, file_type: :image,
                            file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))
    end
  end

  before { lead }

  it 'grava doc_sugestao quando o LLM aponta um item valido' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(lead.reload.custom_attributes.dig('doc_sugestao', 'item_id')).to eq(rg.id)
    sugestao = lead.custom_attributes['doc_sugestao']
    expect(sugestao['resolvida']).to be(false)
    expect(sugestao['message_id']).to eq(message.id)
  end

  it 'anexo casado com o checklist dispara documento_recebido' do
    allow(Ramon::Fluxos::Disparo).to receive(:externo)
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('documento_recebido', lead, hash_including('documento'))
  end

  it 'registra evento de automação doc_match na conversa' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1))
    expect { described_class.new(message).perform }
      .to have_enqueued_job(Conversations::ActivityMessageJob).with(
        message.conversation,
        hash_including(
          message_type: :activity,
          content_attributes: hash_including(
            'ramon_event' => 'doc_match',
            'item_id' => rg.id
          )
        )
      )
  end

  it 'grava doc_sugestao quando o LLM devolve item_id como string' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: %({"item_id": "#{rg.id}"}), input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(lead.reload.custom_attributes.dig('doc_sugestao', 'item_id')).to eq(rg.id)
  end

  it 'chama o LLM só 1 vez mesmo com vários itens pendentes no checklist' do
    create(:thesis_item, thesis: thesis, section: 'documento', content: 'CNIS')
    expect(Ramon::LlmClient).to receive(:complete)
      .once
      .and_return(Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(lead.reload.custom_attributes.dig('doc_sugestao', 'item_id')).to eq(rg.id)
  end

  it 'com chave da Anthropic, o Claude Haiku 5.5 vê a foto e já marca o item como recebido' do
    resposta = Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1)
    allow(Ramon::LlmClient).to receive(:complete).and_return(resposta)
    with_modified_env(ANTHROPIC_API_KEY: 'sk-test') { described_class.new(message).perform }
    expect(Ramon::LlmClient).to have_received(:complete)
      .with(hash_including(provider: 'anthropic', model: 'claude-haiku-5-5', anexo: kind_of(ActiveStorage::Attached::One)))
    attrs = lead.reload.custom_attributes
    expect(attrs.dig('doc_status', rg.id.to_s)).to eq('recebido')
    expect(attrs.dig('doc_anexos', rg.id.to_s)).to eq(message.attachments.first.id)
    expect(attrs['doc_sugestao']).to be_nil
    expect(lead.docs_completos_em).to be_present
    expect(Notification.where(primary_actor: lead, notification_type: 'ramon_fluxo_aviso')).to be_empty # aviso só em Documentos
  end

  it 'em lead ganho, mesmo com visão, só sugere (marcar sobe pro Drive/ADVBOX)' do
    lead.update_column(:won_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
    resposta = Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1)
    allow(Ramon::LlmClient).to receive(:complete).and_return(resposta)
    with_modified_env(ANTHROPIC_API_KEY: 'sk-test') { described_class.new(message).perform }
    attrs = lead.reload.custom_attributes
    expect(attrs['doc_status']).to be_blank
    expect(attrs.dig('doc_sugestao', 'item_id')).to eq(rg.id)
  end

  it 'visão recusa o anexo (PDF com +100 páginas): cai na sugestão sem visão' do
    resposta = Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1)
    anexos = []
    allow(Ramon::LlmClient).to receive(:complete) do |**args|
      anexos << args[:anexo].present?
      raise RubyLLM::Error.new(nil, 'A maximum of 100 PDF pages may be provided') if args[:anexo]

      resposta
    end
    with_modified_env(ANTHROPIC_API_KEY: 'sk-test') { described_class.new(message).perform }
    expect(anexos).to eq([true, false])
    attrs = lead.reload.custom_attributes
    expect(attrs['doc_status']).to be_blank
    expect(attrs.dig('doc_sugestao', 'item_id')).to eq(rg.id)
  end

  it 'sem chave da Anthropic, segue o copiloto sem anexo' do
    resposta = Ramon::LlmClient::Result.new(content: %({"item_id": #{rg.id}}), input_tokens: 1, output_tokens: 1)
    allow(Ramon::LlmClient).to receive(:complete).and_return(resposta)
    with_modified_env(ANTHROPIC_API_KEY: nil) { described_class.new(message).perform }
    expect(Ramon::LlmClient).to have_received(:complete).with(hash_including(anexo: nil))
  end

  it 'nao grava com item fora do checklist' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: '{"item_id": 999999}', input_tokens: 1, output_tokens: 1))
    described_class.new(message).perform
    expect(lead.reload.custom_attributes['doc_sugestao']).to be_nil
  end

  it 'nao chama o LLM quando o lead nao tem checklist pendente' do
    rg.destroy!
    expect(Ramon::LlmClient).not_to receive(:complete)
    described_class.new(message).perform
  end

  it 'nao chama o LLM quando a mensagem nao tem anexo de imagem/arquivo' do
    plain = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')
    expect(Ramon::LlmClient).not_to receive(:complete)
    described_class.new(plain).perform
  end

  # Etapa Documentos (spec §5): lá a IA marca direto, mesmo com o lead ganho; CNIS só o completo.
  context 'with o lead na etapa Documentos' do
    let(:documentos) { Ramon::EtapasPosVenda.criar!(account).first }

    before { lead.update_columns(lead_stage_id: documentos.id, won_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations

    def perform_com(item_json, chave: 'on')
      resposta = Ramon::LlmClient::Result.new(content: item_json, input_tokens: 1, output_tokens: 1)
      allow(Ramon::LlmClient).to receive(:complete).and_return(resposta)
      with_modified_env(ANTHROPIC_API_KEY: 'sk-test', RAMON_ETAPA_DOCUMENTOS: chave) { described_class.new(message).perform }
      lead.reload.custom_attributes
    end

    it 'marca recebido e vincula o anexo', :aggregate_failures do
      attrs = perform_com(%({"item_id": #{rg.id}}))
      expect(attrs.dig('doc_status', rg.id.to_s)).to eq('recebido')
      expect(attrs.dig('doc_anexos', rg.id.to_s)).to eq(message.attachments.first.id)
      expect(attrs['doc_sugestao']).to be_nil
    end

    it 'avisa o SDR para verificar; o push leva só a tese, nunca o nome', :aggregate_failures do
      sdr = create(:user, account: account, role: :agent, auto_offline: false)
      lead.update_columns(sdr_id: sdr.id, name: 'Fulano de Tal') # rubocop:disable Rails/SkipsModelValidations
      allow(Ramon::NtfyPushJob).to receive(:perform_later)

      perform_com(%({"item_id": #{rg.id}}))

      avisos = Notification.where(primary_actor: lead, notification_type: 'ramon_fluxo_aviso')
      expect(avisos.pluck(:user_id)).to eq([sdr.id])
      expect(avisos.first.meta['label']).to eq('IA marcou RG de Fulano de Tal: verificar')
      expect(Ramon::NtfyPushJob).to have_received(:perform_later)
        .with(lead.id, title: "IA marcou documento (#{thesis.name})", body: satisfy { |corpo| corpo.exclude?('Fulano') })
    end

    it 'chave desligada: só sugere, como em qualquer lead ganho', :aggregate_failures do
      attrs = perform_com(%({"item_id": #{rg.id}}), chave: nil)
      expect(attrs['doc_status']).to be_blank
      expect(attrs.dig('doc_sugestao', 'item_id')).to eq(rg.id)
    end

    it 'CNIS resumido: não marca e grava o alerta para o agente pedir o completo', :aggregate_failures do
      cnis = create(:thesis_item, thesis: thesis, section: 'documento', title: 'CNIS completo')
      attrs = perform_com(%({"item_id": #{cnis.id}, "cnis_resumido": true}))
      expect(attrs['doc_status']).to be_blank
      expect(attrs.dig('doc_alertas', 'cnis_resumido')).to be_present
      expect(described_class.alertas(lead.reload)).to contain_exactly(a_string_including('remunerações'))
    end

    it 'cnis_resumido em item que não é CNIS é ignorado: marca normalmente' do
      attrs = perform_com(%({"item_id": #{rg.id}, "cnis_resumido": true}))
      expect(attrs.dig('doc_status', rg.id.to_s)).to eq('recebido')
    end

    it 'CNIS completo chegou depois do resumido: o alerta some' do
      cnis = create(:thesis_item, thesis: thesis, section: 'documento', title: 'CNIS completo')
      perform_com(%({"item_id": #{cnis.id}, "cnis_resumido": true}))
      perform_com(%({"item_id": #{cnis.id}}))
      expect(described_class.alertas(lead.reload)).to be_empty
    end
  end

  it 'fora da etapa Documentos, mesmo com a chave ligada, o CNIS segue como hoje: sem pergunta do resumido, marca', :aggregate_failures do
    cnis = create(:thesis_item, thesis: thesis, section: 'documento', title: 'CNIS completo')
    resposta = Ramon::LlmClient::Result.new(content: %({"item_id": #{cnis.id}, "cnis_resumido": true}), input_tokens: 1, output_tokens: 1)
    allow(Ramon::LlmClient).to receive(:complete).and_return(resposta)
    with_modified_env(ANTHROPIC_API_KEY: 'sk-test', RAMON_ETAPA_DOCUMENTOS: 'on') { described_class.new(message).perform }

    expect(Ramon::LlmClient).to have_received(:complete).with(hash_including(system: described_class::SYSTEM_PROMPT))
    expect(lead.reload.custom_attributes.dig('doc_status', cnis.id.to_s)).to eq('recebido')
    expect(lead.custom_attributes['doc_alertas']).to be_nil
  end

  context 'when the item is already marked as received' do
    it 'does not ask the LLM' do
      lead.update!(custom_attributes: { 'doc_status' => { rg.id.to_s => 'recebido' } })
      expect(Ramon::LlmClient).not_to receive(:complete)
      described_class.new(message).perform
    end
  end
end

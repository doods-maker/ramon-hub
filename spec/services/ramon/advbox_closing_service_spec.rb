require 'rails_helper'

RSpec.describe Ramon::AdvboxClosingService do
  let(:account) { create(:account) }
  let(:thesis) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
  let(:contact) do
    create(:contact, account: account, name: 'João da Silva', phone_number: '+5548999990000',
                     cpf: '529.982.247-25')
  end
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:won_stage) { account.lead_stages.find_by!(is_won: true) }
  let(:lead) do
    # etapa ganha → track_stage_cycle preenche won_at sozinho
    create(:lead, account: account, name: 'João da Silva', thesis: thesis, contact: contact,
                  conversation: conversation, source: 'meta-ads', value: 15_000,
                  lead_stage: won_stage, custom_attributes: { 'foo' => 'bar' })
  end

  def stub_create(path, key, id)
    stub_request(:post, "https://app.advbox.com.br/api/v1/#{path}")
      .to_return(status: 201, body: { 'success' => true, key => id }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  around do |example|
    with_modified_env(ADVBOX_API_TOKEN: 'tok', FRONTEND_URL: 'https://chat.example.com') { example.run }
  end

  it 'cria cliente, caso e tarefa e grava os ids no lead' do
    customers = stub_create('customers', 'customers_id', 111)
    lawsuits = stub_create('lawsuits', 'lawsuits_id', 222)
    posts = stub_create('posts', 'posts_id', 333)

    described_class.new(lead).perform

    advbox = lead.reload.custom_attributes['advbox']
    expect(advbox).to include('customers_id' => 111, 'lawsuits_id' => 222, 'posts_id' => 333)
    expect(lead.custom_attributes['foo']).to eq('bar')
    expect(customers).to have_been_requested
    expect(lawsuits).to have_been_requested
    expect(posts).to have_been_requested
  end

  it 'monta o caso com os ids escolhidos (responsável, fase, tipo pela tese) e o link da ficha' do
    stub_create('customers', 'customers_id', 111)
    stub_create('posts', 'posts_id', 333)
    lawsuits = stub_request(:post, 'https://app.advbox.com.br/api/v1/lawsuits')
               .with do |req|
                 body = JSON.parse(req.body)
                 body['users_id'] == 266_778 && body['stages_id'] == 3_736_299 &&
                   body['type_lawsuits_id'] == 2_408_556 && body['customers_id'] == [111] &&
                   body['notes'].include?("https://chat.example.com/app/accounts/#{account.id}/ramon/lead/#{lead.id}/dossie")
               end
               .to_return(status: 201, body: { 'success' => true, 'lawsuits_id' => 222 }.to_json,
                          headers: { 'Content-Type' => 'application/json' })

    described_class.new(lead).perform
    expect(lawsuits).to have_been_requested
  end

  it 'reaproveita o cliente existente quando o CPF já está no AdvBox (422 duplicado)' do
    stub_request(:post, 'https://app.advbox.com.br/api/v1/customers')
      .to_return(status: 422,
                 body: { 'message' => 'The given data was invalid.',
                         'errors' => { 'duplicate' => ['Client with this name already exists.'] } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    busca = stub_request(:get, 'https://app.advbox.com.br/api/v1/customers')
            .with(query: { 'identification' => '52998224725' })
            .to_return(status: 200, body: { 'data' => [{ 'id' => 999 }] }.to_json,
                       headers: { 'Content-Type' => 'application/json' })
    stub_create('lawsuits', 'lawsuits_id', 222)
    stub_create('posts', 'posts_id', 333)

    described_class.new(lead).perform

    expect(busca).to have_been_requested
    expect(lead.reload.custom_attributes.dig('advbox', 'customers_id')).to eq(999)
  end

  it 'não refaz nada quando o lead já está sincronizado (idempotente)' do
    lead.update!(custom_attributes: { 'advbox' => { 'lawsuits_id' => 222,
                                                    'sincronizado_em' => '2026-07-15T10:00:00-03:00' } })
    described_class.new(lead).perform
    expect(WebMock).not_to have_requested(:post, /app\.advbox\.com\.br/)
  end

  it 'retoma do passo que faltou sem recriar cliente/caso (retry após falha parcial)' do
    lead.update!(custom_attributes: { 'advbox' => { 'customers_id' => 111, 'lawsuits_id' => 222 } })
    posts = stub_create('posts', 'posts_id', 333)

    described_class.new(lead).perform

    expect(posts).to have_been_requested
    expect(WebMock).not_to have_requested(:post, %r{app\.advbox\.com\.br/api/v1/(customers|lawsuits)})
    advbox = lead.reload.custom_attributes['advbox']
    expect(advbox).to include('customers_id' => 111, 'lawsuits_id' => 222, 'posts_id' => 333)
    expect(advbox['sincronizado_em']).to be_present
  end

  it 'persiste o caso já criado quando a tarefa falha com 5xx (retry não duplica o caso)' do
    stub_create('customers', 'customers_id', 111)
    stub_create('lawsuits', 'lawsuits_id', 222)
    stub_request(:post, 'https://app.advbox.com.br/api/v1/posts').to_return(status: 502)

    expect { described_class.new(lead).perform }.to raise_error(Ramon::AdvboxClient::UnavailableError)

    advbox = lead.reload.custom_attributes['advbox']
    expect(advbox).to include('customers_id' => 111, 'lawsuits_id' => 222)
    expect(advbox['sincronizado_em']).to be_blank
  end

  it 'repropaga UnavailableError (5xx) para o retry do job' do
    stub_request(:post, 'https://app.advbox.com.br/api/v1/customers').to_return(status: 502)
    expect { described_class.new(lead).perform }.to raise_error(Ramon::AdvboxClient::UnavailableError)
  end

  it 'grava o erro no lead em falha de validação (4xx), sem levantar' do
    stub_create('customers', 'customers_id', 111)
    stub_request(:post, 'https://app.advbox.com.br/api/v1/lawsuits')
      .to_return(status: 422, body: { 'message' => 'The given data was invalid.' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    described_class.new(lead).perform

    expect(lead.reload.custom_attributes.dig('advbox', 'erro')).to be_present
  end

  describe 'Etapa Documentos (chave ligada)' do
    let(:etapas) { Ramon::EtapasPosVenda.criar!(account) }

    around { |example| with_modified_env(RAMON_ETAPA_DOCUMENTOS: 'on') { example.run } }

    # Checklist completo de verdade: o merge_advbox regrava o lead e o carimbo é recalculado do doc_status.
    def completo_no_juridico(custom_attributes = {})
      create(:thesis_item, thesis: thesis, section: 'documento', title: 'RG')
      status = thesis.thesis_items.where(section: 'documento').to_h { |item| [item.id.to_s, 'recebido'] }
      lead.update_columns(lead_stage_id: etapas.last.id, docs_completos_em: Time.current, # rubocop:disable Rails/SkipsModelValidations
                          custom_attributes: custom_attributes.merge('doc_status' => status))
    end

    def posts_do_tipo(tipo) = a_request(:post, 'https://app.advbox.com.br/api/v1/posts').with { |req| JSON.parse(req.body)['tasks_id'] == tipo }

    # Spec §9 (07/11): o 1º contato de quem vai a Documentos é do agente; a única tarefa do caso é a ANÁLISE DO CASO, no completo.
    it 'lead que vai a Documentos: cliente e caso, sem a tarefa 1º CONTATO COM O LEAD', :aggregate_failures do
      lead.update_columns(lead_stage_id: etapas.first.id) # rubocop:disable Rails/SkipsModelValidations
      stub_create('customers', 'customers_id', 111)
      stub_create('lawsuits', 'lawsuits_id', 222)

      described_class.new(lead.reload).perform

      expect(WebMock).not_to have_requested(:post, 'https://app.advbox.com.br/api/v1/posts')
      advbox = lead.reload.custom_attributes['advbox']
      expect(advbox).to include('customers_id' => 111, 'lawsuits_id' => 222)
      expect(advbox['sincronizado_em']).to be_present
      expect(advbox).not_to have_key('posts_id')
    end

    it 'lead que vai a Fechado (tese sem Documentos): como hoje, com a tarefa 1º CONTATO' do
      lead # em Fechado, antes de as etapas novas existirem
      etapas
      stub_create('customers', 'customers_id', 111)
      stub_create('lawsuits', 'lawsuits_id', 222)
      stub_create('posts', 'posts_id', 333)

      described_class.new(lead).perform

      expect(posts_do_tipo('8745394')).to have_been_made.once
    end

    # Review Focus 2: o checklist completou antes de o caso existir no ADVBOX; a ANÁLISE DO CASO sai quando ele nasce.
    it 'lead que já passou ao Jurídico: cria a ANÁLISE DO CASO assim que o caso nasce', :aggregate_failures do
      completo_no_juridico
      stub_create('customers', 'customers_id', 111)
      stub_create('lawsuits', 'lawsuits_id', 222)
      stub_create('posts', 'posts_id', 444)

      described_class.new(lead.reload).perform

      expect(posts_do_tipo('8745386')).to have_been_made.once
      expect(posts_do_tipo('8745394')).not_to have_been_made
      expect(lead.reload.custom_attributes.dig('advbox', 'analise_posts_id')).to eq(444)
    end

    # Review do PR 6, item 3: arrastado à mão para Jurídico com o checklist incompleto não ganha a tarefa.
    it 'lead no Jurídico com o checklist incompleto: sem ANÁLISE DO CASO' do
      lead.update_columns(lead_stage_id: etapas.last.id, docs_completos_em: nil) # rubocop:disable Rails/SkipsModelValidations
      stub_create('customers', 'customers_id', 111)
      stub_create('lawsuits', 'lawsuits_id', 222)

      described_class.new(lead.reload).perform

      expect(WebMock).not_to have_requested(:post, 'https://app.advbox.com.br/api/v1/posts')
    end

    it 'o retry do job (ADVBOX fora do ar na ANÁLISE DO CASO) a cria, com o caso já sincronizado' do
      completo_no_juridico('advbox' => { 'lawsuits_id' => 222, 'sincronizado_em' => 1.minute.ago.iso8601 })
      stub_create('posts', 'posts_id', 444)

      described_class.new(lead.reload).perform

      expect(posts_do_tipo('8745386')).to have_been_made.once
    end
  end

  # Review do PR 6, item 7: a ANÁLISE DO CASO que falha não vira erro de abertura do caso (advbox.erro).
  it 'falha ao retomar a ANÁLISE DO CASO não é gravada como erro do caso; fica no histórico', :aggregate_failures do
    lead.update!(custom_attributes: { 'advbox' => { 'lawsuits_id' => 222, 'sincronizado_em' => 1.minute.ago.iso8601 } })
    allow(Ramon::Documentos::Passagem).to receive(:retomar).and_raise(ActiveRecord::StatementInvalid, 'deu ruim')

    expect { described_class.new(lead).perform }.not_to raise_error

    expect(lead.reload.custom_attributes['advbox']).not_to have_key('erro')
    expect(lead.lead_activities.where(kind: 'documentos').pluck(:to_value)).to include(a_string_including('ANÁLISE DO CASO'))
  end

  it 'ADVBOX fora do ar ao retomar a ANÁLISE DO CASO: sobe para o retry do job, sem erro gravado' do
    lead.update!(custom_attributes: { 'advbox' => { 'lawsuits_id' => 222, 'sincronizado_em' => 1.minute.ago.iso8601 } })
    allow(Ramon::Documentos::Passagem).to receive(:retomar).and_raise(Ramon::AdvboxClient::UnavailableError)

    expect { described_class.new(lead).perform }.to raise_error(Ramon::AdvboxClient::UnavailableError)
    expect(lead.reload.custom_attributes['advbox']).not_to have_key('erro')
  end

  # Review do PR 6, item 1: a ANÁLISE DO CASO gravada (jsonb_set) entre o reload e o update! do merge_advbox sobrevive.
  it 'a marca da ANÁLISE DO CASO gravada no meio do merge_advbox sobrevive' do
    stub_create('customers', 'customers_id', 111)
    stub_create('lawsuits', 'lawsuits_id', 222)
    stub_create('posts', 'posts_id', 333)
    allow(lead).to receive(:reload).and_wrap_original do |original, *args|
      original.call(*args).tap do
        Lead.where(id: lead.id).update_all([Ramon::AdvboxDocsTaskService::GRAVAR_ANALISE, '444']) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    described_class.new(lead).perform

    expect(Lead.find(lead.id).custom_attributes['advbox']).to include('analise_posts_id' => 444, 'posts_id' => 333)
  end

  it 'não faz nada em lead que não é ganho' do
    aberto = create(:lead, account: account)
    described_class.new(aberto).perform
    expect(WebMock).not_to have_requested(:post, /app\.advbox\.com\.br/)
  end
end

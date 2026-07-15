require 'rails_helper'

RSpec.describe Ramon::AdvboxClosingService do
  let(:account) { create(:account) }
  let(:thesis) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
  let(:contact) do
    create(:contact, account: account, name: 'João da Silva', phone_number: '+5548999990000',
                     cpf: '123.456.789-00')
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

  it 'monta o caso com os ids escolhidos (responsável, fase, tipo pela tese) e o link da conversa' do
    stub_create('customers', 'customers_id', 111)
    stub_create('posts', 'posts_id', 333)
    lawsuits = stub_request(:post, 'https://app.advbox.com.br/api/v1/lawsuits')
               .with do |req|
                 body = JSON.parse(req.body)
                 body['users_id'] == 266_778 && body['stages_id'] == 3_736_299 &&
                   body['type_lawsuits_id'] == 2_408_556 && body['customers_id'] == [111] &&
                   body['notes'].include?("/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
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
            .with(query: { 'identification' => '12345678900' })
            .to_return(status: 200, body: { 'data' => [{ 'id' => 999 }] }.to_json,
                       headers: { 'Content-Type' => 'application/json' })
    stub_create('lawsuits', 'lawsuits_id', 222)
    stub_create('posts', 'posts_id', 333)

    described_class.new(lead).perform

    expect(busca).to have_been_requested
    expect(lead.reload.custom_attributes.dig('advbox', 'customers_id')).to eq(999)
  end

  it 'não refaz nada quando o lead já está sincronizado (idempotente)' do
    lead.update!(custom_attributes: { 'advbox' => { 'lawsuits_id' => 222 } })
    described_class.new(lead).perform
    expect(WebMock).not_to have_requested(:post, %r{app\.advbox\.com\.br})
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

  it 'não faz nada em lead que não é ganho' do
    aberto = create(:lead, account: account)
    described_class.new(aberto).perform
    expect(WebMock).not_to have_requested(:post, %r{app\.advbox\.com\.br})
  end
end

require 'rails_helper'

RSpec.describe Ramon::ZapsignContractService do
  let(:account) { create(:account) }
  let(:thesis) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
  let(:contact) do
    create(:contact, account: account, name: 'João da Silva', phone_number: '+5548999990000',
                     email: 'joao@example.com', cpf: '529.982.247-25')
  end
  let(:lead) do
    create(:lead, account: account, name: 'João da Silva', thesis: thesis, contact: contact,
                  custom_attributes: {
                    'colheita' => { 'dados' => { 'cliente' => {
                      'estado_civil' => 'casado', 'profissao' => 'montador industrial',
                      'endereco' => 'Rua das Flores, 100, Centro, Tubarão/SC'
                    } } }
                  })
  end

  around do |example|
    with_modified_env(ZAPSIGN_API_TOKEN: 'tok') { example.run }
  end

  before { allow(Ramon::ZapsignClient).to receive(:templates).and_return([{ 'token' => 'abc', 'name' => 'Modelo X' }]) }

  def zapsign_response
    { 'token' => 'doc-123',
      'signers' => [{ 'sign_url' => 'https://app.zapsign.com.br/verificar/abc' }] }.to_json
  end

  it 'cria o doc do modelo com as variáveis preenchidas e grava o link no lead' do
    stub = stub_request(:post, 'https://api.zapsign.com.br/api/v1/models/create-doc/')
           .with do |req|
             body = JSON.parse(req.body)
             de_para = body['data'].to_h { |i| [i['de'], i['para']] }
             body['template_id'] == described_class::TEMPLATE_ID &&
               body['send_automatic_whatsapp'] == false &&
               de_para['{{nome}}'] == 'João da Silva' &&
               de_para['{{CPF}}'] == '529.982.247-25' &&
               de_para['{{telefone}}'] == '48999990000' &&
               de_para['{{estado civil}}'] == 'casado' &&
               de_para['{{rua}}'] == 'Rua das Flores, 100, Centro, Tubarão/SC'
           end
           .to_return(status: 200, body: zapsign_response, headers: { 'Content-Type' => 'application/json' })

    result = described_class.new(lead).perform

    expect(stub).to have_been_requested
    expect(result['sign_url']).to eq('https://app.zapsign.com.br/verificar/abc')
    zapsign = lead.reload.custom_attributes['zapsign']
    expect(zapsign['doc_token']).to eq('doc-123')
    expect(zapsign['sign_url']).to eq('https://app.zapsign.com.br/verificar/abc')
  end

  it 'lista as variáveis que ficaram em branco (e manda linha em branco no doc)' do
    stub_request(:post, 'https://api.zapsign.com.br/api/v1/models/create-doc/')
      .to_return(status: 200, body: zapsign_response, headers: { 'Content-Type' => 'application/json' })

    result = described_class.new(lead).perform

    # endereço da colheita vai inteiro na rua; número/bairro/cidade/UF ficam em branco
    expect(result['faltando']).to include('{{número}}', '{{bairro}}', '{{cidade}}', '{{UF}}')
    expect(result['faltando']).not_to include('{{nome}}', '{{CPF}}', '{{data de hoje}}')
  end

  it 'usa o template_id informado e grava o nome' do
    enviado = nil
    allow(Ramon::ZapsignClient).to receive(:create_doc_from_template) do |body|
      enviado = body
      JSON.parse(zapsign_response)
    end

    described_class.new(lead, template_id: 'abc').perform

    expect(enviado[:template_id]).to eq 'abc'
    expect(lead.reload.custom_attributes.dig('zapsign', 'template_name')).to eq 'Modelo X'
  end

  it 'propaga UnavailableError em 5xx (sem gravar nada no lead)' do
    stub_request(:post, 'https://api.zapsign.com.br/api/v1/models/create-doc/').to_return(status: 502)
    expect { described_class.new(lead).perform }.to raise_error(Ramon::ZapsignClient::UnavailableError)
    expect(lead.reload.custom_attributes).not_to have_key('zapsign')
  end

  describe 'dados do contrato no contato' do
    before do
      contact.update!(additional_attributes: { 'city' => 'Laguna', 'state' => 'SC' },
                      custom_attributes: {
                        'estado_civil' => 'solteiro', 'profissao' => 'soldador',
                        'endereco' => { 'cep' => '88701000', 'rua' => 'Rua Lauro Müller', 'numero' => '45',
                                        'complemento' => 'apto 2', 'bairro' => 'Centro', 'cidade' => 'Tubarão', 'uf' => 'SC' }
                      })
    end

    it 'prefere o contato à colheita e junta o complemento na rua' do
      enviado = nil
      allow(Ramon::ZapsignClient).to receive(:create_doc_from_template) do |body|
        enviado = body[:data].to_h { |i| [i[:de], i[:para]] }
        JSON.parse(zapsign_response)
      end

      result = described_class.new(lead).perform

      expect(enviado).to include('{{estado civil}}' => 'solteiro', '{{profissão}}' => 'soldador',
                                 '{{rua}}' => 'Rua Lauro Müller, apto 2', '{{número}}' => '45',
                                 '{{bairro}}' => 'Centro', '{{cidade}}' => 'Tubarão', '{{UF}}' => 'SC')
      expect(result['faltando']).to be_empty
    end

    it 'preview lista o que falta sem chamar o ZapSign e devolve os dados do formulário' do
      contact.update!(custom_attributes: { 'endereco' => { 'rua' => 'Rua A', 'cidade' => 'Tubarão', 'uf' => 'SC' } })

      preview = described_class.new(lead.reload).preview

      expect(preview['faltando']).to contain_exactly('{{número}}', '{{bairro}}')
      expect(preview['dados']).to include('rua' => 'Rua A', 'cidade' => 'Tubarão', 'estado_civil' => 'casado',
                                          'profissao' => 'montador industrial', 'email' => 'joao@example.com')
      expect(a_request(:any, /zapsign/)).not_to have_been_made
    end
  end

  it 'sem endereço no contato cai na colheita (rua inteira) e na cidade do contato' do
    contact.update!(additional_attributes: { 'city' => 'Laguna' })

    preview = described_class.new(lead.reload).preview

    expect(preview['dados']).to include('rua' => 'Rua das Flores, 100, Centro, Tubarão/SC', 'cidade' => 'Laguna', 'uf' => 'SC')
    expect(preview['faltando']).to contain_exactly('{{número}}', '{{bairro}}')
  end

  describe 'gerar de novo' do
    let(:refuse_url) { 'https://api.zapsign.com.br/api/v1/refuse/' }
    let(:create_url) { 'https://api.zapsign.com.br/api/v1/models/create-doc/' }
    let(:conflito) { 'Ramon::ZapsignContractService::ConflictError' }

    before do
      lead.update!(custom_attributes: lead.custom_attributes.merge('zapsign' => { 'doc_token' => 'old', 'sign_url' => 'https://velho' }))
    end

    it 'sem confirmação não cria um 2º contrato' do
      expect { described_class.new(lead).perform }.to(raise_error { |e| expect(e.class.name).to eq(conflito) })
      expect(a_request(:any, /zapsign/)).not_to have_been_made
    end

    it 'cancela o anterior no ZapSign e só depois cria o novo' do
      stub_request(:post, refuse_url).with(body: hash_including('doc_token' => 'old', 'notify_signer' => false))
                                     .to_return(status: 200, body: { message: 'ok' }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, create_url).to_return(status: 200, body: zapsign_response, headers: { 'Content-Type' => 'application/json' })
      expect(Ramon::ZapsignClient).to receive(:refuse_doc).with('old', anything).ordered.and_call_original
      expect(Ramon::ZapsignClient).to receive(:create_doc_from_template).ordered.and_call_original

      result = described_class.new(lead).perform(regenerar: true)

      expect(result['doc_token']).to eq('doc-123')
      expect(lead.reload.custom_attributes.dig('zapsign', 'doc_token')).to eq('doc-123')
    end

    it 'aborta sem criar quando o cancelamento falha' do
      stub_request(:post, refuse_url).to_return(status: 403, body: { error: 'refuse_not_allowed' }.to_json,
                                                headers: { 'Content-Type' => 'application/json' })
      create = stub_request(:post, create_url)

      expect { described_class.new(lead).perform(regenerar: true) }.to raise_error(Ramon::ZapsignClient::RequestError)
      expect(create).not_to have_been_requested
      expect(lead.reload.custom_attributes.dig('zapsign', 'doc_token')).to eq('old')
    end

    it 'não troca contrato que o ZapSign diz já assinado' do
      stub_request(:post, refuse_url).to_return(status: 403, body: { error: 'document_already_signed' }.to_json,
                                                headers: { 'Content-Type' => 'application/json' })
      create = stub_request(:post, create_url)

      expect { described_class.new(lead).perform(regenerar: true) }.to(raise_error { |e| expect(e.class.name).to eq(conflito) })
      expect(create).not_to have_been_requested
    end

    it 'contrato marcado assinado nem chama o ZapSign' do
      lead.update!(custom_attributes: lead.custom_attributes.deep_merge('zapsign' => { 'status' => 'signed' }))
      expect { described_class.new(lead).perform(regenerar: true) }.to(raise_error { |e| expect(e.class.name).to eq(conflito) })
      expect(a_request(:any, /zapsign/)).not_to have_been_made
    end
  end
end

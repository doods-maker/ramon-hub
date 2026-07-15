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

  it 'propaga UnavailableError em 5xx (sem gravar nada no lead)' do
    stub_request(:post, 'https://api.zapsign.com.br/api/v1/models/create-doc/').to_return(status: 502)
    expect { described_class.new(lead).perform }.to raise_error(Ramon::ZapsignClient::UnavailableError)
    expect(lead.reload.custom_attributes).not_to have_key('zapsign')
  end
end

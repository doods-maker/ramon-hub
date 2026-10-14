require 'rails_helper'

RSpec.describe Ramon::ContratoAutomatico do
  let(:account) { create(:account) }
  let(:thesis) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
  let(:endereco) { { 'rua' => 'Rua das Flores', 'numero' => '100', 'bairro' => 'Centro', 'cidade' => 'Tubarão', 'uf' => 'SC' } }
  let(:contact) do
    create(:contact, account: account, name: 'João da Silva', phone_number: '+5548999990000', cpf: '529.982.247-25',
                     custom_attributes: { 'endereco' => endereco })
  end
  let(:conversation) do
    create(:conversation, account: account, contact: contact, status: :pending,
                          custom_attributes: { 'copiloto_modo' => 'piloto_ate_contrato' })
  end
  let(:lead) { create(:lead, account: account, thesis: thesis, contact: contact, conversation: conversation) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  around { |example| with_modified_env(ZAPSIGN_API_TOKEN: 'tok') { example.run } }

  before do
    thesis.update!(zapsign_template_id: 'modelo-aa')
    allow(Ramon::ZapsignClient).to receive(:templates).and_return([])
  end

  # Review Focus 4: o link volta para a IA mesmo com o modo já encerrado pelo callback, e sem handoff.
  it 'com cadastro completo: gera com o modelo da tese, devolve o link e encerra o modo sem handoff' do
    stub = stub_request(:post, 'https://api.zapsign.com.br/api/v1/models/create-doc/')
           .with { |req| JSON.parse(req.body)['template_id'] == 'modelo-aa' }
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: { 'token' => 'doc-1', 'signers' => [{ 'sign_url' => 'https://zap/assinar' }] }.to_json)

    expect(described_class.preparar(lead)).to eq(link: 'https://zap/assinar')
    expect(stub).to have_been_requested
    expect(conversation.reload.custom_attributes).to include('copiloto_modo' => 'rascunho',
                                                             'copiloto_limite' => include('limite' => 'contrato'))
    expect(conversation.status).to eq('pending')
  end

  it 'fora do modo não gera nada (segue a sugestão de sempre)' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_total' })
    expect(Ramon::ZapsignClient).not_to receive(:create_doc_from_template)
    expect(described_class.preparar(lead)).to be_nil
  end

  it 'cadastro incompleto: não gera, diz o que falta, encerra o modo e avisa' do
    contact.update!(cpf: nil, custom_attributes: {})
    expect(Ramon::ZapsignClient).not_to receive(:create_doc_from_template)

    expect(described_class.preparar(lead)).to eq(falta: %w[CPF rua número cidade])
    expect(conversation.reload.custom_attributes['copiloto_limite']).to include('limite' => 'contrato', 'motivo' => include('CPF'))
    expect(Notification.where(user: admin, primary_actor: lead, notification_type: 'ramon_fluxo_aviso').count).to eq(1)
  end

  it 'endereço só da colheita não basta; nome de uma palavra também não' do
    contact.update!(name: 'João', custom_attributes: {})
    lead.update!(custom_attributes: { 'colheita' => { 'dados' => { 'cliente' => { 'endereco' => 'Rua X, 10, Centro, Tubarão/SC' } } } })
    expect(described_class.preparar(lead)).to eq(falta: ['nome completo', 'número', 'cidade'])
  end

  it 'tese sem modelo de contrato não gera' do
    thesis.update!(zapsign_template_id: nil)
    expect(described_class.preparar(lead)).to eq(falta: ['modelo de contrato da tese'])
  end

  it 'ZapSign fora do ar: não quebra, encerra o modo com o motivo' do
    allow(Ramon::ZapsignClient).to receive(:create_doc_from_template).and_raise(Ramon::ZapsignClient::UnavailableError, 'fora do ar')
    expect(described_class.preparar(lead)[:falta].first).to include('fora do ar')
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('rascunho')
  end
end

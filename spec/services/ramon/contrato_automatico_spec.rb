require 'rails_helper'

# rubocop:disable RSpec/DescribedClass -- constante explícita (regra da F5: reload no CI)
RSpec.describe Ramon::ContratoAutomatico do
  let(:account) { create(:account) }
  let(:thesis) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
  let(:endereco) { { 'rua' => 'Rua das Flores', 'numero' => '100', 'bairro' => 'Centro', 'cidade' => 'Tubarão', 'uf' => 'SC' } }
  let(:contact) do
    create(:contact, account: account, name: 'João da Silva', phone_number: '+5548999990000', cpf: '529.982.247-25',
                     custom_attributes: { 'endereco' => endereco })
  end
  let(:conversation) { create(:conversation, account: account, contact: contact, status: :pending) }
  let(:lead) { create(:lead, account: account, thesis: thesis, contact: contact, conversation: conversation) }

  def perfil!(cfg) = account.update!(settings: { 'ia_atendimento' => { 'padrao' => cfg } })

  around { |example| with_modified_env(ZAPSIGN_API_TOKEN: 'tok') { example.run } }

  before do
    perfil!('base' => 'acelerada') # contrato_zapsign sozinha e a Etapa antes do Marcador
    thesis.update!(zapsign_template_id: 'modelo-aa')
    allow(Ramon::ZapsignClient).to receive(:templates).and_return([])
  end

  # Review Focus 4: o link volta para a IA, sem handoff.
  it 'com cadastro completo: gera com o modelo da tese e devolve o link, sem handoff' do
    stub = stub_request(:post, 'https://api.zapsign.com.br/api/v1/models/create-doc/')
           .with { |req| JSON.parse(req.body)['template_id'] == 'modelo-aa' }
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: { 'token' => 'doc-1', 'signers' => [{ 'sign_url' => 'https://zap/assinar' }] }.to_json)

    expect(Ramon::ContratoAutomatico.preparar(lead)).to eq(link: 'https://zap/assinar')
    expect(stub).to have_been_requested
    expect(conversation.reload.status).to eq('pending')
  end

  it 'sem contrato_zapsign direto não gera nada (segue a sugestão de sempre): rascunho, Marcador antes ou Pausa' do
    expect(Ramon::ZapsignClient).not_to receive(:create_doc_from_template)
    perfil!('base' => 'acelerada', 'permissoes' => { 'contrato_zapsign' => 'r' })
    expect(Ramon::ContratoAutomatico.preparar(lead)).to be_nil
    perfil!('base' => 'acelerada', 'marcador' => '_inicio')
    expect(Ramon::ContratoAutomatico.preparar(lead.reload)).to be_nil
    perfil!('base' => 'acelerada')
    conversation.update!(custom_attributes: { 'ia_pausa' => 'rascunho' })
    expect(Ramon::ContratoAutomatico.preparar(lead.reload)).to be_nil
  end

  # O aviso e a Pausa do "não saiu" são do Ramon::CopilotoLimite (fora deste spec).
  it 'cadastro incompleto: não gera e diz o que falta' do
    contact.update!(cpf: nil, custom_attributes: {})
    expect(Ramon::ZapsignClient).not_to receive(:create_doc_from_template)

    expect(Ramon::ContratoAutomatico.preparar(lead)).to eq(falta: %w[CPF rua número cidade])
  end

  it 'endereço só da colheita não basta; nome de uma palavra também não' do
    contact.update!(name: 'João', custom_attributes: {})
    lead.update!(custom_attributes: { 'colheita' => { 'dados' => { 'cliente' => { 'endereco' => 'Rua X, 10, Centro, Tubarão/SC' } } } })
    expect(Ramon::ContratoAutomatico.preparar(lead)).to eq(falta: ['nome completo', 'número', 'cidade'])
  end

  it 'tese sem modelo de contrato não gera' do
    thesis.update!(zapsign_template_id: nil)
    expect(Ramon::CopilotoLimite).to receive(:falhou).with(lead, 'modelo de contrato da tese')
    expect(Ramon::ContratoAutomatico.preparar(lead)).to eq(falta: ['modelo de contrato da tese'])
  end

  it 'ZapSign fora do ar: não quebra e devolve o motivo' do
    allow(Ramon::ZapsignClient).to receive(:create_doc_from_template).and_raise(Ramon::ZapsignClient::UnavailableError, 'fora do ar')
    expect(Ramon::ContratoAutomatico.preparar(lead)[:falta].first).to include('fora do ar')
  end
end
# rubocop:enable RSpec/DescribedClass

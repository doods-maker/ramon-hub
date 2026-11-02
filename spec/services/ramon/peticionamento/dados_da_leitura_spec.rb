require 'rails_helper'

RSpec.describe Ramon::Peticionamento::DadosDaLeitura do
  let(:account) { create(:account) }
  let(:time) { create(:team, account: account, name: Ramon::Papeis::JURIDICO) }
  let!(:ramon) { create(:user, name: 'Ramon Antonio', account: account) }
  let!(:brenda) { create(:user, name: 'Brenda Antunes', account: account) }
  let(:cpf_valido) { '12345678909' }

  before { create(:team_member, team: time, user: ramon) && create(:team_member, team: time, user: brenda) }

  def dados(lida) = described_class.call(account, lida)

  it 'responsável é o associado, não o Dr. Ramon' do
    lida = { 'assinantes' => [{ 'nome' => 'RAMON ANTONIO', 'oab' => 'SC 19.044' }, { 'nome' => 'Brenda Antunes', 'oab' => 'SC 54.338' }] }
    expect(dados(lida)[:responsavel]).to eq(brenda)
  end

  it 'Dr. Ramon sozinho é o responsável' do
    expect(dados('assinantes' => [{ 'nome' => 'Ramon Antonio', 'oab' => 'SC 19.044' }])[:responsavel]).to eq(ramon)
  end

  it 'sem usuário que sirva: sem responsável, e marca incerto' do
    r = dados('assinantes' => [{ 'nome' => 'Ana Souza', 'oab' => 'SC 1' }])
    expect(r[:responsavel]).to be_nil
    expect(r[:incertos]).to include('responsavel')
  end

  it 'nome com um só token só casa se for o único candidato' do
    create(:user, name: 'Brenda Lima', account: account).tap { |u| create(:team_member, team: time, user: u) }
    expect(dados('assinantes' => [{ 'nome' => 'Brenda Antunes Lima', 'oab' => 'SC 1' }])[:responsavel]).to be_nil
  end

  it 'cliente só pelo CPF, nunca pelo nome' do
    contato = create(:contact, account: account, name: 'João', cpf: cpf_valido)
    expect(dados('cpf' => cpf_valido)[:contact]).to eq(contato)
    expect(dados('nome_cliente' => 'João')[:contact]).to be_nil
  end

  it 'inicial vem do tipo' do
    expect(dados('tipo' => 'inicial')[:inicial]).to be(true)
    expect(dados('tipo' => 'intermediaria')[:inicial]).to be(false)
    expect(dados({})[:inicial]).to be_nil
  end
end

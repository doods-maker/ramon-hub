require 'rails_helper'

# A IA grava os dados do contrato no contato do lead (roteiro F5, item 16) — onde o painel e o ZapSign leem.
RSpec.describe 'Ramon::DadosContrato' do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'João', custom_attributes: { 'endereco' => { 'cep' => '88701000' } }) }
  let(:lead) { create(:lead, account: account, contact: contact) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  def gravar(dados) = Ramon::DadosContrato.gravar(lead, dados)

  # Review Focus 4: em partes, sobre o endereço do painel, e branco não apaga.
  it 'grava aos poucos no contato, onde o painel e o ZapSign leem, e diz o que falta' do
    res = gravar(nome: 'João da Silva', cpf: '529.982.247-25', rua: 'Rua das Flores', uf: 'sc')
    expect(res[:gravado]).to contain_exactly('nome', 'cpf', 'rua', 'uf')
    expect(res[:falta]).to eq(%w[número cidade])
    expect([contact.reload.name, contact.cpf]).to eq(['João da Silva', '52998224725'])
    expect(contact.custom_attributes['endereco']).to eq('cep' => '88701000', 'rua' => 'Rua das Flores', 'uf' => 'SC')

    res = gravar('numero' => '100', 'cidade' => 'Tubarão', 'estado_civil' => 'casado', 'profissao' => '')
    expect(res.slice(:falta, :complementar)).to eq(falta: [], complementar: %w[profissão bairro])
    expect(contact.reload.custom_attributes)
      .to include('estado_civil' => 'casado', 'endereco' => include('numero' => '100', 'rua' => 'Rua das Flores'))
  end

  it 'nome de uma palavra e CPF inválido não são gravados; o resto é' do
    res = gravar(nome: 'João', cpf: '111.111.111-11', cidade: 'Tubarão')
    expect(res[:recusado].keys).to eq(%w[nome cpf])
    expect(res[:gravado]).to eq(['cidade'])
    expect(contact.reload.cpf).to be_nil
    expect(Ramon::DadosContrato.texto(res)).to include('Nao gravei nome').and include('Ainda falta para o contrato: nome completo, CPF')
  end

  # Review Focus 3: CPF de outra pessoa nunca troca de dono nem sobrescreve.
  it 'CPF de outro contato da conta: não grava, avisa a equipe e manda a IA passar para humano' do
    create(:contact, account: account, cpf: '52998224725')
    res = gravar(cpf: '529.982.247-25', rua: 'Rua A')

    expect(res[:recusado]).to eq('cpf' => Ramon::DadosContrato::CPF_EM_USO)
    expect(contact.reload.cpf).to be_nil
    expect(contact.custom_attributes['endereco']).to include('rua' => 'Rua A')
    expect(Notification.where(user: admin, primary_actor: lead, notification_type: 'ramon_fluxo_aviso').count).to eq(1)
    expect(Ramon::DadosContrato.texto(res)).to include('passe para humano')
    expect(Ramon::DadosContrato.texto(res)).not_to include('529')
  end

  it 'lead sem contato: erro para a IA, nada gravado' do
    expect(Ramon::DadosContrato.gravar(create(:lead, account: account), cpf: '52998224725')).to include(:erro)
  end
end

require 'rails_helper'

# Testar com tese (F2) pelo mesmo caminho do lead real (F5, revisão integrada item 11).
RSpec.describe 'Ramon::Roteiro::Teste' do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:teste) { Ramon::Roteiro::Teste.de_params(account, { 'thesis_id' => thesis.id.to_s }) }

  def atual(teste) = Ramon::Roteiro::Teste.com_lead(account, teste) { |lead| Ramon::Roteiro.texto_atual(lead) }

  def registrar(teste, **resposta)
    Ramon::Roteiro::Teste.com_lead(account, teste) { |lead| Ramon::Roteiro.registrar(lead, **resposta) }
  end

  before do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'recebeu', position: 0, titulo: 'Recebeu',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'humano', 'motivo' => 'recebeu' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', position: 1, titulo: 'Renda', tipo_resposta: 'numero')
  end

  it 'roda o motor de verdade, devolve o estado no teste e não grava nada' do
    expect(atual(teste)).to include('Passo atual: Recebeu')

    res = registrar(teste, chave: 'recebeu', valor: 'nao')
    expect(Ramon::Roteiro.resumo(res)).to include('Passo atual: Renda')
    expect(teste['estado'].dig('respostas', 'recebeu', 'valor')).to eq('nao')
    expect(atual(teste)).to include('Passo atual: Renda')
    expect([Lead.count, LeadActivity.count, CopilotSuggestion.count]).to eq([0, 0, 0])
  end

  it 'equipe no teste: desfecho no estado e no painel, sem sino e sem handoff (não há conversa)' do
    create(:user, account: account, role: :administrator)
    expect(registrar(teste, chave: 'recebeu', valor: 'sim')[:handoff]).to be(false)
    expect(teste['estado']).to include('desfecho' => 'humano', 'motivo' => 'recebeu')

    resposta = Ramon::Roteiro::Teste.resposta(account, teste)
    expect(resposta).to include('thesis_id' => thesis.id, 'estado' => teste['estado'])
    expect(resposta['painel']).to include('desfecho' => 'humano')
    expect([Notification.count, Lead.count]).to eq([0, 0])
  end

  it 'valor inválido volta o erro para a IA e o estado do teste não muda' do
    expect(registrar(teste, chave: 'recebeu', valor: 'talvez')).to eq(erro: 'Responda sim ou nao.')
    expect(teste['estado']).to be_nil
  end

  it 'de_params: só tese da conta; sem tese = sem teste; estado vira Hash simples' do
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: create(:thesis, account: create(:account)).id })).to be_nil
    expect(Ramon::Roteiro::Teste.de_params(account, nil)).to be_nil
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: thesis.id, estado: { 'respostas' => {} } }))
      .to eq('thesis_id' => thesis.id, 'estado' => { 'respostas' => {} })
  end
end

require 'rails_helper'

RSpec.describe Ramon::Roteiro::Teste do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:teste) { described_class.de_params(account, { 'thesis_id' => thesis.id.to_s }) }

  before do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'recebeu', position: 0, titulo: 'Recebeu',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'humano', 'motivo' => 'recebeu' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', position: 1, titulo: 'Renda', tipo_resposta: 'numero')
  end

  it 'roda o motor de verdade, devolve o estado e não grava nada' do
    expect(described_class.atual(account, teste)).to include('Passo atual: Recebeu')

    texto, estado = described_class.registrar(account, teste, chave: 'recebeu', valor: 'nao')
    expect(texto).to include('Passo atual: Renda')
    expect(estado.dig('respostas', 'recebeu', 'valor')).to eq('nao')
    expect(described_class.atual(account, teste.merge('estado' => estado))).to include('Passo atual: Renda')
    expect([Lead.count, LeadActivity.count, CopilotSuggestion.count]).to eq([0, 0, 0])
  end

  it 'equipe no teste: desfecho no estado e no painel, sem sino' do
    create(:user, account: account, role: :administrator)
    _texto, estado = described_class.registrar(account, teste, chave: 'recebeu', valor: 'sim')
    expect(estado).to include('desfecho' => 'humano', 'motivo' => 'recebeu')
    resposta = described_class.resposta(account, teste.merge('estado' => estado))
    expect(resposta).to include('thesis_id' => thesis.id, 'estado' => estado)
    expect(resposta['painel']).to include('desfecho' => 'humano')
    expect([Notification.count, Lead.count]).to eq([0, 0])
  end

  it 'valor inválido volta o erro para a IA e o estado não muda' do
    texto, estado = described_class.registrar(account, teste, chave: 'recebeu', valor: 'talvez')
    expect(texto).to eq('Responda sim ou nao.')
    expect(estado).to be_nil
  end

  it 'de_params: só tese da conta; sem tese = sem teste; estado vira Hash simples' do
    expect(described_class.de_params(account, { thesis_id: create(:thesis, account: create(:account)).id })).to be_nil
    expect(described_class.de_params(account, nil)).to be_nil
    expect(described_class.de_params(account, { thesis_id: thesis.id, estado: { 'respostas' => {} } }))
      .to eq('thesis_id' => thesis.id, 'estado' => { 'respostas' => {} })
  end
end

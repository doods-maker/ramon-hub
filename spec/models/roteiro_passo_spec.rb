require 'rails_helper'

RSpec.describe RoteiroPasso do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }

  it 'recusa tipo, calculadora e saídas inválidos' do
    passo = build(:roteiro_passo, account: account, thesis: thesis, tipo_resposta: 'x', calculadora: 'nada',
                                  saidas: [{ 'id' => 'a', 'acao' => 'desqualificar' }, { 'acao' => 'pular' },
                                           { 'id' => 'b', 'acao' => 'ir_para' }])
    expect(passo).not_to be_valid
    expect(passo.errors[:tipo_resposta]).to be_present
    expect(passo.errors[:calculadora]).to be_present
    expect(passo.errors[:saidas].join(' ')).to include('motivo obrigatório').and include('ação inválida')
      .and include('falta o id').and include('falta o passo de destino')
  end

  it 'aceita passo válido e calculadora vazia vira nil' do
    passo = build(:roteiro_passo, account: account, thesis: thesis, calculadora: '',
                                  saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'humano', 'motivo' => 'x' }])
    expect(passo).to be_valid
    expect(passo.calculadora).to be_nil
  end

  it 'chave única por tese e, nos comuns, por conta' do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'sequela')
    expect(build(:roteiro_passo, account: account, thesis: thesis, chave: 'sequela')).not_to be_valid
    expect(build(:roteiro_passo, account: account, thesis: create(:thesis, account: account), chave: 'sequela')).to be_valid

    create(:roteiro_passo, account: account, thesis: nil, chave: 'nome')
    expect(build(:roteiro_passo, account: account, thesis: nil, chave: 'nome')).not_to be_valid
    expect(described_class.comuns.pluck(:chave)).to eq(['nome'])
  end

  it 'chave só com minúsculas, números e _' do
    expect(build(:roteiro_passo, account: account, thesis: thesis, chave: 'Tem Advogado')).not_to be_valid
  end

  it 'motivo de perda só do catálogo da conta (Sem viabilidade nasce com a conta)' do
    ok = { 'id' => 'a', 'acao' => 'desqualificar', 'motivo' => 'x', 'motivo_perda' => 'Sem viabilidade' }
    expect(build(:roteiro_passo, account: account, thesis: thesis, saidas: [ok])).to be_valid

    passo = build(:roteiro_passo, account: account, thesis: thesis, saidas: [ok.merge('motivo_perda' => 'Inventado')])
    expect(passo).not_to be_valid
    expect(passo.errors[:saidas].join).to include('fora do catálogo')
  end
end

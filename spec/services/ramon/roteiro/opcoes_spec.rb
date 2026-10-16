require 'rails_helper'

# rubocop:disable RSpec/DescribedClass -- constante explícita: no CI a recarga de código deixa o described_class velho
RSpec.describe Ramon::Roteiro::Opcoes do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account, opcoes_botoes: 'ligado') }
  let(:lead) { create(:lead, account: account, thesis: thesis) }

  def passo(**attrs)
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'situacao', position: 0, **attrs)
  end

  it 'sim/não vira 2 botões (ligado não marca grupo: o grupo é só do teste A/B)' do
    passo(tipo_resposta: 'sim_nao')

    expect(Ramon::Roteiro::Opcoes.itens(lead)).to eq([{ 'title' => 'Sim', 'value' => 'Sim' }, { 'title' => 'Não', 'value' => 'Não' }])
    expect(lead.reload.custom_attributes).not_to have_key('roteiro_opcoes')
  end

  it 'opção longa ganha título curto e a descrição inteira' do
    passo(tipo_resposta: 'escolha', opcoes: ['Doméstica, empregada de MEI ou intermitente', 'Não sabe'])

    longa, curta = Ramon::Roteiro::Opcoes.itens(lead)
    expect(longa['title'].size).to be <= 24
    expect(longa).to include('value' => 'Doméstica, empregada de MEI ou intermitente',
                             'description' => 'Doméstica, empregada de MEI ou intermitente')
    expect(curta).to eq('title' => 'Não sabe', 'value' => 'Não sabe')
  end

  it 'texto, data, número e escolha com mais de 10 opções seguem só em texto' do
    passo(tipo_resposta: 'escolha', opcoes: (1..11).map(&:to_s))
    expect(Ramon::Roteiro::Opcoes.itens(lead)).to be_nil
  end

  it 'quando a IA junta 2 perguntas (bloco), a mensagem vai só em texto' do
    passo(tipo_resposta: 'sim_nao')
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'funcao', position: 1, tipo_resposta: 'texto')

    expect(Ramon::Roteiro::Opcoes.itens(lead)).to be_nil
  end

  it 'o grupo do teste A/B fica no lead mesmo se a tese passar para ligado' do
    thesis.update!(opcoes_botoes: 'teste_ab')
    passo(tipo_resposta: 'sim_nao')
    impar = create_list(:lead, 2, account: account, thesis: thesis).find { |l| l.id.odd? }
    Ramon::Roteiro::Opcoes.itens(impar)
    thesis.update!(opcoes_botoes: 'ligado')

    expect(Ramon::Roteiro::Opcoes.itens(impar.reload)).to be_present
    expect(impar.reload.custom_attributes['roteiro_opcoes']).to eq('texto')
  end

  it 'tese desligada não manda botões' do
    thesis.update!(opcoes_botoes: 'desligado')
    passo(tipo_resposta: 'sim_nao')

    expect(Ramon::Roteiro::Opcoes.itens(lead)).to be_nil
  end

  it 'no teste A/B, lead de id par recebe botões e ímpar só texto' do
    thesis.update!(opcoes_botoes: 'teste_ab')
    passo(tipo_resposta: 'sim_nao')
    par, impar = create_list(:lead, 2, account: account, thesis: thesis).sort_by { |l| l.id % 2 }

    expect(Ramon::Roteiro::Opcoes.itens(par)).to be_present
    expect(Ramon::Roteiro::Opcoes.itens(impar)).to be_nil
    expect(impar.reload.custom_attributes['roteiro_opcoes']).to eq('texto')
  end
end
# rubocop:enable RSpec/DescribedClass

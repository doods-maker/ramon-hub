require 'rails_helper'

RSpec.describe Ramon::Roteiro do
  let(:account) { create(:account) }
  let(:acidente) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:lead) { create(:lead, account: account, conversation: conversation) }

  before do
    create(:user, account: account, role: :administrator)
    acidente.update!(palavras_chave: ['acidente de trabalho'])
    create(:roteiro_passo, account: account, thesis: nil, chave: 'assunto', position: 1, titulo: 'Assunto', tipo_resposta: 'texto')
    create(:roteiro_passo, account: account, thesis: nil, chave: 'tem_advogado', position: 2, titulo: 'Tem advogado')
    create(:roteiro_passo, account: account, thesis: acidente, chave: 'sequela', position: 1, titulo: 'Sequela')
  end

  it 'sem o passo assunto cadastrado, lead sem tese segue sem roteiro (como na F1)' do
    RoteiroPasso.find_by!(chave: 'assunto').destroy!
    expect(described_class.atual(lead)).to be_nil
  end

  it 'lead sem tese começa pelo assunto; com tese, o assunto some da lista' do
    expect(described_class.atual(lead)[:passo].chave).to eq('assunto')
    lead.update!(thesis: acidente)
    expect(described_class.passos(lead.reload).map(&:chave)).to eq(%w[tem_advogado sequela])
  end

  it 'resposta casa com a tese: o lead ganha a tese e o roteiro segue nos passos dela' do
    res = described_class.registrar(lead, chave: 'assunto', valor: 'sofri acidente de trabalho na obra')

    expect(lead.reload.thesis).to eq(acidente)
    expect(res[:proximo].chave).to eq('tem_advogado')
    expect(res[:estado]).to include('tese_id' => acidente.id)
    expect(res[:estado]['respostas']).to have_key('assunto')
    expect(described_class.atual(lead)[:passo].chave).to eq('tem_advogado')
  end

  it 'resposta sem tese vai para a equipe' do
    res = described_class.registrar(lead, chave: 'assunto', valor: 'pensao alimenticia')
    expect(res[:estado]).to include('desfecho' => 'humano', 'motivo' => 'assunto sem tese cadastrada')
    expect(lead.reload.thesis).to be_nil
  end

  it 'assunto sem valor (só saida_id) pede o texto e não manda para a equipe' do
    res = described_class.registrar(lead, chave: 'assunto', saida_id: 'qualquer')
    expect(res[:erro]).to include('assunto')
    expect(lead.reload.custom_attributes['roteiro']).to be_nil
  end

  it 'descrever do assunto não pede saida_id (passo de texto sem saídas)' do
    texto = described_class.descrever(*described_class.atual(lead).values_at(:passo, :estado))
    expect(texto).to include('Passo atual: Assunto').and include('texto livre')
    expect(texto).not_to include('saida_id')
  end

  it 'o painel do lead sem tese mostra o assunto como passo atual' do
    painel = Ramon::Roteiro::Painel.montar(lead)
    expect(painel['passos'].map { |p| p['chave'] }).to eq(%w[assunto tem_advogado])
    expect(painel['so_comuns']).to be(true)
    expect(painel['passos'].first['situacao']).to eq('atual')
  end
end

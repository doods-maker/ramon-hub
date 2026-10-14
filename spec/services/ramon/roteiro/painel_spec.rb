require 'rails_helper'

RSpec.describe Ramon::Roteiro::Painel do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: novo) }

  before do
    create(:roteiro_passo, account: account, thesis: nil, chave: 'tem_advogado', position: 0, titulo: 'Tem advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'recebeu', position: 1, titulo: 'Recebeu',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'ir_para', 'alvo' => 'renda' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'nascimento', position: 2, titulo: 'Nascimento',
                           tipo_resposta: 'data', calculadora: 'meses_ate_65', calculadora_campos: { 'nascimento' => 'nascimento' })
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', position: 3, titulo: 'Renda', tipo_resposta: 'numero')
  end

  def situacoes
    described_class.montar(lead.reload)['passos'].to_h { |linha| [linha['chave'], linha['situacao']] }
  end

  it 'lead sem tese = sem roteiro' do
    expect(described_class.montar(create(:lead, account: account, lead_stage: novo))).to be_nil
  end

  it 'comuns e tese na ordem, com o passo atual e o resto a perguntar' do
    painel = described_class.montar(lead)
    expect(painel['passos'].pluck('chave')).to eq(%w[tem_advogado recebeu nascimento renda])
    expect(painel['passos'].first).to include('situacao' => 'atual')
    expect(painel).to include('desfecho' => nil, 'so_comuns' => false, 'aguarda_equipe' => false)
  end

  it 'pulado pelo "vai para" fica como não perguntado' do
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(lead.reload, chave: 'recebeu', valor: 'sim')
    expect(situacoes).to eq('tem_advogado' => 'respondido', 'recebeu' => 'respondido', 'nascimento' => 'fora', 'renda' => 'atual')
  end

  it 'traz o valor e o resultado da calculadora' do
    Ramon::Roteiro.registrar(lead, chave: 'nascimento', valor: '13/10/1950')
    linha = described_class.montar(lead.reload)['passos'].find { |item| item['chave'] == 'nascimento' }
    expect(linha).to include('valor' => '1950-10-13', 'situacao' => 'respondido')
    expect(linha['calc']).to include('resultado' => 'ja_tem_65')
  end

  it 'desfecho com motivo, passo que decidiu, aguardando a equipe e o resto não perguntado' do
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim') # lead sem conversa: Perdido vira sugestão
    painel = described_class.montar(lead.reload)
    expect(painel).to include('desfecho' => 'desqualificado', 'motivo' => 'tem advogado', 'decisivo' => 'tem_advogado',
                              'aguarda_equipe' => true)
    expect(painel['passos'].pluck('situacao')).to eq(%w[respondido fora fora fora])
  end

  it 'lead já perdido não aguarda mais a equipe' do
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim')
    lead.reload.update!(lead_stage: account.lead_stages.find_by!(is_lost: true), lost_reason: 'Outro')
    expect(described_class.montar(lead.reload)).to include('aguarda_equipe' => false)
  end

  it 'tese sem passos próprios: só os comuns (so_comuns)' do
    outro = create(:lead, account: account, thesis: create(:thesis, account: account), lead_stage: novo)
    expect(described_class.montar(outro)).to include('so_comuns' => true)
  end

  it 'roteiro_versao do lead muda a cada registro' do
    expect(lead.roteiro_versao).to be_nil
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    primeira = lead.reload.roteiro_versao
    Ramon::Roteiro.registrar(lead, chave: 'recebeu', valor: 'nao')
    expect(primeira).to be_present
    expect(lead.reload.roteiro_versao).not_to eq(primeira)
    expect(lead.push_event_data[:roteiro_versao]).to eq(lead.roteiro_versao)
  end
end

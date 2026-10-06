require 'rails_helper'

RSpec.describe Ramon::Fluxos::Contexto do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria da Silva', phone_number: '+5548999990000') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:lead) { create(:lead, account: account, contact: contato, conversation: conversa) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  def execucao(alvo, vars = {})
    fluxo.execucoes.create!(account: account, alvo: alvo, contexto: { 'vars' => vars, 'gatilho' => { 'texto' => 'oi' } })
  end

  it 'monta os dados do lead e da conversa ligada' do
    dados = described_class.new(execucao(lead)).dados
    expect(dados).to include('nome' => 'Maria', 'nome_completo' => 'Maria da Silva', 'etapa' => lead.lead_stage.name,
                             'caixa_id' => conversa.inbox_id, 'texto' => 'oi')
  end

  it 'acha o lead a partir da conversa' do
    lead
    expect(described_class.new(execucao(conversa)).lead).to eq(lead)
  end

  it 'interpola variáveis e deixa desconhecida literal' do
    ctx = described_class.new(execucao(lead, { 'resposta_ia' => 'ok' }))
    expect(ctx.interpolar('Olá {nome}, {resposta_ia} {inventada}')).to eq('Olá Maria, ok {inventada}')
  end

  describe 'documentos do checklist' do
    let(:tese) { create(:thesis, account: account) }
    let!(:rg) { create(:thesis_item, thesis: tese, section: 'documento', title: 'RG', content: 'RG', position: 1) }

    before { create(:thesis_item, thesis: tese, section: 'documento', title: 'CNIS', content: 'CNIS', position: 2) }

    it 'diz se está completo e lista o que falta' do
      lead.update!(thesis: tese, custom_attributes: { 'doc_status' => { rg.id.to_s => 'recebido' } })
      expect(described_class.new(execucao(lead)).dados).to include('documentos_completos' => 'nao', 'documentos_faltantes' => 'CNIS')
    end

    it 'sugestão da IA não conta como recebido (só a confirmação da equipe)' do
      lead.update!(thesis: tese, custom_attributes: { 'doc_sugestao' => { 'item_id' => rg.id, 'resolvida' => false } })
      expect(described_class.new(execucao(lead)).dados).to include('documentos_completos' => 'nao', 'documentos_faltantes' => 'RG, CNIS')
    end
  end

  it 'sem checklist não diz que está completo' do
    expect(described_class.new(execucao(lead)).dados).to include('documentos_completos' => nil, 'documentos_faltantes' => '')
  end

  it 'campos preenchidos pelo fluxo viram variáveis, sem pisar nos do hub' do
    lead.update!(custom_attributes: { 'campos' => { 'beneficio' => 'BPC', 'nome' => 'Outro' } })
    expect(described_class.new(execucao(lead)).dados).to include('beneficio' => 'BPC', 'nome' => 'Maria')
  end

  it 'dados do gatilho viram variáveis' do
    e = fluxo.execucoes.create!(account: account, alvo: lead, contexto: { 'gatilho' => { 'quando' => 'quinta, 20/08 às 14:00', 'regra' => 'exito' } })
    expect(described_class.new(e).dados).to include('quando' => 'quinta, 20/08 às 14:00', 'regra' => 'exito', 'texto' => nil)
  end
end

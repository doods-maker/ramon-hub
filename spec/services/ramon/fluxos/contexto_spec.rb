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
end

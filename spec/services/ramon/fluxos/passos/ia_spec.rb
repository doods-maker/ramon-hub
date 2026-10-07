require 'rails_helper'

RSpec.describe Ramon::Fluxos::Passos::Ia do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria da Silva') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:lead) { create(:lead, account: account, contact: contato, conversation: conversa, name: 'Maria da Silva') }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  def ctx(ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: lead, ensaio: ensaio))
  end

  def llm(conteudo)
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(Ramon::LlmClient::Result.new(content: conteudo, input_tokens: 1, output_tokens: 1))
  end

  it 'perguntar_ia sai por sim/não, a justificativa vira {resposta_ia} e o nome não sai do hub' do
    llm(%(```json\n{"resposta": "Sim", "justificativa": "[nome] já mandou o CNIS"}\n```))
    r = described_class.perguntar_ia({ 'pergunta' => 'A {nome} mandou o CNIS?' }, ctx)
    expect(r).to include(saida: 'sim', vars: { 'resposta_ia' => 'Maria já mandou o CNIS' })
    expect(Ramon::LlmClient).to have_received(:complete)
      .with(hash_including(user: satisfy { |u| u.include?('[nome]') && u.exclude?('Maria') }))
  end

  it 'perguntar_ia: resposta que não é sim sai por não' do
    llm('{"resposta": "talvez", "justificativa": "não dá pra saber"}')
    expect(described_class.perguntar_ia({ 'pergunta' => 'x' }, ctx)[:saida]).to eq('nao')
  end

  it 'rascunho_ia grava nota RASCUNHO com o texto da IA (nunca mensagem pública)' do
    llm('Oi [nome], tudo bem? Falta só o CNIS.')
    r = described_class.rascunho_ia({ 'instrucao' => 'Lembre dos documentos: {documentos_faltantes}' }, ctx)
    nota = conversa.messages.last
    expect(nota.private).to be(true)
    expect(nota.content).to eq("#{Ramon::RascunhoCarimbo::PREFIXO}\nOi Maria, tudo bem? Falta só o CNIS.")
    expect(r[:vars]).to eq('resposta_ia' => 'Oi Maria, tudo bem? Falta só o CNIS.')
  end

  it 'no ensaio, rascunho_ia só descreve (não chama a IA)' do
    allow(Ramon::LlmClient).to receive(:complete)
    expect(described_class.rascunho_ia({ 'instrucao' => 'x' }, ctx(ensaio: true))[:resumo]).to start_with('faria: ')
    expect(Ramon::LlmClient).not_to have_received(:complete)
  end

  it 'teto diário de IA dos fluxos: estourou, o passo falha na hora' do
    llm('{"resposta": "sim", "justificativa": "ok"}')
    c = ctx # uma execução só: a 2ª ativa do mesmo fluxo/lead bateria no índice único
    with_modified_env(RAMON_FLUXO_IA_DIA: '1') do
      described_class.perguntar_ia({ 'pergunta' => 'x' }, c)
      expect { described_class.perguntar_ia({ 'pergunta' => 'x' }, c) }.to raise_error(Ramon::Fluxos::PassoImpossivel, /teto/)
    end
  end

  it 'rascunho_ia nas notas do lead, com título que aceita variável (a retomada da cadência)' do
    llm('Oi [nome], seguimos à disposição.')
    lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1 } })
    config = { 'instrucao' => 'retome', 'onde' => 'notas_do_lead', 'titulo' => 'retomada nº {tentativa}' }
    described_class.rascunho_ia(config, ctx)
    expect(lead.lead_notes.last.body).to eq("RASCUNHO (revisar antes de enviar) — retomada nº 2:\nOi Maria, seguimos à disposição.")
    expect(conversa.messages.where(private: true).count).to eq(0)
  end

  it 'rascunho_ia: IA fora do ar → o texto de reserva (como a cadência do código), sem nova tentativa' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError, 'timeout')
    r = described_class.rascunho_ia({ 'instrucao' => 'retome', 'reserva' => 'Oi {nome}, tudo bem?' }, ctx)
    expect(conversa.messages.last.content).to eq("#{Ramon::RascunhoCarimbo::PREFIXO}\nOi Maria, tudo bem?")
    expect(r[:saida]).to eq('s')
  end

  it 'rascunho_ia sem reserva: IA fora do ar sobe o erro (o executor tenta de novo em 1/5/15 min)' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError, 'timeout')
    expect { described_class.rascunho_ia({ 'instrucao' => 'retome' }, ctx) }.to raise_error(Ramon::LlmClient::TransientError)
  end

  it 'rodar_skill sem enterprise é impossível', unless: ChatwootApp.enterprise? do
    expect { described_class.rodar_skill({ 'assistente_id' => 1, 'skill_id' => 1 }, ctx) }
      .to raise_error(Ramon::Fluxos::PassoImpossivel, /enterprise/)
  end

  context 'with rodar_skill no enterprise', if: ChatwootApp.enterprise? do
    let(:assistente) { create(:captain_assistant, account: account) }
    let(:skill) { create(:captain_scenario, assistant: assistente, account: account, title: 'Resumo do caso') }
    let(:runner) { instance_double(Captain::Assistant::AgentRunnerService) }
    let(:config) { { 'assistente_id' => assistente.id, 'skill_id' => skill.id } }

    before { allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner) }

    it 'roda sem conversa no estado e o resultado vira nota + {resposta_ia}' do
      allow(runner).to receive(:generate_response).and_return('response' => '[nome] tem 20 anos de CNIS.')
      r = described_class.rodar_skill(config, ctx)
      expect(Captain::Assistant::AgentRunnerService).to have_received(:new).with(assistant: assistente, source: 'fluxo')
      expect(r[:vars]).to eq('resposta_ia' => 'Maria tem 20 anos de CNIS.')
      expect(conversa.messages.last).to have_attributes(private: true, content: "⚙ Skill Resumo do caso:\nMaria tem 20 anos de CNIS.")
    end

    it 'erro do runner vira erro do passo (o executor tenta de novo)' do
      allow(runner).to receive(:generate_response).and_return('response' => 'conversation_handoff', 'reasoning' => 'Error occurred: timeout')
      expect { described_class.rodar_skill(config, ctx) }.to raise_error(RuntimeError, /skill falhou/)
    end

    it 'skill desligada ou de outro assistente é impossível' do
      skill.update!(enabled: false)
      expect { described_class.rodar_skill(config, ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, /skill/)
    end
  end
end

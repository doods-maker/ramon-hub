require 'rails_helper'

RSpec.describe Ramon::Fluxos::Rotinas::Leads do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  def llm(conteudo) = Ramon::LlmClient::Result.new(content: conteudo, input_tokens: 1, output_tokens: 1)

  # Pelo passo de verdade (Passos::Rotina → registro Ramon::Fluxos::Rotinas → este módulo). Execução de verdade: 1 por exemplo.
  def rodar(rotina, mensagem: nil, ensaio: false, tentativas: 0)
    gatilho = mensagem ? { 'mensagem_id' => mensagem.id } : {}
    execucao = fluxo.execucoes.create!(account: account, alvo: conversa, ensaio: ensaio, tentativas: tentativas,
                                       contexto: { 'gatilho' => gatilho })
    Ramon::Fluxos::Passos::Rotina.rotina({ 'rotina' => rotina }, Ramon::Fluxos::Contexto.new(execucao))
  end

  it 'registra as 5 rotinas, de conversa' do
    %w[criar_lead origem_do_lead sugestao_documento coach_objecao agente_hub].each do |nome|
      expect(Ramon::Fluxos::Rotinas.alvo(nome)).to eq('conversa')
    end
  end

  describe 'criar_lead' do
    it 'ensaio só descreve; de verdade cria o lead na 1ª etapa (com balão: 1 por conversa nova)' do
      expect(rodar('criar_lead', ensaio: true)[:resumo])
        .to eq('faria: criar o lead na 1ª etapa do funil (ou ligar a conversa ao lead aberto do contato)')
      expect(account.leads.count).to eq(0)
      expect(rodar('criar_lead')).to eq(saida: 's', resumo: 'lead criado: Maria (Novo)')
      expect(account.leads.sole).to have_attributes(contact_id: contact.id, conversation_id: conversa.id)
    end

    it 'caixa sem "Criar lead": nada feito, sem balão' do
      inbox.update!(auto_create_lead: false)
      expect(rodar('criar_lead'))
        .to eq(saida: 's', resumo: 'a caixa não cria lead (ou a conversa não tem contato): nada feito', sem_balao: true)
      expect(account.leads.count).to eq(0)
    end
  end

  describe 'origem_do_lead' do
    let!(:lead) { create(:lead, account: account, contact: contact, conversation: conversa, channel: 'outro', source: nil) }

    it 'anúncio da Meta: grava origem, canal e o anúncio — o mesmo do código; sem balão' do
      msg = create(:message, account: account, conversation: conversa, message_type: :incoming, content: 'oi',
                             content_attributes: { referral: { 'source_id' => '12034', 'ctwa_clid' => 'c1' } })
      expect(rodar('origem_do_lead', ensaio: true)[:resumo]).to start_with('faria: anotar a origem')
      expect(rodar('origem_do_lead', mensagem: msg))
        .to eq(saida: 's', resumo: 'origem do lead: canal meta_ads, origem anuncio-meta: 12034', sem_balao: true)
      expect(lead.reload.custom_attributes['meta_referral']).to include('ctwa_clid' => 'c1')
    end

    it 'de verdade sem a mensagem do gatilho é passo impossível (falha na hora, sem nova tentativa)' do
      expect { rodar('origem_do_lead') }.to raise_error(Ramon::Fluxos::PassoImpossivel, /mensagem do gatilho/)
    end
  end

  describe 'sugestao_documento' do
    let(:thesis) { create(:thesis, account: account) }
    let!(:rg) { create(:thesis_item, thesis: thesis, section: 'documento', title: 'RG', content: 'RG') }
    let!(:lead) { create(:lead, account: account, contact: contact, conversation: conversa, thesis: thesis) }
    let(:anexo) { create(:message, :with_attachment, account: account, conversation: conversa, message_type: :incoming) }

    it 'ensaio não chama a IA; de verdade grava a sugestão e o gatilho Documento recebido continua nascendo' do
      allow(Ramon::LlmClient).to receive(:complete).and_return(llm(%({"item_id": #{rg.id}})))
      allow(Ramon::Fluxos::Disparo).to receive(:externo).and_call_original
      rodar('sugestao_documento', mensagem: anexo, ensaio: true)
      expect(Ramon::LlmClient).not_to have_received(:complete)
      expect(rodar('sugestao_documento', mensagem: anexo)[:resumo]).to eq('a IA sugeriu um documento do checklist (a equipe confirma no painel)')
      expect(lead.reload.custom_attributes.dig('doc_sugestao', 'item_id')).to eq(rg.id)
      expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('documento_recebido', lead, hash_including('documento' => 'RG'))
    end

    it 'IA fora do ar antes da última tentativa: sobe o erro (o motor tenta de novo em 1/5/15 min)' do
      allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError)
      expect { rodar('sugestao_documento', mensagem: anexo, tentativas: 2) }.to raise_error(Ramon::LlmClient::TransientError)
    end

    it 'IA fora do ar na última tentativa: desiste em silêncio (N4), sem sino' do
      allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError)
      expect(rodar('sugestao_documento', mensagem: anexo, tentativas: 3))
        .to eq(saida: 's', resumo: 'sugestão de documento: desistiu depois de 4 tentativas (TransientError)', sem_balao: true)
    end
  end

  describe 'coach_objecao' do
    let(:thesis) { create(:thesis, account: account) }
    let!(:lead) { create(:lead, account: account, contact: contact, conversation: conversa, thesis: thesis) }
    let(:msg) do
      create(:message, account: account, conversation: conversa, message_type: :incoming, content: 'achei caro, vou pensar mais um pouco')
    end

    before { create(:thesis_item, thesis: thesis, section: 'objecao', title: 'Caro', content: 'A análise é gratuita.') }

    it 'ensaio não chama a IA; de verdade o mesmo coach (balão do coach, e a trava de 10 min gravada)' do
      allow(Ramon::LlmClient).to receive(:complete).and_return(
        llm('{"objecao": "custo", "opcoes": [{"titulo": "A", "texto": "a"}, {"titulo": "B", "texto": "b"}]}')
      )
      expect(rodar('coach_objecao', mensagem: msg, ensaio: true)[:resumo]).to start_with('faria: o coach')
      expect(Ramon::LlmClient).not_to have_received(:complete)
      expect { rodar('coach_objecao', mensagem: msg) }.to have_enqueued_job(Conversations::ActivityMessageJob)
        .with(conversa, hash_including(content_attributes: hash_including('ramon_event' => 'coach')))
      expect(lead.reload.custom_attributes.dig('coach', 'ultima_em')).to be_present
    end
  end

  describe 'agente_hub' do
    let(:eduardo) { create(:user, account: account, email: 'edu@x.com') }

    around { |ex| with_modified_env(RAMON_AGENTE_RUNNER_URL: 'http://runner/hub', RAMON_AGENTE_EDUARDO_EMAIL: 'edu@x.com') { ex.run } }

    before { allow(HTTParty).to receive(:post) }

    it '@claude do Eduardo: avisa o runner (o mesmo job de hoje)' do
      nota = create(:message, account: account, conversation: conversa, message_type: :outgoing, private: true, sender: eduardo,
                              content: '@claude resume')
      expect(rodar('agente_hub', mensagem: nota)[:resumo]).to eq('avisou o agente do hub (a resposta chega como nota privada)')
      expect(HTTParty).to have_received(:post).with('http://runner/hub', anything).once
    end

    it 'a trava fica na rotina: nota @claude de outra pessoa não chama o agente, nem com o passo noutro fluxo' do
      outro = create(:user, account: account, email: 'o@x.com')
      nota = create(:message, account: account, conversation: conversa, message_type: :outgoing, private: true, sender: outro,
                              content: '@claude resume')
      expect(rodar('agente_hub', mensagem: nota)[:resumo]).to eq('não é nota @claude do Eduardo: o agente não foi chamado')
      expect(HTTParty).not_to have_received(:post)
    end
  end
end

require 'rails_helper'

RSpec.describe 'Ramon::Fluxos::Passos' do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversa, contact: conversa.contact) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  def ctx(alvo: lead, ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio))
  end

  it 'rascunho vira nota privada com o prefixo, nunca mensagem pública' do
    r = Ramon::Fluxos::Passos::Conversa.rascunho_texto({ 'texto' => 'Oi {nome}' }, ctx)
    msg = conversa.messages.last
    expect(msg.private).to be(true)
    expect(msg.content).to start_with(Ramon::RascunhoCarimbo::PREFIXO)
    expect(r[:saida]).to eq('s')
  end

  it 'rascunho de lead sem conversa vira nota do lead' do
    sozinho = create(:lead, account: account)
    Ramon::Fluxos::Passos::Conversa.rascunho_texto({ 'texto' => 'Oi' }, ctx(alvo: sozinho))
    expect(sozinho.lead_notes.last.body).to start_with(Ramon::RascunhoCarimbo::PREFIXO)
  end

  it 'ensaio não grava nada' do
    expect do
      r = Ramon::Fluxos::Passos::Conversa.rascunho_texto({ 'texto' => 'Oi' }, ctx(ensaio: true))
      expect(r[:resumo]).to start_with('faria: ')
    end.not_to(change { conversa.messages.count })
  end

  it 'ação do Chatwoot põe etiqueta e ignora envio ao cliente' do
    acoes = [{ 'action_name' => 'add_label', 'action_params' => ['urgente'] },
             { 'action_name' => 'send_message', 'action_params' => ['oi'] }]
    expect do
      Ramon::Fluxos::Passos::Conversa.acao_chatwoot({ 'acoes' => acoes }, ctx)
    end.not_to(change { conversa.messages.where(message_type: :outgoing, private: false).count })
    expect(conversa.reload.label_list).to include('urgente')
  end

  it 'ação do Chatwoot fora da lista permitida é descartada antes de rodar' do
    acoes = [{ 'action_name' => 'add_label', 'action_params' => ['urgente'] }, { 'action_name' => 'system', 'action_params' => [] }]
    servico = Ramon::Fluxos::AcaoChatwootService.new(ctx.execucao, conversa, acoes)
    expect(servico.instance_variable_get(:@rule).actions.pluck('action_name')).to eq(['add_label'])
    servico.perform
    expect(conversa.reload.label_list).to include('urgente')
  end

  it 'mover etapa atualiza a etapa inicial da execução' do
    nova = create(:lead_stage, account: account, position: 5)
    c = ctx
    Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => nova.id }, c)
    expect(lead.reload.lead_stage).to eq(nova)
    expect(c.execucao.contexto['etapa_inicial_id']).to eq(nova.id)
  end

  it 'passo de lead sem lead é impossível (não repete)' do
    sem_lead = create(:conversation, account: account)
    expect do
      Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => lead.lead_stage_id }, ctx(alvo: sem_lead))
    end.to raise_error(Ramon::Fluxos::PassoImpossivel)
  end

  it 'tarefa na Esteira com prazo relativo' do
    Ramon::Fluxos::Passos::Lead.criar_tarefa({ 'titulo' => 'Conferir docs de {nome}', 'prazo_dias' => 2 }, ctx)
    tarefa = lead.lead_tasks.last
    expect(tarefa.title).to start_with('Conferir docs de')
    expect(tarefa.due_at.in_time_zone('America/Sao_Paulo').to_date).to eq(Time.find_zone!('America/Sao_Paulo').today + 2)
  end

  it 'esperar devolve o momento de retomar' do
    freeze_time do
      r = Ramon::Fluxos::Passos::Logica.esperar({ 'quantidade' => 2, 'unidade' => 'dias' }, ctx)
      expect(r[:esperar_ate]).to eq(2.days.from_now)
    end
  end

  it 'escolha sai pela chave do caso' do
    lead.update!(source: 'indicacao')
    config = { 'campo' => 'origem', 'casos' => [{ 'chave' => 'c1', 'rotulo' => 'Indicação', 'valores' => ['indicacao'] },
                                                { 'chave' => 'c2', 'rotulo' => 'Anúncio', 'valores' => ['anuncio'] }] }
    expect(Ramon::Fluxos::Passos::Logica.escolha(config, ctx)[:saida]).to eq('c1')
  end

  it 'sino avisa o responsável' do
    agente = create(:user, account: account)
    lead.update!(closer: agente)
    expect do
      Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Ver {nome}' }, ctx)
    end.to change { agente.notifications.where(notification_type: 'ramon_fluxo_aviso').count }.by(1)
  end

  it 'sino sem responsável não cai em todo mundo' do
    create(:user, account: account)
    r = nil
    expect { r = Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Ver' }, ctx) }.not_to change(Notification, :count)
    expect(r[:resumo]).to eq('sino: sem responsável')
  end
end

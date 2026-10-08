require 'rails_helper'

# Visão geral da Inteligência (I-VG1–3). A nota-rascunho do Assistente entra por
# insert_all (sender Captain::Assistant sem instanciar) — assim roda no CI FOSS.
RSpec.describe 'Ramon Inteligencia API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_inteligencia" }

  def visao
    get url, headers: agent.create_new_auth_token, as: :json
    response.parsed_body
  end

  # O cliente fala, o Assistente deixa a nota-rascunho e o humano responde `resposta`.
  def rascunho_respondido(resposta)
    conversa = create(:conversation, account: account, inbox: inbox)
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, content: 'oi',
                     created_at: 10.minutes.ago)
    # rubocop:disable Rails/SkipsModelValidations
    Message.insert_all([{ account_id: account.id, inbox_id: inbox.id, conversation_id: conversa.id, message_type: 1,
                          private: true, sender_type: 'Captain::Assistant', sender_id: 1,
                          content: "RASCUNHO (revisar antes de enviar):\nOla, tudo bem?", content_attributes: {},
                          created_at: 5.minutes.ago, updated_at: 5.minutes.ago }])
    # rubocop:enable Rails/SkipsModelValidations
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :outgoing, sender: agent,
                     content: resposta)
    conversa
  end

  it 'conta os rascunhos por desfecho, a regua da D7 e a 1a resposta com IA' do
    rascunho_respondido('Ola, tudo bem?')
    rascunho_respondido('Ola, tudo bem? Pode mandar o laudo')
    rascunho_respondido('Bom dia')

    body = visao

    expect(response).to have_http_status(:success)
    expect(body['rascunhos']).to include('igual' => 1, 'editado' => 1, 'descartado' => 1)
    expect(body['piloto']).to eq('conversas' => 3, 'meta' => 20, 'sem_correcao_pct' => 33)
    expect(body['primeira_resposta']['com_ia']['conversas']).to eq(3)
    expect(body['primeira_resposta']['com_ia']['mediana_min']).to be_between(9, 11)
  end

  it 'conta transferencias, sugestoes pendentes por tipo e o agente de hoje no fuso de Brasilia' do
    travel_to Time.find_zone('America/Sao_Paulo').local(2026, 10, 5, 22, 0) do
      conversa = rascunho_respondido('Bom dia')
      create(:reporting_event, account: account, inbox: inbox, conversation: conversa, name: 'conversation_bot_handoff')
      create(:copilot_suggestion, account: account, kind: 'move_stage')
      create(:copilot_suggestion, account: account, kind: 'acao', payload: { 'acao' => 'zapsign' })
      create(:copilot_suggestion, account: account, status: 'applied')
      account.agente_execucoes.create!(pedido: 'resumo do caso', status: 'ok')
      account.agente_execucoes.create!(pedido: 'falhou', status: 'erro')
      # cap/pausa: o runner grava a linha sem rodar o claude — não conta na cota do dia
      account.agente_execucoes.create!(pedido: 'sem cota', status: 'cap',
                                       resumo: 'Cap diário atingido (ou pausado até amanhã por limite de uso). Não executei.')
      account.agente_execucoes.create!(pedido: 'de manha', status: 'ok', created_at: 12.hours.ago)
      account.agente_execucoes.create!(pedido: 'ontem', status: 'ok', created_at: 23.hours.ago)

      body = visao

      expect(body['transferencias']).to eq('total' => 1, 'conversas' => [conversa.display_id])
      expect(body['aprovacoes']).to eq('sugestoes' => 2, 'sugestoes_por_tipo' => { 'move_stage' => 1, 'zapsign' => 1 })
      expect(body['agente']).to include('hoje' => 3, 'teto' => 30, 'problemas_hoje' => 2)
    end
  end

  # ramon_ia_rodadas e captain_assistants são do enterprise: as linhas entram por SQL (roda no CI FOSS).
  def inserir(sql, *binds)
    ActiveRecord::Base.connection.select_value(ActiveRecord::Base.sanitize_sql_array([sql, *binds]))
  end

  it 'mostra a ultima rodada concluida do caderno por assistente (I-X6)' do
    agora = Time.current
    assistente = inserir('INSERT INTO captain_assistants (name, account_id, created_at, updated_at) VALUES (?, ?, ?, ?) RETURNING id',
                         'Atendimento', account.id, agora, agora)
    sql = 'INSERT INTO ramon_ia_rodadas (account_id, assistant_id, status, total, passou, falhou, created_at, updated_at) '           "VALUES (?, ?, 'concluida', 43, ?, ?, ?, ?) RETURNING id"
    inserir(sql, account.id, assistente, 40, 3, 2.days.ago, 2.days.ago)
    inserir(sql, account.id, assistente, 41, 2, 1.hour.ago, 1.hour.ago)

    expect(visao['caderno']).to match([a_hash_including('assistant_id' => assistente.to_i, 'nome' => 'Atendimento',
                                                        'passou' => 41, 'total' => 43)])
  end

  it 'conta vazia devolve zeros sem quebrar' do
    body = visao

    expect(body['rascunhos']).to eq({})
    expect(body['piloto']).to eq('conversas' => 0, 'meta' => 20, 'sem_correcao_pct' => nil)
    expect(body['primeira_resposta']).to eq({})
    expect(body['transferencias']).to eq('total' => 0, 'conversas' => [])
    expect(body['agente']).to include('hoje' => 0, 'ultima_em' => nil)
    expect(body['caderno']).to eq([])
  end

  it 'exige autenticacao' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end

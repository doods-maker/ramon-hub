# Espelho do ADVBOX para 1 cliente do painel: processos por CPF + andamentos +
# pedidos de documento abertos. 1 + 2×N chamadas (limite 500/dia/rota).
# ponytail: sync cheio por cliente; passando de ~250 clientes, varrer
# /last_movements e re-buscar só os processos cuja última data mudou.
class Ramon::PortalSyncService
  TAREFA_SOLICITAR = 'SOLICITAR DOCUMENTOS'.freeze
  LIMITE_PROCESSOS = 10
  LIMITE_ANDAMENTOS = 100 # mesma 1 chamada; janela maior pra achar o andamento que define a fase
  LIMITE_TAREFAS = 50
  # Tipos de tarefa do ADVBOX que são compromisso do cliente (os "ACOMPANHAR/AVISAR…" são internos).
  TAREFAS_AGENDA = { 'AUDIENCIA DE INSTRUCAO/JULGAMENTO' => 'audiencia', 'AUDIENCIA DE CONCILIACAO' => 'audiencia',
                     'PERICIA AGENDADA' => 'pericia' }.freeze
  # Sem autorização da IA (LGPD art. 33, VIII) o pedido aparece resumido.
  ITEM_SEM_IA = 'Documentos pedidos pela equipe (confira a lista com a equipe no WhatsApp)'.freeze

  def initialize(cliente)
    @cliente = cliente
  end

  def perform
    anteriores = Array(@cliente.processos).index_by { |p| p['id'].to_s }
    processos = lista(Ramon::AdvboxClient.lawsuits(identification: @cliente.cpf, limit: LIMITE_PROCESSOS))
                .map { |l| Ramon::PortalNovidades.aplicar(anteriores[l['id'].to_s], espelho(l)) }
    @cliente.update!(processos: processos, sincronizado_em: Time.current, telefone: @cliente.telefone.presence || telefone_advbox)
    processos
  end

  private

  def espelho(lawsuit)
    id = lawsuit['id']
    tarefas = lista(Ramon::AdvboxClient.posts(lawsuit_id: id, limit: LIMITE_TAREFAS))
    {
      'id' => id,
      'numero' => lawsuit['process_number'],
      'protocolo' => lawsuit['protocol_number'],
      'tipo' => lawsuit['type'],
      'inicio' => lawsuit['process_date'] || lawsuit['date'],
      'responsavel' => lawsuit['responsible'],
      'responsavel_id' => lawsuit['responsible_id'],
      'etapa' => lawsuit['stage'],
      'fase' => lawsuit['step'],
      'andamentos' => andamentos(id),
      'docs_pendentes' => docs_pendentes(tarefas),
      'agenda' => agenda(tarefas)
    }
  end

  # Audiência/perícia marcada pela equipe, ainda por acontecer → mostrada ao cliente com data e formato.
  def agenda(tarefas)
    hoje = Date.current.iso8601
    tarefas.filter_map do |p|
      tipo = TAREFAS_AGENDA[Ramon::PortalTexto.normalizar(p['task'])]
      next unless tipo && aberta?(p) && p['date'].to_s[0, 10] >= hoje

      { 'tipo' => tipo, 'quando' => p['date'].to_s, 'formato' => formato(p['notes']) }
    end.sort_by { |a| a['quando'] }
  end

  # ponytail: formato lido das observações da tarefa ("PRESENCIAL"); sem a palavra, o painel não diz.
  def formato(notes)
    texto = Ramon::PortalTexto.normalizar(notes)
    return 'por vídeo' if texto.match?(/VIRTUAL|VIDEO|ONLINE|TELEPRESENCIAL/)

    'presencial' if texto.include?('PRESENCIAL')
  end

  def andamentos(id)
    lista(Ramon::AdvboxClient.movements(id, limit: LIMITE_ANDAMENTOS))
      .map { |m| { 'data' => m['date'].to_s[0, 10], 'titulo' => m['title'] } }
  end

  # /posts não devolve tasks_id (confirmado na API real) — casa pelo nome da
  # tarefa, mas tolerante (acento/maiúscula/espaço) em vez de igualdade exata.
  # Os itens saem do LLM (Ramon::PortalDocsService); `digest` das observações
  # guarda o resultado no espelho pra não pagar a chamada de novo toda noite.
  def docs_pendentes(tarefas)
    tarefas
      .select { |p| Ramon::PortalTexto.normalizar(p['task']).include?(TAREFA_SOLICITAR) && aberta?(p) }
      .flat_map do |p|
        digest = Digest::SHA256.hexdigest("#{usa_ia? ? 'ia' : 'sem-ia'}#{p['notes']}")[0, 16]
        itens = itens_anteriores[[p['id'], digest]] || itens_do_pedido(p['notes'])
        Array(itens).map { |item| { 'item' => item, 'post_id' => p['id'], 'digest' => digest } }
      end
  end

  def itens_do_pedido(notes)
    return [] if notes.to_s.strip.blank?
    return [ITEM_SEM_IA] unless usa_ia?

    Ramon::PortalDocsService.itens(notes, nome: @cliente.nome, account: @cliente.account)
  end

  # Com os textos v2 ligados a IA exige a autorização do cliente; antes disso segue como está.
  def usa_ia? = !Ramon::PortalTexto.v2? || @cliente.ia_consentimento == true

  # ponytail: lista vazia legítima não fica no espelho, então uma tarefa sem
  # documento pedido custa 1 chamada por noite — aceitável no volume atual.
  def itens_anteriores
    @itens_anteriores ||= Array(@cliente.processos).flat_map { |p| Array(p['docs_pendentes']) }
                                                   .select { |d| d['digest'].present? }
                                                   .group_by { |d| [d['post_id'], d['digest']] }
                                                   .transform_values { |ds| ds.map { |d| d['item'] } }
  end

  # 1 chamada só enquanto o cliente não tem telefone (pro wa.me do resumo da equipe).
  def telefone_advbox
    dados = Ramon::AdvboxClient.customer(@cliente.advbox_customer_id)
    dados = dados['data'] if dados.is_a?(Hash) && dados['data'].is_a?(Hash)
    dados.is_a?(Hash) ? dados['cellphone'].to_s.delete('^0-9').presence : nil
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError
    nil
  end

  def aberta?(post)
    Array(post['users']).none? { |u| u['completed'].present? }
  end

  # Envelope das listas do ADVBOX: { offset, limit, totalCount, data } — nunca Array.
  def lista(resposta)
    Array(resposta.is_a?(Hash) ? resposta['data'] : resposta)
  end
end

# Espelho do ADVBOX para 1 cliente do painel: processos por CPF + andamentos +
# pedidos de documento abertos. 1 + 2×N chamadas (limite 500/dia/rota).
# ponytail: sync cheio por cliente; passando de ~250 clientes, varrer
# /last_movements e re-buscar só os processos cuja última data mudou.
class Ramon::PortalSyncService
  TAREFA_SOLICITAR = 'SOLICITAR DOCUMENTOS'.freeze
  LIMITE_PROCESSOS = 10
  LIMITE_ANDAMENTOS = 30
  LIMITE_TAREFAS = 50

  def initialize(cliente)
    @cliente = cliente
  end

  def perform
    processos = lista(Ramon::AdvboxClient.lawsuits(identification: @cliente.cpf, limit: LIMITE_PROCESSOS))
                .map { |l| espelho(l) }
    @cliente.update!(processos: processos, sincronizado_em: Time.current)
    processos
  end

  private

  def espelho(lawsuit)
    id = lawsuit['id']
    {
      'id' => id,
      'numero' => lawsuit['process_number'],
      'tipo' => lawsuit['type'],
      'inicio' => lawsuit['process_date'] || lawsuit['date'],
      'responsavel' => lawsuit['responsible'],
      'responsavel_id' => lawsuit['responsible_id'],
      'etapa' => lawsuit['stage'],
      'fase' => lawsuit['step'],
      'andamentos' => andamentos(id),
      'docs_pendentes' => docs_pendentes(id)
    }
  end

  def andamentos(id)
    lista(Ramon::AdvboxClient.movements(id, limit: LIMITE_ANDAMENTOS))
      .map { |m| { 'data' => m['date'].to_s[0, 10], 'titulo' => m['title'] } }
  end

  # /posts não devolve tasks_id (confirmado na API real) — casa pelo nome da
  # tarefa, mas tolerante (acento/maiúscula/espaço) em vez de igualdade exata.
  def docs_pendentes(id)
    lista(Ramon::AdvboxClient.posts(lawsuit_id: id, limit: LIMITE_TAREFAS))
      .select { |p| Ramon::PortalTexto.normalizar(p['task']).include?(TAREFA_SOLICITAR) && aberta?(p) }
      .flat_map { |p| p['notes'].to_s.lines.map(&:strip).reject(&:blank?).map { |item| { 'item' => item, 'post_id' => p['id'] } } }
  end

  def aberta?(post)
    Array(post['users']).none? { |u| u['completed'].present? }
  end

  # Envelope das listas do ADVBOX: { offset, limit, totalCount, data } — nunca Array.
  def lista(resposta)
    Array(resposta.is_a?(Hash) ? resposta['data'] : resposta)
  end
end

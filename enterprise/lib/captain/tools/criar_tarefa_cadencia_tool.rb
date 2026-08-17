# Escrita INTERNA: cria a tarefa de cadencia do caso na Esteira (lead_tasks).
# Nada chega ao cliente — a tarefa e o lembrete do humano. Por isso nao passa
# por Sugestao pendente (mesma regra do "Subir na esteira" do Cockpit).
class Captain::Tools::CriarTarefaCadenciaTool < Captain::Tools::RamonBaseTool
  TZ = 'America/Sao_Paulo'.freeze

  description 'Cria uma tarefa de cadencia do caso na Esteira (lembrete interno para a equipe: cobrar documento, ' \
              'retomar contato, ligar). Nao envia nada ao cliente.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :titulo, type: 'string', desc: 'O que fazer, em uma linha', required: true
  param :quando, type: 'string', desc: 'AAAA-MM-DD ou AAAA-MM-DD HH:MM (sem hora, assume 09:00)', required: true
  param :tipo, type: 'string', desc: 'follow_up (padrao), document, meeting ou other', required: false

  def perform(tool_context, titulo: nil, quando: nil, lead_id: nil, tipo: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    kind = tipo.presence || 'follow_up'
    due = horario_de(quando)
    nome = titulo.to_s.strip
    erro = recusa(kind, due, nome, lead)
    return erro if erro

    log_tool_usage('criar_tarefa_cadencia', { lead_id: lead.id, kind: kind, due_at: due.iso8601 })
    lead.lead_tasks.create!(account: lead.account, kind: kind, title: nome.truncate(255), due_at: due)
    confirmacao(lead, nome, due)
  end

  private

  # A LLM nao sabe a data de hoje sozinha — datas relativas ("semana que vem")
  # viram chute e batem na recusa. Devolver "hoje e X" no proprio texto deixa
  # a recusa autocorretiva sem acrescentar branch (CyclomaticComplexity).
  def hoje
    Time.current.in_time_zone(TZ).strftime('%d/%m/%Y')
  end

  def recusa(kind, due, nome, lead)
    return "Tipo invalido. Use: #{LeadTask::KINDS.join(', ')}." unless LeadTask::KINDS.include?(kind)
    return "Nao entendi a data (hoje e #{hoje}). Use AAAA-MM-DD ou AAAA-MM-DD HH:MM." if due.blank?
    return "A data ja passou (hoje e #{hoje}). Use uma data futura." if due < Time.current
    return 'Informe o titulo da tarefa.' if nome.blank?
    return "Ja existe a tarefa aberta \"#{nome}\" no caso #{lead.name}." if lead.lead_tasks.open_tasks.any? { |t| t.title.casecmp?(nome) }

    nil
  end

  def confirmacao(lead, nome, due)
    "Tarefa \"#{nome}\" criada na Esteira do caso #{lead.name} para #{due.in_time_zone(TZ).strftime('%d/%m/%Y %H:%M')}."
  end

  def horario_de(quando)
    texto = quando.to_s.strip
    texto = "#{texto} 09:00" if texto.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    ActiveSupport::TimeZone[TZ].parse(texto)
  rescue ArgumentError
    nil
  end
end

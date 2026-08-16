# Leitura pura: a mesa do dia — reunioes e tarefas do hub (do dia + atrasadas)
# e as tarefas do AdvBox com prazo no dia. Mesmo material do Cockpit, em texto.
# O id NAO e "agenda_do_dia": resolve_tool_class faz tool_id.classify, e o Inflector
# singulariza "dia" -> "dium" (AgendaDoDiumTool), tool sumiria do catalogo.
class Captain::Tools::AgendaDoEscritorioTool < Captain::Tools::BasePublicTool
  description 'Agenda do dia do escritorio: reunioes marcadas, tarefas do hub vencendo, tarefas atrasadas e ' \
              'prazos do AdvBox. Use quando perguntarem o que tem hoje, o que esta atrasado ou os prazos do dia.'
  param :data, type: 'string', desc: 'Dia no formato AAAA-MM-DD. Sem ele, usa hoje.', required: false

  TIME_ZONE = Ramon::CockpitMetrics::TIME_ZONE
  MAX_ATRASADAS = 20
  ADVBOX_FORA = 'AdvBox indisponivel agora.'.freeze

  def perform(_tool_context, data: nil)
    dia = resolver_dia(data)
    return 'Data invalida. Use o formato AAAA-MM-DD.' if dia.nil?

    log_tool_usage('agenda_do_escritorio', { dia: dia.to_s })
    blocos = {
      'Reunioes' => tarefas_do_dia(dia).where(kind: 'meeting').map { |t| linha_tarefa(t) },
      'Tarefas do hub no dia' => tarefas_do_dia(dia).where.not(kind: 'meeting').map { |t| linha_tarefa(t) },
      'Atrasadas' => atrasadas.map { |t| linha_tarefa(t, com_data: true) },
      'Prazos no AdvBox' => tarefas_advbox(dia)
    }
    montar(dia, blocos)
  end

  private

  def account
    @assistant.account
  end

  def atrasadas
    account.lead_tasks.overdue.includes(lead: :lead_stage).order(:due_at).limit(MAX_ATRASADAS)
  end

  def montar(dia, blocos)
    corpo = blocos.map { |titulo, linhas| "#{titulo}:\n#{linhas.presence&.join("\n") || '- nenhuma'}" }
    totais = blocos.map { |titulo, linhas| linhas == [ADVBOX_FORA] ? ADVBOX_FORA : "#{linhas.size} #{titulo.downcase}" }.join(', ')
    ["Agenda de #{dia.strftime('%d/%m/%Y')}", *corpo, "Totais: #{totais}."].join("\n\n")
  end

  def resolver_dia(data)
    return Time.current.in_time_zone(TIME_ZONE).to_date if data.blank?

    Date.iso8601(data.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def tarefas_do_dia(dia)
    account.lead_tasks.where(due_at: dia.in_time_zone(TIME_ZONE).all_day).includes(lead: :lead_stage).order(:due_at)
  end

  def linha_tarefa(task, com_data: false)
    quando = task.due_at.in_time_zone(TIME_ZONE).strftime(com_data ? '%d/%m %H:%M' : '%H:%M')
    lead = task.lead
    "- #{quando} #{task.title} — #{lead&.name} (#{lead&.lead_stage&.name || 'sem etapa'}, lead_id #{task.lead_id})"
  end

  # Formato real do AdvBox (16/08): envelope {data: [{task, date_deadline, lawsuit: {customers: [{name}]}, users: [{name}]}]}.
  def tarefas_advbox(dia)
    resposta = Ramon::AdvboxClient.posts(deadline_start: dia.iso8601, deadline_end: dia.iso8601, limit: 50)
    lista = resposta.is_a?(Hash) ? Array(resposta['data']) : Array(resposta)
    lista.map { |t| linha_advbox(t) }
  rescue StandardError => e
    Rails.logger.warn("AgendaDoEscritorioTool: AdvBox falhou (#{e.class}: #{e.message})")
    [ADVBOX_FORA]
  end

  def linha_advbox(tarefa)
    cliente = tarefa.dig('lawsuit', 'customers')&.first&.dig('name') || 'sem cliente'
    quem = Array(tarefa['users']).filter_map { |u| u['name'] }.join(', ').presence || 'sem responsavel'
    "- #{tarefa['task']} — #{cliente} (#{quem}, processo #{tarefa['lawsuits_id']})"
  end
end

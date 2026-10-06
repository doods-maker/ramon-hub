# B4.1 (spec §8, passo 2): evento a evento — reunião marcada, remarcada, cancelada —, os rastros que o código deixou
# ao lado do que os fluxos em sombra dizem que fariam (linhas "faria: …" da trilha). Só leitura.
# O ensaio roda na mesma requisição, logo ANTES do código: casa pelo lead e pelo minuto seguinte ao ensaio.
# Sino do código: o rastro no Redis (Reunioes.rastros) — a tabela de avisos deduplica e perde o histórico.
class Ramon::Fluxos::CompararAgendamentos
  JANELA = 1.minute
  KINDS = { 'marcada' => 'meeting_scheduled', 'remarcada' => 'meeting_rescheduled', 'cancelada' => 'meeting_cancelled' }.freeze
  RASCUNHO = Ramon::Fluxos::Passos::Conversa.cabecalho('titulo' => 'confirmação de reunião')

  attr_reader :de, :ate

  def initialize(account, dias: 1, ate: Time.current)
    @account = account
    @ate = ate
    @de = Ramon::Fluxos::CompararLembretes.inicio(account, dias, ate)
  end

  def linhas
    @linhas ||= begin
      sobra = eventos_do_codigo
      casadas = ensaios.map { |execucao| casar(execucao, sobra) }
      (casadas + sobra.map { |atividade| so_codigo(atividade) }).sort_by { |item| item[:em] }
    end
  end

  def divergencias = linhas.count { |item| item[:situacao] != 'igual' }

  def relatorio = [cabecalho, *linhas.map { |item| texto(item) }, total, resultado].join("\n")

  private

  def ensaios
    fluxos = Ramon::Fluxos::Reunioes.fluxos(@account).where(sistema_chave: %w[reuniao_marcada reuniao_cancelada])
    FluxoExecucao.where(fluxo: fluxos, ensaio: true, alvo_type: 'Lead', created_at: de..ate).includes(:alvo)
                 .reject { |execucao| execucao.contexto['pular_esperas'] }
  end

  def eventos_do_codigo = @account.lead_activities.where(kind: KINDS.values, created_at: de..ate).includes(:lead).to_a

  def casar(execucao, sobra)
    evento = execucao.contexto.dig('gatilho', 'evento')
    inicio = execucao.created_at
    janela = inicio..(inicio + JANELA)
    atividade = sobra.delete(sobra.find { |a| a.lead_id == execucao.alvo_id && a.kind == KINDS[evento] && janela.cover?(a.created_at) })
    fluxo = do_fluxo(execucao)
    codigo = atividade ? do_codigo(execucao, janela) : []
    { evento: evento, em: inicio, lead_id: execucao.alvo_id, lead: execucao.alvo&.name,
      situacao: situacao(atividade, codigo, fluxo), so_no_codigo: menos(codigo, fluxo), so_no_fluxo: menos(fluxo, codigo) }
  end

  def situacao(atividade, codigo, fluxo)
    return 'so_fluxo' unless atividade

    codigo.sort == fluxo.sort ? 'igual' : 'diferente'
  end

  def so_codigo(atividade)
    { evento: KINDS.key(atividade.kind), em: atividade.created_at, lead_id: atividade.lead_id, lead: atividade.lead&.name,
      situacao: 'so_codigo', so_no_codigo: [], so_no_fluxo: [] }
  end

  # O ensaio: as linhas "faria: …", menos o push (o código não deixa rastro dele); o sino vira "sino para <pessoas>".
  def do_fluxo(execucao)
    execucao.trilha.filter_map do |t|
      resumo = t['resumo'].to_s
      next unless resumo.start_with?('faria: ') && t['tipo'] != 'avisar_push'

      t['tipo'] == 'avisar_sino' ? sino(resumo[Ramon::Fluxos::CompararLembretes::PESSOAS, 1].split(', ')) : resumo.delete_prefix('faria: ')
    end
  end

  # Os rastros do código na janela do evento, na mesma frase do ensaio.
  def do_codigo(execucao, janela)
    lead = execucao.alvo
    atividades(lead, janela) + tarefas(lead, janela) + rascunhos(lead, janela) + sinos(lead, janela) + apagadas(execucao)
  end

  def atividades(lead, janela)
    lead.lead_activities.where(created_at: janela, kind: KINDS.values + %w[stage_changed closer_changed]).map do |a|
      case a.kind
      when 'stage_changed' then "mover para #{a.to_value}"
      when 'closer_changed' then "closer → #{a.to_value}"
      else "atividade #{a.kind}: #{[a.from_value, a.to_value].compact.join(' → ')}"
      end
    end
  end

  def tarefas(lead, janela)
    lead.lead_tasks.where(kind: 'meeting', created_at: janela).map { |t| "tarefa \"#{t.title}\" para #{hora(t.due_at)}" }
  end

  def rascunhos(lead, janela)
    lead.lead_notes.where(created_at: janela).where('body LIKE ?', "#{RASCUNHO}%")
        .map { |n| "rascunho \"#{n.body.split("\n", 2).last.to_s.truncate(120)}\"" }
  end

  # O sino de marcada/remarcada/cancelada que o Ramon::ReuniaoAgendamento gravou no rastro (quem recebeu).
  def sinos(lead, janela)
    rastros.select { |r| r['lead_id'] == lead.id && KINDS.key?(r['tipo']) && janela.cover?(Time.zone.at(r['em'])) }
           .map { |r| sino(User.where(id: r['user_ids']).pluck(:name)) }
  end

  def rastros = @rastros ||= Ramon::Fluxos::Reunioes.rastros(@account, de, ate)

  # Nomes em ordem do Ruby nos dois lados (a ordem do banco, com acentos, pode ser outra).
  def sino(nomes) = "sino para #{nomes.sort.join(', ')}"

  # Cancelada: as tarefas do evento sumiram? (o código apaga; o ensaio diria "apagar tarefas …")
  def apagadas(execucao)
    return [] unless execucao.contexto.dig('gatilho', 'evento') == 'cancelada'

    ids = Array(execucao.contexto.dig('gatilho', 'tarefa_ids')).map(&:to_i).sort
    vivas = LeadTask.where(id: ids).pluck(:id)
    ["apagar tarefas #{Ramon::Fluxos::Passos::Reuniao.lista(ids)}#{" (ainda existem: #{vivas.join(', ')})" if vivas.any?}"]
  end

  # Diferença de listas com repetição (multiconjunto): o que está em `lista` e falta em `outra`.
  def menos(lista, outra) = outra.each_with_object(lista.dup) { |x, resto| (i = resto.index(x)) && resto.delete_at(i) }

  def hora(momento) = Ramon::Fluxos::Passos::Logica.hora(momento)

  def cabecalho = "Agendamentos — código × fluxos em sombra · conta #{@account.id} · #{Ramon::Fluxos::CompararLembretes.periodo(de, ate)}"

  def texto(item)
    dif = [("só no código: #{item[:so_no_codigo].join(' | ')}" if item[:so_no_codigo].any?),
           ("só no fluxo: #{item[:so_no_fluxo].join(' | ')}" if item[:so_no_fluxo].any?)].compact.join(' · ')
    "#{item[:situacao].ljust(10)} #{hora(item[:em])}  #{item[:lead]} (lead #{item[:lead_id]})  #{item[:evento]}  #{dif}".rstrip
  end

  def total
    por_evento = KINDS.keys.map { |e| "#{linhas.count { |item| item[:evento] == e }} #{e}(s)" }.join(' · ')
    "Total: #{por_evento} — #{linhas.size - divergencias} iguais · #{divergencias} com diferença"
  end

  def resultado
    return 'Resultado: nada para comparar ainda (nenhum agendamento no período)' if linhas.empty?

    divergencias.zero? ? 'Resultado: BATEU' : 'Resultado: NÃO BATEU — veja as linhas que não são "igual"'
  end
end

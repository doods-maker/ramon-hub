# B4.1 (spec §8 e §15): o agendamento de reuniões (marcar, remarcar, cancelar e os 5 lembretes) saindo do código para
# fluxos. As regras de reunião moram aqui, uma vez só, e valem para os dois lados — o código (Ramon::MeetingReminderJob,
# Ramon::ReuniaoAgendamento) e os fluxos —, então a sombra compara exatamente a mesma regra.
module Ramon::Fluxos::Reunioes
  TOLERANCIA = 60.seconds
  # Os 3 fluxos que substituem o código (spec §14: fluxo próprio, origem 'usuario'): sistema_chave → gatilho esperado.
  GATILHOS = { 'reuniao_marcada' => 'reuniao_marcada', 'reuniao_cancelada' => 'reuniao_cancelada',
               'lembretes_reuniao' => 'reuniao_na_agenda' }.freeze
  RASTRO_RETENCAO = 8.days

  module_function

  # A reunião segue de pé: a tarefa da reunião segue aberta naquele horário (±60 s).
  # Cancelou (tarefa apagada), concluiu ou remarcou (outro horário) → não.
  def reuniao_aberta?(lead, inicio)
    return false if inicio.blank?

    lead.lead_tasks.open_tasks.exists?(kind: 'meeting', due_at: (inicio - TOLERANCIA)..(inicio + TOLERANCIA))
  end

  # Closer e SDR do lead; lead sem nenhum dos dois avisa os administradores (nunca a conta toda).
  def destinatarios(lead)
    [lead.closer_id, lead.sdr_id].compact.uniq.presence || lead.account.account_users.administrator.pluck(:user_id)
  end

  # Rastro do que o código avisou (a tabela notifications não serve: a deduplicação guarda só a última por pessoa).
  # Redis, 8 dias: grava o hash + 'em' (epoch) e apara o que passou da retenção.
  def rastro!(account, dados)
    agora = Time.current.to_f
    chave = chave_rastro(account)
    Redis::Alfred.zadd(chave, agora, dados.merge('em' => agora).to_json)
    Redis::Alfred.zremrangebyscore(chave, '-inf', "(#{agora - RASTRO_RETENCAO.to_f}")
    Redis::Alfred.expire(chave, RASTRO_RETENCAO.to_i)
  end

  # Entradas do rastro entre desde e ate (Time), da mais antiga para a mais nova.
  def rastros(account, desde, ate)
    Redis::Alfred.zrangebyscore(chave_rastro(account), desde.to_f, ate.to_f).map { |linha| JSON.parse(linha) }
  end

  def chave_rastro(account)
    "ramon:reunioes:rastro:#{account.id}"
  end

  def migrado?(fluxo) = fluxo.origem == 'usuario' && GATILHOS.key?(fluxo.sistema_chave)

  # A reunião entrou na agenda (tarefa criada ou movida): começa o ciclo de lembretes DESSA reunião (alvo = a tarefa).
  # 'assumido' = a decisão do evento que a pôs na agenda (código ou fluxos no comando).
  def na_agenda(tarefa, assumido)
    dados = { 'inicio' => tarefa.due_at.iso8601, 'quando' => Ramon::ReuniaoAgendamento.quando(tarefa.due_at),
              'lead_id' => tarefa.lead_id, 'assumido' => assumido }
    Ramon::Fluxos::Disparo.externo('reuniao_na_agenda', tarefa, dados)
  end
end

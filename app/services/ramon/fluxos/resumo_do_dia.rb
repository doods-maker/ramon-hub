# B5-conta (spec §8): o Resumo do dia pelo fluxo "Resumo do dia" (gatilho Horário da conta) ou pelo cron de sempre
# (Ramon::DailyDigestJob). Decisão do Eduardo 08/10: é a única rotina da conta que roda no fluxo; as outras 6 (retrato do
# funil, fechamento do extrato, espelho e avisos do Painel, copiloto noturno, publicar peças) são regra fixa — ficam no
# cron de sempre (config/schedule.yml), sem chave. A rotina pronta do passo é Passos::Rotina#resumo_do_dia.
# A chave é a da migração genérica (Migracao::GRUPOS['resumo_do_dia']): RAMON_FLUXO_RESUMO_DIA=on (ou o nome antigo,
# RAMON_FLUXO_ROTINAS) E o fluxo (origem usuario, sistema_chave = resumo_do_dia) ligado, publicado, em modo normal.
module Ramon::Fluxos::ResumoDoDia
  NOME = 'resumo_do_dia'.freeze

  module_function

  def migrado?(fluxo) = fluxo.origem == 'usuario' && fluxo.sistema_chave == NOME

  # O caminho de hoje para uma conta (a reserva do relógio).
  def pelo_codigo(account) = Ramon::DailyDigestJob.perform_later(account.id)

  # O job do código, conta a conta. Com account_id (o passo do fluxo ou a reserva): só aquela, sem perguntar. No cron:
  # pula a conta cujo fluxo está no comando; com o fluxo criado e fora do comando, faz só se pegar a vez dele
  # (HorarioConta.reivindicar — o relógio pode ter feito pelo código primeiro). Sem o fluxo: como sempre.
  def cada_conta(account_id = nil, &)
    return Account.where(id: account_id).find_each(&) if account_id

    agora = Time.find_zone!(Fluxo::ZONA).now
    Account.find_each { |account| yield account if do_codigo?(account, agora) }
  end

  def do_codigo?(account, agora)
    return false if Ramon::Fluxos::Migracao.assumiu?(account, NOME)

    fluxo = Ramon::Fluxos::Migracao.fluxo(account, NOME)
    fluxo.nil? || !disputa?(fluxo) || Ramon::Fluxos::HorarioConta.reivindicar(fluxo, agora)
  end

  # O relógio pegou a vez do fluxo migrado. No comando → o fluxo faz; não começou (ocupado — a execução de antes ainda
  # viva —, erro do motor) → o código faz (reserva). Fora do comando → o código faz nesta vez (o cron não a pega mais),
  # se o fluxo tem o ritmo do código (disputa?).
  def decidir(fluxo)
    no_comando = Ramon::Fluxos::Migracao.assumiu?(fluxo.account, NOME)
    return if no_comando && iniciar(fluxo)

    pelo_codigo(fluxo.account) if no_comando || disputa?(fluxo)
  end

  # Ruling F3: fora do comando, o horário do fluxo só vale para o código quando é o ritmo do próprio código — "por dia".
  # Fluxo editado para "a cada N min" em sombra: nem o relógio faz pelo código nem o cron disputa a vez — o cron faz 1 vez no dia.
  def disputa?(fluxo) = Ramon::Fluxos::HorarioConta.intervalo(Ramon::Fluxos::HorarioConta.config(fluxo)).nil?

  def iniciar(fluxo)
    Ramon::Fluxos::Disparo.new(fluxo, fluxo.account, { 'assumido' => true }, nil).iniciar
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: fluxo.account).capture_exception
    nil
  end
end

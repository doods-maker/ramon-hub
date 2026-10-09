# B5-conta (spec §8): o Resumo do dia como "Rotina pronta do hub" no gatilho Horário da conta — chama o MESMO job de hoje,
# só para esta conta (perform(account_id)). Decisão do Eduardo 08/10: é a única rotina da conta que roda no fluxo; as
# outras 6 (retrato do funil, fechamento do extrato, espelho e avisos do Painel, copiloto noturno, publicar peças) são
# regra fixa — ficam no cron de sempre (config/schedule.yml), sem chave.
# :agora roda dentro do passo (o "depois" do fluxo é depois de verdade).
# A chave é a da migração genérica (Migracao junta os GRUPOS daqui): RAMON_FLUXO_ROTINAS=on E o fluxo (origem usuario,
# sistema_chave = resumo_do_dia) ligado, publicado, em modo normal e no Horário da conta.
# Na carga este módulo não cita Ramon::Fluxos::Migracao (ela carrega este arquivo: autoload circular) — só dentro dos métodos.
module Ramon::Fluxos::Rotinas::Conta
  # nome → [job de hoje, :agora | :fila, env da chave, o que faz]
  JOBS = {
    'resumo_do_dia' => ['Ramon::DailyDigestJob', :agora, 'RAMON_FLUXO_ROTINAS', 'o resumo do dia']
  }.freeze
  ROTINAS = JOBS.transform_values { 'conta' }.freeze
  GRUPOS = JOBS.to_h { |nome, (_job, _modo, env, faz)| [nome, { env: env, faz: faz, fluxos: { nome => 'horario_conta' }.freeze }] }.freeze

  module_function

  def rodar(nome, ctx)
    job, modo, _env, faz = JOBS.fetch(nome)
    return "faria: #{faz}#{' (na fila)' if modo == :fila}" if ctx.ensaio?

    job.constantize.public_send(modo == :fila ? :perform_later : :perform_now, ctx.execucao.alvo_id)
    modo == :fila ? "pôs na fila: #{faz}" : "fez: #{faz}"
  end

  def migrado?(fluxo) = fluxo.origem == 'usuario' && JOBS.key?(fluxo.sistema_chave)

  # O caminho de hoje para uma conta (a reserva do relógio).
  def pelo_codigo(account, nome) = JOBS.fetch(nome).first.constantize.perform_later(account.id)

  # O job do código, conta a conta. Com account_id (o passo do fluxo ou a reserva): só aquela, sem perguntar. No cron:
  # pula a conta cujo fluxo está no comando; com o fluxo criado e fora do comando, faz só se pegar a vez dele
  # (HorarioConta.reivindicar — o relógio pode ter feito pelo código primeiro). Sem o fluxo: como sempre.
  def cada_conta(nome, account_id = nil, &)
    return Account.where(id: account_id).find_each(&) if account_id

    agora = Time.find_zone!(Fluxo::ZONA).now
    Account.find_each { |account| yield account if do_codigo?(account, nome, agora) }
  end

  def do_codigo?(account, nome, agora)
    return false if Ramon::Fluxos::Migracao.assumiu?(account, nome)

    fluxo = Ramon::Fluxos::Migracao.fluxo(account, nome)
    fluxo.nil? || !disputa?(fluxo) || Ramon::Fluxos::HorarioConta.reivindicar(fluxo, agora)
  end

  # O relógio pegou a vez do fluxo migrado. No comando → o fluxo faz; não começou (ocupado — a execução de antes ainda
  # viva —, erro do motor) → o código faz (reserva). Fora do comando → o código faz nesta vez (o cron não a pega mais),
  # se o fluxo tem o ritmo do código (disputa?).
  def decidir(fluxo)
    nome = fluxo.sistema_chave
    no_comando = Ramon::Fluxos::Migracao.assumiu?(fluxo.account, nome)
    return if no_comando && iniciar(fluxo)

    pelo_codigo(fluxo.account, nome) if no_comando || disputa?(fluxo)
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

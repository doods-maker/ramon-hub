# B5-conta (spec §8, decisão do Eduardo 07/10): as 7 rotinas da conta como "Rotina pronta do hub" no gatilho Horário da
# conta. Cada uma chama o MESMO job de hoje, só para esta conta (perform(account_id)): a lógica e as travas não mudam
# (avisos do Painel só com PORTAL_AVISOS=on; o Instagram só publica peça já agendada com "pode postar").
# :agora roda dentro do passo (o "depois" do fluxo é depois de verdade); :fila vai para a fila — espelho, copiloto e
# Instagram podem passar de 10 min, e o relógio acharia a execução órfã e repetiria o passo.
# A chave de cada uma é a da migração genérica (Migracao junta os GRUPOS daqui): env do grupo =on E o fluxo (origem
# usuario, sistema_chave = o nome da rotina) ligado, publicado, em modo normal e no Horário da conta.
# Na carga este módulo não cita Ramon::Fluxos::Migracao (ela carrega este arquivo: autoload circular) — só dentro dos métodos.
module Ramon::Fluxos::Rotinas::Conta
  # nome → [job de hoje, :agora | :fila, env da chave (T1: por família de risco), o que faz]
  JOBS = {
    'resumo_do_dia' => ['Ramon::DailyDigestJob', :agora, 'RAMON_FLUXO_ROTINAS', 'o resumo do dia'],
    'retrato_funil' => ['Ramon::DailyFunnelSnapshotJob', :agora, 'RAMON_FLUXO_ROTINAS', 'o retrato do funil'],
    'fechamento_extrato' => ['Ramon::ExtratoFechamentoJob', :agora, 'RAMON_FLUXO_ROTINAS', 'o fechamento do extrato'],
    'espelho_painel' => ['Ramon::PortalSyncJob', :fila, 'RAMON_FLUXO_ROTINAS', 'o espelho do Painel do Cliente'],
    'copiloto_noturno' => ['Ramon::NightCopilotJob', :fila, 'RAMON_FLUXO_ROTINAS', 'o copiloto noturno'],
    'publicar_pecas' => ['Ramon::PublicarPecasJob', :fila, 'RAMON_FLUXO_PUBLICAR_PECAS', 'a publicação das peças no Instagram'],
    'avisos_painel' => ['Ramon::PortalAvisosJob', :agora, 'RAMON_FLUXO_AVISOS_PAINEL', 'os avisos do Painel do Cliente']
  }.freeze
  ROTINAS = JOBS.transform_values { 'conta' }.freeze
  GRUPOS = JOBS.to_h { |nome, (_job, _modo, env, faz)| [nome, { env: env, faz: faz, fluxos: { nome => 'horario_conta' }.freeze }] }.freeze
  # N2: o fluxo "Publicar peças" (a cada minuto) só começa com peça vencida ou presa — sem 1.440 execuções vazias por dia.
  # Roda a cada minuto até meia-noite: pendente? é UMA consulta barata (exists?), nunca carrega coleção.
  PENDENTE = { 'publicar_pecas' => ->(account) { Ramon::PublicarPecasJob.pendente?(account) } }.freeze
  # As que o código já roda a cada minuto (o resto é 1 vez por dia).
  A_CADA_MINUTO = %w[publicar_pecas].freeze
  AVISOS_DESLIGADOS = 'avisos do Painel desligados até aprovar os textos (PORTAL_AVISOS) — nada enviado'.freeze

  module_function

  def rodar(nome, ctx)
    job, modo, _env, faz = JOBS.fetch(nome)
    return AVISOS_DESLIGADOS if nome == 'avisos_painel' && ENV.fetch('PORTAL_AVISOS', nil) != 'on'
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

  # Ruling F3: fora do comando, o horário do fluxo só vale para o código quando é o ritmo do próprio código — "por dia"
  # nas diárias, "a cada 1 min" no Publicar peças. Fluxo editado para outro ritmo em sombra: nem o relógio faz pelo
  # código nem o cron disputa a vez — o cron faz no ritmo de sempre (1 vez no dia; a cada minuto).
  def disputa?(fluxo)
    ritmo = A_CADA_MINUTO.include?(fluxo.sistema_chave) ? 1 : nil
    Ramon::Fluxos::HorarioConta.intervalo(Ramon::Fluxos::HorarioConta.config(fluxo)) == ritmo
  end

  def iniciar(fluxo)
    Ramon::Fluxos::Disparo.new(fluxo, fluxo.account, { 'assumido' => true }, nil).iniciar
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: fluxo.account).capture_exception
    nil
  end
end

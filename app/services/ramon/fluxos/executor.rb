# Anda uma execução de fluxo passo a passo (spec §6). Seguro para chamada dupla:
# reivindica a execução (esperando e vencida → rodando) numa transação curta e só
# então anda — os passos rodam fora de transação (cada um commita o seu).
# Passos lentos (IA, ADVBOX) também rodam fora de transação; a execução é gravada a cada passo.
# Esperar só anota retomar_em — quem retoma é o Ramon::FluxoRelogioJob.
class Ramon::Fluxos::Executor
  LIMITE_PASSOS = 50
  ESPERAS_ERRO = [1, 5, 15].freeze # minutos até a próxima tentativa
  VISIVEIS = %w[mover_etapa criar_tarefa acao_chatwoot avisar_sino avisar_push trocar_responsavel preencher_campo advbox webhook].freeze
  # tipo do passo → módulo que tem o método de mesmo nome (chamado por nome: dá pra stubar no spec)
  PASSOS = {
    'se' => Ramon::Fluxos::Passos::Logica, 'escolha' => Ramon::Fluxos::Passos::Logica,
    'esperar' => Ramon::Fluxos::Passos::Logica, 'parar' => Ramon::Fluxos::Passos::Logica,
    'rascunho_texto' => Ramon::Fluxos::Passos::Conversa, 'nota_privada' => Ramon::Fluxos::Passos::Conversa,
    'acao_chatwoot' => Ramon::Fluxos::Passos::Conversa,
    'mover_etapa' => Ramon::Fluxos::Passos::Lead, 'criar_tarefa' => Ramon::Fluxos::Passos::Lead,
    'registrar_atividade' => Ramon::Fluxos::Passos::Lead, 'trocar_responsavel' => Ramon::Fluxos::Passos::Lead,
    'preencher_campo' => Ramon::Fluxos::Passos::Lead,
    'advbox' => Ramon::Fluxos::Passos::Externo, 'webhook' => Ramon::Fluxos::Passos::Externo,
    'perguntar_ia' => Ramon::Fluxos::Passos::Ia, 'rascunho_ia' => Ramon::Fluxos::Passos::Ia, 'rodar_skill' => Ramon::Fluxos::Passos::Ia,
    'avisar_sino' => Ramon::Fluxos::Passos::Aviso, 'avisar_push' => Ramon::Fluxos::Passos::Aviso
  }.freeze

  def initialize(execucao)
    @execucao = execucao
  end

  def avancar!
    Current.executed_by = @execucao # os after_commit dos passos leem performed_by
    return @execucao unless reivindicar
    return @execucao if cancelar_se_preciso

    andar
    @execucao.save!
    avisar_falha if @execucao.status == 'falhou' && !@execucao.ensaio
    @execucao
  ensure
    Current.executed_by = nil
  end

  private

  def grafo = @grafo ||= @execucao.grafo

  # Troca esperando (vencida) → rodando numa transação curta: dois jobs nunca andam a mesma execução.
  def reivindicar
    ok = false
    @execucao.with_lock do
      next unless @execucao.status == 'esperando' && @execucao.retomar_em.present? && @execucao.retomar_em <= Time.current

      @execucao.update!(status: 'rodando', retomar_em: nil)
      ok = true
    end
    ok
  end

  # Roda já com status 'rodando' (reivindicada).
  def cancelar_se_preciso
    motivo = if @execucao.alvo.nil? then 'o lead/conversa foi apagado'
             elsif desligado? then 'o fluxo foi desligado'
             elsif saiu_da_etapa? then 'o lead saiu da etapa'
             end
    return false unless motivo

    @execucao.update!(status: 'cancelada', trilha: @execucao.trilha + [linha('cancelado', 'cancelado', "cancelado: #{motivo}")])
    true
  end

  def desligado? = !@execucao.ensaio && !@execucao.fluxo&.ativo

  def saiu_da_etapa?
    inicial = @execucao.contexto['etapa_inicial_id']
    return false if inicial.blank? || grafo.gatilho&.dig('config', 'cancelar_se_sair_da_etapa') == false

    lead = @execucao.lead
    lead.present? && lead.lead_stage_id != inicial
  end

  def andar
    LIMITE_PASSOS.times do
      passo = grafo.no(@execucao.no_atual)
      return @execucao.status = 'concluida' if passo.nil?

      resultado = executar(passo)
      return if resultado.nil? # erro: já ficou esperando nova tentativa ou falhou

      registrar(passo, resultado)
      return @execucao.status = 'concluida' if resultado[:parar]

      @execucao.no_atual = grafo.proximo(passo['id'], resultado[:saida])
      @execucao.save! # a cada passo, JÁ no próximo: o relógio só vê "órfã" se UM passo passar de 10 min (sem repetir o feito)
      return esperar(resultado[:esperar_ate]) if resultado[:esperar_ate] && !@execucao.contexto['pular_esperas']
    end
    @execucao.assign_attributes(status: 'falhou', erro: "passou de #{LIMITE_PASSOS} passos")
  end

  def executar(passo)
    resultado = PASSOS.fetch(passo['tipo']).public_send(passo['tipo'], passo['config'] || {}, Ramon::Fluxos::Contexto.new(@execucao))
    @execucao.tentativas = 0
    @execucao.contexto = @execucao.contexto.merge('vars' => (@execucao.contexto['vars'] || {}).merge(resultado[:vars] || {}))
    resultado
  rescue StandardError => e
    tratar_erro(passo, e)
    nil
  ensure
    Current.executed_by = @execucao # o ActionService dá Current.reset
  end

  def tratar_erro(passo, erro)
    espera = ESPERAS_ERRO[@execucao.tentativas] unless @execucao.ensaio || erro.is_a?(Ramon::Fluxos::PassoImpossivel)
    if espera
      @execucao.assign_attributes(tentativas: @execucao.tentativas + 1, status: 'esperando', retomar_em: espera.minutes.from_now)
    else
      @execucao.assign_attributes(status: 'falhou', erro: "#{passo['id']}: #{erro.message}".truncate(500))
      @execucao.trilha = @execucao.trilha + [linha(passo['id'], passo['tipo'], "erro: #{erro.message}".truncate(300), erro: true)]
    end
  end

  def esperar(ate)
    @execucao.assign_attributes(status: 'esperando', retomar_em: ate)
  end

  def registrar(passo, resultado)
    @execucao.trilha = @execucao.trilha + [linha(passo['id'], passo['tipo'], resultado[:resumo], saida: resultado[:saida])]
    return if @execucao.ensaio || VISIVEIS.exclude?(passo['tipo'])

    Ramon::EventoInline.registrar(@execucao.conversa, "⚙ Fluxo #{@execucao.fluxo&.nome}: #{resultado[:resumo]}", tipo: 'fluxo')
  end

  def linha(passo_id, tipo, resumo, saida: nil, erro: false)
    { 'no' => passo_id, 'tipo' => tipo, 'em' => Time.current.iso8601, 'saida' => saida, 'resumo' => resumo, 'erro' => erro }
  end

  def avisar_falha
    fluxo = @execucao.fluxo
    lead = @execucao.lead
    admins = fluxo.account.account_users.administrator.pluck(:user_id)
    if lead && admins.any? # lista vazia no builder vira "todo mundo"
      Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_falhou',
                                         meta: { 'label' => fluxo.nome }, user_ids: admins).perform
    end
    Ramon::NtfyPushJob.perform_later(title: "Fluxo falhou: #{fluxo.nome}", body: @execucao.erro.to_s.truncate(200))
  end
end

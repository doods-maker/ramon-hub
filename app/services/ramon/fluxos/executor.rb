# Anda uma execução de fluxo passo a passo (spec §6). Seguro para chamada dupla:
# trava a linha, só anda se estiver rodando/esperando E a espera venceu.
# Esperar só anota retomar_em — quem retoma é o Ramon::FluxoRelogioJob.
class Ramon::Fluxos::Executor
  LIMITE_PASSOS = 50
  ESPERAS_ERRO = [1, 5, 15].freeze # minutos até a próxima tentativa
  VISIVEIS = %w[mover_etapa criar_tarefa acao_chatwoot avisar_sino avisar_push].freeze
  # tipo do passo → módulo que tem o método de mesmo nome (chamado por nome: dá pra stubar no spec)
  PASSOS = {
    'se' => Ramon::Fluxos::Passos::Logica, 'escolha' => Ramon::Fluxos::Passos::Logica,
    'esperar' => Ramon::Fluxos::Passos::Logica, 'parar' => Ramon::Fluxos::Passos::Logica,
    'rascunho_texto' => Ramon::Fluxos::Passos::Conversa, 'nota_privada' => Ramon::Fluxos::Passos::Conversa,
    'acao_chatwoot' => Ramon::Fluxos::Passos::Conversa,
    'mover_etapa' => Ramon::Fluxos::Passos::Lead, 'criar_tarefa' => Ramon::Fluxos::Passos::Lead,
    'avisar_sino' => Ramon::Fluxos::Passos::Aviso, 'avisar_push' => Ramon::Fluxos::Passos::Aviso
  }.freeze

  def initialize(execucao)
    @execucao = execucao
  end

  def avancar!
    falhou = false
    Current.executed_by = @execucao # fica até depois do commit: os after_commit leem performed_by
    @execucao.with_lock do
      next unless pode_andar?
      next if cancelar_se_preciso

      @execucao.assign_attributes(status: 'rodando', retomar_em: nil)
      andar
      @execucao.save!
      falhou = @execucao.status == 'falhou' && !@execucao.ensaio
    end
    avisar_falha if falhou
    @execucao
  ensure
    Current.executed_by = nil
  end

  private

  def grafo = @grafo ||= @execucao.grafo

  def pode_andar?
    return true if @execucao.status == 'rodando'

    @execucao.status == 'esperando' && @execucao.retomar_em.present? && @execucao.retomar_em <= Time.current
  end

  def cancelar_se_preciso
    motivo = if @execucao.alvo.nil? then 'o lead/conversa foi apagado'
             elsif saiu_da_etapa? then 'o lead saiu da etapa'
             end
    return false unless motivo

    @execucao.update!(status: 'cancelada', retomar_em: nil,
                      trilha: @execucao.trilha + [linha('cancelado', 'cancelado', "cancelado: #{motivo}")])
    true
  end

  def saiu_da_etapa?
    inicial = @execucao.contexto['etapa_inicial_id']
    return false if @execucao.status != 'esperando' || inicial.blank?
    return false if grafo.gatilho&.dig('config', 'cancelar_se_sair_da_etapa') == false

    lead = @execucao.lead
    lead.present? && lead.lead_stage_id != inicial
  end

  def andar
    LIMITE_PASSOS.times do
      no = grafo.no(@execucao.no_atual)
      return @execucao.status = 'concluida' if no.nil?

      resultado = executar(no)
      return if resultado.nil? # erro: já ficou esperando nova tentativa ou falhou

      registrar(no, resultado)
      return @execucao.status = 'concluida' if resultado[:parar]

      @execucao.no_atual = grafo.proximo(no['id'], resultado[:saida])
      return esperar(resultado[:esperar_ate]) if resultado[:esperar_ate] && !@execucao.contexto['pular_esperas']
    end
    @execucao.assign_attributes(status: 'falhou', erro: "passou de #{LIMITE_PASSOS} passos")
  end

  def executar(no)
    Current.executed_by = @execucao
    # savepoint: erro de banco dentro do passo não envenena a transação do with_lock
    resultado = ActiveRecord::Base.transaction(requires_new: true) do
      PASSOS.fetch(no['tipo']).public_send(no['tipo'], no['config'] || {}, Ramon::Fluxos::Contexto.new(@execucao))
    end
    acompanhar_etapa(no)
    @execucao.tentativas = 0
    @execucao.contexto = @execucao.contexto.merge('vars' => (@execucao.contexto['vars'] || {}).merge(resultado[:vars] || {}))
    resultado
  rescue StandardError => e
    tratar_erro(no, e)
    nil
  ensure
    Current.executed_by = @execucao # o ActionService dá Current.reset
  end

  # mover_etapa do próprio fluxo não pode contar como "o lead saiu da etapa"
  def acompanhar_etapa(no)
    return if no['tipo'] != 'mover_etapa' || @execucao.ensaio

    @execucao.contexto = @execucao.contexto.merge('etapa_inicial_id' => @execucao.lead&.reload&.lead_stage_id)
  end

  def tratar_erro(no, erro)
    espera = ESPERAS_ERRO[@execucao.tentativas] unless @execucao.ensaio || erro.is_a?(Ramon::Fluxos::PassoImpossivel)
    if espera
      @execucao.assign_attributes(tentativas: @execucao.tentativas + 1, status: 'esperando', retomar_em: espera.minutes.from_now)
    else
      @execucao.assign_attributes(status: 'falhou', erro: "#{no['id']}: #{erro.message}".truncate(500))
      @execucao.trilha = @execucao.trilha + [linha(no['id'], no['tipo'], "erro: #{erro.message}".truncate(300), erro: true)]
    end
  end

  def esperar(ate)
    @execucao.assign_attributes(status: 'esperando', retomar_em: ate)
  end

  def registrar(no, resultado)
    @execucao.trilha = @execucao.trilha + [linha(no['id'], no['tipo'], resultado[:resumo], saida: resultado[:saida])]
    return if @execucao.ensaio || VISIVEIS.exclude?(no['tipo'])

    Ramon::EventoInline.registrar(@execucao.conversa, "⚙ Fluxo #{@execucao.fluxo.nome}: #{resultado[:resumo]}", tipo: 'fluxo')
  end

  def linha(no, tipo, resumo, saida: nil, erro: false)
    { 'no' => no, 'tipo' => tipo, 'em' => Time.current.iso8601, 'saida' => saida, 'resumo' => resumo, 'erro' => erro }
  end

  def avisar_falha
    fluxo = @execucao.fluxo
    lead = @execucao.lead
    if lead
      admins = fluxo.account.account_users.administrator.pluck(:user_id)
      Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_falhou',
                                         meta: { 'label' => fluxo.nome }, user_ids: admins).perform
    end
    Ramon::NtfyPushJob.perform_later(title: "Fluxo falhou: #{fluxo.nome}", body: @execucao.erro.to_s.truncate(200))
  end
end

# Operação com SDR + Closer (playbook operacional §13): atribuição automática,
# reunião qualificada e carimbos do contrato limpo.
# Extraído do Lead pra caber no Metrics/ClassLength (mesmo precedente do LeadDocs).
module LeadComercial
  extend ActiveSupport::Concern

  REUNIAO_RESULTADOS = %w[qualificada nao_qualificada].freeze
  ETAPA_REUNIAO_REALIZADA = 'fase-reuniao-realizada'.freeze

  included do
    before_create :assign_sdr
    before_save :stamp_docs_completos, if: -> { new_record? || will_save_change_to_custom_attributes? || will_save_change_to_thesis_id? }
    after_save :cancelar_contrato_limpo, if: -> { saved_change_to_won_at? && won_at.nil? && contrato_limpo_em.present? }
    after_save :registrar_contrato_cancelado, if: -> { saved_change_to_won_at? && won_at.nil? }
    after_commit :verificar_registro_completo, on: [:create, :update], if: -> { saved_change_to_thesis_id? || saved_change_to_contact_id? }
    after_commit :assign_conversation_to_sdr, on: [:create, :update],
                                              if: -> { saved_change_to_sdr_id? || saved_change_to_conversation_id? }
    # Registro de ações (audits, somente-inclusão, 5 anos): etapa, ganho/perda,
    # valor e dono do lead, e a exclusão. Aqui e não no Lead (no teto do
    # ClassLength). contact_id fica no destroy para a tela saber de quem era.
    # contrato_cancelado_em é update_columns (sem callback): o cancelamento
    # aparece como won_at → nil na mesma linha da troca de etapa.
    audited only: %w[lead_stage_id value sdr_id closer_id won_at lost_reason contact_id],
            on: [:update, :destroy], associated_with: :account
    # Perdido exige motivo (regra 06/10), de qualquer pessoa, admin inclusive. Ponto
    # único: tela, API, lote e IA passam por aqui; o controller devolve 422.
    before_validation :motivo_da_perda_automatico, if: :sem_motivo_da_perda?
    validate :exigir_motivo_da_perda, if: :sem_motivo_da_perda?
  end

  # Closer registra a reunião (regulamento §2): qualificada ou não. A 1ª data
  # vale (correção não muda o mês da apuração); quem marca vira Closer se o lead
  # não tinha; o lead anda pra "Reunião realizada", nunca volta. A tarefa da
  # reunião (a informada, senão a aberta mais antiga até hoje) é concluída.
  # vou_pensar: o cliente vai pensar — marca à parte (atividade), NUNCA um 3º
  # resultado: a qualificação é o que paga o SDR e não muda por isso.
  def registrar_reuniao!(resultado, user, task: nil, vou_pensar: false)
    attrs = { reuniao_resultado: resultado, reuniao_registrada_em: reuniao_registrada_em || Time.current }
    attrs[:closer] = user if closer_id.blank?
    stage = account.lead_stages.find_by(label: ETAPA_REUNIAO_REALIZADA)
    attrs[:lead_stage] = stage if stage && lead_stage.position < stage.position
    update!(attrs)
    registrar_atividades_da_reuniao(resultado, user, vou_pensar)
    (task || reuniao_em_aberto)&.complete!(user)
  end

  def comercial_event_data
    {
      reuniao_resultado: reuniao_resultado,
      reuniao_registrada_em: reuniao_registrada_em&.iso8601,
      docs_completos_em: docs_completos_em&.iso8601,
      contrato_limpo_em: contrato_limpo_em&.iso8601,
      # selo do contrato ZapSign no card do funil (o índice é slim, sem o jsonb)
      zapsign_status: custom_attributes&.dig('zapsign', 'status'),
      zapsign_assinado_em: custom_attributes&.dig('zapsign', 'assinado_em')
    }
  end

  private

  # Entrando em Perdido (ou apagando o motivo lá dentro) sem motivo.
  def sem_motivo_da_perda?
    return false if lost_reason.present?

    (new_record? || will_save_change_to_lead_stage_id? || will_save_change_to_lost_reason?) && lead_stage&.is_lost
  end

  # Automação não abre janela: fluxo, regra do Chatwoot, IA ou job sem pessoa
  # gravam "Automação: <origem>" em vez de quebrar. Pessoa sem motivo → 422.
  def motivo_da_perda_automatico
    autor = Current.executed_by
    return if autor.blank? && Current.user.present?

    self.lost_reason = "Automação: #{autor.try(:fluxo).try(:nome) || autor.try(:name) || 'sistema'}"
  end

  def exigir_motivo_da_perda
    errors.add(:base, 'Escolha o motivo da perda para marcar o lead como perdido.')
  end

  def registrar_atividades_da_reuniao(resultado, user, vou_pensar)
    lead_activities.create!(account: account, user: user, kind: 'reuniao_registrada', to_value: resultado)
    lead_activities.create!(account: account, user: user, kind: 'vou_pensar') if vou_pensar
  end

  # Reunião que acabou de acontecer: aberta, marcada até o fim de hoje (a
  # futura, de outra conversa já marcada, não é fechada por engano).
  def reuniao_em_aberto
    lead_tasks.open_tasks.where(kind: 'meeting', due_at: ..Time.current.in_time_zone('America/Sao_Paulo').end_of_day)
              .order(:due_at).first
  end

  # Lead novo de qualquer canal vai pro SDR com menos leads abertos.
  # Import e caso de cálculo ficam de fora.
  def assign_sdr
    return if sdr_id.present? || source == Lead::FONTE_CALCULO || Current.suppress_import_events

    self.sdr = Ramon::Papeis.proximo(account, Ramon::Papeis::SDR)
  end

  # Conversa sem responsável vira do SDR do lead ("Minhas" + notificações
  # nativas do Chatwoot). Nunca tira a conversa de quem já a assumiu.
  def assign_conversation_to_sdr
    return if sdr_id.blank? || conversation.blank? || conversation.assignee_id.present?

    conversation.update!(assignee_id: sdr_id)
  end

  # Saiu de Fechado depois de limpo (regulamento §5.2): apaga o carimbo (se
  # voltar a fechar, carimba de novo na data nova) e registra quando — base do
  # desconto na apuração seguinte se a unidade já estava num extrato fechado
  # (Ramon::ExtratoDescontos). Mês fechado não muda. after_save: o won_at só
  # zera no track_stage_cycle do Lead, que roda depois dos before_save daqui.
  def cancelar_contrato_limpo
    update_columns(contrato_cancelado_em: Time.current, contrato_limpo_em: nil) # rubocop:disable Rails/SkipsModelValidations
  end

  # Saiu de Fechado (Painel do time, KPI "cancelamento em 7 dias"): o won_at
  # volta a nil no track_stage_cycle; a atividade guarda o won_at antigo em
  # from_value — é dele que o KPI conta os 7 dias. Vale daqui pra frente.
  def registrar_contrato_cancelado
    lead_activities.create!(account: account, user: Current.user, kind: 'contrato_cancelado',
                            from_value: saved_change_to_won_at.first&.iso8601)
  end

  def verificar_registro_completo = Ramon::RegistroCompleto.verificar(self)

  # Documentos mínimos = checklist inteira da tese "recebido" (decisão 02/10).
  # Carimba o momento em que completou; desmarcar um item apaga o carimbo.
  def stamp_docs_completos
    counts = docs_counts
    completo = counts[:total].positive? && counts[:received] == counts[:total]
    self.docs_completos_em = completo ? (docs_completos_em || Time.current) : nil
  end
end

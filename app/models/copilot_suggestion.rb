# Sugestão do copiloto noturno (mock 4b) e das tools de escrita do agente
# (Fatia 2 da área de IA): a IA prepara, o humano aprova. NADA é enviado ao
# cliente — aplicar um rascunho vira NOTA RASCUNHO no painel do lead; quem
# envia é o Eduardo. As sugestões do tipo 'acao' executam uma ação em sistema
# real (ZapSign, AdvBox, Esteira) SOMENTE quando o humano clica em aplicar.
class CopilotSuggestion < ApplicationRecord
  KINDS = %w[draft move_stage alert acao].freeze
  ACOES = %w[zapsign advbox reuniao perdido].freeze
  STATUSES = %w[pending applied dismissed].freeze

  belongs_to :account
  belongs_to :lead

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }

  # Motivo da última recusa de apply! — o controller devolve isso ao humano.
  attr_reader :motivo_da_recusa

  # Aplica a sugestão. Retorna false quando a ação não pôde ser executada
  # (etapa que não resolve pelo nome, ZapSign fora do ar, caso ainda não
  # ganho): a sugestão continua pendente e o olho humano decide.
  def apply!(user: nil)
    # Idempotência: aplicar de novo (clique duplo / apply_all repetido) não
    # duplica nota nem re-move etapa.
    return false unless status == 'pending'
    return false unless executar(user)

    update!(status: 'applied')
    true
  end

  private

  def executar(user)
    case kind
    when 'draft' then criar_nota(user, draft_note_body)
    when 'move_stage' then mover_etapa
    when 'acao' then executar_acao(user)
    else true # alert: não tem ação, aplicar só arquiva o cartão
    end
  end

  # A LLM nunca marca ganho/perdido: só etapa aberta resolve por nome.
  def mover_etapa
    stage = account.lead_stages.where(is_won: false, is_lost: false).find_by(name: payload['etapa_sugerida'])
    return recusar('Etapa sugerida não encontrada no funil — mova manualmente') if stage.blank?

    lead.update!(lead_stage_id: stage.id)
  end

  def executar_acao(user)
    case payload['acao']
    when 'zapsign' then preparar_zapsign(user)
    when 'advbox' then abrir_caso_advbox(user)
    when 'reuniao' then agendar_reuniao(user)
    when 'perdido' then marcar_perdido
    else recusar('Ação desconhecida nesta sugestão')
    end
  end

  # O documento nasce aqui, não na hora em que a IA sugeriu. Nada é enviado ao
  # cliente: o ZapSign devolve o link e ele vira nota no caso.
  def preparar_zapsign(user)
    stored = Ramon::ZapsignContractService.new(lead).perform
    faltando = stored['faltando'].presence
    criar_nota(user, "Contrato preparado no ZapSign: #{stored['sign_url']}" \
                     "#{faltando ? "\nFalta preencher: #{faltando.join(', ')}" : ''}")
  rescue Ramon::ZapsignClient::RequestError, Ramon::ZapsignClient::UnavailableError => e
    recusar("O ZapSign recusou ou não respondeu: #{e.message.to_s.truncate(120)}")
  end

  # Mesmo caminho do fechamento automático (Lead#enqueue_advbox_closing): job
  # com retry, não chamada síncrona no clique do humano.
  def abrir_caso_advbox(user)
    return recusar('O caso ainda não está marcado como ganho') if lead.won_at.blank?

    Ramon::AdvboxClosingJob.perform_later(lead.id)
    criar_nota(user, "Abertura do caso no AdvBox enfileirada para #{lead.name}.")
  end

  def agendar_reuniao(user)
    horario = begin
      Time.zone.parse(payload['quando'].to_s)
    rescue ArgumentError
      nil
    end
    return recusar('A sugestão não trouxe data válida para a reunião') if horario.blank?

    lead.lead_tasks.create!(account: account, user: user, kind: 'meeting',
                            title: payload['titulo'].presence || 'Reunião de fechamento', due_at: horario)
    true
  end

  # Perdido e reversivel no Kanban (arrastar de volta), mas so o humano decide.
  def marcar_perdido
    return recusar('O caso ja esta ganho — nao da para marcar perdido') if lead.won_at.present?
    return recusar('O caso ja esta marcado como perdido') if lead.lost_at.present?

    etapa = account.lead_stages.find_by(is_lost: true)
    return recusar('Nao ha etapa de perdido configurada no funil') if etapa.blank?

    lead.update!(lead_stage: etapa, lost_reason: payload['lost_reason'].presence || 'Sugerido pelo agente')
  end

  def criar_nota(user, body)
    lead.lead_notes.create!(account: account, user: user, body: body.truncate(1000))
    true
  end

  def recusar(motivo)
    @motivo_da_recusa = motivo
    false
  end

  # mesmo prefixo do FollowUpDraftService: a nota nasce e morre RASCUNHO
  def draft_note_body
    "RASCUNHO (revisar antes de enviar) — copiloto noturno:\n#{payload['texto']}"
  end
end

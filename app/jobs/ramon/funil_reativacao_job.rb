# Reativação de perdidos por sumiço (seg-sex, 10h SP): aos 30 e 60 dias da perda, nota-rascunho de retomada + tarefa
# de follow-up pro SDR. NUNCA envia ao cliente. A janela de 3 dias (não só "exatamente N dias") cobre fim de semana e
# feriado; a idempotência vem da FunilAcao (acao 'reativar', alvo '30'|'60'), contando o ensaio também.
class Ramon::FunilReativacaoJob < ApplicationJob
  queue_as :low

  MOTIVO = 'Sumiu / não respondeu'.freeze
  DIAS = [30, 60].freeze
  JANELA = 3
  FUSO = ActiveSupport::TimeZone['America/Sao_Paulo']

  def perform
    Account.find_each do |account|
      next if Ramon::FunilAutomatico.modo(account, 'reativacao') == 'off'

      DIAS.each do |dias|
        perdidos(account, dias).find_each do |lead|
          reativar(lead, dias)
        rescue StandardError => e
          ChatwootExceptionTracker.new(e, account: account).capture_exception
          Rails.logger.error("FunilReativacaoJob: lead #{lead.id} falhou (#{e.class})") # sem e.message (LGPD)
        end
      end
    end
  end

  private

  def perdidos(account, dias)
    hoje = FUSO.today
    janela = (hoje - dias - JANELA).in_time_zone(FUSO).beginning_of_day..(hoje - dias).in_time_zone(FUSO).end_of_day
    Lead.where(account: account, lost_reason: MOTIVO, won_at: nil, lost_at: janela)
  end

  def reativar(lead, dias)
    return if FunilAcao.exists?(lead: lead, acao: 'reativar', alvo: dias.to_s)

    # o hash é gravado na FunilAcao depois do bloco: a tarefa só nasce dentro dele, então o id entra aqui
    desfazer = {}
    Ramon::FunilAutomatico.executar(lead, peca: 'reativacao', acao: 'reativar', motivo: "Perdido por sumiço há #{dias} dias",
                                          alvo: dias.to_s, desfazer: desfazer) do
      task = lead.lead_tasks.create!(account: lead.account, user: lead.sdr || lead.closer, kind: 'follow_up',
                                     title: "Retomar contato (#{dias} dias)", due_at: FUSO.now.change(hour: 10))
      desfazer['task_id'] = task.id
      lead.lead_notes.create!(account: lead.account, body: rascunho(lead))
    end
  end

  def rascunho(lead)
    nome = lead.name.to_s.split.first.presence || 'cliente'
    "RASCUNHO (revisar antes de enviar) — retomada:\n" \
      "\"Oi #{nome}, tudo bem? Passando pra saber se você ainda quer ajuda com o seu caso. " \
      'Se fizer sentido, é só me responder por aqui que a gente retoma de onde parou."'
  end
end

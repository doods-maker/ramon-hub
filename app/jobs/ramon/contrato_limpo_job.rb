# Contrato limpo (regulamento de remuneração §2; playbook §13, item 5):
# assinado (won_at) + checklist completa (docs_completos_em) + 7 dias corridos
# sem cancelamento. O carimbo é o momento EXATO em que ficou limpo (o mais
# tardio dos dois marcos), não a hora em que o job rodou — o mês da apuração
# fica certo mesmo na virada. Uma vez carimbado não muda mais (extrato estável).
# Cancelar em até 7 dias = sair de Fechado (won_at volta a nil) → nunca carimba.
class Ramon::ContratoLimpoJob < ApplicationJob
  queue_as :scheduled_jobs

  CARIMBO_SQL = "GREATEST(won_at + INTERVAL '7 days', docs_completos_em)".freeze

  def perform
    Lead.funil.reorder(nil)
        .where(contrato_limpo_em: nil)
        .where.not(won_at: nil)
        .where.not(docs_completos_em: nil)
        .where("#{CARIMBO_SQL} <= ?", Time.current)
        .update_all("contrato_limpo_em = #{CARIMBO_SQL}") # rubocop:disable Rails/SkipsModelValidations
  end
end

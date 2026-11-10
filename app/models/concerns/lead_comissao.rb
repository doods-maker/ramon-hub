# O que protege a comissão depois que o contrato fechou (Ramon::ExtratoVariavel e Ramon::FatorTrimestre leem daqui):
# a tese do lead apto e o carimbo de cancelamento. Separado do LeadComercial, que está no teto do Metrics/ModuleLength.
module LeadComissao
  extend ActiveSupport::Concern

  # Arrasto por engano: saiu de Fechado e voltou dentro deste prazo. Depois dele o cancelamento fica (já pode ter
  # entrado na apuração do trimestre).
  PRAZO_DO_ENGANO = 24.hours

  included do
    # Depois do apto a comissão do contrato sai da tese do lead: só o gestor troca. Ponto único, como o motivo da
    # perda: tela, API, roteiro e IA passam por aqui (job e IA não têm gestor: não trocam).
    validate :tese_travada_pelo_apto, if: -> { persisted? && will_save_change_to_thesis_id? && apto_em_in_database.present? }
    after_save :desfazer_cancelamento_por_engano, if: -> { saved_change_to_won_at? && won_at.present? && contrato_cancelado_em.present? }
  end

  private

  def tese_travada_pelo_apto
    return if Current.account_user&.administrator?

    errors.add(:base, 'Contrato já apto: só o gestor troca a tese.')
  end

  # A atividade `contrato_cancelado` (LeadComercial) continua no histórico do lead.
  def desfazer_cancelamento_por_engano
    update_columns(contrato_cancelado_em: nil) if contrato_cancelado_em > PRAZO_DO_ENGANO.ago # rubocop:disable Rails/SkipsModelValidations
  end
end

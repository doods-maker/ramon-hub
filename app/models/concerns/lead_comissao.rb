# O que protege a comissão depois que o contrato fechou (Ramon::ExtratoVariavel e Ramon::FatorTrimestre leem daqui):
# a tese do lead apto e o carimbo de cancelamento. Separado do LeadComercial, que está no teto do Metrics/ModuleLength.
module LeadComissao
  extend ActiveSupport::Concern

  # Arrasto por engano: saiu de Fechado e voltou dentro deste prazo. Depois dele o cancelamento fica (já pode ter
  # entrado na apuração do trimestre).
  PRAZO_DO_ENGANO = 24.hours
  ORIGEM_IA = 'reuniao_ia_em'.freeze # chave do jsonb que só o servidor grava (fora de ATRIBUTOS_DA_TELA)

  included do
    # Depois do apto a comissão do contrato sai da tese do lead: só o gestor troca. Ponto único, como o motivo da
    # perda: tela, API, roteiro e IA passam por aqui (job e IA não têm gestor: não trocam).
    validate :tese_travada_pelo_apto, if: -> { persisted? && will_save_change_to_thesis_id? && apto_em_in_database.present? }
    after_save :desfazer_cancelamento_por_engano, if: -> { saved_change_to_won_at? && won_at.present? && contrato_cancelado_em.present? }
  end

  # Ramon::ReuniaoAgendamento chama quando quem marca não é pessoa (IA, automação), com o código ou os fluxos no
  # comando. Direto no banco, só esta chave: sem callbacks do lead e sem pisar nas outras chaves do jsonb.
  def marcar_reuniao_da_ia!
    sql = "custom_attributes = jsonb_set(COALESCE(custom_attributes, '{}'::jsonb), '{#{ORIGEM_IA}}', to_jsonb(?::text))"
    self.class.where(id: id).update_all([sql, Time.current.iso8601]) # rubocop:disable Rails/SkipsModelValidations
    self.custom_attributes = (custom_attributes || {}).merge(ORIGEM_IA => Time.current.iso8601)
    clear_attribute_changes([:custom_attributes])
  end

  private

  def tese_travada_pelo_apto
    return if Current.account_user&.administrator?

    errors.add(:base, 'Contrato já apto: só o gestor troca a tese.')
  end

  # Prêmio do SDR (decisão 10/11/2026), contra manipulação: só existe resultado de reunião que esteve na agenda (aberta,
  # concluída ou marcada para depois, tanto faz), e resultado já registrado só o gestor corrige. O gestor passa direto.
  def conferir_registro_da_reuniao!(task, resultado)
    erro = erro_no_registro_da_reuniao(task, resultado)
    return if erro.nil? || Current.account_user&.administrator?

    errors.add(:base, erro)
    raise ActiveRecord::RecordInvalid, self
  end

  def erro_no_registro_da_reuniao(task, resultado)
    return 'Resultado da reunião já registrado: só o gestor corrige.' if reuniao_resultado.present? && reuniao_resultado != resultado

    'Marque a reunião na agenda antes de registrar o resultado.' if task.nil? && !lead_tasks.exists?(kind: 'meeting')
  end

  # Da IA/automação: a tarefa nasceu sem criador, ou algum lead do mesmo contato já teve reunião marcada sem pessoa
  # (carimbo de `marcar_reuniao_da_ia!`; antes dele, a atividade `meeting_scheduled`). Cancelar a reunião da IA e
  # remarcar à mão, apagar a tarefa ou abrir outro lead do mesmo contato não muda a origem.
  def reuniao_da_ia?(task)
    return true if task.present? && task.user_id.nil?

    do_contato = contact_id ? account.leads.where(contact_id: contact_id) : account.leads.where(id: id)
    do_contato.exists?(['jsonb_exists(leads.custom_attributes, ?)', ORIGEM_IA]) ||
      LeadActivity.unscoped.exists?(lead_id: do_contato.select(:id), kind: 'meeting_scheduled', user_id: nil)
  end

  # A atividade `contrato_cancelado` (LeadComercial) continua no histórico do lead.
  def desfazer_cancelamento_por_engano
    update_columns(contrato_cancelado_em: nil) if contrato_cancelado_em > PRAZO_DO_ENGANO.ago # rubocop:disable Rails/SkipsModelValidations
  end
end

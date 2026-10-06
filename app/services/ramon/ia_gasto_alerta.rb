# Alerta de gasto da IA (tela Uso e custo): o custo do dia passou do teto em US$ da conta →
# sino dos administradores, UMA vez por dia (chave no Redis). Roda a cada chamada gravada
# com custo (Ramon::LlmUso). Teto em accounts.settings; vazio = sem alerta.
# O agente @claude fica de fora: custo nominal da assinatura, não cobra por chamada.
module Ramon::IaGastoAlerta
  CHAVE_TETO = 'ramon_ia_teto_diario_usd'.freeze

  module_function

  def teto(account) = account.settings&.dig(CHAVE_TETO).presence&.to_f

  def hoje = Time.find_zone!(Ramon::CockpitMetrics::TIME_ZONE).now.all_day

  def gasto_hoje(account_id) = LlmChamada.where(account_id: account_id, created_at: hoje).sum(:custo_usd).to_f

  def verificar(chamada)
    return if chamada.custo_usd.to_f.zero?

    account = chamada.account
    limite = teto(account)
    return if limite.nil? || limite <= 0

    gasto = gasto_hoje(account.id)
    return if gasto <= limite
    return unless Redis::Alfred.set(chave(account.id), 1, nx: true, ex: 2.days.to_i)

    avisar(account, chamada, format('US$ %<gasto>.2f (teto US$ %<teto>.2f)', gasto: gasto, teto: limite).tr('.', ','))
  end

  def chave(account_id) = "RAMON::IA_GASTO::#{account_id}::#{Time.find_zone!(Ramon::CockpitMetrics::TIME_ZONE).today}"

  def avisar(account, chamada, rotulo)
    User.where(id: Ramon::Papeis.gestor_ids(account)).find_each do |user|
      user.notifications.create!(notification_type: 'ramon_ia_gasto', account: account, primary_actor: chamada,
                                 meta: { 'label' => rotulo })
    end
  end
end

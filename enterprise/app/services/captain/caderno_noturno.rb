# Caderno de provas automático (Inteligência A5 — I-X6): para cada assistente com casos ativos, enfileira uma rodada
# dos Casos de teste (modo teste: só consulta executa, nada é gravado nem enviado) — se a chave da conta estiver
# ligada, se o gasto do dia mais o custo estimado da rodada não passa do teto e se algo mudou desde a última rodada
# concluída (decisão N3). Sem disparado_por = rodada da madrugada.
class Captain::CadernoNoturno
  def self.ligado?(account)
    ActiveModel::Type::Boolean.new.cast(account.settings&.dig(Ramon::CadernoNoturnoJob::CHAVE)) == true
  end

  def initialize(account)
    @account = account
    @previsto = nil
  end

  def perform
    return [] unless self.class.ligado?(@account)
    return [] if Ramon::IaGastoAlerta.passou_do_teto?(@account)

    Captain::Assistant.for_account(@account.id).order(:id).filter_map { |assistant| enfileirar(assistant) }
  end

  private

  # ponytail: gêmea de Api::V1::Accounts::Captain::IaRodadasController#create (destravar → ativas → total → create →
  # perform_later → RecordNotUnique); o controller tem as próprias respostas 409/422, então não extraí. Mudou lá, mude aqui.
  def enfileirar(assistant)
    Captain::IaRodada.destravar!(assistant.id)
    return if Captain::IaRodada.ativas.exists?(assistant_id: assistant.id)

    total = Captain::IaCaso.ativos.where(assistant_id: assistant.id).count
    return if total.zero? || !mudou?(assistant) || estoura_teto?(total)

    rodada = Captain::IaRodada.create!(account: @account, assistant: assistant, total: total)
    Captain::IaRodadaJob.perform_later(rodada.id)
    rodada
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # F5: o custo estimado da rodada também não pode estourar o teto — somado ao gasto de hoje e às rodadas já
  # enfileiradas nesta madrugada (@previsto); só entra no previsto quem de fato foi enfileirado.
  def estoura_teto?(total)
    limite = Ramon::IaGastoAlerta.teto(@account)
    custo = Captain::IaRodada.estimativa(total)[:custo_usd]
    @previsto ||= Ramon::IaGastoAlerta.gasto_hoje(@account.id)
    return true if limite.to_f.positive? && @previsto + custo > limite

    @previsto += custo
    false
  end

  # Mudou = o assistente (configurações, regras), uma skill, uma FAQ aprovada ou um caso de teste mexidos depois
  # da última rodada concluída. Sem rodada anterior conta como mudou. (O contador de uso da FAQ não mexe em updated_at.)
  def mudou?(assistant)
    ultima = Captain::IaRodada.where(assistant_id: assistant.id, status: 'concluida').maximum(:created_at)
    return true if ultima.nil?

    [assistant.updated_at, assistant.scenarios.maximum(:updated_at), assistant.responses.approved.maximum(:updated_at),
     Captain::IaCaso.where(assistant_id: assistant.id).maximum(:updated_at)].compact.max > ultima
  end
end

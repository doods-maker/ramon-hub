# Ponto único das ações automáticas do funil: lê a chave da peça (off/ensaio/on em account.settings), registra em
# FunilAcao e só então aplica. Toda peça nova passa por aqui; padrão = off.
class Ramon::FunilAutomatico
  CHAVE = 'funil_automatico'.freeze
  MODOS = %w[off ensaio on].freeze
  PECAS = %w[etapa_ia perdido_recusa reuniao_ia colheita promessas pendencias temperatura
             zapsign_negociacao zapsign_ganho tempo_ultima_chance tempo_perdido no_show reativacao].freeze

  def self.modo(account, peca)
    valor = account.settings&.dig(CHAVE, peca.to_s)
    MODOS.include?(valor) ? valor : 'off'
  end

  def self.mudar!(account, peca, modo)
    raise ArgumentError, "peça inválida: #{peca}" unless PECAS.include?(peca.to_s)
    raise ArgumentError, "modo inválido: #{modo}" unless MODOS.include?(modo.to_s)

    settings = account.settings || {}
    account.update!(settings: settings.merge(CHAVE => (settings[CHAVE] || {}).merge(peca.to_s => modo.to_s)))
  end

  # Devolve a FunilAcao gravada, ou nil (off, ou o bloco devolveu false = nada foi feito).
  def self.executar(lead, peca:, acao:, motivo:, alvo: nil, desfazer: {}) # rubocop:disable Metrics/ParameterLists
    atual = modo(lead.account, peca)
    return if atual == 'off'

    dados = { account: lead.account, lead: lead, peca: peca.to_s, acao: acao, motivo: motivo.to_s.truncate(250),
              alvo: alvo&.to_s, desfazer: desfazer }
    return FunilAcao.create!(**dados, ensaio: true) if atual == 'ensaio'

    FunilAcao.transaction do
      next if yield == false

      # a "marca de que foi a IA" no histórico do lead
      LeadActivity.create!(account: lead.account, lead: lead, user: Current.user, kind: 'funil_auto',
                           to_value: "#{acao}: #{motivo}".truncate(250))
      FunilAcao.create!(**dados, ensaio: false)
    end
  end

  # Alguém desfez esta ação e o lead não escreveu de novo desde então: a IA não deve refazer.
  def self.desfeita_recente?(lead, acao:, alvo:)
    desfeitas = FunilAcao.where(lead: lead, acao: acao, alvo: alvo&.to_s).where.not(desfeita_em: nil)
    ultima = lead.conversation&.last_incoming_message
    desfeitas = desfeitas.where('desfeita_em > ?', ultima.created_at) if ultima
    desfeitas.exists?
  end
end

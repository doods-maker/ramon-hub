# Etapas de ganho depois de Fechado (ADR 0015): Documentos (o agente de documentos conduz a pasta) e Jurídico
# (a esteira do jurídico). Idempotente: reaproveita pelo label e só reposiciona o que mudou. Sem `nome_cliente`:
# texto que o cliente lê no portal é gate do Eduardo.
# ponytail: conta nova não ganha as duas pelo seed — fork de uma conta só; levar ao seed se surgir 2ª conta.
module Ramon::EtapasPosVenda
  ETAPAS = [
    { label: Ramon::EtapaDeGanho::DOCUMENTOS, name: 'Documentos', color: '#14b8a6' },
    { label: Ramon::EtapaDeGanho::JURIDICO, name: 'Jurídico', color: '#0ea5e9' }
  ].freeze

  module_function

  def criar!(account)
    account.transaction do
      fechado = account.lead_stages.find_by!(label: Ramon::EtapaDeGanho::FECHADO)
      novas = ETAPAS.map { |attrs| criar_etapa!(account, attrs) }
      reposicionar!(account, fechado, novas)
      novas
    end
  end

  def criar_etapa!(account, attrs)
    account.lead_stages.find_or_create_by!(label: attrs[:label]) do |stage|
      stage.assign_attributes(name: attrs[:name], color: attrs[:color], is_won: true, probability: 100)
    end
  end

  # As novas logo depois de Fechado; as seguintes (Perdido) andam para depois delas.
  def reposicionar!(account, fechado, novas)
    ordem = account.lead_stages.where.not(id: novas.map(&:id)).to_a
    ordem.insert(ordem.index(fechado) + 1, *novas)
    ordem.each_with_index do |stage, position|
      stage.update_columns(position: position) if stage.position != position # rubocop:disable Rails/SkipsModelValidations
    end
  end
end

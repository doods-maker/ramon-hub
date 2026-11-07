# Onde o ganho entra, agora que a conta tem várias etapas de ganho (ADR 0015). Quem precisa de "a etapa de ganho"
# (ZapSign assinado, contrato fechado no ADVBOX, importação, fluxo dos eventos ADVBOX) pergunta aqui, nunca
# `find_by(is_won: true)`: com Documentos e Jurídico antes de Fechado na ordem, aquilo cai na etapa errada.
# "Está ganho" continua sendo qualquer etapa `is_won`.
module Ramon::EtapaDeGanho
  FECHADO = 'fase-fechado'.freeze
  DOCUMENTOS = 'fase-documentos'.freeze
  JURIDICO = 'fase-juridico'.freeze
  # Etapas de ganho que a IA conduz e onde envia sozinha (spec §2), com gatilhos próprios na tela "Como a IA atende".
  CONDUZIDAS = [DOCUMENTOS].freeze

  module_function

  # Chave da Etapa Documentos (ENV direto, padrão dos RAMON_*): desligada, tudo como antes do PR 2.
  def documentos_ligado? = ENV.fetch('RAMON_ETAPA_DOCUMENTOS', nil) == 'on'

  # Chave desligada: nenhuma é conduzida (são pós-venda como as outras, :fechado no Perfil da IA).
  def conduzida?(etapa) = etapa&.is_won == true && CONDUZIDAS.include?(etapa.label) && documentos_ligado?

  # As conduzidas que a conta tem, na ordem do funil; chave desligada = nenhuma.
  def conduzidas(account) = documentos_ligado? ? account.lead_stages.where(is_won: true, label: CONDUZIDAS).to_a : []

  # O caminho do agente de documentos: o lead está em Documentos, ou já passou dela ao Jurídico (chave ligada). Lá o 1º contato
  # depois do Ganho é do agente, não de uma pessoa (spec §9): o ADVBOX do Ganho pergunta aqui.
  def pelo_agente_de_documentos?(lead) = documentos_ligado? && [DOCUMENTOS, JURIDICO].include?(lead.lead_stage&.label)

  def juridico(account) = account.lead_stages.find_by(label: JURIDICO, is_won: true)

  def juridico?(etapa) = etapa&.is_won == true && etapa.label == JURIDICO

  # A etapa de ganho da conta: Fechado; sem ela, a primeira `is_won` por posição.
  def principal(account)
    account.lead_stages.find_by(label: FECHADO, is_won: true) || account.lead_stages.find_by(is_won: true)
  end

  # Para quem não tem o que fazer sem etapa de ganho (importação, preparo do fluxo dos eventos ADVBOX).
  def principal!(account)
    principal(account) || raise(ActiveRecord::RecordNotFound, "conta #{account.id} sem etapa de ganho")
  end

  # Onde um lead que acabou de ganhar deve cair: Documentos (abaixo) ou a principal. Não depende de o lead ter conversa:
  # sem WhatsApp, Documentos fica com o SDR (Ramon::Documentos::Entrada).
  def entrada(lead)
    etapa_documentos(lead) || principal(lead.account)
  end

  # Documentos: chave ligada, tese marcada "passa pela etapa Documentos", o lead com checklist de documentos (docs_total,
  # o mesmo critério do funil: helpers/stage.js pulaDocumentos) e a etapa existe.
  def etapa_documentos(lead)
    return unless documentos_ligado? && lead.thesis&.passa_documentos && lead.docs_counts[:total].positive?

    lead.account.lead_stages.find_by(label: DOCUMENTOS, is_won: true)
  end
end

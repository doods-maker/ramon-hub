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

  # A etapa de ganho da conta: Fechado; sem ela, a primeira `is_won` por posição.
  def principal(account)
    account.lead_stages.find_by(label: FECHADO, is_won: true) || account.lead_stages.find_by(is_won: true)
  end

  # Para quem não tem o que fazer sem etapa de ganho (importação, preparo do fluxo dos eventos ADVBOX).
  def principal!(account)
    principal(account) || raise(ActiveRecord::RecordNotFound, "conta #{account.id} sem etapa de ganho")
  end

  # Onde um lead que acabou de ganhar deve cair. Neste PR é sempre a principal; o PR 2 desvia para Documentos.
  def entrada(lead)
    principal(lead.account)
  end
end

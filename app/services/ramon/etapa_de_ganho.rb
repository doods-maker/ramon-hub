# Onde o ganho entra, agora que a conta tem várias etapas de ganho (ADR 0015). Quem precisa de "a etapa de ganho"
# (ZapSign assinado, contrato fechado no ADVBOX, importação, fluxo dos eventos ADVBOX) pergunta aqui, nunca
# `find_by(is_won: true)`: com Documentos e Jurídico antes de Fechado na ordem, aquilo cai na etapa errada.
# "Está ganho" continua sendo qualquer etapa `is_won`.
module Ramon::EtapaDeGanho
  FECHADO = 'fase-fechado'.freeze
  DOCUMENTOS = 'fase-documentos'.freeze
  JURIDICO = 'fase-juridico'.freeze

  module_function

  # A etapa de ganho da conta: Fechado; sem ela, a primeira `is_won` por posição.
  def principal(account)
    account.lead_stages.find_by(label: FECHADO, is_won: true) || account.lead_stages.find_by(is_won: true)
  end

  # Onde um lead que acabou de ganhar deve cair. Neste PR é sempre a principal; o PR 2 desvia para Documentos.
  def entrada(lead)
    principal(lead.account)
  end
end

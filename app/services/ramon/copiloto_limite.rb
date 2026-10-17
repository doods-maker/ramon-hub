# Aviso de cruzar o Marcador (spec "Como a IA atende"): quando o lead passa da Etapa até onde a IA vai sozinha, a equipe
# recebe sino + push e a conversa ganha o carimbo copiloto_limite (bi_roteiro lê limite, em, motivo). Nada muda na conversa:
# o Perfil da IA recalcula a cada turno pela Etapa. Quem chama: Lead (etapa/conversa mudou) e o roteiro (fim de Efeitos).
# O contrato automático que não saiu (Ramon::ContratoAutomatico) entra por `falhou`: esse sim põe a conversa em rascunho.
module Ramon::CopilotoLimite
  MARCADOR = 'marcador'.freeze
  # O contrato automático não saiu (falta dado ou o ZapSign falhou): conta à parte (bi_roteiro, card de limites).
  CONTRATO_FALHOU = 'contrato_falhou'.freeze

  module_function

  # Idempotente por Marcador: avisa uma vez por valor do Marcador da conta. Mudar o Marcador e cruzar de novo avisa.
  # @return [String, nil] a chave do Marcador avisado
  def verificar(lead)
    conversa = lead.conversation
    return unless conversa

    perfil = Ramon::PerfilIa.de(lead)
    marcador = perfil.marcador
    return if marcador == Ramon::PerfilIa::INICIO || perfil.estado(lead.lead_stage) != :rascunho

    return if avisado?(conversa, marcador)

    carimbar(conversa, 'limite' => MARCADOR, 'marcador' => marcador, 'etapa' => Ramon::PerfilIa.chave_da_etapa(lead.lead_stage))
    avisar(lead, "IA passou do marcador com #{lead.name} - daqui pra frente ela escreve rascunho",
           "IA passou do marcador: #{lead.name}", 'Daqui pra frente ela escreve rascunho')
    marcador
  end

  def avisado?(conversa, marcador)
    carimbo = conversa.custom_attributes&.dig('copiloto_limite')
    carimbo.is_a?(Hash) && carimbo['limite'] == MARCADOR && carimbo['marcador'] == marcador
  end

  # O contrato não saiu na hora: a conversa vai para rascunho (Pausa) e a equipe é avisada.
  def falhou(lead, motivo)
    conversa = lead.conversation
    return unless conversa

    carimbar(conversa, 'limite' => CONTRATO_FALHOU, 'motivo' => motivo)
    Ramon::PerfilIa.pausar(conversa, 'rascunho')
    avisar(lead, "IA: contrato não saiu na hora com #{lead.name}: #{motivo} - conversa em rascunho",
           "IA: contrato não saiu: #{lead.name}", motivo)
  end

  def carimbar(conversa, dados)
    carimbo = dados.merge('em' => Time.zone.now.iso8601).compact
    conversa.update!(custom_attributes: (conversa.custom_attributes || {}).merge('copiloto_limite' => carimbo))
  end

  def avisar(lead, texto, titulo, corpo)
    Ramon::AvisoDaIa.avisar(lead, texto, titulo, corpo)
  end
end

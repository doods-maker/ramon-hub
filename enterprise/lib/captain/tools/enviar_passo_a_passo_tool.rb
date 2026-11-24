# Etapa Documentos: anexa à resposta do agente a imagem do passo a passo de um tema (uma imagem, uma mensagem: a resposta
# vira a legenda). A regra (temas, janela, chave, conversa com a IA, uma por turno) é Ramon::Documentos::PassoAPasso;
# aqui só entram as imagens do assistente e o estado do turno.
class Captain::Tools::EnviarPassoAPassoTool < Captain::Tools::RamonBaseTool
  description 'Anexa à sua resposta a imagem do passo a passo de um tema (sai numa mensagem só, com a resposta de legenda). ' \
              'Use quando o cliente travar num passo, antes de explicar de novo. ' \
              "Temas: #{::Ramon::Documentos::PassoAPasso::TEMAS.join(', ')}."
  param :tema, type: 'string', desc: 'Um dos temas da lista', required: true

  def perform(tool_context, tema:)
    conversa = find_conversation(tool_context.state)
    return SEM_LEAD if conversa.blank?

    log_tool_usage('enviar_passo_a_passo', { conversation_id: conversa.id, tema: tema })
    ::Ramon::Documentos::PassoAPasso.preparar(conversa, tema.to_s, imagens: biblioteca.passos_a_passo.blobs.to_a, estado: tool_context.state)
  end

  private

  # A biblioteca é uma só: a do assistente da etapa Documentos (só ele tem a tela de envio das imagens). O de Atendimento usa
  # a mesma na assinatura do contrato; conta sem etapa ligada fica com as do próprio assistente.
  def biblioteca
    id = @assistant.account.lead_stages.where(is_won: true, label: ::Ramon::EtapaDeGanho::CONDUZIDAS)
                   .where.not(captain_assistant_id: nil).pick(:captain_assistant_id)
    Captain::Assistant.find_by(id: id) || @assistant
  end
end

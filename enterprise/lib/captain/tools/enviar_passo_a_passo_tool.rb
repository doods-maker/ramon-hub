# Etapa Documentos: manda ao cliente a imagem do passo a passo de um tema (uma imagem, uma mensagem). A regra (temas,
# janela de 24 h, chave, conversa com a IA) é Ramon::Documentos::PassoAPasso; aqui só entram as imagens do assistente.
class Captain::Tools::EnviarPassoAPassoTool < Captain::Tools::RamonBaseTool
  description 'Envia ao cliente, numa mensagem, a imagem do passo a passo de um tema. Use quando ele travar num passo, ' \
              "antes de explicar de novo com palavras. Temas: #{::Ramon::Documentos::PassoAPasso::TEMAS.join(', ')}."
  param :tema, type: 'string', desc: 'Um dos temas da lista', required: true

  def perform(tool_context, tema:)
    conversa = find_conversation(tool_context.state)
    return SEM_LEAD if conversa.blank?

    log_tool_usage('enviar_passo_a_passo', { conversation_id: conversa.id, tema: tema })
    ::Ramon::Documentos::PassoAPasso.enviar(conversa, tema.to_s, imagens: @assistant.passos_a_passo.blobs.to_a, remetente: @assistant)
  end
end

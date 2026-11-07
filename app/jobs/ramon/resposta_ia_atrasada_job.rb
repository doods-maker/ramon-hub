# Resposta da IA que sai sozinha pro cliente (Perfil da IA): o texto nasce na hora e só o ENVIO espera o atraso
# aleatório (30s–3min, tela Como a IA atende) pra não ter ritmo de robô. Rascunho pra equipe não passa por aqui.
class Ramon::RespostaIaAtrasadaJob < ApplicationJob
  queue_as :high

  # Não sai se, depois da mensagem do cliente (apos_id), uma pessoa respondeu. Fora o aviso de handoff (sai com a
  # conversa já aberta), também não sai se o cliente escreveu de novo (o job da mensagem nova responde tudo) ou se a
  # conversa saiu da IA (pausada/assumida).
  # ponytail: "Só rascunho" ligado durante a espera não segura este envio (a conversa segue pendente); reler o Perfil
  # aqui se isso incomodar.
  # passo_a_passo: blob da imagem que a tool enviar_passo_a_passo preparou no turno; vai anexada a esta mensagem, que vira a
  # legenda (uma mensagem por resposta: Ramon::Documentos::PassoAPasso).
  def perform(conversation, message_params, apos_id, handoff: false, passo_a_passo: nil)
    depois = conversation.messages.where('id > ?', apos_id)
    return if depois.outgoing.exists?(sender_type: 'User', private: false)
    return if !handoff && (depois.incoming.exists? || !conversation.reload.pending?)
    return Ramon::Documentos::PassoAPasso.criar_mensagem(conversation, message_params, passo_a_passo) if passo_a_passo

    conversation.messages.create!(message_params)
  end
end

# Imagem do passo a passo para o cliente na etapa Documentos (spec Etapa Documentos §3; decisões do Eduardo 07/11, custo da
# Meta por mensagem): UMA imagem por tema e UMA mensagem por resposta. A tool enviar_passo_a_passo (enterprise) só chama
# preparar, que guarda a imagem no estado do turno; a resposta do agente sai com ela anexada (o texto vira a legenda) em
# Ramon::RespostaIaAtrasadaJob, pelo mesmo caminho e com a mesma decisão do Perfil da IA de qualquer resposta.
# As imagens ficam no assistente "Documentos" (ActiveStorage, nome do arquivo = tema; fora do git, o repo é público).
module Ramon::Documentos::PassoAPasso
  TEMAS = %w[govbr_criar_conta govbr_recuperar_senha govbr_duas_etapas meu_inss_cnis meu_inss_laudos meu_inss_processo
             meu_inss_decisao meu_inss_cat].freeze
  # Chave no estado do turno do agente (AgentRunnerService devolve como response['passo_a_passo']).
  ESTADO = :ramon_passo_a_passo
  PREPARADA = 'A imagem vai anexada à sua resposta, que sai como legenda dela numa mensagem só. Escreva a resposta curta, ' \
              'apontando para a imagem, sem repetir os passos.'.freeze
  JA_TEM = 'Já há uma imagem nesta resposta: só uma por mensagem.'.freeze
  SEM_IMAGEM = 'Sem imagem para este tema: explique os passos em texto.'.freeze
  FORA_DA_JANELA = 'Fora da janela de 24 h do WhatsApp: a imagem não vai.'.freeze
  NAO_SAI = 'A imagem não vai: a conversa não está com a IA da etapa Documentos agora.'.freeze

  module_function

  # imagens: blobs do assistente (um por tema, o nome do arquivo sem extensão é o tema). estado: o do turno (tool_context.state).
  # @return [String] o que o agente fica sabendo (nada levanta: o turno segue)
  def preparar(conversa, tema, imagens:, estado:)
    return "Tema desconhecido. Use um destes: #{TEMAS.join(', ')}." unless TEMAS.include?(tema)
    return NAO_SAI unless sai_agora?(conversa)
    return JA_TEM if estado[ESTADO]

    imagem = imagens.find { |blob| File.basename(blob.filename.to_s, '.*') == tema }
    return SEM_IMAGEM unless imagem
    return FORA_DA_JANELA unless janela_aberta?(conversa)

    estado[ESTADO] = imagem.id
    PREPARADA
  end

  # A resposta do agente (params do ResponseBuilderJob) com a imagem do turno: uma mensagem só. Imagem apagada no meio do
  # caminho: o texto sai sozinho.
  def criar_mensagem(conversa, params, blob_id)
    mensagem = conversa.messages.new(params)
    imagem = ActiveStorage::Blob.find_by(id: blob_id)
    # Cópia, não o blob do tema: o anexo da mensagem é apagado com a conversa (purge) e levaria a imagem do tema junto.
    if imagem
      mensagem.attachments.new(account_id: conversa.account_id, file_type: :image,
                               file: { io: StringIO.new(imagem.download), filename: imagem.filename.to_s, content_type: imagem.content_type })
    end
    mensagem.save!
  end

  # Conversa com a IA (pendente), lead em Documentos (chave ligada) e uma resposta da IA sairia sozinha agora (Pausa, fora
  # do horário em rascunho etc.: Ramon::PerfilIa).
  def sai_agora?(conversa)
    lead = conversa.account.leads.find_by(conversation_id: conversa.id)
    conversa.pending? && lead.present? && Ramon::EtapaDeGanho.conduzida?(lead.lead_stage) &&
      Ramon::PerfilIa.de(conversa).logistica_sai_agora?
  end

  # Janela do canal (WhatsApp: 24 h desde a última mensagem do cliente; upload do portal não conta). A janela grátis de
  # anúncio é do PR 5.
  def janela_aberta?(conversa) = Conversations::MessageWindowService.new(conversa).can_reply?
end

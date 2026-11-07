# Imagem do passo a passo para o cliente na etapa Documentos (spec Etapa Documentos §3; decisão do Eduardo 07/11, custo da
# Meta por mensagem): UMA imagem por tema, mandada numa mensagem só, com um anexo. As imagens ficam no assistente
# "Documentos" (ActiveStorage, nome do arquivo = tema; fora do git, o repo é público). Chamado pela tool
# enviar_passo_a_passo (enterprise); aqui fica a regra, para o CI (que roda sem enterprise/) testar.
module Ramon::Documentos::PassoAPasso
  TEMAS = %w[govbr_criar_conta govbr_recuperar_senha govbr_duas_etapas meu_inss_cnis meu_inss_laudos meu_inss_processo
             meu_inss_decisao meu_inss_cat].freeze
  ENVIADA = 'Imagem enviada ao cliente. Não mande outra mensagem repetindo os passos: pergunte se ele conseguiu.'.freeze
  SEM_IMAGEM = 'Sem imagem para este tema: explique os passos em texto.'.freeze
  FORA_DA_JANELA = 'Fora da janela de 24 h do WhatsApp: a imagem não foi enviada.'.freeze
  NAO_SAI = 'A imagem não foi enviada: a conversa não está com a IA da etapa Documentos agora.'.freeze

  module_function

  # imagens: blobs do assistente (um por tema, o nome do arquivo sem extensão é o tema).
  # @return [String] o que o agente fica sabendo (nada levanta: o turno segue)
  def enviar(conversa, tema, imagens:, remetente:)
    return "Tema desconhecido. Use um destes: #{TEMAS.join(', ')}." unless TEMAS.include?(tema)
    return NAO_SAI unless sai_agora?(conversa)

    imagem = imagens.find { |blob| File.basename(blob.filename.to_s, '.*') == tema }
    return SEM_IMAGEM unless imagem
    return FORA_DA_JANELA unless janela_aberta?(conversa)

    mensagem = conversa.messages.new(account_id: conversa.account_id, inbox_id: conversa.inbox_id, message_type: :outgoing,
                                     sender: remetente)
    # Cópia, não o blob do tema: o anexo da mensagem é apagado com a conversa (purge) e levaria a imagem do tema junto.
    mensagem.attachments.new(account_id: conversa.account_id, file_type: :image,
                             file: { io: StringIO.new(imagem.download), filename: imagem.filename.to_s, content_type: imagem.content_type })
    mensagem.save!
    ENVIADA
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

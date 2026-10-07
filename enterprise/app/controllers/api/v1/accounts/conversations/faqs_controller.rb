# "Virar FAQ" (Inteligência A4 — I-X1): uma resposta enviada ao lead vira FAQ PENDENTE do assistente que
# atende leads, com a pergunta que o lead fez logo antes (Ramon::FaqDeConversa — sem IA, dados mascarados).
# Quem vê a conversa pode criar; só administrador aprova (update/bulk_actions = AssistantPolicy admin).
# Clicar de novo na mesma resposta devolve a mesma FAQ.
class Api::V1::Accounts::Conversations::FaqsController < Api::V1::Accounts::Conversations::BaseController
  def create
    mensagem = @conversation.messages.find(params[:message_id])
    assistente = assistente_de_leads
    return render(json: { erro: 'SEM_ASSISTENTE' }, status: :unprocessable_content) if assistente.nil?

    faq = Ramon::FaqDeConversa.de_mensagem(mensagem)
    existente = assistente.responses.find_by(documentable: @conversation, answer: faq[:answer])
    return render(json: corpo(existente, true)) if existente

    render json: corpo(assistente.responses.create!(faq.merge(status: :pending, documentable: @conversation)), false),
           status: :created
  rescue Ramon::FaqDeConversa::Recusa => e
    render json: { erro: e.message }, status: :unprocessable_content
  end

  private

  # O assistente da caixa desta conversa; se a caixa não tem, o primeiro que atende alguma caixa (o Atendimento).
  def assistente_de_leads
    @conversation.inbox.captain_assistant ||
      Current.account.captain_assistants.joins(:captain_inboxes).order(:id).first
  end

  def corpo(faq, ja_existia)
    { id: faq.id, assistant_id: faq.assistant_id, ja_existia: ja_existia }
  end
end

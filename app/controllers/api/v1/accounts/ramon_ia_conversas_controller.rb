# Botão "IA: {perfil}" do cabeçalho da conversa: o perfil que vale agora (Ramon::PerfilIa) para quem pode ver a conversa.
# :conversation_id = display_id, como nas demais rotas de conversa.
class Api::V1::Accounts::RamonIaConversasController < Api::V1::Accounts::BaseController
  def show
    conversa = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversa, :show?
    perfil = Ramon::PerfilIa.de(conversa)
    pausa = perfil.estado == :pausada ? 'pausada' : perfil.pausa # lead em Perdido também cala a IA
    render json: { perfil: perfil.nome, origem: perfil.origem, etapa: perfil.etapa&.name, pausa: pausa, alvo: perfil.alvo }
  end
end

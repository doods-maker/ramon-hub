# Aba "Agente Claude" das Execuções (I-EX4): a trilha que o runner da VPS grava em
# agente_execucoes (pedido, status, resumo, ações, duração) e o uso do teto de hoje.
# Leitura pura; o custo (nominal, da assinatura) fica na tela Uso e custo, só admin.
class Api::V1::Accounts::RamonAgenteExecucoesController < Api::V1::Accounts::BaseController
  LIMITE = 100

  before_action :current_account
  before_action :check_authorization

  def index
    execucoes = visiveis.includes(:lead, :conversation).order(created_at: :desc, id: :desc).limit(LIMITE)
    render json: { resumo: resumo, items: execucoes.map { |execucao| linha(execucao) } }
  end

  private

  # Mesmas permissões das Execuções das ferramentas (admin + agent).
  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end

  # Cada um vê só o que é seu: agente só enxerga pedidos de conversas das caixas de que participa
  # (linha sem conversa some); admin vê a trilha toda. O resumo do dia é só contagem.
  def visiveis
    todas = Current.account.agente_execucoes
    return todas if Current.account_user.administrator?

    todas.where(conversation_id: Current.account.conversations.where(inbox_id: Current.user.inboxes.select(:id)).select(:id))
  end

  def resumo
    hoje = Current.account.agente_execucoes.de_hoje
    { hoje: hoje.consumiu_cota.count, teto: AgenteExecucao::TETO_DIA, problemas_hoje: hoje.where.not(status: 'ok').count }
  end

  # N5: sem campos de custo — só a trilha (custo fica em Uso e custo, admin).
  def linha(execucao)
    execucao.slice(:id, :pedido, :status, :resumo, :acoes, :modelo, :esforco, :duracao_ms, :lead_id, :created_at)
            .merge(lead_nome: execucao.lead&.name, conversa_display_id: execucao.conversation&.display_id)
  end
end

# Automações em fluxo (spec §7): CRUD do rascunho, publicar, ensaiar e rodar na mão.
class Api::V1::Accounts::RamonFluxosController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fluxo, except: [:index, :create, :opcoes_advbox]
  before_action :bloquear_sistema, only: [:update, :destroy, :publicar, :rodar]

  def index
    fluxos = Current.account.fluxos.includes(:versao_publicada).order(:origem, :nome)
    payload = fluxos.map(&:resumo_json)
    render json: { payload: payload, resumo: resumo(payload) }
  end

  def show
    render json: @fluxo.resumo_json.merge(rascunho: @fluxo.rascunho,
                                          versoes: @fluxo.versoes.order(numero: :desc).map { |v| { numero: v.numero, created_at: v.created_at } })
  end

  def create
    fluxo = Current.account.fluxos.create!(fluxo_params.merge(created_by: Current.user))
    render json: fluxo.resumo_json
  end

  def update
    @fluxo.update!(fluxo_params)
    render json: @fluxo.resumo_json
  end

  def destroy
    @fluxo.destroy!
    head :ok
  end

  def publicar
    render json: { versao: @fluxo.publicar!(Current.user).numero }
  rescue Ramon::Fluxos::Grafo::Invalido
    render json: { erros: Ramon::Fluxos::Grafo.new(@fluxo.rascunho).erros }, status: :unprocessable_entity
  end

  def ensaio
    usar = params[:usar].presence_in(%w[rascunho publicada]) || 'rascunho'
    erros = erros_do_ensaio(usar)
    return render json: { erros: erros }, status: :unprocessable_entity if erros.any?

    render json: Ramon::Fluxos::Disparo.ensaiar(@fluxo, alvo, usar: usar).resumo_json
  end

  def rodar
    execucao = Ramon::Fluxos::Disparo.manual(@fluxo, alvo)
    return render json: { erro: 'FLUXO_NAO_RODOU' }, status: :unprocessable_entity if execucao.nil?

    render json: execucao.resumo_json
  end

  # Selects do passo ADVBOX: usuários e tipos de tarefa da conta AdvBox (sem e-mail/telefone).
  def opcoes_advbox
    cfg = Ramon::AdvboxClient.settings
    render json: { usuarios: Array(cfg['users']).map { |u| { id: u['id'], nome: u['name'] } },
                   tipos_tarefa: Array(cfg['tasks']).map { |t| { id: t['id'], nome: t['task'] } } }
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError => e
    render json: { erro: e.message }, status: :service_unavailable
  end

  private

  def check_authorization
    authorize(:ramon_fluxo, :gerenciar?)
  end

  def fluxo
    @fluxo = Current.account.fluxos.find(params[:id])
  end

  def bloquear_sistema
    head :forbidden if @fluxo.origem == 'sistema'
  end

  # Disparo.ensaiar quebra sem versão publicada (usar publicada) ou sem gatilho (rascunho): barra antes.
  def erros_do_ensaio(usar)
    return Ramon::Fluxos::Grafo.new(@fluxo.rascunho).erros if usar == 'rascunho'

    @fluxo.versao_publicada.nil? ? ['O fluxo ainda não foi publicado'] : []
  end

  def alvo
    return Current.account.leads.find(params[:lead_id]) if params[:lead_id].present?

    Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end

  def fluxo_params
    permitidos = params.permit(:nome, :descricao, :ativo, :limite_dia, :modo).to_h
    permitidos[:rascunho] = params[:rascunho].permit!.to_h if params[:rascunho].present?
    permitidos
  end

  def resumo(payload)
    {
      ligados: payload.count { |f| f[:ativo] }, total: payload.size, hoje: payload.sum { |f| f[:hoje] },
      esperando: payload.sum { |f| f[:esperando] }, falharam_24h: payload.sum { |f| f[:falharam_24h] }
    }
  end
end

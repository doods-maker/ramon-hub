# Peticionamento · Fase 1: petições a protocolar à mão (pacote de PDFs, seletor do Drive, registro do protocolo).
class Api::V1::Accounts::RamonPeticoesController < Api::V1::Accounts::BaseController
  LIMITE = 200
  ORDEM = <<~SQL.squish.freeze
    CASE WHEN status = 'rascunho' THEN 0 ELSE 1 END,
    CASE WHEN status = 'rascunho' THEN prazo END ASC NULLS LAST,
    protocolada_em DESC NULLS LAST
  SQL

  before_action :current_account
  before_action :check_authorization
  before_action :carregar_peticao, except: %i[index create drive drive_busca processos]
  before_action :exigir_editavel, only: %i[update destroy arquivos arquivos_drive atualizar_arquivo remover_arquivo ordem]
  before_action :exigir_drive, only: %i[drive drive_busca]

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end
  rescue_from ArgumentError do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def index
    lista = Current.account.peticoes.includes(:arquivos, :contact, :responsavel, :criado_por)
    lista = lista.where(status: params[:status]) if Peticao::STATUS.include?(params[:status])
    render json: { payload: lista.reorder(Arel.sql(ORDEM)).limit(LIMITE).map { |p| p.as_json_hub.except(:arquivos) },
                   tribunais: Ramon::Peticionamento::Tribunais::TODOS.map { |chave, info| info.merge(chave: chave) },
                   tipos: Ramon::Peticionamento::Tribunais::TIPOS }
  end

  def show
    render_peticao
  end

  def create
    peticao = Current.account.peticoes.new(peticao_atributos.merge(criado_por: Current.user))
    peticao.responsavel ||= Current.user
    peticao.drive_pasta_base_id = pasta_base(peticao.contact_id)
    peticao.save!
    render json: peticao.as_json_hub
  end

  def update
    @peticao.update!(peticao_atributos)
    render_peticao
  end

  def destroy
    @peticao.destroy!
    head :no_content
  end

  def arquivos
    arquivo = params.require(:file)
    Ramon::Peticionamento::AdicionarArquivo.call(
      @peticao, bytes: arquivo.read, nome: arquivo.original_filename, content_type: arquivo.content_type, origem: 'upload',
                tipo: params[:tipo].presence, principal: ActiveModel::Type::Boolean.new.cast(params[:principal]) || false
    )
    render_peticao
  end

  def arquivos_drive
    Array(params[:file_ids]).each do |file_id|
      bytes, mime, nome = Ramon::DriveClient.download(file_id)
      Ramon::Peticionamento::AdicionarArquivo.call(@peticao, bytes: bytes, nome: nome, content_type: mime, origem: 'drive',
                                                             drive_origem_id: file_id)
    end
    render_peticao
  end

  def atualizar_arquivo
    arquivo = @peticao.arquivos.find(params[:arquivo_id])
    principal = params.key?(:principal) ? ActiveModel::Type::Boolean.new.cast(params[:principal]) : arquivo.principal
    @peticao.transaction do
      @peticao.arquivos.where.not(id: arquivo.id).find_each { |a| a.update!(principal: false) } if principal
      arquivo.update!(tipo: params[:tipo].presence || arquivo.tipo, principal: principal)
    end
    render_peticao
  end

  def remover_arquivo
    @peticao.arquivos.find(params[:arquivo_id]).destroy!
    renumerar(@peticao.arquivos.reload.map(&:id))
    render_peticao
  end

  def ordem
    ids = Array(params[:ids]).map(&:to_i)
    @peticao.arquivos.find(ids) # 404 se algum id não for do pacote
    renumerar(ids)
    render_peticao
  end

  def registrar_protocolo
    return render json: { error: 'SO_RESPONSAVEL' }, status: :unauthorized unless responsavel_ou_admin?

    @peticao.registrar_protocolo!(usuario: Current.user, numero_evento: params[:numero_evento].presence, comprovante: params[:comprovante])
    render_peticao
  end

  def drive
    raiz = Ramon::DriveClient.root_id
    pasta = params[:pasta_id].presence || raiz
    pai = pasta == raiz ? nil : Ramon::DriveClient.parent_of(pasta)
    render json: { pasta_id: pasta, pai_id: pai, raiz_id: raiz, itens: Ramon::DriveClient.children(pasta) }
  end

  def drive_busca
    render json: { itens: Ramon::DriveClient.search(params[:q]) }
  end

  def processos
    contato = Current.account.contacts.find(params[:contact_id])
    cpf = contato.cpf.to_s.delete('^0-9')
    portal = PortalCliente.find_by(account: Current.account, cpf: cpf) if cpf.present?
    lista = Array(portal&.processos).map { |p| { numero: p['numero'], tipo: p['tipo'] } }
    render json: { processos: lista }
  end

  private

  def render_peticao
    render json: @peticao.reload.as_json_hub
  end

  def carregar_peticao
    @peticao = Current.account.peticoes.find(params[:id])
  end

  def exigir_editavel
    render json: { error: 'protocolada' }, status: :unprocessable_entity unless @peticao.editavel?
  end

  def exigir_drive
    render json: { error: 'DRIVE_OFF' }, status: :service_unavailable unless Ramon::DriveClient.configured?
  end

  def responsavel_ou_admin?
    Current.account_user.administrator? || @peticao.responsavel_id == Current.user.id
  end

  def peticao_atributos
    attrs = params.permit(:contact_id, :numero_processo, :inicial, :tribunal, :prazo, :descricao).to_h
    attrs[:contact] = Current.account.contacts.find(attrs.delete(:contact_id)) if attrs[:contact_id].present?
    attrs.delete(:contact_id)
    attrs[:responsavel] = Current.account.users.find(params[:responsavel_id]) if params[:responsavel_id].present?
    attrs
  end

  # Pasta do Drive do lead ganho mais recente do contato (sugestão de onde arquivar).
  def pasta_base(contact_id)
    return if contact_id.blank?

    lead = Current.account.leads.where(contact_id: contact_id).where.not(won_at: nil).order(won_at: :desc).first
    lead&.custom_attributes&.dig('drive', 'pasta_id')
  end

  def renumerar(ids)
    ids.each_with_index { |id, i| @peticao.arquivos.find(id).update!(posicao: i + 1) }
  end

  def check_authorization
    authorize(:ramon_peticao, :"#{action_name}?")
  end
end

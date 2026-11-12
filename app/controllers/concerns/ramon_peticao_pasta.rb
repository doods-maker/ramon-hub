# Peticionamento pela pasta: apontar uma pasta do Drive, reler e confirmar a conferência; navegador e busca do Drive.
module RamonPeticaoPasta
  extend ActiveSupport::Concern

  RELEITURA_MINUTOS = 10

  # Navegador confinado à raiz do Drive do hub (decisão de 12/11/2026).
  def drive
    raiz = Ramon::DriveClient.root_id
    pasta = Ramon::DriveClient.id_de_query!(params[:pasta_id].presence || raiz) # antes de qualquer chamada ao Drive
    return fora_da_raiz unless Ramon::DriveClient.dentro_da_raiz?(pasta)

    pai = pasta == raiz ? nil : Ramon::DriveClient.parent_of(pasta)
    render json: { pasta_id: pasta, pai_id: pai, raiz_id: raiz, itens: Ramon::DriveClient.children(pasta) }
  end

  def drive_busca
    render json: { itens: Ramon::DriveClient.search_na_raiz(params[:q]) }
  end

  # Pastas que a esteira deixou prontas: o admin vê todas (inclusive sem dono); os demais, só as suas.
  def pastas_prontas
    lista = Current.account.pastas_prontas.includes(:responsavel).order(:created_at)
    lista = lista.where(responsavel_id: Current.user.id) unless Current.account_user.administrator?
    render json: { pastas: lista.map(&:as_json_hub) }
  end

  private

  # Uma principal só no pacote; trocar a principal de um rascunho da pasta volta à conferência.
  def gravar_arquivo(arquivo)
    principal = params.key?(:principal) ? ActiveModel::Type::Boolean.new.cast(params[:principal]) : arquivo.principal
    mudou_principal = principal != arquivo.principal
    @peticao.transaction do
      @peticao.arquivos.where.not(id: arquivo.id).find_each { |a| a.update!(principal: false) } if principal
      arquivo.update!(tipo: params[:tipo].presence || arquivo.tipo, principal: principal)
      @peticao.reabrir_conferencia! if mudou_principal
    end
  end

  def peticao_da_pasta(pasta_id)
    Current.account.peticoes.find_by(pela_pasta: true, drive_pasta_id: pasta_id)
  end

  # O id entra na query do Drive: só caracteres de id; e tem de ser uma pasta de verdade. A raiz é conferida à parte (fora_da_raiz).
  def pasta_valida?(pasta_id)
    pasta_id.match?(/\A[\w-]+\z/) && Ramon::DriveClient.pasta?(pasta_id)
  end

  # Peticionamento confinado à raiz do Drive do hub (decisão de 12/11/2026).
  def fora_da_raiz
    render json: { error: 'fora_da_raiz' }, status: :unprocessable_entity
  end

  def pasta_ja_usada(existente)
    render json: { error: 'pasta_ja_usada', peticao_id: existente&.id }, status: :unprocessable_entity
  end

  # O item da lista de pastas prontas sai na hora (o job também limparia).
  def criar_da_pasta(pasta_id)
    Current.account.peticoes.create!(status: 'conferencia', pela_pasta: true, drive_pasta_id: pasta_id,
                                     criado_por: Current.user, responsavel: Current.user,
                                     leitura: { 'estado' => 'lendo', 'lendo_desde' => Time.current.iso8601 }).tap do
      Current.account.pastas_prontas.where(drive_pasta_id: pasta_id).find_each(&:destroy)
    end
  end

  # Sob trava: :protocolada, :em_leitura ou :ok; no :ok grava `lendo` (mantém os campos anteriores) e volta a conferência.
  def reservar_releitura
    @peticao.with_lock do # recarrega: o registro pode ter sido protocolado depois do before_action
      next :protocolada if @peticao.protocolada?
      next :em_leitura if lendo_recentemente?

      @peticao.update!(status: 'conferencia', leitura: @peticao.leitura.merge('estado' => 'lendo', 'lendo_desde' => Time.current.iso8601))
      :ok
    end
  end

  # Leitura em andamento há menos de 10 min; sem `lendo_desde` (travada de antes) pode reler.
  def lendo_recentemente?
    desde = Time.zone.parse(@peticao.leitura['lendo_desde'].to_s)
    @peticao.leitura['estado'] == 'lendo' && desde.present? && desde > RELEITURA_MINUTOS.minutes.ago
  end

  def exigir_pela_pasta
    render json: { error: 'nao_e_pela_pasta' }, status: :unprocessable_entity unless @peticao.pela_pasta?
  end

  def exigir_pacote_livre
    render json: { error: 'pacote_da_pasta' }, status: :unprocessable_entity if @peticao.pela_pasta?
  end
end

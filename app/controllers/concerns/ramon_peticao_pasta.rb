# Peticionamento pela pasta: apontar uma pasta do Drive, reler e confirmar a conferência.
module RamonPeticaoPasta
  extend ActiveSupport::Concern

  RELEITURA_MINUTOS = 10

  # Pastas que a esteira deixou prontas: o admin vê todas (inclusive sem dono); os demais, só as suas.
  def pastas_prontas
    lista = Current.account.pastas_prontas.includes(:responsavel).order(:created_at)
    lista = lista.where(responsavel_id: Current.user.id) unless Current.account_user.administrator?
    render json: { pastas: lista.map(&:as_json_hub) }
  end

  private

  def peticao_da_pasta(pasta_id)
    Current.account.peticoes.find_by(pela_pasta: true, drive_pasta_id: pasta_id)
  end

  # O id entra na query do Drive: só caracteres de id; e tem de ser uma pasta de verdade (em qualquer lugar do Drive do escritório).
  def pasta_valida?(pasta_id)
    pasta_id.match?(/\A[\w-]+\z/) && Ramon::DriveClient.pasta?(pasta_id)
  end

  def pasta_ja_usada(existente)
    render json: { error: 'pasta_ja_usada', peticao_id: existente&.id }, status: :unprocessable_entity
  end

  def criar_da_pasta(pasta_id)
    Current.account.peticoes.create!(status: 'conferencia', pela_pasta: true, drive_pasta_id: pasta_id,
                                     criado_por: Current.user, responsavel: Current.user,
                                     leitura: { 'estado' => 'lendo', 'lendo_desde' => Time.current.iso8601 })
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

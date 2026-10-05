# CNIS por caso (Onda 3b): recebe o PDF, manda o motor parsear e guarda o
# resultado no lead — o Simulador passa a usar o histórico real de salários.
# Ajustes do advogado (excluir_seqs/mensalidades) vão junto do upload: o PDF
# não fica no servidor (LGPD) — reprocessar = reenviar o arquivo com os params.
class Api::V1::Accounts::LeadCnisController < Api::V1::Accounts::BaseController
  include CalculoProxy

  SEXOS = %w[M F].freeze
  SEXO_OBRIGATORIO = 'sexo do segurado (M ou F) é obrigatório'.freeze

  def show
    authorize(@lead, :show?)
    return head :not_found if @lead.cnis.blank?

    render json: detalhe
  end

  def create
    authorize(@lead, :show?)
    return render json: { error: 'arquivo (PDF do CNIS) é obrigatório' }, status: :unprocessable_entity if params[:arquivo].blank?
    return render json: { error: SEXO_OBRIGATORIO }, status: :unprocessable_entity unless SEXOS.include?(params[:sexo])

    responder do
      resultado = Ramon::MotorClient.cnis(
        params[:arquivo],
        sexo: params[:sexo].to_s,
        excluir_seqs: params[:excluir_seqs].to_s,
        mensalidades: params[:mensalidades].to_s
      )
      @lead.update!(cnis: stored(resultado))
      render json: detalhe
    end
  end

  # Trocar o sexo sem reanexar o PDF: o motor só copia o sexo do upload pra
  # entrada.segurado (o parse do PDF não depende dele) e todo cálculo lê o
  # segurado de lá — basta corrigir o valor guardado.
  def update
    authorize(@lead, :show?)
    return head :not_found if @lead.cnis.blank?
    return render json: { error: SEXO_OBRIGATORIO }, status: :unprocessable_entity unless SEXOS.include?(params[:sexo])

    cnis = @lead.cnis.deep_dup
    cnis['entrada'] = (cnis['entrada'] || {}).merge('segurado' => (cnis.dig('entrada', 'segurado') || {}).merge('sexo' => params[:sexo]))
    @lead.update!(cnis: cnis)
    render json: detalhe
  end

  def destroy
    authorize(@lead, :show?)
    @lead.update!(cnis: nil)
    head :no_content
  end

  private

  def detalhe
    @lead.cnis_detalhe
  end

  def stored(resultado)
    {
      entrada: resultado['entrada_calcular'],
      vinculos: resultado['vinculos'],
      # identificação do cabeçalho do CNIS: nomeia o cálculo no histórico sem
      # o advogado digitar (motor só passou a devolver em 27/07 — pode vir nil)
      segurado_nome: resultado['segurado_nome'],
      segurado_cpf: resultado['segurado_cpf'],
      avisos: avisos_de(resultado),
      parametros: {
        excluir_seqs: params[:excluir_seqs].to_s,
        mensalidades: params[:mensalidades].to_s
      }.reject { |_k, v| v.blank? },
      filename: params[:arquivo].original_filename,
      uploaded_at: Time.current.iso8601
    }
  end

  def avisos_de(resultado)
    (resultado['avisos'] || []).map do |aviso|
      aviso['alvo'].present? ? "#{aviso['alvo']}: #{aviso['mensagem']}" : aviso['mensagem']
    end
  end
end

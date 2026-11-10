# Planejamento previdenciário: calcular (motor, sem histórico), gerar (histórico + job de PDF/memória),
# estado da geração e download. A regra de corpo/nomes/arquivos mora em Ramon::PlanejamentoPrevidenciario.
class Api::V1::Accounts::LeadPlanejamentosController < Api::V1::Accounts::BaseController
  include CalculoProxy
  include RegistraCalculo

  SEM_CNIS = 'Anexe o CNIS para montar o planejamento.'.freeze
  TIPOS = { 'pdf' => 'application/pdf', 'memoria' => Ramon::PlanejamentoPrevidenciario::XLSX }.freeze

  before_action -> { authorize(@lead, :show?) }
  before_action :fetch_calculo, only: [:geracao, :arquivo]

  def create
    return render json: { error: SEM_CNIS }, status: :unprocessable_entity if @lead.cnis.blank?

    responder do
      corpo = Ramon::PlanejamentoPrevidenciario.payload(@lead.cnis, permitted[:perfil] || {}, segurado_nome: nome_do_segurado)
      render json: Ramon::MotorClient.planejamento_previdenciario(corpo).except('memoria_xlsx_b64')
    end
  end

  def gerar
    calculo = registrar_calculo('planejamento', valor: rmi_da_sugestao)
    return render json: { error: 'não deu para registrar o planejamento — tente de novo' }, status: :service_unavailable if calculo.nil?

    calculo.update!(snapshot: calculo.snapshot.merge('geracao' => { 'estado' => 'gerando' }))
    Ramon::PlanejamentoGerarJob.perform_later(calculo.id)
    render json: { calculo_id: calculo.id }, status: :accepted
  end

  def geracao
    render json: @calculo.snapshot['geracao']
  end

  def arquivo
    tipo = params[:tipo].to_s
    return render json: { error: 'tipo inválido' }, status: :unprocessable_entity unless TIPOS.key?(tipo)

    bytes = Ramon::PlanejamentoPrevidenciario.arquivo(@calculo, tipo)
    return render json: { error: 'arquivo expirou — gere de novo' }, status: :not_found if bytes.nil?

    nomes = Ramon::PlanejamentoPrevidenciario.nomes(@calculo.snapshot.dig('params', 'dados'), hoje: @calculo.created_at.to_date)
    send_data bytes, filename: nomes[tipo.to_sym], type: TIPOS[tipo], disposition: 'attachment'
  end

  private

  def fetch_calculo
    @calculo = @lead.calculos.where(tipo: 'planejamento').find(params[:calculo_id])
  end

  # perfil: Parameters → Hash string-keyed (chaves conhecidas). dados: o motor devolveu e a tela editou; é
  # estrutura profunda (arrays, arrays vazios) que permit(dados: {}) não garante — to_unsafe_h preserva.
  # Seguro: staff autenticado + authorize, e o motor revalida o dados no recálculo.
  def permitted
    @permitted ||= begin
      base = params.permit(:segurado_nome, perfil: %i[forma salario_atual empresa salario_emprego cenario_livre turma
                                                      facultativo_semestral descarte_pontos]).to_h
      base['dados'] = params[:dados].to_unsafe_h if params[:dados].respond_to?(:to_unsafe_h)
      base
    end
  end

  def rmi_da_sugestao
    permitted.dig('dados', 'cenarios')&.find { |c| c['sugestao'] }&.dig('rmi')
  end
end

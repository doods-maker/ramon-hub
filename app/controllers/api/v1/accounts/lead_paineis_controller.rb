# Painel de possibilidades (estilo Previdenciarista): todos os cartões de
# benefício do lead — pré-reforma e EC 103, elegível ou não, com "faltou" e
# previsão. Usa o CNIS anexado ao lead (quando houver) + vínculos manuais do
# advogado (ex.: atividade rural que não está no CNIS).
class Api::V1::Accounts::LeadPaineisController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def create
    authorize(@lead, :show?)
    return render json: { error: 'DER inválida — use o formato AAAA-MM-DD' }, status: :unprocessable_entity if der.blank?
    return render json: { error: 'especiais: JSON inválido' }, status: :unprocessable_entity if especiais_invalidos?

    render json: Ramon::MotorClient.painel(motor_payload)
    persistir_especiais
  rescue Ramon::MotorClient::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Ramon::MotorClient::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def permitted
    params.permit(:nascimento, :sexo, :der, :memoria_calculo, :especiais,
                  vinculos_extras: [:inicio, :fim, :tipo, :salario, { especial: [:grau, :inicio, :fim] }])
  end

  # especiais: JSON string (mapa seq => {grau, inicio?, fim?}) — mesmo padrão
  # cru de excluir_seqs/mensalidades no /cnis. nil = JSON inválido.
  def especiais_map
    return @especiais_map if defined?(@especiais_map)

    @especiais_map = permitted[:especiais].present? ? JSON.parse(permitted[:especiais]) : {}
  rescue JSON::ParserError
    @especiais_map = nil
  end

  # nil (JSON quebrado) OU JSON válido mas de forma errada (array, número,
  # mapa com valor que não é um hash de especial) — tudo 422, nunca chega
  # no merge/motor pra virar 500.
  def especiais_invalidos?
    return false if permitted[:especiais].blank?

    !especiais_map.is_a?(Hash) || !especiais_map.values.all?(Hash)
  end

  # Normaliza {grau, inicio, fim} vindo tanto do mapa `especiais` (Hash cru do
  # JSON.parse) quanto do `especial` de um vinculo_extra (Parameters permitido).
  def especial_normalizado(bruto)
    return if bruto.blank?

    h = bruto.to_h.with_indifferent_access
    { 'grau' => h[:grau], 'inicio' => h[:inicio], 'fim' => h[:fim] }
  end

  # entrada.vinculos (usado no motor_payload) NÃO tem seq — quem tem é
  # cnis['vinculos'] (o vinculos_detalhe do /cnis). Invariante verificado no
  # motor (fonte da verdade): os dois vêm da MESMA comprehension 1:1 sobre
  # resultado.vinculos (montagem.py `vinculos = [Vinculo(...) for v in
  # res.vinculos]` + api/main.py `"vinculos": [... for v_ in
  # resultado.vinculos]`) — mesma ordem, sem filtro. Por isso a fusão é por
  # posição (índice i -> detalhe[i]['seq']), não por um campo 'seq' que não
  # existe em entrada.vinculos. Se os tamanhos divergirem (dado velho/
  # corrompido), pula a fusão inteira em vez de arriscar casar posição errada.
  def vinculos_com_especial
    vinculos = cnis_entrada['vinculos'] || []
    detalhe = @lead.cnis&.dig('vinculos') || []
    return vinculos if especiais_map.blank? || detalhe.length != vinculos.length

    vinculos.each_with_index.map { |v, i| com_especial(v, especiais_map[detalhe[i]['seq'].to_s]) }
  end

  def com_especial(vinculo, bruto)
    especial = especial_normalizado(bruto)
    especial.present? ? vinculo.merge('especial' => especial) : vinculo
  end

  def persistir_especiais
    # o front sempre envia a chave (mesmo vazia ao desmarcar tudo) — chave
    # ausente = não mexeu; chave vazia = limpou (remove a marcação persistida,
    # senão marca velha "fantasma" reaparece no reload)
    return unless params.key?(:especiais)
    return if @lead.cnis.blank?

    cnis = @lead.cnis
    parametros = cnis['parametros'] || {}
    cnis['parametros'] = if permitted[:especiais].present?
                           parametros.merge('especiais' => permitted[:especiais])
                         else
                           parametros.except('especiais')
                         end
    @lead.update!(cnis: cnis)
  end

  def der
    @der ||= data(permitted[:der])
  end

  def data(valor)
    Date.iso8601(valor.to_s)
  rescue ArgumentError
    nil
  end

  def cnis_entrada
    @cnis_entrada ||= @lead.cnis&.dig('entrada') || {}
  end

  def segurado
    cnis_entrada['segurado'].presence ||
      { nascimento: permitted[:nascimento], sexo: permitted[:sexo].presence || 'M' }
  end

  # Vínculos manuais: contam tempo/carência no motor; com salário informado
  # também entram na média (competências mensais geradas aqui).
  def extras
    @extras ||= (permitted[:vinculos_extras] || []).filter_map { |v| extra_de(v) }
  end

  def extra_de(vinculo)
    inicio = data(vinculo[:inicio])
    fim = data(vinculo[:fim])
    return if inicio.blank? || fim.blank? || fim < inicio

    { inicio: inicio, fim: fim, tipo: vinculo[:tipo].presence || 'EMPREGO',
      salario: vinculo[:salario], especial: vinculo[:especial] }
  end

  def competencias_de(extra)
    return [] if extra[:salario].blank?

    salario = format('%.2f', extra[:salario].to_f)
    mes = extra[:inicio].beginning_of_month
    lista = []
    while mes <= extra[:fim]
      lista << { ano: mes.year, mes: mes.month, salario: salario }
      mes = mes.next_month
    end
    lista
  end

  def motor_payload
    {
      segurado: segurado,
      der: der.iso8601,
      competencias: (cnis_entrada['competencias'] || []) + extras.flat_map { |e| competencias_de(e) },
      vinculos: vinculos_com_especial + extras_vinculos,
      memoria_calculo: ActiveModel::Type::Boolean.new.cast(permitted[:memoria_calculo]) || false
    }
  end

  def extras_vinculos
    extras.map do |e|
      item = { inicio: e[:inicio].iso8601, fim: e[:fim].iso8601, tipo: e[:tipo], indicadores: [] }
      especial = especial_normalizado(e[:especial])
      especial.present? ? item.merge(especial: especial) : item
    end
  end
end

# Escrita INTERNA (nao sai pro mundo, D11): grava a qualificacao viva do caso —
# o mesmo custom_attributes.qualificacao_status que o painel QualificacaoViva
# le e escreve (chave = id do thesis_item, valor ok|falta).
class Captain::Tools::RegistrarQualificacaoTool < Captain::Tools::RamonBaseTool
  STATUS = %w[ok falta limpar].freeze

  description 'Registra no caso se um criterio de qualificacao da tese foi confirmado (ok) ou nao atendido (falta). ' \
              'So marca o painel do caso; nao manda nada ao cliente.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :criterio, type: 'string', desc: 'Nome (ou parte) do criterio de qualificacao da tese', required: true
  param :status, type: 'string', desc: 'ok, falta ou limpar', required: true

  def perform(tool_context, criterio: nil, status: nil, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    status = status.to_s.strip.downcase
    erro = recusa(lead, status)
    return erro if erro

    itens = lead.thesis.thesis_items.where(section: 'qualificacao')
    return "A tese #{lead.thesis.name} nao tem criterios de qualificacao cadastrados." if itens.empty?

    item = achar(itens, criterio)
    return "Nao achei esse criterio. Os criterios da tese sao: #{itens.map { |i| rotulo(i) }.join(' | ')}." if item.blank?

    log_tool_usage('registrar_qualificacao', { lead_id: lead.id, item_id: item.id, status: status })
    gravar(lead, item, status)
    "#{rotulo(item)} marcado como #{status}. Placar: #{placar(lead, itens)}."
  end

  private

  def recusa(lead, status)
    return 'Status invalido: use ok, falta ou limpar.' unless STATUS.include?(status)
    return "O caso #{lead.name} esta sem tese definida — nao ha criterios para marcar." if lead.thesis.blank?

    nil
  end

  def rotulo(item)
    item.title.presence || item.content.to_s.truncate(60)
  end

  def normal(texto)
    I18n.transliterate(texto.to_s).downcase.strip
  end

  def achar(itens, criterio)
    alvo = normal(criterio)
    return nil if alvo.blank?

    itens.find { |i| normal(rotulo(i)) == alvo } || itens.find { |i| normal(rotulo(i)).include?(alvo) }
  end

  def gravar(lead, item, status)
    atual = (lead.custom_attributes || {}).dup
    mapa = (atual['qualificacao_status'] || {}).dup
    if status == 'limpar'
      mapa.delete(item.id.to_s)
    else
      mapa[item.id.to_s] = status
    end
    lead.update!(custom_attributes: atual.merge('qualificacao_status' => mapa))
  end

  def placar(lead, itens)
    mapa = lead.reload.custom_attributes['qualificacao_status'] || {}
    ok = itens.count { |i| mapa[i.id.to_s] == 'ok' }
    falta = itens.count { |i| mapa[i.id.to_s] == 'falta' }
    "#{ok} ok, #{falta} falta, #{itens.size - ok - falta} sem resposta"
  end
end

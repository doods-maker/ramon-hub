# Leitura pura: o playbook da tese (o que a Sala de Fechamento mostra) servido
# ao agente — descricao, honorario configurado e os itens por secao.
class Captain::Tools::PlaybookDaTeseTool < Captain::Tools::BasePublicTool
  description 'Playbook de uma tese da banca: descricao, honorario configurado e itens por secao ' \
              '(abertura, apresentacao, qualificacao, objecao, documento, roteiro, colheita). ' \
              'Informe a tese pelo nome (ou parte) ou pelo lead_id do caso; sem tese, lista as teses ativas.'
  param :tese, type: 'string', desc: 'Nome (ou parte do nome) da tese', required: false
  param :lead_id, type: 'string', desc: 'Id do caso (lead) — usa a tese dele', required: false
  param :secao, type: 'string', desc: "Filtra uma secao: #{::ThesisItem::SECTIONS.join(', ')}", required: false

  TETO = 6000
  TETO_SECAO = 1500

  def perform(_tool_context, tese: nil, lead_id: nil, secao: nil)
    thesis = resolver_tese(tese, lead_id)
    return listar_ativas(tese) if thesis.blank?

    secoes = secao.present? ? [secao.to_s.downcase.strip] : ::ThesisItem::SECTIONS
    return "Secao invalida. Use uma de: #{::ThesisItem::SECTIONS.join(', ')}." unless (secoes - ::ThesisItem::SECTIONS).empty?

    log_tool_usage('playbook_da_tese', { thesis_id: thesis.id, secao: secao })
    [cabecalho(thesis), *secoes.map { |s| bloco_secao(thesis, s) }].compact.join("\n\n").truncate(TETO)
  rescue StandardError => e
    Rails.logger.error("PlaybookDaTeseTool: #{e.class}: #{e.message}")
    'Nao consegui ler o playbook agora. Siga sem ele.'
  end

  private

  def teses
    account_scoped(::Thesis).where(active: true)
  end

  def resolver_tese(nome, lead_id)
    id = Integer(lead_id.to_s, exception: false)
    return account_scoped(::Lead).find_by(id: id)&.thesis if id
    return nil if nome.blank?

    teses.find_by('name ILIKE ?', "%#{::Thesis.sanitize_sql_like(nome.to_s.strip)}%")
  end

  def listar_ativas(nome)
    lista = teses.pluck(:name)
    return 'Nenhuma tese ativa cadastrada na conta.' if lista.empty?

    prefixo = nome.present? ? "Nao achei tese com \"#{nome}\". " : 'Informe a tese. '
    "#{prefixo}Teses ativas: #{lista.join('; ')}."
  end

  def cabecalho(thesis)
    linhas = ["Tese: #{thesis.name}"]
    linhas << "Descricao: #{thesis.description}" if thesis.description.present?
    linhas << "Honorario: #{honorario(thesis)}"
    linhas.join("\n")
  end

  def honorario(thesis)
    return 'nao configurado' if thesis.honorario_percentual.blank? && thesis.honorario_n_mensalidades.blank?

    "#{thesis.honorario_percentual.to_f}% dos atrasados + #{thesis.honorario_n_mensalidades.to_i} mensalidades"
  end

  def bloco_secao(thesis, secao)
    itens = thesis.thesis_items.select { |i| i.section == secao }
    return nil if itens.empty?

    corpo = itens.map { |i| i.title.present? ? "- #{i.title}: #{i.content}" : "- #{i.content}" }.join("\n")
    corpo = corpo.truncate(TETO_SECAO, omission: "... [secao truncada — peca so a secao '#{secao}' para ver tudo]")
    "## #{secao} (#{itens.size})\n#{corpo}"
  end
end

# Honorário da tese pela tabela do POP JUR-02 (linha online): percentual dos atrasados
# + N benefícios, com mínimo. Único lugar da regra — simulador (LeadSimulacoesController),
# tools simular_honorario/playbook_da_tese e dossiê. calcular devolve o mesmo Hash do endpoint.
class Ramon::Honorario
  SEM_CONFIG = 'tese do lead sem honorário configurado (% e nº de mensalidades)'.freeze
  FORA_DA_TABELA = 'tese fora da tabela de honorários do escritório (POP JUR-02) — não cite valor; ' \
                   'o advogado explica o honorário na conversa'.freeze

  def self.calcular(tese, atrasados:, mensal:)
    return { valor: nil, motivo: FORA_DA_TABELA } if tese && !tese.honorario_na_tabela
    return { valor: nil, motivo: SEM_CONFIG } unless configurada?(tese)

    mensal = BigDecimal(mensal.to_s)
    sm = Ramon::SalarioMinimo.vigente
    percentual = tese.honorario_percentual || 0
    n = tese.honorario_n_mensalidades || 0
    # JUR-02: o "3" é sempre 3 benefícios ou 3 salários mínimos, o que for maior.
    formula = (BigDecimal(atrasados.to_s) * percentual / 100) + ([mensal, sm].max * n)
    valor = [formula, minimo(tese, mensal, sm)].max
    { valor: format('%.2f', valor), percentual: percentual.to_f, n_mensalidades: n, tese: tese.name,
      descricao: descricao(tese) }
  end

  def self.descricao(tese)
    return nil if tese.nil?
    return FORA_DA_TABELA unless tese.honorario_na_tabela
    return nil unless configurada?(tese)

    "#{numero(tese.honorario_percentual || 0)}% dos atrasados#{parte_mensalidades(tese)}#{parte_minimo(tese)}"
  end

  def self.parte_mensalidades(tese)
    n = tese.honorario_n_mensalidades.to_i
    if n.positive?
      " + #{n} #{n == 1 ? 'benefício (de' : 'benefícios (cada um de'} pelo menos 1 salário mínimo)"
    else
      ''
    end
  end

  def self.parte_minimo(tese)
    q = tese.honorario_minimo_qtd.to_i
    q.positive? ? ", mínimo #{q} #{unidade(tese.honorario_minimo_base, q)}" : ''
  end

  def self.configurada?(tese)
    tese && (tese.honorario_percentual.present? || tese.honorario_n_mensalidades.present?)
  end

  def self.minimo(tese, mensal, salario_minimo)
    q = tese.honorario_minimo_qtd.to_i
    q * (tese.honorario_minimo_base == 'sm' ? salario_minimo : mensal)
  end

  def self.numero(pct)
    (pct % 1).zero? ? pct.to_i.to_s : pct.to_f.to_s.tr('.', ',')
  end

  def self.unidade(base, qtd)
    return (qtd == 1 ? 'salário mínimo' : 'salários mínimos') if base == 'sm'

    qtd == 1 ? 'benefício' : 'benefícios'
  end
  private_class_method :configurada?, :parte_mensalidades, :parte_minimo, :minimo, :numero, :unidade
end

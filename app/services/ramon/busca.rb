# Busca da paleta Ctrl K (redesign v2): leads do funil + espelho do painel do
# cliente (PortalCliente, inclusive nº de processo no jsonb). Tudo local — zero
# cota do ADVBOX. O banco não tem `unaccent`: o acento sai no translate().
# ponytail: LIKE '%termo%' varre as tabelas sem índice — ok com milhares de
# linhas; passando disso, índice trigram (pg_trgm já está ligado).
class Ramon::Busca
  LIMITE = 6
  COM_ACENTO = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ'.freeze
  SEM_ACENTO = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'.freeze
  PROCESSO_SQL = 'EXISTS (SELECT 1 FROM jsonb_array_elements(portal_clientes.processos) p ' \
                 "WHERE regexp_replace(p->>'numero', '[^0-9]', '', 'g') LIKE ?)".freeze

  def initialize(account, termo)
    @account = account
    @termo = termo.to_s.strip
  end

  def perform
    return { leads: [], clientes: [], processos: [] } if @termo.length < 2

    { leads: leads, clientes: clientes, processos: processos }
  end

  private

  def digitos = @termo.gsub(/\D/, '')
  # telefone/CPF/processo só quando o termo é basicamente número ("(47) 9 9634-2210")
  def numerico? = @termo.match?(/\A[\d\s().+-]+\z/)
  def like = "%#{ActiveRecord::Base.sanitize_sql_like(I18n.transliterate(@termo).downcase)}%"
  # só constantes interpoladas — o termo vai sempre como bind (?)
  def sem_acento(coluna) = "LOWER(translate(#{coluna}, '#{COM_ACENTO}', '#{SEM_ACENTO}'))"

  def leads
    escopo = @account.leads.funil.left_joins(:contact)
    condicao = escopo.where("#{sem_acento('leads.name')} LIKE ?", like)
    condicao = condicao.or(escopo.where('contacts.phone_number LIKE ?', "%#{digitos}%")) if numerico? && digitos.length >= 4
    condicao.includes(:lead_stage, :thesis, :contact).reorder(updated_at: :desc).limit(LIMITE).map do |lead|
      { id: lead.id, nome: lead.name, tese: lead.thesis&.name, telefone: lead.contact&.phone_number,
        stage_name: lead.lead_stage&.name, stage_color: lead.lead_stage&.color }
    end
  end

  def clientes
    escopo = PortalCliente.where(account_id: @account.id)
    condicao = escopo.where("#{sem_acento('nome')} LIKE ?", like)
    condicao = condicao.or(escopo.where(cpf: digitos)).or(escopo.where('telefone LIKE ?', "%#{digitos}%")) if numerico? && digitos.length >= 8
    condicao.order(:nome).limit(LIMITE).map do |cliente|
      principal = Array(cliente.processos).first || {}
      { id: cliente.id, nome: cliente.nome, advogada: principal['responsavel'], desde: principal['inicio'].to_s[0, 4].presence }
    end
  end

  def processos
    return [] unless numerico? && digitos.length >= 7

    PortalCliente.where(account_id: @account.id)
                 .where(PROCESSO_SQL, "%#{digitos}%")
                 .order(:nome).limit(LIMITE)
                 .flat_map { |cliente| processos_do(cliente) }.first(LIMITE)
  end

  def processos_do(cliente)
    Array(cliente.processos).select { |p| p['numero'].to_s.gsub(/\D/, '').include?(digitos) }
                            .map { |p| { numero: p['numero'], tipo: p['tipo'], cliente: cliente.nome, cliente_id: cliente.id } }
  end
end

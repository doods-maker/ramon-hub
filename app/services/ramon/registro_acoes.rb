# Registro de ações (tela só do gestor): lê a trilha somente-inclusão (audits)
# da conta, filtra (período, quem fez, tipo, nome do lead/contato), pagina e
# troca ids por nomes. A frase em pt-BR ("mudou a etapa de X para Y") é
# montada na tela (helpers/registroAcoes.js), com i18n.
class Ramon::RegistroAcoes
  TIPOS = {
    'lead' => %w[Lead],
    'contato' => %w[Contact],
    'conversa' => %w[Conversation],
    'dinheiro' => %w[ExtratoFechado MetaComercial],
    'acesso' => %w[AccountUser]
  }.freeze
  TIPO_DO_MODELO = TIPOS.flat_map { |tipo, modelos| modelos.map { |modelo| [modelo, tipo] } }.to_h.freeze
  # campo do audited_changes → modelo cujo nome a tela mostra no lugar do id
  REFERENCIAS = {
    'lead_stage_id' => 'LeadStage', 'sdr_id' => 'User', 'closer_id' => 'User', 'assignee_id' => 'User',
    'user_id' => 'User', 'team_id' => 'Team', 'contact_id' => 'Contact'
  }.freeze
  # associação que o alvo da linha precisa (contato do lead/conversa, pessoa da meta)
  INCLUI = { 'Lead' => :contact, 'Conversation' => :contact, 'MetaComercial' => :user,
             'ExtratoFechado' => :user, 'AccountUser' => :user }.freeze
  FUSO = 'America/Sao_Paulo'.freeze
  POR_PAGINA = 50
  # ponytail: teto do CSV; paginar a exportação se a trilha filtrada passar disso
  LIMITE_CSV = 5000

  def initialize(account, params)
    @account = account
    @params = params
  end

  def resultado
    audits = lista.includes(:user).to_a
    @registros = carregar(audits)
    @nomes = nomes(audits)
    {
      registros: audits.map { |audit| linha(audit) },
      total: escopo.count, pagina: pagina, por_pagina: POR_PAGINA,
      pessoas: @account.users.order(:name).map { |user| { id: user.id, nome: user.name } }
    }
  end

  private

  def escopo
    @escopo ||= por_nome(por_pessoa(por_periodo(base)))
  end

  # Contato: a criação (todo contato novo do WhatsApp) não é ação sensível.
  # Acesso: só papel e entrada na conta (disponibilidade online/offline é ruído).
  def base
    Audited.audit_class
           .where(associated_type: 'Account', associated_id: @account.id, auditable_type: TIPOS.fetch(@params[:tipo], TIPOS.values.flatten))
           .where.not(auditable_type: 'Contact', action: 'create')
           .where.not("audits.auditable_type = 'AccountUser' AND audits.action = 'update' AND audits.audited_changes->'role' IS NULL")
  end

  def por_periodo(scope)
    desde = data(@params[:desde])
    ate = data(@params[:ate])
    return scope unless desde || ate

    scope.where(created_at: desde&.in_time_zone(FUSO)..ate&.in_time_zone(FUSO)&.end_of_day)
  end

  def por_pessoa(scope)
    @params[:user_id].present? ? scope.where(user_type: 'User', user_id: @params[:user_id]) : scope
  end

  # Busca pelo nome do lead ou do contato — pega também as conversas e os leads do contato.
  def por_nome(scope)
    return scope if @params[:q].blank?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(@params[:q].strip)}%"
    contatos = @account.contacts.where('contacts.name ILIKE ?', like).select(:id)
    leads = Lead.unscoped.where(account_id: @account.id)
    leads = leads.where('leads.name ILIKE ?', like).or(leads.where(contact_id: contatos)).select(:id)
    scope.where(auditable_type: 'Contact', auditable_id: contatos)
         .or(scope.where(auditable_type: 'Lead', auditable_id: leads))
         .or(scope.where(auditable_type: 'Conversation', auditable_id: @account.conversations.where(contact_id: contatos).select(:id)))
  end

  def lista
    ordenada = escopo.order(created_at: :desc, id: :desc)
    return ordenada.limit(LIMITE_CSV) if ActiveModel::Type::Boolean.new.cast(@params[:todos])

    ordenada.offset((pagina - 1) * POR_PAGINA).limit(POR_PAGINA)
  end

  def pagina = [@params[:page].to_i, 1].max

  def data(valor)
    Date.iso8601(valor.to_s)
  rescue Date::Error
    nil
  end

  # Registros auditados da página, por tipo — os apagados (lead/contato excluído) não vêm.
  def carregar(audits)
    audits.group_by(&:auditable_type).to_h do |modelo, grupo|
      [modelo, modelo.constantize.unscoped.includes(INCLUI[modelo]).where(id: grupo.map(&:auditable_id)).index_by(&:id)]
    end
  end

  # Um SELECT por modelo para todos os ids das mudanças (e o contato-base das mesclagens).
  def nomes(audits)
    pares = audits.flat_map { |audit| referencias(audit) }
    pares.group_by(&:first).to_h do |modelo, grupo|
      [modelo, modelo.constantize.unscoped.where(id: grupo.map(&:last)).pluck(:id, :name).to_h]
    end
  end

  def referencias(audit)
    pares = audit.audited_changes.flat_map do |campo, valor|
      REFERENCIAS[campo] ? Array(valor).compact.map { |id| [REFERENCIAS[campo], id.to_i] } : []
    end
    base_id = mesclado_em(audit)
    base_id ? pares << ['Contact', base_id] : pares
  end

  def mesclado_em(audit)
    audit.comment.to_s[/\Amesclado:(\d+)\z/, 1]&.to_i
  end

  def linha(audit)
    {
      id: audit.id, quando: audit.created_at.iso8601, tipo: TIPO_DO_MODELO[audit.auditable_type],
      modelo: audit.auditable_type, acao: audit.action, comentario: audit.comment,
      quem: quem(audit.user), alvo: alvo(audit), mudancas: mudancas(audit)
    }
  end

  # Sem autor = automação (job, webhook, auto-atribuição).
  def quem(user)
    return if user.blank?

    user.is_a?(String) ? { id: nil, nome: user } : { id: user.id, nome: user.try(:name) }
  end

  # Antes e depois de cada campo, com ids trocados por nomes. Criação vem
  # como [nil, valor] e exclusão como [valor, nil].
  def mudancas(audit)
    audit.audited_changes.to_h do |campo, valor|
      par = case audit.action
            when 'update' then valor
            when 'destroy' then [valor, nil]
            else [nil, valor]
            end
      [campo, Array(par).map { |item| nome(campo, item) }]
    end
  end

  def nome(campo, valor)
    modelo = REFERENCIAS[campo]
    return valor if modelo.nil? || valor.nil?

    @nomes.dig(modelo, valor.to_i) || "##{valor}"
  end

  # Para onde a linha leva: lead (dossiê) ou contato (Linha da Vida); nome de quem é.
  def alvo(audit)
    registro = @registros.dig(audit.auditable_type, audit.auditable_id)
    case audit.auditable_type
    when 'Lead' then alvo_lead(audit, registro)
    when 'Contact' then alvo_contato(audit, registro)
    when 'Conversation' then alvo_conversa(registro)
    else alvo_pessoa(audit, registro)
    end
  end

  def alvo_conversa(conversa)
    conversa && { contato_id: conversa.contact_id, nome: conversa.contact&.name, conversa: conversa.display_id }
  end

  # Meta, extrato e acesso: de quem é (a pessoa do registro).
  def alvo_pessoa(audit, registro)
    { nome: registro&.user&.name || nome('user_id', audit.audited_changes['user_id']) }
  end

  def alvo_lead(audit, lead)
    return { lead_id: lead.id, contato_id: lead.contact_id, nome: lead.name } if lead

    contato = audit.audited_changes['contact_id']
    { contato_id: contato, nome: contato && nome('contact_id', contato) }
  end

  def alvo_contato(audit, contato)
    base_id = mesclado_em(audit)
    return { contato_id: base_id, nome: nome('contact_id', base_id) } if base_id

    contato && { contato_id: contato.id, nome: contato.name }
  end
end

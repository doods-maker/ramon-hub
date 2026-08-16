# Leitura pura: tudo que a banca ja teve com a pessoa — casos, conversas e as
# ultimas notas. Para o agente nao tratar quem volta como se fosse novo.
class Captain::Tools::HistoricoDoContatoTool < Captain::Tools::RamonBaseTool
  description 'Historico da pessoa no hub: casos (tese, etapa, criado, ganho/perdido), conversas ' \
              '(data, canal, status, primeira mensagem) e as ultimas 5 notas. Use antes de responder quem ja e conhecido.'
  param :lead_id, type: 'string', desc: 'Id de um caso (lead) da pessoa. Sem ele, usa o caso da conversa aberta.', required: false
  param :contact_id, type: 'string', desc: 'Id do contato no hub, quando souber', required: false

  TETO = 5000
  NOTAS = 5
  CONVERSAS = 20

  def perform(tool_context, lead_id: nil, contact_id: nil)
    contact = resolver_contato(tool_context.state, lead_id, contact_id)
    return 'Nao encontrei a pessoa. Informe o lead_id ou o contact_id.' if contact.blank?

    log_tool_usage('historico_do_contato', { contact_id: contact.id })
    leads = account_scoped(::Lead).where(contact_id: contact.id).includes(:lead_stage, :thesis).to_a
    ["Pessoa: #{contact.name} (contact_id #{contact.id})", casos(leads), conversas(contact), notas(leads)]
      .join("\n\n").truncate(TETO)
  rescue StandardError => e
    Rails.logger.error("HistoricoDoContatoTool: #{e.class}: #{e.message}")
    'Nao consegui ler o historico agora. Siga sem ele.'
  end

  private

  def resolver_contato(state, lead_id, contact_id)
    id = Integer(contact_id.to_s, exception: false)
    return account_scoped(::Contact).find_by(id: id) if id

    resolver_lead(state, lead_id)&.contact || find_contact(state)
  end

  def casos(leads)
    return 'Casos: nenhum.' if leads.empty?

    linhas = leads.map do |l|
      "- ##{l.id} #{l.name} | tese: #{l.thesis&.name || '-'} | etapa: #{l.lead_stage&.name || '-'} | " \
        "criado #{data(l.created_at)}#{desfecho(l)}"
    end
    "Casos (#{leads.size}):\n#{linhas.join("\n")}"
  end

  def desfecho(lead)
    return " | GANHO em #{data(lead.won_at)}" if lead.won_at.present?
    return '' if lead.lost_at.blank?

    motivo = lead.lost_reason.present? ? " (#{lead.lost_reason})" : ''
    " | PERDIDO em #{data(lead.lost_at)}#{motivo}"
  end

  def conversas(contact)
    lista = contact.conversations.includes(:inbox).order(created_at: :desc).limit(CONVERSAS)
    return 'Conversas: nenhuma.' if lista.empty?

    linhas = lista.map do |c|
      primeira = c.messages.incoming.order(:created_at).pick(:content).to_s.squish.truncate(120)
      "- #{data(c.created_at)} | #{c.inbox&.name} | #{c.status} | #{primeira.presence || '(sem mensagem do cliente)'}"
    end
    "Conversas (#{lista.size}):\n#{linhas.join("\n")}"
  end

  def notas(leads)
    lista = ::LeadNote.unscoped.where(lead_id: leads.map(&:id)).includes(:user).order(created_at: :desc).limit(NOTAS)
    return 'Notas: nenhuma.' if lista.empty?

    linhas = lista.map { |n| "- #{data(n.created_at)} | #{n.user&.name || 'sistema'}: #{n.body.to_s.squish.truncate(200)}" }
    "Ultimas notas:\n#{linhas.join("\n")}"
  end

  def data(momento)
    momento&.in_time_zone('America/Sao_Paulo')&.strftime('%d/%m/%Y') || '-'
  end
end

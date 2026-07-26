# Leitura pura: a Linha da Vida da pessoa — todos os casos dela no hub e os
# marcos etarios (aposentadoria por idade, rural, BPC). Mesmo material da tela
# Pessoa, servido ao agente.
class Captain::Tools::LinhaDaVidaTool < Captain::Tools::RamonBaseTool
  description 'Linha da vida da pessoa: todos os casos dela no hub (etapa, tese, beneficio, valor) e os marcos ' \
              'etarios com a data em que cada um vence (aposentadoria por idade urbana e rural, BPC/LOAS). ' \
              'Use quando quiser ver o historico completo da pessoa, nao so um caso.'
  param :lead_id, type: 'string', desc: 'Id de um caso (lead) da pessoa. Sem ele, usa o caso da conversa aberta.', required: false
  param :contact_id, type: 'string', desc: 'Id do contato no hub, quando souber', required: false

  def perform(tool_context, lead_id: nil, contact_id: nil)
    contact = resolver_contato(tool_context.state, lead_id, contact_id)
    return 'Nao encontrei a pessoa. Informe o lead_id ou o contact_id.' if contact.blank?

    log_tool_usage('linha_da_vida', { contact_id: contact.id })
    { pessoa: pessoa(contact), casos: casos(contact), marcos: marcos(contact) }.to_json
  end

  private

  def resolver_contato(state, lead_id, contact_id)
    id = Integer(contact_id.to_s, exception: false)
    return account_scoped(::Contact).find_by(id: id) if id

    resolver_lead(state, lead_id)&.contact || find_contact(state)
  end

  def pessoa(contact)
    { contact_id: contact.id, nome: contact.name, nascimento: contact.data_nascimento, sexo: contact.sexo,
      cidade: contact.additional_attributes&.dig('city') }
  end

  def casos(contact)
    account_scoped(::Lead).where(contact_id: contact.id).includes(:lead_stage, :benefit_type, :thesis).map do |lead|
      { lead_id: lead.id, nome: lead.name, etapa: lead.lead_stage&.name, tese: lead.thesis&.name,
        beneficio: lead.benefit_type&.name, valor: lead.value&.to_f, origem: lead.source,
        criado_em: lead.created_at, ganho_em: lead.won_at, perdido_em: lead.lost_at }
    end
  end

  def marcos(contact)
    ::Ramon::MarcosEtarios.para(data_nascimento: contact.data_nascimento, sexo: contact.sexo)
  end
end

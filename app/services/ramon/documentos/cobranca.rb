# Cobrança da etapa Documentos (spec Etapa Documentos §7): a configuração (config/ramon/documentos_cobranca.yml: ritmo, horário,
# textos aprovados, modelo da Meta e preço) e o estado do relógio, na sub-chave custom_attributes['documentos_cobranca'] do lead.
# O estado só se grava aqui: num UPDATE da sub-chave (jsonb_set), sem regravar o resto do custom_attributes nem disparar os
# callbacks de cadência (lição do B4.3); e todo save comum do lead relê a sub-chave do banco sob a mesma trava (antes_de_salvar),
# para o DocMatch (reload + update! sem lock) não apagar uma marca gravada no meio do caminho.
module Ramon::Documentos::Cobranca
  CHAVE = 'documentos_cobranca'.freeze
  CONFIG = YAML.safe_load_file(Rails.root.join('config/ramon/documentos_cobranca.yml')).freeze
  MARCAR = "custom_attributes = jsonb_set(custom_attributes, '{#{CHAVE}}', (COALESCE(custom_attributes -> '#{CHAVE}', '{}'::jsonb) " \
           '- ARRAY(SELECT jsonb_array_elements_text(?::jsonb))) || ?::jsonb)'.freeze
  LIGAR = "custom_attributes = jsonb_set(custom_attributes, '{#{CHAVE}}', ?::jsonb)".freeze
  # O que a devolução à IA zera: o ciclo de lembretes e os gatilhos (a abertura é uma por entrada).
  RECOMECO = %w[lembrete_1_em lembrete_2_em silencio_em acompanhamento_em travado_em].freeze

  module_function

  # marcas: { 'passo_em' => iso8601 }; remover: chaves que saem antes.
  def marcar(lead, marcas, remover: [])
    Lead.unscoped.where(id: lead.id).update_all([MARCAR, remover.to_json, marcas.to_json]) # rubocop:disable Rails/SkipsModelValidations
  end

  # Entrada em Documentos: o relógio do zero.
  def ligar(lead)
    Lead.unscoped.where(id: lead.id).update_all([LIGAR, { 'entrou_em' => Time.current.iso8601 }.to_json]) # rubocop:disable Rails/SkipsModelValidations
  end

  # Uma pessoa devolveu a conversa à IA ("Devolver à IA": a conversa sai de aberta para pendente, ou perde a Pausa já
  # pendente; RamonLeadListener#conversation_updated): o ciclo recomeça da devolução — dois lembretes "até uma pessoa agir".
  def devolvida(conversa, mudancas)
    return unless conversa.pending? && devolucao?(mudancas.to_h.stringify_keys)

    lead = conversa.account.leads.find_by(conversation_id: conversa.id)
    marcar(lead, { 'devolvido_em' => Time.current.iso8601 }, remover: RECOMECO) if lead && em_documentos?(lead) && lead.custom_attributes.key?(CHAVE)
  end

  def devolucao?(mudancas)
    pausa = Array(mudancas['custom_attributes']).map { |attrs| attrs.to_h[Ramon::PerfilIa::PAUSA] }
    Array(mudancas['status']).map(&:to_s) == %w[open pending] || (pausa.first.present? && pausa.last.blank?)
  end

  # before_save do lead (LeadDocs). Em Documentos, a sub-chave que vale é a do banco, lida com FOR UPDATE: o UPDATE de marcar
  # espera esta transação ou já terminou; documento novo neste save (item que passou a recebido, de quem for) entra junto.
  # Fora de Documentos, o estado não existe: o save que já grava o custom_attributes leva sem ele.
  def antes_de_salvar(lead)
    return unless lead.persisted? && lead.custom_attributes_changed? && na_cobranca?(lead)

    lead.custom_attributes = lead.custom_attributes.except(CHAVE).merge(em_documentos?(lead) ? do_banco_com_documento(lead) : {})
  end

  # Saiu de Documentos (Jurídico, perdido, arrastado): o estado sai junto, num UPDATE que confere a etapa no banco
  # (RamonLeadListener, depois que a etapa mudou).
  def desligar_fora_de_documentos(lead)
    Lead.unscoped.where(id: lead.id).where("custom_attributes -> '#{CHAVE}' IS NOT NULL")
        .where.not(lead_stage_id: LeadStage.where(label: Ramon::EtapaDeGanho::DOCUMENTOS).select(:id))
        .update_all("custom_attributes = custom_attributes - '#{CHAVE}'") # rubocop:disable Rails/SkipsModelValidations
  end

  def em_documentos?(lead) = lead.lead_stage&.label == Ramon::EtapaDeGanho::DOCUMENTOS

  def do_banco_com_documento(lead)
    atual = do_banco(lead)
    return {} unless atual

    { CHAVE => documento_novo?(lead) ? atual.merge('ultimo_documento_em' => Time.current.iso8601) : atual }
  end

  def na_cobranca?(lead) = lead.custom_attributes.key?(CHAVE) || lead.custom_attributes_was.to_h.key?(CHAVE)

  def do_banco(lead) = Lead.unscoped.where(id: lead.id).lock.pick(Arel.sql("custom_attributes ->> '#{CHAVE}'"))&.then { |json| JSON.parse(json) }

  def documento_novo?(lead)
    antes = lead.custom_attributes_was.to_h['doc_status'] || {}
    lead.custom_attributes['doc_status'].to_h.any? { |id, status| status == 'recebido' && antes[id] != 'recebido' }
  end
end

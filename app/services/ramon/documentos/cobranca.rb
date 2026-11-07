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

  module_function

  # marcas: { 'passo_em' => iso8601 }; remover: chaves que saem antes.
  def marcar(lead, marcas, remover: [])
    Lead.unscoped.where(id: lead.id).update_all([MARCAR, remover.to_json, marcas.to_json]) # rubocop:disable Rails/SkipsModelValidations
  end

  # Entrada em Documentos: o relógio do zero.
  def ligar(lead)
    Lead.unscoped.where(id: lead.id).update_all([LIGAR, { 'entrou_em' => Time.current.iso8601 }.to_json]) # rubocop:disable Rails/SkipsModelValidations
  end

  # before_save do lead (LeadDocs). A sub-chave que vale é a do banco, lida com FOR UPDATE: o UPDATE de marcar espera esta
  # transação ou já terminou. Documento novo neste save (item que passou a recebido, de quem for) entra junto.
  def antes_de_salvar(lead)
    return unless lead.persisted? && lead.custom_attributes_changed? && na_cobranca?(lead)

    atual = do_banco(lead)
    atual = atual.merge('ultimo_documento_em' => Time.current.iso8601) if atual && documento_novo?(lead)
    lead.custom_attributes = lead.custom_attributes.except(CHAVE).merge(atual ? { CHAVE => atual } : {})
  end

  def na_cobranca?(lead) = lead.custom_attributes.key?(CHAVE) || lead.custom_attributes_was.to_h.key?(CHAVE)

  def do_banco(lead) = Lead.unscoped.where(id: lead.id).lock.pick(Arel.sql("custom_attributes ->> '#{CHAVE}'"))&.then { |json| JSON.parse(json) }

  def documento_novo?(lead)
    antes = lead.custom_attributes_was.to_h['doc_status'] || {}
    lead.custom_attributes['doc_status'].to_h.any? { |id, status| status == 'recebido' && antes[id] != 'recebido' }
  end
end

# Testar com tese (spec §3.8.5): o motor de verdade num lead descartável, dentro de uma transação desfeita — nada
# fica gravado (lead, respostas, histórico, sugestões, sino). As tools do roteiro passam pelo mesmo caminho do lead
# real (Captain::Tools::RamonBaseTool#no_roteiro): só o lead muda. O estado do roteiro vai e volta pelo Testar.
# teste = { 'thesis_id' => id, 'estado' => estado do roteiro ou nil }
# ponytail: o push do ntfy (perform_later) sai da transação, acha o lead apagado e não envia.
module Ramon::Roteiro::Teste
  NOME = 'Teste do roteiro'.freeze

  module_function

  # Do corpo do playground: só tese da conta; estado vira Hash simples (chaves texto).
  def de_params(account, roteiro)
    roteiro = (roteiro || {}).to_h.with_indifferent_access
    tese = account.theses.find_by(id: roteiro[:thesis_id]) if roteiro[:thesis_id].present?
    tese && { 'thesis_id' => tese.id, 'estado' => roteiro[:estado].presence&.to_hash }
  end

  # Roda o bloco com o lead descartável e devolve o resultado dele; o estado do roteiro depois volta para o teste.
  # Erro no bloco desfaz tudo e sobe (a tool trata, como no lead real).
  def com_lead(account, teste)
    resultado = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      lead = account.leads.create!(name: NOME, thesis_id: teste['thesis_id'], lead_stage: etapa_aberta(account),
                                   custom_attributes: { 'roteiro' => teste['estado'] }.compact)
      resultado = yield lead
      teste['estado'] = lead.reload.custom_attributes['roteiro']
      raise ActiveRecord::Rollback
    end
    resultado
  end

  def etapa_aberta(account)
    account.lead_stages.where(is_won: false, is_lost: false).order(:position).first
  end

  # O que o Testar recebe de volta: o estado (vai de novo na próxima mensagem) e o passo a passo para a tela.
  def resposta(account, teste)
    painel = com_lead(account, teste) { |lead| Ramon::Roteiro::Painel.montar(lead) }
    { 'thesis_id' => teste['thesis_id'], 'estado' => teste['estado'], 'painel' => painel }
  end
end

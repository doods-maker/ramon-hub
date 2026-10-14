# Testar com tese (spec §3.8.5): o motor de verdade num lead descartável, dentro de uma transação desfeita — nada
# fica gravado (lead, respostas, histórico, sugestões, sino). Sem conversa = fora do piloto total (Perdido vira
# sugestão, como em rascunho). O estado do roteiro vai e volta pelo Testar a cada mensagem.
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

  # Texto do passo atual para a IA; nil = a tese não tem roteiro.
  def atual(account, teste)
    rodar(account, teste) do |lead|
      atual = Ramon::Roteiro.atual(lead)
      Ramon::Roteiro.descrever(atual[:passo], atual[:estado]) if atual
    end.first
  end

  # @return [texto para a IA, estado depois]
  def registrar(account, teste, chave:, valor: nil, saida_id: nil)
    rodar(account, teste) do |lead|
      res = Ramon::Roteiro.registrar(lead, chave: chave, valor: valor, saida_id: saida_id)
      res[:erro] || Ramon::Roteiro.resumo(res)
    end
  end

  def painel(account, teste)
    rodar(account, teste) { |lead| Ramon::Roteiro::Painel.montar(lead) }.first
  end

  # O que o Testar recebe de volta: o estado (vai de novo na próxima mensagem) e o passo a passo para a tela.
  def resposta(account, teste)
    { 'thesis_id' => teste['thesis_id'], 'estado' => teste['estado'], 'painel' => painel(account, teste) }
  end

  # @return [resultado do bloco, estado do roteiro depois]
  def rodar(account, teste)
    saida = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      etapa = account.lead_stages.where(is_won: false, is_lost: false).order(:position).first
      lead = account.leads.create!(name: NOME, thesis_id: teste['thesis_id'], lead_stage: etapa,
                                   custom_attributes: { 'roteiro' => teste['estado'] }.compact)
      resultado = yield lead
      saida = [resultado, lead.reload.custom_attributes['roteiro']]
      raise ActiveRecord::Rollback
    end
    saida
  end
end

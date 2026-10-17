# Testar com tese (spec §3.8.5): o motor de verdade num lead descartável, dentro de uma transação desfeita — nada
# fica gravado (lead, respostas, histórico, sugestões, sino). As tools do roteiro passam pelo mesmo caminho do lead
# real (Captain::Tools::RamonBaseTool#no_roteiro): só o lead muda. O estado do roteiro vai e volta pelo Testar.
# teste = { 'thesis_id' => id ou nil (lead sem tese), 'estado' => estado do roteiro ou nil,
#           'perfil' => cfg do Perfil da IA da tela (salvo ou não) ou nil (vale o da tese do lead, ou o padrão) }
# ponytail: o push do ntfy (perform_later) sai da transação, acha o lead apagado e não envia.
module Ramon::Roteiro::Teste
  NOME = 'Teste do roteiro'.freeze

  module_function

  # Do corpo do playground. nil = Testar sem roteiro (ou tese de outra conta). thesis_id vazio = lead sem tese: roda os
  # passos comuns, inclusive o "assunto". perfil = o cfg da tela, normalizado (sozinha antes do Marcador aplica
  # etapa/Perdido na hora); sem ele, Ramon::PerfilIa.de usa o cfg em vigor para a tese do lead. O 'modo' antigo do
  # front é ignorado. O contrato automático exige conversa e não dispara no lead descartável (inofensivo).
  def de_params(account, roteiro)
    roteiro = roteiro.to_h.with_indifferent_access # nil.to_h = {}
    return if roteiro.empty?

    tese = account.theses.find_by(id: roteiro[:thesis_id]) if roteiro[:thesis_id].present?
    return if roteiro[:thesis_id].present? && tese.nil?

    { 'thesis_id' => tese&.id, 'estado' => roteiro[:estado].presence&.to_hash, 'perfil' => perfil_da_tela(roteiro[:perfil]) }
  end

  def perfil_da_tela(perfil)
    Ramon::PerfilIa.normalizar(perfil.to_hash) if perfil.is_a?(Hash)
  end

  # Roda o bloco com o lead descartável e devolve o resultado dele; o estado do roteiro depois volta para o teste.
  # Erro no bloco desfaz tudo e sobe (a tool trata, como no lead real).
  def com_lead(account, teste)
    resultado = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      # Conta própria: o lead e o que nasce dele (sugestões via lead.account) ficam no cache de associação dela, não no
      # account de quem chamou — depois do rollback voltariam como registros novos e o próximo save daquele account os
      # gravaria de novo (autosave do has_many).
      conta = Account.find(account.id)
      lead = conta.leads.create!(name: NOME, thesis_id: teste['thesis_id'], lead_stage: etapa_aberta(conta),
                                 custom_attributes: { 'roteiro' => teste['estado'] }.compact)
      lead.perfil_ia_simulado = teste['perfil']
      resultado = yield lead
      lead.reload
      # o "assunto" pode ter escolhido a tese do lead sem tese: ela vale nas próximas mensagens do Testar
      teste['estado'] = lead.custom_attributes['roteiro']
      teste['thesis_id'] = lead.thesis_id
      raise ActiveRecord::Rollback
    end
    resultado
  end

  # O Perfil do turno no Testar (spec, sugestão 2): o do lead descartável no início do turno — 1ª Etapa aberta, tese do
  # teste e o cfg da tela (não salvo) ou, sem ele, o em vigor. Dá as Tools bloqueadas e os gatilhos do prompt do turno.
  # account_id (não account): o lead não entra no cache account.leads (ver com_lead).
  def perfil(account, teste)
    lead = Lead.new(account_id: account.id, thesis_id: teste['thesis_id'], lead_stage: etapa_aberta(account))
    lead.perfil_ia_simulado = teste['perfil']
    Ramon::PerfilIa.de(lead)
  end

  # O que o Perfil faria com a resposta do playground: a mesma decisão do ResponseBuilderJob (decidir_turno, com o
  # relógio de agora). ponytail: logística não é classificada no Testar (o classificador custa LLM) — vai nil.
  def decisao(perfil, resposta)
    handoff = resposta['handoff_tool_called'] == true || resposta['response'] == 'conversation_handoff' || resposta['action'] == 'handoff'
    valor, motivo = perfil.decidir_turno(resposta, logistica: nil, handoff: handoff)
    { 'decisao' => { 'valor' => valor.to_s, 'motivo' => motivo }.merge(limitada_pelo_marcador(perfil, motivo)),
      'bloqueadas' => perfil.tools_bloqueadas }
  end

  # Depois do Marcador a Tool de texto vira rascunho mesmo com a permissão da ação em Sozinha ("acao:x" no motivo): a tela diz
  # que quem limitou foi o Marcador, não a ação.
  def limitada_pelo_marcador(perfil, motivo)
    acao = motivo.to_s[/\Aacao:(.+)\z/, 1]
    acao && perfil.permissao(acao) != :rascunho ? { 'limitado' => true } : {}
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

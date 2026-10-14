# Motor do roteiro da tese (spec docs/superpowers/specs/2026-10-13-roteiro-da-tese-design.md §3.2–3.4).
# Regra fixa: a IA pergunta e informa a resposta; aqui se grava, se faz a conta e se escolhe a saída.
# Estado em lead.custom_attributes['roteiro']:
#   tese_id · cursor (chave; muda no ir_para e na correção) · desfecho (qualificado|desqualificado|humano) · motivo ·
#   decisivo (passo que encerrou) · aguarda_equipe (Perdido virou sugestão) · respostas { chave => { valor, calc, saida, em } }
# Passo atual = o 1º sem resposta a partir do cursor: resposta adiantada pelo lead não é perguntada de novo.
# ponytail: last-write-wins no custom_attributes (duas respostas no mesmo instante); with_lock se aparecer corrida.
module Ramon::Roteiro
  TIPOS = { 'sim_nao' => 'sim ou nao', 'escolha' => 'uma das opcoes', 'numero' => 'numero',
            'data' => 'data AAAA-MM-DD', 'texto' => 'texto livre' }.freeze
  COMUNS_OK = 'Passos comuns concluidos e esta tese nao tem roteiro proprio: siga a triagem de sempre ' \
              '(playbook da tese e registrar qualificacao).'.freeze
  # Passo comum que descobre a tese do lead que chegou sem (spec §3.6, F3). Chave fixa.
  ASSUNTO = 'assunto'.freeze
  # Desfechos do roteiro (spec §3.2) — fonte única: a ação da saída que encerra → o desfecho.
  QUALIFICADO = 'qualificado'.freeze
  DESQUALIFICADO = 'desqualificado'.freeze
  HUMANO = 'humano'.freeze
  DESFECHO_DA_ACAO = { 'concluir' => QUALIFICADO, 'desqualificar' => DESQUALIFICADO, 'humano' => HUMANO }.freeze
  # Saída que o motor monta quando nada casa ou o destino não existe (spec §5: equipe + aviso ao admin).
  SEM_SAIDA = 'sem_saida'.freeze

  module_function

  # Comuns da conta (em toda tese) e depois os da tese. Nenhum passo = sem roteiro (triagem de sempre).
  # Lead sem tese (F3): só os comuns, e só se existir o comum "assunto" — é ele que descobre a tese. Com tese, ele sai.
  def passos(lead)
    comuns = RoteiroPasso.comuns.where(account_id: lead.account_id).to_a
    sem_tese = lead.thesis_id.nil?
    return [] if sem_tese && comuns.none? { |p| p.chave == ASSUNTO }
    return comuns if sem_tese

    comuns.reject { |p| p.chave == ASSUNTO } + RoteiroPasso.where(thesis_id: lead.thesis_id).to_a
  end

  # Trocar a tese reinicia o roteiro; as respostas dos passos comuns ficam, menos a que encerrou o roteiro.
  def estado(lead)
    salvo = (lead.custom_attributes || {})['roteiro'].deep_dup || {}
    return salvo.reverse_merge('respostas' => {}) if salvo['tese_id'] == lead.thesis_id

    comuns = RoteiroPasso.comuns.where(account_id: lead.account_id).pluck(:chave)
    { 'tese_id' => lead.thesis_id, 'respostas' => (salvo['respostas'] || {}).slice(*comuns).except(salvo['decisivo']) }
  end

  def proximo(lista, est)
    lista[indice(lista, est['cursor'])..].find { |p| !est['respostas'].key?(p.chave) }
  end

  # cursor nil (ou passo que sumiu) = 1º passo.
  def indice(lista, chave)
    lista.index { |p| p.chave == chave } || 0
  end

  # Correção e reabrir só VOLTAM o cursor: ir para frente pularia passos anteriores ainda sem resposta.
  def voltar_cursor(lista, est, chave)
    est['cursor'] = chave if indice(lista, chave) < indice(lista, est['cursor'])
  end

  def atual(lead)
    lista = passos(lead)
    return if lista.empty?

    est = estado(lead)
    { passo: est['desfecho'] ? nil : proximo(lista, est), estado: est }
  end

  # Texto do passo atual para a IA (tool roteiro_passo_atual, no lead real ou no Testar); nil = sem roteiro.
  def texto_atual(lead)
    atual = atual(lead)
    atual && descrever(atual[:passo], atual[:estado])
  end

  def registrar(lead, chave:, valor: nil, saida_id: nil)
    Registro.new(lead).call(chave: chave, valor: valor, saida_id: saida_id)
  end

  # Reabre no passo que decidiu (as outras respostas ficam) e devolve a conversa ao modo de antes (decisões 13/10).
  # Chamado ao recusar o Perdido sugerido pelo roteiro, ao tirar o lead do Perdido no Kanban e, na F2, pelo painel.
  def reabrir(lead, se: nil) # rubocop:disable Naming/MethodParameterName -- `se:` é a interface do plano
    est = estado(lead)
    return false if est['desfecho'].nil? || (se && est['desfecho'] != se)

    est['respostas'].delete(est['decisivo'])
    voltar_cursor(passos(lead), est, est['decisivo'])
    novo = est.except('desfecho', 'motivo', 'decisivo', 'aguarda_equipe')
    novo['passo'] = proximo(passos(lead), novo)&.chave # bi_roteiro: mesmo valor que Registro#gravar escreveria
    lead.update!(custom_attributes: (lead.custom_attributes || {}).merge('roteiro' => novo))
    Efeitos.reabrir(lead)
    true
  end

  # Texto para a IA: o passo a perguntar (ou o desfecho) e o que já foi respondido.
  def descrever(passo, est)
    return encerrado(est) if passo.nil?

    respondidas = est['respostas'].map { |chave, r| "#{chave}=#{r['valor'] || r['saida']}" }
    linhas = linhas_do_passo(passo)
    linhas << "Ja respondido: #{respondidas.join('; ')}" if respondidas.any?
    linhas.join("\n")
  end

  def linhas_do_passo(passo)
    linhas = ["Passo atual: #{passo.titulo} (chave: #{passo.chave}; resposta: #{TIPOS[passo.tipo_resposta]})"]
    linhas << "Como perguntar: #{passo.orientacao}" if passo.orientacao.present?
    linhas << "Opcoes: #{passo.opcoes.join(' | ')}" if passo.tipo_resposta == 'escolha'
    saidas = passo.saidas.map { |s| "#{s['id']} = #{s['quando']}" }.join('; ')
    linhas << "Saidas (informe saida_id): #{saidas}" if passo.tipo_resposta == 'texto' && saidas.present?
    linhas
  end

  def encerrado(est)
    return COMUNS_OK if est['desfecho'].nil?

    motivo = " (#{est['motivo']})" if est['motivo']
    espera = ' - aguardando a equipe confirmar' if est['aguarda_equipe']
    "Roteiro encerrado: #{est['desfecho']}#{motivo}#{espera}. Nao faca mais perguntas do roteiro."
  end

  # Texto para a IA depois de registrar.
  def resumo(res)
    partes = ['Registrado.']
    partes << "Conta: #{res[:calc][:resultado]} (#{res[:calc][:detalhe]})." if res[:calc]
    partes << "Base para a resposta: #{res[:mensagem]}" if res[:mensagem].present?
    partes << descrever(res[:proximo], res[:estado])
    partes.join("\n")
  end
end

# Motor do roteiro da tese (spec docs/superpowers/specs/2026-10-13-roteiro-da-tese-design.md §3.2–3.4).
# Regra fixa: a IA pergunta e informa a resposta; aqui se grava, se faz a conta e se escolhe a saída.
# Constantes irmãs sempre com o nome completo (Ramon::Roteiro::Registro): no CI a recarga de código deixa o módulo
# velho nas mãos do spec, e a busca curta ali dá NameError.
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
  def passos(lead) = passos_de(lead.account_id, lead.thesis_id)

  def passos_de(account_id, thesis_id)
    comuns = RoteiroPasso.comuns.where(account_id: account_id).to_a
    return [] if thesis_id.nil? && comuns.none? { |p| p.chave == ASSUNTO }
    return comuns if thesis_id.nil?

    comuns.reject { |p| p.chave == ASSUNTO } + RoteiroPasso.where(thesis_id: thesis_id).to_a
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
    Ramon::Roteiro::Registro.new(lead).call(chave: chave, valor: valor, saida_id: saida_id)
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
    Ramon::Roteiro::Efeitos.reabrir(lead, est['desfecho'])
    true
  end

  # Texto para a IA: o passo a perguntar (ou o desfecho) e o que já foi respondido.
  def descrever(passo, est)
    return encerrado(est) if passo.nil?

    respondidas = est['respostas'].map { |chave, r| "#{chave}=#{r['valor'] || r['saida']}" }
    linhas = linhas_do_passo(passo)
    seguinte = junto(passo, est)
    linhas << "Pode perguntar junto, na mesma mensagem: #{linhas_do_passo(seguinte, 'Passo seguinte').join(' / ')}" if seguinte
    linhas << "Ja respondido: #{respondidas.join('; ')}" if respondidas.any?
    linhas.join("\n")
  end

  # Perguntas em bloco (custo da Meta, decisão 15/10): passo sem saída não decide nada, então o seguinte é sempre o
  # próximo sem resposta da lista. O seguinte também não pode decidir nada ("tem advogado?" vai sozinho), nem mandar
  # não perguntar (ex.: enquadramento).
  def junto(passo, est)
    return if passo.saidas.present?

    lista = passos_de(passo.account_id, est['tese_id'])
    seguinte = lista[(lista.index { |p| p.id == passo.id } || lista.size)..].drop(1).find { |p| !est['respostas'].key?(p.chave) }
    seguinte unless seguinte.nil? || seguinte.saidas.present? || seguinte.orientacao.to_s.match?(/n[ãa]o pergunte/i)
  end

  def linhas_do_passo(passo, rotulo = 'Passo atual')
    linhas = ["#{rotulo}: #{passo.titulo} (chave: #{passo.chave}; resposta: #{TIPOS[passo.tipo_resposta]})"]
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

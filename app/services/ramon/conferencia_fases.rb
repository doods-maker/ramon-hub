# Conferência de fases: refaz a tabela RamonConferenciaFase (processos judiciais ativos do ADVBOX) sem estourar o
# limite da API. Toda noite lista a carteira (/lawsuits, ~90 chamadas) e a última movimentação de cada processo
# (/last_movements, ~12) e só busca andamentos e tarefas dos processos que andaram desde a última vez — até
# LIMITE_BUSCAS por noite, então a carga inicial se completa em poucas noites. Os demais são recalculados com o
# que já está guardado (a etapa do ADVBOX pode ter mudado). A fase do painel é a mesma regra do Painel do Cliente
# (Ramon::PortalTexto.etapa_real). `aplicar!` grava no ADVBOX a etapa sugerida das linhas marcadas.
class Ramon::ConferenciaFases
  LIMITE_BUSCAS = 400 # processos buscados por noite (2 chamadas cada; ADVBOX = 500/dia/rota)
  LIMITE_APLICAR = 400 # PUT /lawsuits por vez
  PAGINA = 100
  PAUSA = 1 # s entre chamadas: rajada sem pausa leva HTTP 429 do ADVBOX
  T = Ramon::PortalTexto

  def initialize(account, pausa: PAUSA)
    @account = account
    @pausa = pausa
  end

  def atualizar!
    existentes = @account.ramon_conferencias_fase.index_by(&:lawsuit_id)
    ultimas = ultimas_movimentacoes
    @buscas = 0
    carteira_judicial_ativa.each do |lawsuit|
      linha = existentes.delete(lawsuit['id']) || @account.ramon_conferencias_fase.new(lawsuit_id: lawsuit['id'])
      processar!(linha, lawsuit, ultimas[lawsuit['id']])
    end
    existentes.each_value(&:destroy!) # saiu da carteira judicial ativa (arquivado no ADVBOX)
  end

  # Grava no ADVBOX a etapa sugerida das linhas marcadas "atualizar" (o clique do administrador é o "aprovado").
  def aplicar!(user)
    @account.ramon_conferencias_fase.para_aplicar.limit(LIMITE_APLICAR).each do |linha|
      pausar
      Ramon::AdvboxClient.update_lawsuit(linha.lawsuit_id, stages_id: linha.sugestao['etapa_id'])
      linha.update!(aplicado_em: Time.current, aplicado_por: user, erro_aplicacao: nil, etapa_advbox: linha.sugestao['etapa'],
                    etapa_advbox_id: linha.sugestao['etapa_id'], fase_advbox: linha.fase_painel, grupo: 'igual')
    rescue Ramon::AdvboxClient::RequestError, Ramon::AdvboxClient::UnavailableError => e
      linha.update!(erro_aplicacao: e.message.first(250))
    end
  end

  # Atributos da linha a partir do lawsuit do ADVBOX e do que está guardado (tribunal, agenda, último andamento).
  def classificar(linha, lawsuit)
    processo = processo(linha, lawsuit)
    etapa = T.etapa_real(processo)
    do_tribunal = T.etapa_do_tribunal(processo)
    fases = { fase_advbox: T.fase_de(lawsuit['stage'], lawsuit['step']), fase_painel: T.fase_de(etapa, lawsuit['step']) || 'documentos' }
    grupo = grupo(do_tribunal, *fases.values)
    { numero: lawsuit['process_number'], cliente: cliente(lawsuit), responsavel: lawsuit['responsible'], etapa_advbox: lawsuit['stage'],
      etapa_advbox_id: lawsuit['stages_id'], painel_titulo: T.etapa(etapa)['titulo'], grupo: grupo,
      sugestao: (sugestao(do_tribunal) if %w[atrasada baixa].include?(grupo)) }.merge(fases)
  end

  private

  # Busca de novo só o que andou (até LIMITE_BUSCAS por noite); processo novo que ficou pra depois não é salvo vazio.
  def processar!(linha, lawsuit, ultima)
    if @buscas < LIMITE_BUSCAS && precisa_buscar?(linha, ultima)
      buscar!(linha, lawsuit['id'])
      @buscas += 1
    end
    salvar!(linha, lawsuit) unless linha.new_record? && linha.ultimo_andamento.nil?
  end

  # O processo no formato do espelho do Painel do Cliente; o último andamento basta pra validar a baixa.
  def processo(linha, lawsuit)
    { 'numero' => lawsuit['process_number'], 'etapa' => lawsuit['stage'], 'fase' => lawsuit['step'], 'tribunal' => linha.tribunal,
      'agenda' => Array(linha.agenda).select { |a| a['quando'].to_s[0, 10] >= Date.current.iso8601 },
      'andamentos' => [{ 'data' => linha.ultimo_andamento.to_s }] }
  end

  def grupo(do_tribunal, fase_advbox, fase_painel)
    return 'baixa' if do_tribunal == T::ARQUIVADO
    return 'igual' if fase_advbox == fase_painel

    do_tribunal ? 'atrasada' : 'diferente'
  end

  # Sugestão nova invalida a marcação antiga (a equipe marcou outra etapa).
  def salvar!(linha, lawsuit)
    atributos = classificar(linha, lawsuit)
    atributos.merge!(atualizar: false, aplicado_em: nil, erro_aplicacao: nil) if linha.persisted? && linha.sugestao != atributos[:sugestao]
    linha.update!(atributos)
  end

  def precisa_buscar?(linha, ultima)
    linha.new_record? || linha.ultimo_andamento.nil? || (ultima.present? && ultima > linha.ultimo_andamento.to_s)
  end

  def buscar!(linha, lawsuit_id)
    andamentos = lista(chamar { Ramon::AdvboxClient.movements(lawsuit_id, limit: Ramon::PortalSyncService::LIMITE_ANDAMENTOS) })
                 .map { |m| { 'data' => m['date'].to_s[0, 10], 'titulo' => m['title'] } }
    tarefas = lista(chamar { Ramon::AdvboxClient.posts(lawsuit_id: lawsuit_id, limit: Ramon::PortalSyncService::LIMITE_TAREFAS) })
    linha.assign_attributes(tribunal: T.achado_do_tribunal(andamentos, linha.tribunal), agenda: Ramon::PortalSyncService.agenda(tarefas),
                            ultimo_andamento: andamentos.pluck('data').max || linha.ultimo_andamento || Date.current)
  end

  def cliente(lawsuit)
    Array(lawsuit['customers']).find { |c| c['origin'] != 'PARTE CONTRÁRIA' }&.dig('name')
  end

  def sugestao(etapa)
    id, nome = etapas_advbox[T.normalizar(etapa)]
    id && { 'etapa' => nome, 'etapa_id' => id }
  end

  def etapas_advbox
    @etapas_advbox ||= Array(chamar { Ramon::AdvboxClient.settings }['stages']).to_h { |s| [T.normalizar(s['stage']), [s['id'], s['stage']]] }
  end

  def carteira_judicial_ativa
    paginas { |off| Ramon::AdvboxClient.lawsuits(limit: PAGINA, offset: off) }
      .select { |l| T.cnj?({ 'numero' => l['process_number'] }) && T.normalizar(l['step']) != T::FASE_ENCERRADA }
  end

  # { lawsuit_id => 'AAAA-MM-DD' } da última movimentação de cada processo.
  def ultimas_movimentacoes
    paginas { |off| Ramon::AdvboxClient.last_movements(limit: PAGINA, offset: off) }
      .to_h { |m| [m['lawsuit_id'], m['date'].to_s[0, 10]] }
  end

  def paginas
    primeira = chamar { yield 0 }
    total = primeira.is_a?(Hash) ? primeira['totalCount'].to_i : 0
    lista(primeira) + (PAGINA...total).step(PAGINA).flat_map { |off| lista(chamar { yield off }) }
  end

  def chamar
    pausar
    yield
  end

  def pausar = (sleep(@pausa) if @pausa.positive?)

  def lista(resposta) = Array(resposta.is_a?(Hash) ? resposta['data'] : resposta)
end

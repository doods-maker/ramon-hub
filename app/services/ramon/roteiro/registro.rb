# Registra a resposta da IA num passo do roteiro: normaliza, faz a conta, escolhe a saída, avança o estado e aplica
# os efeitos (spec 2026-10-13 §3.4 e §5). Porta de entrada: Ramon::Roteiro.registrar.
class Ramon::Roteiro::Registro
  SEGUIR = { 'id' => 'seguir', 'acao' => 'seguir' }.freeze
  DESFECHOS = { 'concluir' => 'qualificado', 'desqualificar' => 'desqualificado', 'humano' => 'humano' }.freeze

  def initialize(lead)
    @lead = lead
    @lista = Ramon::Roteiro.passos(lead)
    @est = Ramon::Roteiro.estado(lead)
  end

  # @return { erro: } | { estado:, proximo:, calc:, mensagem: }
  def call(chave:, valor: nil, saida_id: nil)
    @passo = @lista.find { |p| p.chave == chave.to_s }
    erro = recusa(chave)
    return { erro: erro } if erro

    normal, erro = ler(valor, saida_id)
    return { erro: erro } if erro

    return { erro: 'Informe o assunto em texto no valor.' } if assunto? && normal.blank?

    calc = calcular(normal)
    saida = saida_de(saida_id, normal, calc)
    return { erro: "A saida #{saida_id} nao existe neste passo." } if saida.nil?

    gravar(normal, calc, saida)
  end

  private

  def ler(valor, saida_id)
    normal, erro = Ramon::Roteiro::Resposta.normalizar(@passo, valor)
    erro ||= 'Informe o valor da resposta ou o saida_id.' if normal.nil? && saida_id.blank?
    [normal, erro]
  end

  def recusa(chave)
    return 'Este caso nao tem roteiro.' if @lista.empty?
    return "O roteiro ja terminou (#{@est['desfecho']}). Nao registre mais passos." if @est['desfecho']

    "Passo #{chave} nao existe. Passos: #{@lista.map(&:chave).join(', ')}." if @passo.nil?
  end

  # Campos da calculadora vêm das respostas; o do próprio passo, da resposta de agora.
  def calcular(valor)
    return if @passo.calculadora.blank?

    campos = @passo.calculadora_campos.transform_values do |chave|
      chave == @passo.chave ? valor : @est.dig('respostas', chave, 'valor')
    end
    Ramon::Roteiro::Calculadoras.calcular(@passo.calculadora, campos)
  end

  # Sem saídas = só coleta (segue). Com saídas e nada casando = roteiro sem saída (equipe).
  def escolher(saida_id, comparado)
    return SEGUIR if @passo.saidas.blank?
    return @passo.saidas.find { |s| s['id'].to_s == saida_id.to_s } if saida_id.present?

    @passo.saidas.find { |s| Ramon::Roteiro::Resposta.casa?(s['quando'], comparado) } || sem_saida('nenhuma saida casou')
  end

  def saida_de(saida_id, normal, calc)
    return assunto(normal) if assunto?

    escolher(saida_id, calc ? calc[:resultado] : normal)
  end

  def assunto?
    @passo.thesis_id.nil? && @passo.chave == Ramon::Roteiro::ASSUNTO
  end

  # Passo comum "assunto" (F3): a resposta casa com nome/palavras-chave das teses. Casou com uma → o lead ganha a tese
  # e o roteiro segue nos passos dela (as respostas dos comuns ficam); nenhuma ou mais de uma → equipe.
  def assunto(texto)
    tese = Ramon::TeseAutomatica.por_texto(@lead.account, texto)
    return { 'id' => 'sem_tese', 'acao' => 'humano', 'motivo' => 'assunto sem tese cadastrada' } if tese.nil?

    @lead.update!(thesis: tese)
    @lista = Ramon::Roteiro.passos(@lead)
    @est = Ramon::Roteiro.estado(@lead)
    { 'id' => 'tese', 'acao' => 'seguir' }
  end

  def gravar(valor, calc, saida)
    guardar_resposta(valor, calc, saida)
    saida = avancar(saida)
    @est['aguarda_equipe'] = true if vira_sugestao_de_perdido?(saida)
    proximo = @est['desfecho'] ? nil : Ramon::Roteiro.proximo(@lista, @est)
    @est['passo'] = proximo&.chave # bi_roteiro (F4): onde o lead parou; ponytail: fica nulo depois do reabrir até o próximo registro
    ActiveRecord::Base.transaction do
      @lead.update!(custom_attributes: (@lead.custom_attributes || {}).merge('roteiro' => @est))
      Ramon::Roteiro::Efeitos.aplicar(@lead, @passo, saida)
    end
    { estado: @est, proximo: proximo, calc: calc, mensagem: saida['mensagem'] }
  end

  def guardar_resposta(valor, calc, saida)
    # Correção de um passo já respondido: vale a nova resposta e o roteiro volta a seguir dali (decisão 13/10) —
    # se o passo estiver antes do cursor; resposta adiantada corrigida não pula os anteriores.
    Ramon::Roteiro.voltar_cursor(@lista, @est, @passo.chave) if @est['respostas'].key?(@passo.chave)
    @est['respostas'][@passo.chave] = { 'valor' => valor, 'calc' => calc&.stringify_keys, 'saida' => saida['id'],
                                        'em' => Time.zone.now.iso8601 }.compact
  end

  # ir_para move o cursor; seguir/ir_para sem passo pela frente = concluir (qualificado) — menos numa tese sem
  # passos próprios: ao fim dos comuns a IA volta para a triagem de sempre, sem desfecho (decisão 13/10).
  def avancar(saida)
    if saida['acao'] == 'ir_para'
      return avancar(sem_saida("destino #{saida['alvo']} nao existe")) if @lista.none? { |p| p.chave == saida['alvo'] }

      @est['cursor'] = saida['alvo']
    end
    saida = saida.merge('acao' => 'concluir') if acabou?(saida)
    encerrar(saida)
    saida
  end

  # Só quando Efeitos.desqualificar de fato cria a sugestão (lead ganho/perdido sai cedo, sem ela).
  def vira_sugestao_de_perdido?(saida)
    saida['acao'] == 'desqualificar' && !Ramon::Roteiro::Efeitos.direto?(@lead) && @lead.won_at.nil? && @lead.lost_at.nil?
  end

  def acabou?(saida)
    %w[seguir ir_para].include?(saida['acao']) && Ramon::Roteiro.proximo(@lista, @est).nil? && @lista.any?(&:thesis_id)
  end

  def encerrar(saida)
    desfecho = DESFECHOS[saida['acao']]
    return if desfecho.nil?

    @est.merge!('desfecho' => desfecho, 'motivo' => saida['motivo'], 'decisivo' => @passo.chave)
  end

  def sem_saida(detalhe)
    { 'id' => 'sem_saida', 'acao' => 'humano', 'motivo' => "roteiro sem saida no passo #{@passo.chave} (#{detalhe})" }
  end
end

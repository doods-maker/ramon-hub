# Conferência do roteiro no salvar da tela (F2; desvio 6 da F1): "vai para" e campos da calculadora apontando para
# passos que existem, e chave sem repetir entre os comuns e a tese (o motor junta as duas listas pela chave).
# Fica fora do model porque o seed (F4) cria os passos em ordem — um "vai para" adiante ainda não existe na hora.
module Ramon::Roteiro::Conferencia
  module_function

  # @return [Array<String>] vazio = pode salvar
  def erros(passo)
    chaves = chaves_alcancaveis(passo)
    destinos = Array(passo.saidas).filter_map { |saida| saida['alvo'] if saida['acao'] == 'ir_para' }
    campos = (passo.calculadora_campos || {}).to_h
    [*(destinos.compact_blank - chaves).map { |chave| "o passo de destino '#{chave}' não existe neste roteiro" },
     *(campos.values.compact_blank - chaves).map { |chave| "a calculadora usa o passo '#{chave}', que não existe neste roteiro" },
     *campos_fora_da_calculadora(passo, campos.keys), colisao(passo)].compact.uniq
  end

  # Quem aponta para este passo ("vai para" ou campo da calculadora): remover quebraria o roteiro deles.
  def referencias(passo)
    escopo = RoteiroPasso.where(account_id: passo.account_id).where.not(id: passo.id)
    escopo = escopo.where(thesis_id: passo.thesis_id) if passo.thesis_id
    escopo.select { |outro| aponta?(outro, passo.chave) }.map(&:titulo)
  end

  # Passo comum só alcança os comuns (roda em toda tese); passo da tese alcança os comuns e os da tese.
  def chaves_alcancaveis(passo)
    escopo = RoteiroPasso.where(account_id: passo.account_id, thesis_id: [nil, passo.thesis_id].uniq)
    escopo.where.not(id: passo.id).pluck(:chave) << passo.chave
  end

  def campos_fora_da_calculadora(passo, nomes)
    return [] if passo.calculadora.blank?

    validos = Ramon::Roteiro::Calculadoras::CATALOGO.dig(passo.calculadora, :campos) || []
    (nomes.map(&:to_s) - validos).map { |nome| "a calculadora não tem o campo '#{nome}'" }
  end

  def colisao(passo)
    outros = RoteiroPasso.where(account_id: passo.account_id, chave: passo.chave).where.not(id: passo.id)
    return "a chave '#{passo.chave}' já existe nos passos comuns" if passo.thesis_id && outros.comuns.exists?

    "a chave '#{passo.chave}' já existe no roteiro de uma tese" if passo.thesis_id.nil? && outros.where.not(thesis_id: nil).exists?
  end

  def aponta?(outro, chave)
    Array(outro.saidas).any? { |saida| saida['acao'] == 'ir_para' && saida['alvo'] == chave } ||
      (outro.calculadora_campos || {}).value?(chave)
  end
end

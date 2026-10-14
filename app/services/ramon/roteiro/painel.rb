# Painel do lead e Testar (F2): o roteiro passo a passo — respondido, atual, a perguntar ou não perguntado (pulado
# pelo "vai para" ou depois do desfecho) — com o valor, o resultado da calculadora e o desfecho com motivo.
# nil = lead sem roteiro (o painel mostra a qualificação de sempre).
module Ramon::Roteiro::Painel
  module_function

  def montar(lead)
    atual = Ramon::Roteiro.atual(lead)
    return if atual.nil?

    est = atual[:estado]
    lista = Ramon::Roteiro.passos(lead)
    cursor = lista.index { |passo| passo.chave == est['cursor'] } || 0
    passos = lista.each_with_index.map { |passo, i| linha(passo, est, situacao(passo, i, cursor, atual[:passo], est)) }
    { 'desfecho' => est['desfecho'], 'motivo' => est['motivo'], 'decisivo' => est['decisivo'],
      'aguarda_equipe' => est['aguarda_equipe'] == true && lead.lost_at.nil?,
      'so_comuns' => lista.none?(&:thesis_id), 'passos' => passos }
  end

  def situacao(passo, indice, cursor, passo_atual, est)
    return 'respondido' if est['respostas'].key?(passo.chave)
    return 'atual' if passo_atual&.chave == passo.chave
    return 'fora' if est['desfecho'] || indice < cursor

    'pendente'
  end

  def linha(passo, est, situacao)
    resposta = est['respostas'][passo.chave] || {}
    { 'chave' => passo.chave, 'titulo' => passo.titulo, 'situacao' => situacao,
      'valor' => resposta['valor'], 'saida' => resposta['saida'], 'calc' => resposta['calc'] }
  end
end

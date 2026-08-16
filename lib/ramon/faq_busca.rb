# FORK-PONTO (ramon): a FAQ do Captain e buscada por texto (tsvector 'portuguese')
# em vez de embedding OpenAI — nesta instalacao so ha DeepSeek, sem embeddings.
# RAMON_FAQ_BUSCA=texto (padrao) | qualquer outro valor = comportamento vetorial original.
module Ramon::FaqBusca
  def self.textual?
    ENV.fetch('RAMON_FAQ_BUSCA', 'texto') == 'texto'
  end
end

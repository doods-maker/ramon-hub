# Monta desenhos de fluxo nos specs: gatilho → passos em fila pela saída 's'.
module FluxoHelpers
  def no_fluxo(id, tipo, config = {})
    { 'id' => id, 'tipo' => tipo, 'config' => config, 'posicao' => { 'x' => 0, 'y' => 0 } }
  end

  # passos: [['nota_privada', { 'texto' => 'oi' }], ['parar', {}]]
  def grafo_linear(gatilho_config, *passos)
    nos = [no_fluxo('g', 'gatilho', gatilho_config)]
    passos.each_with_index { |(tipo, config), i| nos << no_fluxo("p#{i + 1}", tipo, config || {}) }
    setas = nos.each_cons(2).map { |a, b| { 'de' => a['id'], 'saida' => 's', 'para' => b['id'] } }
    { 'nos' => nos, 'setas' => setas }
  end

  def fluxo_publicado(account, grafo, **attrs)
    fluxo = Fluxo.create!({ account: account, nome: 'Fluxo de teste', ativo: true, rascunho: grafo }.merge(attrs))
    fluxo.publicar!(nil)
    fluxo.reload
  end
end

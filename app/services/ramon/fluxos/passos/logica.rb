# Passos sem efeito fora do fluxo: decidir (se/escolha), esperar, parar.
module Ramon::Fluxos::Passos::Logica
  UNIDADES = { 'minutos' => :minutes, 'horas' => :hours, 'dias' => :days }.freeze

  module_function

  def se(config, ctx)
    ok = Ramon::Fluxos::Condicao.avaliar(config, ctx.dados)
    { saida: ok ? 'sim' : 'nao', resumo: ok ? 'sim' : 'não' }
  end

  def escolha(config, ctx)
    chave = Ramon::Fluxos::Condicao.escolher(config, ctx.dados)
    rotulo = Array(config['casos']).find { |c| c['chave'] == chave }&.dig('rotulo') || 'outro'
    { saida: chave, resumo: "#{config['campo']} → #{rotulo}" }
  end

  def esperar(config, ctx)
    return esperar_reuniao(config, ctx) if config['antes_de'] == 'reuniao'

    ate = config['ate'] == 'horario_comercial' ? Ramon::Fluxos::Horario.proximo(Time.current) : Time.current + duracao(config)
    { saida: 's', resumo: "espera até #{hora(ate)}", esperar_ate: ate }
  end

  # B4.1: conta para TRÁS a partir da reunião (lembretes). Momento já passado → não espera e marca
  # {horario_passou} = sim; o `se` seguinte pula o aviso — como o código, que só agenda os lembretes ainda futuros.
  def esperar_reuniao(config, ctx)
    inicio = ctx.reuniao_em || raise(Ramon::Fluxos::PassoImpossivel, 'sem reunião marcada para contar o tempo')
    ate = inicio - duracao(config)
    return { saida: 's', resumo: "#{hora(ate)} já passou: segue sem esperar", vars: { 'horario_passou' => 'sim' } } if ate.past?

    { saida: 's', resumo: "espera até #{hora(ate)}", esperar_ate: ate, vars: { 'horario_passou' => 'nao' } }
  end

  def duracao(config) = config['quantidade'].to_i.public_send(UNIDADES.fetch(config['unidade']))

  def hora(momento) = momento.in_time_zone(Fluxo::ZONA).strftime('%d/%m %H:%M')

  def parar(_config, _ctx) = { saida: nil, resumo: 'parou', parar: true }
end

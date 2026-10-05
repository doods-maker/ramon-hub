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

  def esperar(config, _ctx)
    ate = if config['ate'] == 'horario_comercial'
            Ramon::Fluxos::Horario.proximo(Time.current)
          else
            Time.current + config['quantidade'].to_i.public_send(UNIDADES.fetch(config['unidade']))
          end
    { saida: 's', resumo: "espera até #{ate.in_time_zone(Fluxo::ZONA).strftime('%d/%m %H:%M')}", esperar_ate: ate }
  end

  def parar(_config, _ctx) = { saida: nil, resumo: 'parou', parar: true }
end

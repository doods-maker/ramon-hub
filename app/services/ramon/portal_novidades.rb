# Novidades do Painel do Cliente: o que mudou entre o espelho de ontem e o de hoje.
# - etapa "interna" (ex.: NEGADO / AVISAR CLIENTE) não aparece pro cliente: o painel
#   segue na etapa anterior até a equipe mover o processo (notícia ruim chega por pessoa);
# - etapa/marco "delicada" (resultado) aparece com texto neutro, mas sem e-mail
#   automático — vai só pro resumo da equipe, com alerta;
# - etapa com 'email' => false (dicionário v2) aparece no painel, mas sem e-mail automático.
# 1º sync de um processo (sem espelho anterior) não gera novidade.
module Ramon::PortalNovidades
  RETENCAO = 30.days

  module_function

  def aplicar(anterior, novo, agora: Time.current)
    novo['etapa_cliente'] = etapa_cliente(anterior, novo['etapa'])
    novo['novidades'] = antigas(anterior) + (anterior ? detectar(anterior, novo, agora.iso8601) : [])
    novo
  end

  def etapa_cliente(anterior, etapa)
    return etapa unless Ramon::PortalTexto.interna?(etapa)
    return if anterior.nil?

    etapa_exibida(anterior)
  end

  # Espelho anterior ao PR de avisos não tem 'etapa_cliente'.
  def etapa_exibida(processo)
    return processo['etapa_cliente'] if processo.key?('etapa_cliente')

    processo['etapa'] unless Ramon::PortalTexto.interna?(processo['etapa'])
  end

  def antigas(anterior)
    Array(anterior&.dig('novidades')).reject do |n|
      n['vista'] && n['avisada'] && Time.zone.parse(n['em'].to_s).to_i < RETENCAO.ago.to_i
    end
  end

  def detectar(anterior, novo, quando)
    (novidade_de_etapa(anterior, novo) + marcos_novos(anterior, novo))
      .map { |n| n.merge('em' => quando, 'vista' => false, 'avisada' => false) }
  end

  def novidade_de_etapa(anterior, novo)
    atual = novo['etapa_cliente']
    return [] if atual.blank? || Ramon::PortalTexto.normalizar(atual) == Ramon::PortalTexto.normalizar(etapa_exibida(anterior))

    texto = Ramon::PortalTexto.etapa(atual)
    [{ 'tipo' => 'etapa', 'titulo' => texto['titulo'], 'o_que_esperar' => texto['o_que_esperar'], 'delicada' => texto['delicada'] == true,
       'email' => Ramon::PortalTexto.email?(atual) }]
  end

  def marcos_novos(anterior, novo)
    vistos = Ramon::PortalTexto.marcos(anterior['andamentos']).map { |m| [m['tipo'], m['data']] }
    Ramon::PortalTexto.marcos(novo['andamentos']).reject { |m| vistos.include?([m['tipo'], m['data']]) }.map do |m|
      { 'tipo' => 'marco', 'titulo' => m['titulo'], 'o_que_esperar' => m['explicacao'], 'delicada' => m['delicada'] == true }
    end
  end
end

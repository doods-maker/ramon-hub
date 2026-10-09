# B5-externos: a rotina pronta da chegada de cliente — o MESMO código de hoje (Chegada#escalar!). Decisão do Eduardo
# 08/10: a chegada é a única automação de fora do funil que roda no fluxo; assinatura e documento do Painel, contrato no
# ZapSign, ata da reunião e acervo das peças viraram regra fixa (código, sem chave).
# Contrato do registro Ramon::Fluxos::Rotinas: ROTINAS nome → alvo + rodar(nome, ctx) → String (o resumo da trilha); o
# ensaio só descreve; alvo errado = PassoImpossivel (falha na hora, sem nova tentativa). Na carga este módulo não cita
# Ramon::Fluxos::Migracao (autoload circular).
module Ramon::Fluxos::Rotinas::Externos
  # A migração da chegada (juntada em Migracao::GRUPOS pelo registro); quem decide cada evento é Ramon::Fluxos::Externos.evento.
  GRUPOS = {
    'chegada_cliente' => { env: 'RAMON_FLUXO_CHEGADA', faz: 'a escalada da chegada de cliente',
                           fluxos: { 'chegada_cliente' => 'chegada_cliente' }.freeze }
  }.freeze
  # 'outro' = o alvo é o registro do evento (a chegada), não lead nem conversa.
  ROTINAS = { 'escalar_chegada' => 'outro' }.freeze
  ALVOS = { 'Chegada' => 'uma chegada de cliente' }.freeze

  module_function

  def rodar(nome, ctx) = public_send(nome, ctx)

  def escalar_chegada(ctx)
    chegada = alvo!(ctx, Chegada)
    return 'chegada já respondida (ou já escalada): não escala' unless chegada.escalavel?
    return 'faria: escalar — o alerta volta a tocar na tela de quem avisou' if ctx.ensaio?

    chegada.escalar!
    'escalou: o alerta voltou a tocar na tela de quem avisou'
  end

  def alvo!(ctx, classe)
    alvo = ctx.execucao.alvo
    return alvo if alvo.is_a?(classe)

    raise Ramon::Fluxos::PassoImpossivel, "esta rotina só roda com #{ALVOS.fetch(classe.name)} (o Testar com um lead não serve aqui)"
  end
end

# B5 (spec §8): a automação que começa FORA do funil e roda no fluxo — a chegada de cliente (recepção), com a chave da
# B4.1 (env própria + o fluxo em modo normal). As outras 5 viraram regra fixa (decisão do Eduardo 08/10); os gatilhos
# delas seguem para fluxos comuns (N1 = B: cada ponto chama Disparo.externo direto). O grupo mora em
# Ramon::Fluxos::Migracao::GRUPOS.
# A decisão é do evento, lida UMA vez em `evento`:
# 1) Migracao.decidir: os fluxos migrados do grupo, com 'assumido' (agem, ou ensaiam), e o código (o bloco) se o fluxo
#    não está no comando OU não começou este evento (ocupado com o mesmo alvo, erro do motor, desligado no meio) — nada
#    se perde, nada em dobro;
# 2) os fluxos comuns desse gatilho, sem 'assumido', como sempre.
# O alvo é o registro do evento (a Chegada).
module Ramon::Fluxos::Externos
  module_function

  # Os gatilhos que estes pontos disparam duas vezes (Disparo::DUAS_VEZES).
  def gatilhos = Ramon::Fluxos::Migracao.gatilhos('chegada_cliente').values

  def evento(grupo, gatilho, alvo, dados = {}, &)
    Ramon::Fluxos::Migracao.decidir(grupo, gatilho, alvo, dados, &)
    Ramon::Fluxos::Disparo.externo(gatilho, alvo, dados)
  end
end

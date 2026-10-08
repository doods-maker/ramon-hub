# B5 (spec §8): as automações que começam FORA do funil — webhook do ZapSign, Painel do Cliente, recepção, gravação de
# reunião, peças do Instagram — cada uma com a chave da B4.1 (env própria + os fluxos do grupo em modo normal). Os 6
# grupos moram em Ramon::Fluxos::Rotinas::Externos::GRUPOS (o registro os junta em Migracao::GRUPOS).
# A decisão é do evento, lida UMA vez em `evento`:
# 1) Migracao.decidir: os fluxos migrados do grupo, com 'assumido' (agem, ou ensaiam), e o código (o bloco) se o fluxo
#    não está no comando OU não começou este evento (ocupado com o mesmo alvo, erro do motor, desligado no meio) — nada
#    se perde, nada em dobro;
# 2) os fluxos comuns desse gatilho, sem 'assumido', como sempre.
# O alvo é o registro do evento (PortalAssinatura, PortalEnvio, Chegada, Reuniao, Peca) — só o contrato é do lead.
module Ramon::Fluxos::Externos
  module_function

  # Os gatilhos que estes pontos disparam duas vezes (Disparo::DUAS_VEZES).
  def gatilhos = Ramon::Fluxos::Rotinas::Externos::GRUPOS.values.flat_map { |g| g[:fluxos].values }

  def evento(grupo, gatilho, alvo, dados = {}, &)
    Ramon::Fluxos::Migracao.decidir(grupo, gatilho, alvo, dados, &)
    Ramon::Fluxos::Disparo.externo(gatilho, alvo, dados)
  end
end

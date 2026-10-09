# Critério fluxo × regra fixa

Em 2026-10-07 a decisão era migrar para fluxo todas as 29 automações do código.
As B5 migraram mais 16, mas nenhuma chegou a ser ligada — e cada migração deixa
caminho duplo (código de reserva, env, chave, rake, JSON) que custa manutenção
sem ganho enquanto a regra não muda.

Decidimos (Eduardo, 2026-10-08) o critério: **migra para fluxo só a automação
cuja regra de negócio vai MUDAR ou TIRAR comportamento**. Para **ACRESCENTAR**
comportamento ao mesmo evento, não se migra: monta-se um Fluxo comum no mesmo
Gatilho, ao lado da regra fixa.

- **7 no fluxo** (já ligadas em produção): reuniões, SLA da 1ª resposta,
  cadência de retomada, lead ganho, eventos do ADVBOX, chegada de cliente e
  resumo do dia.
- **22 regras fixas** (ficam no código de propósito): as 6 que já tinham o selo
  (histórico do lead, documentos completos, contrato limpo, contrato limpo
  cancelado, SDR automático, etiquetas de etapa e tese) + as 16 das B5 nunca
  ligadas. Os andaimes delas saíram (grupos, `migrados/*.json`, envs, rotinas
  prontas, pontos de decisão); mudar uma regra fixa é pedir ao Claude.
- **Ficha no hub para as 29**: o que faz, quando, o que mexe, travas, por que
  está onde está e como pedir mudança (arquivos citados travados por spec); nas
  7, o link para o fluxo de verdade.
- **Os 5 gatilhos de fora do funil ficam** (assinatura e documento pelo Painel,
  reunião gravada, peça publicada, peça mudou de status), contra a recomendação
  do plano, para os fluxos comuns do Eduardo: o código roda a linha de sempre e
  dispara esses fluxos uma vez, sem decisão. Como o alvo não é lead, só aceitam
  Passos que rodam sem lead.

Alternativas descartadas:

- **Migrar todas** (a decisão de 07/10): 16 caminhos duplos para regras que
  ninguém pediu para mudar.
- **Nada em fluxo**: perde-se a edição na tela exatamente onde a regra muda
  (horários e avisos de reunião, SLA, cadência).
- **Tirar os 5 gatilhos junto com as automações**: fecharia a porta para o
  Eduardo acrescentar comportamento a esses eventos sem pedir código.

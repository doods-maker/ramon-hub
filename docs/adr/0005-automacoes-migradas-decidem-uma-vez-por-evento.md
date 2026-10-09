# Automações migradas decidem uma vez por evento, com o código de reserva

As automações da banca nasceram no código (reuniões, SLA, cadência, lead ganho,
eventos do ADVBOX, chegada, resumo do dia…). Passar uma delas para um Fluxo
editável tem um risco que o usuário sente na hora: o evento ser feito **em dobro**
(código e fluxo) ou **nenhuma vez** (cada um achando que é do outro) — num
deploy, numa env esquecida ou numa edição do fluxo.

Decidimos (2026-10-06, generalizado em 2026-10-07) que **quem decide é o evento,
uma vez só**. No ponto do código onde o evento acontece, `Ramon::Fluxos::Migracao`
lê `assumiu?(conta, grupo)` uma vez e manda o resultado (`assumido`) no gatilho;
`Migracao.decidir(grupo, gatilho, alvo, dados) { código de hoje }` dispara os
fluxos migrados do grupo e roda o bloco do código `unless assumido && feitas.any?`.

- **Fluxo no comando** = env do grupo `on` **e** os fluxos dele (`sistema_chave`)
  ligados, publicados, em modo normal, com o gatilho certo e sem limite do dia
  (salvo grupo que registra `limite_devolve: false`, como a cadência). Qualquer
  peça fora → o código faz e os fluxos migrados só ensaiam (**sombra**).
- **Reserva pelo código:** no comando, se o fluxo não começou aquele evento
  (ocupado com o mesmo alvo, filtro editado, erro do motor antes de criar a
  execução), o código faz como antes. Execução que começou e falhou conta como
  feita — a falha aparece na tela de execuções, o código não repete.
- **Dois disparos por evento** nos gatilhos compartilhados (`Disparo::DUAS_VEZES`):
  com `assumido` só os migrados ouvem; sem ele, só os fluxos comuns do usuário,
  exatamente como antes da migração.
- **Virar e voltar sem deploy:** `rake ramon:fluxos:migracao:modo[grupo,conta,normal|sombra]`
  (normal recusa sem a env). Voltar pelo rake, nunca desligando o fluxo na tela.

Consequências: o código antigo continua no repositório como reserva até a
limpeza (~2 semanas depois de rodar em normal), e cada grupo carrega env, JSON
em `migrados/` e um ponto de decisão. Limites aceitos: com o fluxo no comando,
um 2º evento do mesmo alvo enquanto a execução espera nova tentativa é descartado
pelo índice único; desligar o fluxo na tela com ele no comando pode deixar
conversa em andamento sem vigia (SLA).

Alternativas descartadas:

- **Trocar por deploy** (apagar o código quando o fluxo ficar pronto): não há
  volta rápida se o fluxo errar em produção.
- **Cada lado ler a chave por conta própria** (código num ponto, motor em outro):
  entre as duas leituras a chave pode virar — dobro ou nada.
- **Deixar os dois rodarem e deduplicar efeitos**: cada efeito (sino, tarefa,
  rascunho, ADVBOX) precisaria da sua própria trava; um esquecido vira duplicata
  na frente do cliente ou da equipe.

# Automações em fluxo (motor + quadro tipo n8n) — design

**Data:** 05/10/2026 · **Status:** aprovado em conversa com o Eduardo (partes 1–5), aguardando revisão desta spec
**Mockup aprovado (alvo da tela):** `RAdvogados\comercial\docs\mockups\2026-10-05-inteligencia-fluxos\fluxos.html` (+ prints claro/escuro na mesma pasta)
**Subprojeto irmão:** A — Inteligência completa (tela a tela), documento próprio.

---

## 1. Objetivo

Dar ao hub **um lugar só** onde se vê, monta e acompanha tudo que ele faz sozinho: um
quadro de **fluxos** (gatilho → condições → esperas → ações) com cara de n8n, que **roda
de verdade** dentro do hub, cobre eventos de **conversa e de lead** e as ações da banca
(funil, Esteira, IA, ADVBOX, avisos).

Hoje: a Automação nativa do Chatwoot é linear (evento → condições → ações, sem espera, sem
ramo, sem evento de lead) e todas as automações da banca (cadência, SLA, lembretes, regras
do Flowter, pós-ganho, resumo) estão escritas no código, invisíveis e não editáveis.

**Sucesso =** o Eduardo monta um fluxo como "Contrato assinado → boas-vindas (rascunho) →
tarefa → espera 2 dias → se faltam documentos → rascunho IA + push", testa com um lead
real sem executar nada, publica, e depois abre qualquer execução e vê o caminho aceso.

## 2. Decisões (todas do Eduardo, 05/10/2026)

| # | Decisão |
|---|---|
| D1 | Motor de fluxos **próprio** dentro do hub (não instalar o n8n; não só "pele" nas regras nativas). |
| D2 | Quadro livre (Vue Flow) com as travas de esteira do Flowter: **1 gatilho por fluxo**, espera conta **do passo anterior**, ramos **sim/não** (`se`) ou **escolha por valor** com várias saídas (`escolha`, incluída a pedido do Eduardo em 05/10), sem laços. |
| D3 | Mensagem ao cliente **sempre rascunho** (nota privada "RASCUNHO…"); quem envia é uma pessoa. |
| D4 | Só **administradores** montam/editam; equipe vê o efeito (balão de evento na conversa, atividade do lead). |
| D5 | Automações ficam **dentro da Inteligência** no menu. |
| D6 | Regras nativas do Chatwoot são **absorvidas** (convertidas em fluxos; a tela antiga sai do menu). |
| D7 | Automações de hoje aparecem como **"Do sistema" (só leitura)** e migram **uma a uma**, em modo sombra. |
| D8 | Extras obrigatórios: **ensaio**, **versão congelada**, **falhou→tenta 3×→avisa**, **limite por dia**, **gatilho manual**, **variáveis entre passos**, **modelos prontos**. |
| D9 | Fluxo corre **de cima para baixo** no quadro (horizontal ficou ilegível na tela real — visto no mockup). |
| D10 | A e B andam **em paralelo**. |

## 3. Vocabulário (entra no `CONTEXT.md`, § Inteligência)

- **Fluxo** — uma automação desenhada no quadro: 1 gatilho + passos ligados por setas.
- **Passo** — uma caixinha do fluxo (condição, ação ou controle).
- **Versão (de fluxo)** — foto publicada do desenho; execuções rodam na versão em que começaram.
- **Execução de fluxo** — uma passada de um fluxo por um lead/conversa, com trilha.
  _Não confundir com **Execução** (registro de uma Tool da IA), que já existe no glossário._
- **Trilha** — a lista de passos por onde uma execução passou, com entrada/saída/erro.
- **Ensaio** — execução de mentira num alvo real: avalia condições, descreve as ações, não executa nada.
- **Modo sombra** — fluxo que roda como ensaio nos eventos reais, para comparar com o código antes de assumir.
- **Fluxo do sistema** — desenho só-leitura de uma automação que ainda roda pelo código.

## 4. Peças (catálogo)

Cada nó do desenho: `{ id, tipo, config, posicao: {x, y} }`. Setas: `{ de, saida, para }`,
`saida ∈ {s, sim, nao}` ou, no `escolha`, a chave de um caso (`c1`, `c2`, …) / `outro`.

### 4.1 Gatilhos (exatamente 1 por fluxo)

| tipo | quando | de onde vem (ponto no código) | alvo |
|---|---|---|---|
| `conversa_criada` | nova conversa | ouvinte novo `RamonFluxoListener` (`conversation_created`) | conversa |
| `mensagem_recebida` | mensagem incoming | `message_created` (incoming, não-privada) | conversa |
| `conversa_resolvida` / `conversa_reaberta` | status | `conversation_resolved` / `conversation_opened` | conversa |
| `conversa_atribuida` | atribuição mudou | `assignee_changed` | conversa |
| `lead_criado` | lead novo | `lead_created` | lead |
| `lead_mudou_etapa` | etapa mudou (filtro opcional de→para) | `lead_updated` c/ mudança de `lead_stage_id` | lead |
| `lead_ganho` / `lead_perdido` | entrou em etapa `is_won` / `is_lost` | `lead_updated` | lead |
| `lead_parado` | parado há N dias (1×/dia, hora configurável, padrão 11:00 SP) | relógio; reaproveita `Ramon::Cadencia.parado?` | lead |
| `reuniao_marcada` / `reuniao_cancelada` | reunião | 1 linha em `Ramon::ReuniaoAgendamento` (cobre Cal.com e painel) | lead |
| `evento_advbox` | regra do Flowter (filtro por chave: contrato_fechado, indeferimento…) | 1 linha em `Ramon::AdvboxEventProcessor` | lead |
| `contrato_assinado` / `contrato_recusado` | ZapSign | 1 linha em `ZapsignLeadStatusJob` | lead |
| `documento_recebido` | anexo casado com o checklist | 1 linha no fim do `DocMatchJob` | lead |
| `relogio` | todo dia HH:MM sobre um grupo de leads (filtro: etapa/tese/responsável) | relógio | cada lead do grupo |
| `manual` | botão "Rodar fluxo" no lead/conversa | API `POST …/fluxos/:id/rodar` | o lead/conversa |

Conversa ↔ lead: quando o alvo é conversa e existe lead ligado (`lead.conversation_id`), o
contexto carrega os dois; idem ao contrário.

### 4.2 Condição

- `se` — lista de condições com **E/OU** sobre o contexto (campo, operador, valor). Operadores:
  `igual, diferente, contem, nao_contem, maior, menor, existe, vazio, em_horario_comercial`.
  Saídas `sim` e `nao` (uma delas pode ficar sem seta = termina).
- `escolha` — olha **um** campo (tese, etapa, origem, caixa, responsável, prioridade ou
  qualquer variável) e abre **uma saída por valor** cadastrado + a saída **"outro"**
  (nenhum caso bateu). Ex.: tese → Auxílio-acidente · BPC · Aposentadoria · outro. Cada
  caso é `{chave, rotulo, valores: []}` (um caso pode juntar vários valores). Saída sem seta
  = termina. No quadro, as setas saem com o rótulo do caso.
- `perguntar_ia` — pergunta de sim/não ao LLM (`Ramon::LlmClient`) com a conversa/lead no
  contexto; resposta normalizada para `sim|nao`; o texto da justificativa vira `{resposta_ia}`.

### 4.3 Ações

| tipo | faz | reaproveita |
|---|---|---|
| `rascunho_texto` | nota privada `RASCUNHO (revisar antes de enviar): …` com texto fixo + variáveis | prefixo de `Ramon::RascunhoCarimbo::PREFIXO` (o carimbo de desfecho continua funcionando) |
| `rascunho_ia` | idem, texto escrito pela IA a partir de uma instrução (+ assistente/skill opcional) | `Ramon::LlmClient`; skill via `Captain::Assistant::AgentRunnerService` (enterprise) |
| `acao_chatwoot` | qualquer ação nativa (etiqueta, atribuir, time, status, prioridade, e-mail p/ time, anexo, transcript, SLA…) | `AutomationRules::ActionService` com regra em memória — **mesma execução das regras nativas** |
| `nota_privada` | nota interna | — |
| `mover_etapa` | muda etapa do lead | update do lead (dispara sync etapa↔etiqueta de sempre) |
| `criar_tarefa` | tarefa na Esteira (`LeadTask`) c/ responsável e prazo relativo | — |
| `trocar_responsavel` / `preencher_campo` | SDR/Closer; `custom_attributes` (merge por chave após reload) | — |
| `registrar_atividade` | linha na atividade do lead | `LeadActivity` |
| `avisar_sino` / `avisar_push` | sino do hub / push ntfy | `Notification` tipo `ramon_*` / `Ramon::NtfyPushJob` |
| `rodar_skill` | roda uma skill de um assistente; resultado vira nota privada e `{resposta_ia}` | `AgentRunnerService` (enterprise) |
| `advbox` | criar tarefa ou movimentação **fixa** (IDs escolhidos na tela a partir de `advbox_configuracoes`) | `Ramon::AdvboxMcpService` |
| `webhook` | POST JSON do contexto para uma URL | — ; **só como último passo** (regra do Flowter) |

Nota: nota de rascunho criada por fluxo não entra no carimbo `bi_ia` — este só mede notas do Assistente.

### 4.4 Controle

- `esperar` — X min/h/dias **ou** "até o próximo horário comercial"; conta do passo anterior.
- `parar` — encerra a execução.

### 4.5 Variáveis

Contexto = `{ contato, lead, conversa, gatilho, vars }`. No texto, `{chave}` com apelidos
amigáveis (`{nome}`, `{tese}`, `{etapa}`, `{responsavel}`, `{documentos_faltantes}`, …) +
o que cada passo devolve (`{resposta_ia}`, `{prazo_advbox}`, …). Substituição simples
(sem Liquid); chave desconhecida fica literal e o **ensaio aponta**.

## 5. Dados (3 tabelas, migração à mão na VPS)

**`ramon_fluxos`** — `account_id`, `nome`, `descricao`, `gatilho_tipo` (indexado), `ativo`,
`limite_dia` (null = sem limite), `origem` (`usuario|convertido|sistema`), `sistema_chave`
(ex. `lembretes_reuniao`), `modo` (`normal|sombra`), `rascunho` jsonb (desenho em edição),
`versao_publicada_id`, `ultimo_disparo_em`, `created_by_id`, timestamps.

**`ramon_fluxo_versoes`** — `fluxo_id`, `numero` (único por fluxo), `grafo` jsonb,
`publicado_por_id`, `created_at`. Imutável.

**`ramon_fluxo_execucoes`** — `account_id`, `fluxo_id`, `versao_id`, `alvo_type/alvo_id`
(Lead|Conversation), `status` (`rodando|esperando|concluida|falhou|cancelada`) e `ensaio` boolean
(`versao_id` nulo quando se ensaia o rascunho),
`no_atual`, `retomar_em`, `tentativas`, `contexto` jsonb, `trilha` jsonb (array
`{no, inicio, fim, resultado, saida, erro}`), `profundidade`, `erro`, timestamps.
- Índice **único parcial** `(fluxo_id, alvo_type, alvo_id) WHERE status IN ('rodando','esperando')`
  → "não roda 2× ao mesmo tempo para o mesmo alvo" garantido pelo banco.
- Índice parcial `(retomar_em) WHERE status = 'esperando'`.

**Publicar** valida o rascunho: 1 gatilho; sem ciclo; todo passo alcançável; `webhook` sem
saída; `se` com ≥1 saída; `escolha` com ≥2 casos, chaves únicas e sem valor repetido entre casos; config obrigatória preenchida. Erro → aponta o passo no quadro.

## 6. Motor

- **Disparo** (`Ramon::Fluxos::Disparo.call(gatilho, alvo, dados)`): acha fluxos ativos da
  conta com aquele `gatilho_tipo` (origem ≠ sistema), aplica o filtro do gatilho, checa
  **limite do dia** (execuções não-ensaio de hoje, fuso SP) e cria a execução (o índice
  único barra duplicata — conflito = ignora). Enfileira `Ramon::FluxoAvancarJob(id)`.
  Fluxo em `modo: sombra` cria execução com `status: ensaio`.
- **Avançar** (`Ramon::Fluxos::Executor`): sob `with_lock`, segue as setas a partir de
  `no_atual`; cada tipo de passo é uma classe pequena `Ramon::Fluxos::Passos::<Tipo>#call(ctx)`
  que devolve `{saida:, vars:, resumo:}`; grava a trilha a cada passo; guarda de 50 passos.
  - `esperar` → `status: esperando`, `retomar_em`, solta.
  - **ao retomar**: se "cancelar se sair da etapa" (padrão ligado em fluxos de lead) e a
    etapa mudou desde o início → `cancelada`.
  - **erro numa ação** → `tentativas += 1`, `retomar_em` = +1 / +5 / +15 min; na 3ª →
    `falhou` + sino para admins (`ramon_fluxo_falhou`) + push.
- **Relógio** (`Ramon::FluxoRelogioJob`, cron a cada minuto): retoma execuções vencidas;
  dispara `relogio` e `lead_parado` do dia (marca `ultimo_disparo_em`). Nada fica preso em
  memória → deploy/reinício não perde quem esperava (sem `perform_in` longo).
- **Cadeia entre fluxos**: ação de um fluxo pode disparar outro (ex.: mover etapa → fluxo de
  etapa). O contexto leva `profundidade`; > 3 não dispara; um fluxo **nunca** redispara a si
  mesmo para o mesmo alvo.
- **Ensaio** (`POST …/fluxos/:id/ensaio {lead_id|conversation_id, usar: rascunho|publicada}`):
  síncrono; condições de verdade (inclusive `perguntar_ia`), esperas puladas, ações só
  **descrevem** o que fariam; devolve a trilha (persistida como `ensaio`, fora de limite e de
  unicidade).
- **Visível para a equipe**: cada ação executada registra balão via `Ramon::EventoInline`
  ("⚙ Fluxo Pós-contrato: moveu para Documentação") e/ou atividade do lead.
- Sidekiq `strict_args`: jobs só recebem IDs.
- Código em `app/` (namespace `Ramon::Fluxos`), **fora de `enterprise/`**, para os specs
  rodarem no CI FOSS; os passos que tocam Captain (`rodar_skill`) ficam atrás de
  `ChatwootApp.enterprise?` e os specs deles com o guard de sempre.

## 7. Tela (alvo = mockup aprovado)

- **Rotas** (área Captain, antes do catch-all `:navigationPath`):
  `captain/automacoes` (lista), `captain/automacoes/:id` (editor),
  `captain/automacoes/:id/execucoes/:execId` (execução/ensaio).
- **Menu Inteligência** ganha "Automações". "Configurações → Automação" sai na fatia B3.
- **Lista**: abas *Meus fluxos* / *Do sistema*; 4 números (ligados, execuções hoje,
  esperando, falharam 24h); linha = chave, nome, gatilho, hoje/limite, esperando, última,
  selo (ok / N falhou / desligado). ⚠️ Divergência consciente do mockup: na aba *Do sistema*
  a coluna "Hoje" só aparece onde já existe fonte barata; senão "—".
- **Editor**: Vue Flow (`@vue-flow/core` + `minimap` + `controls`, MIT — dependência nova,
  única); vertical; "+ Adicionar passo" abre a paleta por grupos; clique no passo abre o
  painel direito com a config e as variáveis clicáveis; selo "sai como rascunho" em toda
  mensagem ao cliente; barra: Ligado + limite, Versões, **Testar com um lead…**, **Publicar vN**.
- **Execução/Ensaio**: mesmo quadro só-leitura, caminho aceso em verde, resto apagado;
  painel com alvo (abrir) e trilha com horários.
- **Novo fluxo**: em branco + modelos (os modelos são JSON versionados em
  `db/seeds/ramon/fluxos/*.json`).
- **Rodar na mão**: menu ⋯ do painel do lead / conversa → "Rodar fluxo…" (lista os fluxos
  com gatilho `manual`).
- Kit visual do hub (`ramon/helpers/ui.js` + components-next), tokens branco/preto + azul,
  fundos coloridos translúcidos; claro e escuro.
- API admin-only (policy como as demais de `ramon_*`).

## 8. Migração

**B3 — regras nativas → fluxos** (rake `ramon:fluxos:converter_regras[account_id]`,
idempotente): evento → gatilho; condições → um `se` (E/OU preservado); ações → `acao_chatwoot`;
**`send_message` → `rascunho_texto`** (única mudança de comportamento; o rake lista quais
regras tinham envio antes de converter, para o Eduardo ver). Regra antiga: `active=false`
(não apaga). Fluxo convertido nasce `origem: convertido`, ligado se a regra estava ativa.

**B3 — fluxos do sistema (só leitura)**: 6 desenhos em `db/seeds/ramon/fluxos/sistema/*.json`
(cadência, SLA 1ª resposta, lembretes de reunião, eventos do ADVBOX, lead ganho, resumo do dia),
`origem: sistema`, nunca executados pelo motor.

**B4+ — migração 1 a 1, modo sombra**, um PR por automação, nesta ordem:
lembretes de reunião → SLA → cadência → lead ganho → eventos do ADVBOX.
1. fluxo equivalente em `modo: sombra` (ensaio nos eventos reais) por alguns dias;
2. comparar trilhas × o que o código fez;
3. bateu + aprovado → env/flag desliga o caminho do código, fluxo vira `normal` e editável.
**Resumo do dia fica no código** (é relatório, não fluxo).

## 9. Testes

- Specs (RSpec, fora de `enterprise/`): cada passo; filtro de cada gatilho; disparo
  (limite, unicidade, profundidade, sombra); esperar/retomar via relógio; cancelar se saiu da
  etapa; tentativas 1/5/15 → falhou + sino; versão congelada (editar/publicar não afeta
  execução em andamento); ensaio não grava nada fora da própria execução; validação de
  publicar; rake de conversão (inclui `send_message` → rascunho). Relógio fixo em dia útil
  10h SP onde tocar ADVBOX.
- Vitest: desenho ↔ JSON (salvar e reabrir idêntico); validação no front espelha a do back.
- **Prova real na VPS** (`rails runner`): fluxo de teste ponta a ponta num lead temporário
  (apagar `LeadActivity` antes do lead), incluindo uma espera curta retomada pelo relógio.
- Prints claro/escuro das 4 telas (harness Vite + Chrome headless) → página de aprovação do pacote.

## 10. Fatias e entrega

| Fatia | Conteúdo | Migração |
|---|---|---|
| **B1** | tabelas, motor, relógio, gatilhos de conversa/lead/manual, ações básicas (`registrar_atividade`, `trocar_responsavel` e `preencher_campo` ficam p/ a B2b; rascunho texto, nota, etiqueta via `acao_chatwoot`, mover etapa, tarefa, sino/push, esperar, se, escolha), API de execuções | sim (3 tabelas) |
| **B2** | quadro (lista, editor Vue Flow, versões, ensaio, execução acesa, modelos) + menu | não |
| **B2b** | passos de IA (`perguntar_ia`, `rascunho_ia`, `rodar_skill`), `advbox`, `webhook`, gatilhos externos (reunião, ADVBOX, ZapSign, documento), `lead_parado`, `relogio` | não |
| **B3** | conversão das regras nativas + aba "Do sistema" + sai "Configurações → Automação" | não |
| **B4+** | migração 1 a 1 em sombra | não |

Ritmo combinado: merge contínuo com CI verde; aprovação por pacote (prints); 1 deploy por
pacote, Eduardo roda via `!`; migração `db:migrate` à mão no deploy da B1; smoke em bloco.
Motor entra **desligado** (nenhum fluxo ativo) até o smoke.

## 11. Fora de escopo (agora)

Laços/loops e "para cada item"; envio automático ao cliente;
edição por não-admin; fluxos entre contas; n8n externo; gatilho por webhook de entrada
genérico (só os 4 externos conhecidos).

## 12. Riscos

- **Tempestade de eventos** (`message_created` em massa): o disparo é barato (consulta por
  `gatilho_tipo` indexado) e o limite do dia segura o resto.
- **Fluxo encadeando fluxo**: profundidade ≤ 3 + não-autodisparo.
- **Mudança de comportamento na conversão** (`send_message` → rascunho): listada antes, aprovada pelo Eduardo.
- **Dependência nova** (Vue Flow): MIT, Vue 3 nativo, isolada nas 2 telas do quadro.

## 13. Notas da B2b (06/10/2026)

- `rascunho_ia` não tem assistente/skill opcional: para texto escrito por skill, `rodar_skill` → `rascunho_texto` com `{resposta_ia}`.
- `rodar_skill` roda sem conversa no estado do runner (como o Testar): ferramentas da skill não agem na conversa; resultado = nota privada + `{resposta_ia}`. Ferramenta HTTP própria do assistente (CustomTool) ainda chama o serviço dela — só vê texto pseudonimizado.
- `documento_recebido` nasce em `Ramon::DocMatchService#gravar_sugestao` (o `DocMatchJob` não sabe se houve casamento); é sugestão da IA — "Documentos completos?" conta só o confirmado pela equipe.
- Reunião: 1 linha em `Ramon::ReuniaoAgendamento.notify` (cobre painel e Cal.com, inclusive o cancel do Cal.com); remarcar = `reuniao_marcada`.
- `preencher_campo` grava em `custom_attributes['campos'][chave]` e o campo vira variável; nomes que o hub já usa (`Contexto::RESERVADAS`) são recusados ao publicar e ao rodar.
- `lead_parado` dispara 1 vez por parada; `relogio`/`lead_parado` 1×/dia por fluxo (`ultimo_disparo_em`, fuso SP, reivindicado antes de disparar); erro num lead não derruba os outros.
- O executor grava a execução a cada passo, já apontando o próximo (passo lento não parece órfão; queda não repete o passo feito).
- Teto próprio de IA: `RAMON_FLUXO_IA_DIA` (padrão 200 chamadas/conta/dia, conta tentativas); estourou → passo falha + sino.
- Webhook (decisão do Eduardo, "nome e telefone, sem CPF, sem documentos"): `dados` leva só `Passos::Externo::CAMPOS_WEBHOOK` — campos livres nunca saem; só https (publicar) + `SafeFetch` (rede interna barrada; não ligar `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` na VPS).
- Erro de configuração (ADVBOX sem token, ação/IDs faltando, webhook 4xx exceto 408/429, papel/pessoa inválidos) falha na hora, sem nova tentativa; erro passageiro repete 1/5/15 min.
- ADVBOX e webhook são "pelo menos uma vez": se o outro lado gravou mas a resposta não chegou, a nova tentativa repete. O payload leva `execucao_id` para o receptor descartar repetido.

## 14. Notas da B3 (06/10/2026)

- **Conversor das regras nativas descartado** (decisão do Eduardo, 06/10): produção tem 0 `AutomationRule`, então o rake `ramon:fluxos:converter_regras` do §8 não existe e não há `origem: convertido` em uso. "Configurações → Automação" saiu do menu e o link antigo (`/settings/automation`, `/settings/automation/list`) cai em Inteligência → Automações; o motor nativo do Chatwoot segue no código, sem tela (o `AutomationRules::ActionService` continua servindo o passo `acao_chatwoot`).
- **Fluxos do sistema = as 29 automações do código** (não só as 6 do §8), em 5 grupos: Leads e conversas · Contrato e documentos · Painel do Cliente · Rotinas e relatórios · Instagram. São JSON em `db/seeds/ramon/fluxos/sistema/<chave>.json` (`{nome, grupo, alcance?, resumo, descricao, limite_dia?, desenho}`); `Ramon::Fluxos::Sistema.sincronizar` cria/atualiza 1 `Fluxo` `origem: sistema` por conta quando a lista abre (re-checa dentro do lock da conta; nada mudou = 1 SELECT). `grupo`, `alcance`, `resumo` e o rótulo do gatilho saem do JSON (`Sistema.extras`), sem coluna nova.
- Nunca rodam: `Fluxo.executaveis` exclui a origem, `Disparo#iniciar` recusa (evento, relógio, manual e ensaio), a API devolve 403 em editar/excluir/publicar/ensaiar/rodar e o desenho esconde "Testar com um lead…" e "Versões". O ensaio fica bloqueado até cada um migrar (B4+). A lista não calcula contadores de execução para eles.
- Convenção dos desenhos: `resumo` = 1 frase simples (é o que a lista mostra); `descricao` começa com "No código:" (onde vive) e diz o que o desenho não expressa (aparece no painel "Como roda hoje"). Onde o gatilho real não existe nos fluxos, o desenho usa `manual` com o rótulo do evento real; ações sem passo (Drive, Notion, e-mail, carimbos de coluna) usam o tipo mais próximo com "(representação)" no rótulo. `mover_etapa` vem sem `etapa_id` (a etapa é do funil de cada conta). Os 5 lembretes de reunião são um ciclo só. "Contrato fechado" do ADVBOX dispara também o Lead ganho (a B4 não pode migrar os dois em dobro); um lead pode ter até 2 rascunhos de NPS (ganho e êxito).
- Selo nas 2 que saem para fora sem uma pessoa no meio: **Avisos do Painel do Cliente** = "fala com o cliente" (desligado até o Eduardo aprovar os textos, `PORTAL_AVISOS=on`); **Publicar peças no Instagram** = "publica".
- "Hoje" na aba Do sistema só com fonte barata (10 das 29), no dia de São Paulo, cada um com dica do que conta (ex.: lembretes = reuniões marcadas/remarcadas; SLA = conversas novas nas caixas que criam lead; Instagram = publicações **iniciadas**, não há coluna de publicada); o resto "—".
- **Rodar fluxo…** (§7) entrou na B3, só admin (a API de fluxos é admin-only): no ⋯ do cabeçalho da conversa (`conversation_id`) e no ⋯ do painel do lead **aberto pelo funil** (`lead_id`); dentro da conversa o painel do lead não repete o item (evita 2 execuções da mesma pessoa). O alvo é fixado no clique. Lista os fluxos publicados e ligados com gatilho `manual` (nunca os do sistema) e avisa com link para a execução; sem fluxo, aponta para Automações.
- Quadro: desenho longo abre com zoom mínimo 0,75 e o gatilho no topo (rola em vez de encolher).
- **B4**: o fluxo em sombra é um fluxo próprio (origem `usuario`), porque o motor recusa `origem: sistema`; quando assumir, apagar o JSON **e** a linha do sistema (a sincronização não apaga linha cujo JSON sumiu).

## 15. Notas da B4.1 (06/10/2026) — agendamento de reuniões em sombra

- **Escopo (Eduardo, 06/10):** a cadeia inteira do `Ramon::ReuniaoAgendamento` migra — marcar (atividade, tarefa da reunião, etapa só para a frente, Closer automático, rascunho de confirmação nas notas do lead, sino para a conta, push), remarcar (atividade de→para, rascunho, sino, push), cancelar (atividade, tarefa apagada, sino, push) — e os 5 lembretes de **cada** reunião. Mover a tarefa no remarcar e apagar o Cal.com no remarcado ficam no código (são o evento em si; N1, aceito em 06/10).
- **3 fluxos** (`origem: usuario`, `sistema_chave` = `reuniao_marcada`, `reuniao_cancelada`, `lembretes_reuniao`), criados pelo rake `ramon:fluxos:reunioes:sombra[conta]` a partir de `db/seeds/ramon/fluxos/migrados/*.json` (idempotente; existindo, não toca). "Reunião marcada" tem `escolha` pelo `{evento}` (marcada/remarcada). "Lembretes de reunião" usa o gatilho novo `reuniao_na_agenda` com **alvo = a tarefa da reunião**: um ciclo por reunião sem migração; remarcar recomeça só o ciclo dela (`Disparo::RECOMECA`); cancelar apaga a tarefa e o ciclo é cancelado ("o alvo foi apagado").
- **Motor ganhou:** `LeadTask` como alvo; `esperar {antes_de: 'reuniao'}` + `{horario_passou}`; `{reuniao_de_pe}`; variáveis `{evento}`, `{titulo}`, `{titulo_tarefa}`, `{resumo}`, `{resumo_antes}`, `{primeiro_nome}` (textos prontos que o código manda no gatilho); sino `para: closer_e_sdr | conta`; `mover_etapa {so_para_frente}`; `trocar_responsavel {so_se_vazio}`; `registrar_atividade {tipo, de}` com quem marcou; `criar_tarefa {prazo: 'reuniao'}` (põe a reunião na agenda; o ciclo de lembretes segue a decisão do evento — num fluxo comum, a chave da conta); `rascunho_texto {onde: notas_do_lead, titulo}`; passo `apagar_reuniao`; ensaios que dizem quem/quando; desligar o fluxo cancela também a sombra.
- **A decisão é do evento:** cada marcar/remarcar/cancelar lê `Reunioes.assumiu?` uma vez e manda `assumido` no gatilho. Cada evento dispara os fluxos **duas vezes**: antes dos efeitos do código, com `assumido` (só os 3 fluxos migrados — agem ou ensaiam conforme a decisão) e depois dos efeitos, sem `assumido` (só os fluxos comuns de usuário, exatamente como hoje). "Reunião marcada/cancelada" rodam na hora, dentro da requisição; o ensaio roda antes dos efeitos do código.
- **A chave:** `RAMON_FLUXO_REUNIOES=on` **e** os 3 fluxos ligados, publicados, em `modo: normal`, com o gatilho certo e **sem limite diário** (`limite_dia`) → o código só dispara; qualquer peça fora → o código faz tudo e os fluxos ensaiam. Um limite diário em qualquer dos 3 devolve o comando ao código (senão ninguém agiria no evento que passasse do limite). Filtros do gatilho nos 3 fluxos são edição de admin sob E6 (um filtro pode tirar o efeito). Virar = `rake ramon:fluxos:reunioes:modo[conta,normal]` (recusa sem a env); voltar = `…modo[conta,sombra]` (ou env desligada, ou um fluxo desligado na tela). Os lembretes já enfileirados pelo código saem pelo código (o job não consulta a chave).
- **Comparação:** `rake ramon:fluxos:reunioes:comparar[conta,dias]` (só leitura): agendamentos (cada evento: atividade, tarefa, etapa, Closer, rascunho, sino, tarefas apagadas, na frase do ensaio) e lembretes (lead, horário ±3 min, pessoas). Só eventos depois que a sombra nasceu; ignora o "Testar com um lead…". Os sinos do código (marcada/remarcada/cancelada e lembretes) vêm de um **rastro no Redis** (`ramon:reunioes:rastro:<conta>`, guardado 8 dias), escrito pelo `MeetingReminderJob` e pelo `ReuniaoAgendamento` — não das notificações, porque o Chatwoot guarda só a notificação mais recente por pessoa+lead. Logo a janela de comparação é de no máximo 8 dias para trás: rodar todo dia; o critério E4 (≥ 7 dias) cabe. A janela também para no próximo ensaio (para não contar como "só no fluxo" o que ainda não aconteceu). Sem nada comparado, o rake diz "nada para comparar" (não "BATEU") e avisa quando os fluxos já estão no comando. A tarefa que o código criou ao marcar também vem do rastro (título e horário da hora da marcação — a tarefa viva pode ter sido remarcada ou apagada depois). Alarme falso conhecido: lead com uma reunião de antes da sombra existir e outra depois pode mostrar os lembretes do código da reunião antiga como "só no código" (nunca um BATEU falso).
- **Etapa de perda (PR #216):** `mover_etapa` aceita `motivo` opcional (motivo da lista da conta ou "Outro"); só vale para etapa `is_lost` e vai como `lost_reason`; sem ele, o `Lead` preenche "Automação: <fluxo>".
- **Teto conhecido (N2, aceito em 06/10):** com os fluxos no comando, dois eventos do mesmo lead na mesma fração de segundo → o 2º é ignorado pelo índice único (duplo clique não cria 2 reuniões); passo que falha na hora tenta de novo em 1/5/15 min (aparece com atraso, não em dobro). Enquanto tenta de novo (até ~21 min), a execução de "Reunião marcada/cancelada" fica `esperando` e o **próximo evento do mesmo lead nessa janela também é descartado** pelo índice único (não só o duplo clique) — conferir no quadro a execução com erro e refazer o evento à mão.
- **Fica para a limpeza (outro PR, 2 semanas depois de rodar em normal):** apagar os efeitos do código no `ReuniaoAgendamento` (fica só o disparo e o mover tarefa), o `Ramon::MeetingReminderJob`, o JSON `sistema/lembretes_reuniao.json` **e** a linha `origem: sistema` dele, o rastro do Redis e a env.

## 16. Notas da B4.2 (07/10/2026) — SLA da 1ª resposta direto no fluxo

- **Escopo (Eduardo, 07/10):** o vigia do SLA da 1ª resposta migra **direto**, sem fase de sombra e sem comparação (D1); horário configurável por passo, o fluxo nasce 7h–21h todo dia (D2); N1–N3 aceitas. Fluxo "SLA da 1ª resposta" (`origem: usuario`, `sistema_chave: sla_primeira_resposta`, gatilho `conversa_criada`), criado por `rake ramon:fluxos:migracao:criar[sla,conta]` a partir de `db/seeds/ramon/fluxos/migrados/sla_primeira_resposta.json`.
- **Módulo comum das migrações:** `Ramon::Fluxos::Migracao` (`GRUPOS`, congelado: env, fluxos `sistema_chave → gatilho`, ajuste do desenho por conta, e a opção por migração "limite diário devolve o comando ao código", padrão `true` como na B4.1; a cadência B4.3 registra `false`) faz a chave e a semeadura de qualquer migração; `Ramon::Fluxos::Reunioes` usa ele (mesma API). Rake genérico `ramon:fluxos:migracao:{criar,modo}[grupo,conta(,modo)]` (o `ramon:fluxos:reunioes:*` segue igual). A `Ramon::Fluxos::Migrados` imaginada para a B4.4 foi substituída por `Migracao`. B4.3+ = uma entrada em `GRUPOS` + JSON + o código lendo `assumiu?` uma vez por evento.
- **A decisão é da conversa nova:** o `RamonLeadListener` (só caixas com Criar lead e com contato) lê `Migracao.assumiu?(conta, 'sla')` uma vez e dispara `conversa_criada` com `assumido`. `conversa_criada` é gatilho "disparado 2 vezes" (`Disparo::DUAS_VEZES`): com `assumido` só o fluxo migrado ouve; sem (o `RamonFluxoListener`), só os demais. O job do código só não é agendado quando o fluxo está no comando **e** pegou a conversa (filtro editado ou erro → o código vigia, N2).
- **A chave:** `RAMON_FLUXO_SLA=on` **e** o fluxo ligado, publicado, em modo normal, sem limite diário e com o gatilho `conversa_criada`. Virar = `…migracao:modo[sla,conta,normal]`; voltar = `…modo[sla,conta,sombra]` (ou env desligada).
- **Motor ganhou:** janela por passo (`dias` 0–6, `inicio`, `fim` no config da condição `em_horario_comercial` e do `esperar {ate: horario_comercial}`; sem as chaves = seg–sex 8h–18h; `Horario.janela/janela_valida?`, recusada ao publicar no back e no front); `esperar {desde: 'conversa'}` (quantidade/unidade, ou `prazo: 'sla_caixa'` = `Ramon::Cadencia.sla_minutes`, **só com `desde: 'conversa'`**; já passado → `{horario_passou} = sim`); variáveis `{primeira_resposta}` e `{sla_minutos}`; sino `para: sdr_ou_gestores | gestores`.
- **Fidelidade:** guardas = sem 1ª resposta + aberta + com lead; aviso 7h–21h todo dia; escalada aos 60 min da criação esperada mesmo fora do horário e só se ainda for futura; sem cancelar por etapa. Mudou: sino `ramon_fluxo_aviso` (era `ramon_sla_breach`), balão "⚙ Fluxo …" na conversa, precisão de ~1 min (N1).
- **Bordas conhecidas (aceitas, ficam para o PR de limpeza ou a pedido):**
  - Falha ao enfileirar depois do `create!` da execução pode deixar fluxo **e** código vigiando a mesma conversa (raro; no máximo um aviso repetido).
  - Desligar o fluxo **na tela** com ele no comando deixa sem vigia as conversas em andamento (N3). Para voltar, use sempre `rake 'ramon:fluxos:migracao:modo[sla,2,sombra]'`, nunca desligar.
  - Caixa com SLA de 59 min: o relógio de ~1 min pode fazer a escalada de 60 min ser pulada (a espera já passou do prazo).
  - `Reunioes.mudar_modo!` ganhou texto de erro novo (aponta para `ramon:fluxos:migracao:criar[reunioes,N]`); só cosmético.
  - Nota para migrações futuras: `Disparo::DUAS_VEZES` e o `.any?` do listener supõem que o SLA é o único grupo migrado em `conversa_criada`; um novo grupo nesse gatilho precisa da sua própria chave de decisão.
- **Fica para a limpeza (outro PR, 2 semanas depois de rodar em normal):** apagar `Ramon::FirstResponseSlaJob` e o agendamento dele no `RamonLeadListener` (fica só o disparo), o JSON `sistema/sla_primeira_resposta.json` **e** a linha `origem: sistema` dele, e a env.

## 17. Notas da B4.3 (07/10/2026) — a cadência de retomada vira fluxo (direto)

- **Escopo (Eduardo, 07/10, o mesmo da B4.2):** direto, sem sombra nem comparação; N1–N4 aceitas. Fluxo "Cadência de retomada" (`origem: usuario`, `sistema_chave: cadencia`, gatilho `lead_parado`), criado por `rake ramon:fluxos:migracao:criar[cadencia,conta]` a partir de `db/seeds/ramon/fluxos/migrados/cadencia.json` (grupo `cadencia` em `Ramon::Fluxos::Migracao`, `limite_devolve: false`; o `criar` passou a gravar o `limite_dia` do JSON, 15).
- **A chave:** `RAMON_FLUXO_CADENCIA=on` **e** o fluxo ligado, publicado, em modo normal, gatilho `lead_parado` → o fluxo faz e o código para (o `DailyFollowUpJob` pula a conta; o botão "Preparar retomada" roda o fluxo, para aquele lead, sem o teto). Qualquer peça fora → o código faz e o fluxo fica parado. Virar = `…migracao:modo[cadencia,conta,normal]` (recusa sem a env); voltar = `…modo[cadencia,conta,sombra]`, sem deploy. Fluxo migrado dispara com `assumido` (senão vira ensaio).
- **Regras únicas:** `Ramon::Fluxos::Retomada` (quem pode: conversa, nenhuma tarefa `follow_up` aberta, última retomada há ≥ 5 dias, data envenenada = nunca; nº da tentativa; dias parado; contador `custom_attributes.follow_up`), usadas pelo código e pelo fluxo.
- **Motor ganhou:** `lead_parado {retomada: true}` = todo dia enquanto seguir parado, só quem pode, na ordem do funil, sem o "1 vez por parada" (§13); variáveis `{tentativa}` e `{dias_parado}`; `rascunho_ia {onde, titulo, reserva}` (`reserva` = texto fixo se a IA falhar, sem retentar); passo `registrar_retomada`; `avisar_push {uma_vez_por_dia}` (Redis, 1ª execução do fluxo no dia SP; rodadas do botão não gastam o push do dia).
- **Virada no meio do dia:** o relógio reivindica o dia antes de olhar a chave; o lote do código também reivindica o dia do fluxo; código e fluxo leem a mesma regra. Logo, virar a chave nunca roda 2 lotes nem repete um lead; desligar/ligar o fluxo depois das 11h não roda um 2º lote.
- **Operação:** virar a chave **fora de 10:55–11:30**; depois das 11h esperar ≥ 2 min entre `criar` e `modo normal`. O fluxo só começa no 11h seguinte se virado depois das 11h.
- **Mudou (textos internos, E3/N3, aceitos):** balões "⚙ Fluxo Cadência de retomada: …" (2 por lead: rascunho e tarefa) no lugar de "⟳ Cadência do hub…"; push "Retomadas prontas pra revisar" sem o número do lote; tarefa com dono (Closer, senão SDR) e vence 23:59 SP (N2); rascunho usa o modelo dos fluxos (DeepSeek), não a escolha do Copiloto, e conta em `RAMON_FLUXO_IA_DIA`; conversa pelos últimos ~8 mil caracteres; teto 15 conta também os cliques do botão (N4).
- **Front:** `descrever` ("os FLUXOS fazem…" / "o CÓDIGO faz…"); Watchdog mostra o teto em vigor, ou "sem teto" quando o fluxo não tem limite.
- **Fica para a limpeza (outro PR, 2 semanas depois de rodar em normal):** apagar `Ramon::FollowUpDraftService`, `Ramon::DailyFollowUpJob` e a entrada em `config/schedule.yml`, o ramo do código no `FollowUpDraftJob`, o JSON `sistema/cadencia.json` **e** a linha `origem: sistema` dele, o `HOJE['cadencia']` do `Ramon::Fluxos::Sistema`, o spec do serviço e a env.

## 18. Notas da B4.4/B4.5 (07/10/2026) — lead ganho e eventos do ADVBOX (direto)

- **Escopo (Eduardo, 07/10, o mesmo da B4.2):** direto, sem sombra nem comparação — deploy, criar, virar a chave e teste ao vivo. Reusa a `Ramon::Fluxos::Migracao` da B4.2: grupos `lead_ganho` (`RAMON_FLUXO_LEAD_GANHO`, fluxo "Lead ganho", `sistema_chave: lead_ganho`) e `eventos_advbox` (`RAMON_FLUXO_EVENTOS_ADVBOX`, fluxo "Eventos do ADVBOX", `sistema_chave: eventos_advbox`; o `mover_etapa` recebe a etapa de ganho da conta ao criar). Chave `on` **e** fluxo (`origem: usuario`) ligado, publicado, em modo normal, sem limite do dia e com o gatilho certo ⇒ o fluxo faz e o código para; qualquer peça fora ⇒ o código faz e o fluxo só ensaia. `rake "ramon:fluxos:migracao:criar[grupo,2]"` e `…modo[grupo,2,normal|sombra]`; voltar = `modo …,sombra`, sem deploy. Sem migração.
- **Passo novo "rotina pronta do hub" (`rotina`):** `dossie_passagem` (`Leads::HandoffNoteService`), `pesquisa_nps` / `pesquisa_nps_exito` (`Ramon::NpsDraftJob`), `abrir_caso_advbox` (`Ramon::AdvboxClosingService`: só com token, nunca de novo com `advbox.sincronizado_em`, id guardado ao nascer; fora do ar o motor tenta de novo em 1/5/15 min; 4xx anotado no lead e segue), `concluir_tarefas`. É o mesmo código de hoje: o texto da NPS e do dossiê não se edita na tela (N5). `dossie_passagem`/`pesquisa_nps` também conferem `won_at`, como os callbacks (execução tardia depois de o lead sair do Ganho).
- **A decisão é do evento:** o callback do Lead (`Lead#ganhou`, `won_at` mudou) chama `Ramon::Fluxos::LeadGanho.ganhou`; o `Ramon::AdvboxEventProcessor` chama `Ramon::Fluxos::EventosAdvbox.processar`. Cada um lê `assumiu?` uma vez e manda `assumido`; `lead_ganho` e `evento_advbox` entraram em `Disparo` (`DUAS_VEZES`; `evento_advbox` também em `NA_HORA`: o fluxo roda dentro do job do ADVBOX, para 2 eventos seguidos do mesmo lead não se barrarem no índice único).
- **Reserva do "Lead ganho" (decisão do Eduardo, 07/10):** `pelo_codigo(lead) unless assumido && feitas.any?` — se o fluxo não começa (erro do motor antes de criar a execução, ou fluxo ocupado com o mesmo lead), o código faz o ganho como hoje, nunca em dobro. Resíduo aceito: no caso "ocupado", a execução viva e o job reserva do ADVBOX podem correr em paralelo (igual ao ganho em dobro de hoje).
- **Reserva dos "Eventos do ADVBOX" (N6):** se o fluxo está no comando mas não pega o evento (lead numa execução viva, motor com erro), o código (`Ramon::AdvboxEventRegras`, cópia literal dos 10 handlers) faz aquele evento. Por isso o filtro "regras" do gatilho não desliga efeito: para tirar um efeito, apague o passo do ramo. Na limpeza: manter a reserva ou aceitar perder esse evento raro.
- **Contrato fechado:** o ADVBOX só move o lead para o ganho (nos dois caminhos), **sem** `so_para_frente` — como o código, um lead em Perdido vira ganho (decisão revista na Task 5; um lead já ganho só recebe o balão "⚙ Fluxo …" cosmético, N4). Dossiê/ADVBOX/NPS são sempre e só do "Lead ganho" — as 4 combinações de chave dão 1 de cada. Um lead pode ter 2 rascunhos de NPS (ganho e êxito), como antes.
- **Ficou no código:** o Drive (`Lead#enqueue_drive_export`, N1 — roda a cada atualização dos documentos, não só no ganho). Os efeitos de hoje mudaram de arquivo: `Ramon::Fluxos::LeadGanho.pelo_codigo` e `Ramon::AdvboxEventRegras`. `Lead` e o processador ficaram menores.
- **Motor ganhou:** `{hoje}` (dd/mm/aaaa) e `{primeiro_nome}` no gatilho do ADVBOX; `registrar_atividade` com os 10 tipos `advbox_*`; passo `rotina`. **Limites conhecidos:** `{hoje}` entra como chave (nil) em todo fluxo — um `{hoje}` literal num texto de fluxo antigo vira vazio, e um campo livre chamado `hoje` é sobreposto; o id da etapa de ganho é fixado ao criar o fluxo (se o funil mudar, recrie ou edite o passo `mover_etapa`); `primeiro_nome` duplica o `first_name` do código (limpeza).
- **Execução migrada que falha conta como feita** (semântica "o fluxo está no comando"): o código não repete o evento; a falha fica na tela das execuções. Só "nenhuma execução criada" aciona a reserva.
- **Diferenças aceitas (N2–N4, 07/10):** ordem dossiê → NPS → ADVBOX por último e, fora do ar, 4 tentativas em ~21 min + sino/push aos admins (antes: 3, em silêncio); tarefas de follow-up do ADVBOX vencem no fim do dia (SP) e ficam com o Closer/SDR; balão "⚙ Fluxo …" na conversa e push com o nome do contato; texto da NPS/dossiê não editável (N5). **N1–N7 aceitas em 07/10.** O teste ao vivo usa lead de teste com a trava do ADVBOX pré-marcada e eventos fabricados no console (N7): o "abrir caso" real só aparece no 1º ganho de verdade.
- **Fica para a limpeza (outro PR, 2 semanas depois em normal):** `LeadGanho.pelo_codigo`, os JSON `sistema/lead_ganho.json` e `sistema/eventos_advbox.json` **e** as linhas `origem: sistema` deles, as 2 envs; `AdvboxEventRegras` só se o Eduardo abrir mão da reserva (N6).

## 19. Notas da B5-conta (07/10/2026) — Horário da conta, as 7 rotinas da conta e o selo "regra fixa"

- **Escopo (Eduardo, 07/10):** migrar todas as automações do código, exceto as regras de dado. Revoga o "Resumo do dia fica no código" do §8. As 7 rotinas da conta (resumo do dia, retrato do funil, fechamento do extrato, espelho do Painel, copiloto noturno, publicar peças, avisos do Painel) viram 7 fluxos (`origem: usuario`, `sistema_chave` = o nome da rotina), criados por `rake ramon:fluxos:migracao:criar[<rotina>,conta]` a partir de `db/seeds/ramon/fluxos/migrados/<rotina>.json`, no horário de hoje do código.
- **Gatilho novo `horario_conta` (alvo = a conta):** `hora` (1x/dia a partir dela) ou `a_cada_minutos` (1-1440), `dias` (0-6; sem a chave = todos), fuso SP; chamado pelo `Ramon::FluxoRelogioJob` (`Ramon::Fluxos::HorarioConta`). No quadro só entram Se, Escolha, Esperar, Parar, Push e Rotina pronta (o sino precisa de lead). "Testar na conta..." ensaia com `{conta: true}`. `FluxoExecucao#lead/#conversa` = nil com alvo conta.
- **A vez (o "reivindicar o dia" da B4.3, generalizado):** UPDATE condicional em `ultimo_disparo_em` (`HorarioConta.reivindicar`; a regra é a mesma de `Relogio.reivindicar_dia`, duplicada de propósito para não mexer na B4.3). Por dia: 1 vez no dia; fluxo que nasceu depois da hora de hoje começa amanhã. A cada N min: 1 vez por bloco. O relógio e o job do código disputam a mesma vez do fluxo migrado: no comando, o fluxo faz (não começou — ocupado, erro do motor — o código faz: reserva); fora do comando, quem pegou a vez faz pelo código.
- **Cadência do fluxo = cadência do código (Ruling F3, `Conta.disputa?`/`do_codigo?`):** fora do comando (sombra/desligado), o horário do fluxo só vale para o código quando é o ritmo do próprio código — "por dia" nas seis diárias, "a cada 1 min" no Publicar peças. Um fluxo editado em sombra para outro ritmo (ex.: Resumo do dia "a cada 5 min") NÃO faz o código rodar a cada 5 min: nem o relógio faz pelo código nem o cron disputa a vez; o cron segue no ritmo de sempre. Caso de borda aceito: devolver o comando ao código entre a hora do cron e a hora do fluxo pode pular a rotina daquele dia.
- **Rotina pronta = o job de hoje para a conta:** cada job ganhou `perform(account_id = nil)` (sem conta = o cron, pulando a conta do fluxo no comando; com conta = o fluxo ou a reserva). Resumo, retrato, extrato e avisos rodam dentro do passo (o "depois" do fluxo é depois de verdade); espelho, copiloto e Instagram vão para a fila (passariam de 10 min e o relógio repetiria o passo órfão) — para esses o push "depois" sai quando a rotina é posta na fila, não quando termina. Publicar peças só começa com peça vencida/presa (`PENDENTE`, uma consulta barata por minuto). Avisos do Painel seguem atrás de `PORTAL_AVISOS`.
- **Chaves:** 1 grupo de migração por rotina; 3 envs por família — `RAMON_FLUXO_ROTINAS` (as 5 internas), `RAMON_FLUXO_PUBLICAR_PECAS`, `RAMON_FLUXO_AVISOS_PAINEL`. Virar/voltar cada rotina: `...migracao:modo[<rotina>,conta,normal|sombra]`, sem deploy. Só os 7 fluxos migrados não ensaiam sozinhos em sombra (a vez é decidida por `decidir`); um fluxo de conta criado pelo usuário em sombra ensaia a cada vez.
- **Registro de rotinas por plano:** `Ramon::Fluxos::Rotinas` acha `app/services/ramon/fluxos/rotinas/<plano>.rb` (`ROTINAS` nome -> alvo, `rodar(nome, ctx)`, opcionais `GRUPOS` — juntados em `Migracao::GRUPOS` — e `PENDENTE`); o front acha `automacoes/rotinas/<plano>.js`. Publicar recusa rotina desconhecida e rotina do alvo errado. Os módulos de plano não citam `Migracao` na carga (autoload circular).
- **Regras de dado ficam no código** com o selo "regra fixa (fica no código)" na aba Do sistema (`"fixa": true` no JSON — a chave é `fixa`): histórico do lead, documentos completos, contrato limpo, contrato limpo cancelado, SDR automático.
- **Tetos aceitos:** retrato do funil datado pelo relógio do servidor (UTC) — só muda de data se o horário for para 21:00-23:59; o resumo da equipe dos avisos é 1 por conta (há 1 conta); o expurgo de acessos do Painel fica no cron; o relógio roda `PENDENTE` todo minuto (uma consulta); falha depois de pegar a vez perde a rotina daquele dia (igual aos fluxos comuns); fluxo criado no minuto exato de uma rotina (00:05/00:20/00:30/05:00/08:00) pode ficar 0 vezes naquele dia — não criar os fluxos nesses minutos.
- **Fica para a limpeza (outro PR, 2 semanas depois em normal):** tirar 6 entradas do `config/schedule.yml` (todas menos `Ramon::PortalSyncJob`, que fica: é o cron dele que expurga os logs de acesso do Painel após 6 meses, Marco Civil, via `PortalAcesso.expurgar!`; ou vira job de expurgo próprio) e o ramo "cron" do `cada_conta` (os jobs ficam: são a rotina), os JSON `sistema/<rotina>.json` **e** as linhas `origem: sistema` deles, as 3 envs.

## 20. Notas da B5-leads (07/10/2026) — leads e conversas

- **Escopo (decisões do Eduardo de 07/10 + N1–N5 desta fatia):** criar lead da conversa, origem do lead, sugestão de documento, coach de objeção e agente do hub saem do código para 5 fluxos (`origem: usuario`; chaves `criar_lead_da_conversa`, `origem_do_lead`, `sugestao_documento`, `coach_objecao`, `agente_hub`), direto, sem sombra. Uma chave por automação: `RAMON_FLUXO_CRIAR_LEAD`, `RAMON_FLUXO_ORIGEM_LEAD`, `RAMON_FLUXO_SUGESTAO_DOC`, `RAMON_FLUXO_COACH`, `RAMON_FLUXO_AGENTE` (grupos `criar_lead`, `origem_lead`, `sugestao_doc`, `coach`, `agente`). Etiquetas de etapa/tese (N1 = A): ficam no código como a **6ª regra fixa** (`"fixa": true` em `sistema/etiquetas_etapa_tese.json`), sem fluxo nem chave.
- **Decisão por evento com grupo:** `Ramon::Fluxos::Migracao.decidir(grupo, gatilho, alvo, dados) { código }` — lê `assumiu?` uma vez, dispara os migrados com `assumido` e `migracao` (vários grupos dividem `conversa_criada` e `mensagem_recebida`: o `Disparo.da_vez?` só inicia os do grupo que decidiu) e roda o código `unless assumido && feitas.any?` (reserva). O SLA (B4.2) usa o mesmo ajudante. `mensagem_recebida` e `nota_escrita` entraram em `DUAS_VEZES`. Os 5 grupos moram em `Ramon::Fluxos::Rotinas::Leads::GRUPOS` (juntados em `Migracao::GRUPOS` pelo registro de rotinas da B5-conta), não no literal de `migracao.rb`.
- **A ordem de sempre:** criar lead e origem migrados rodam na hora, dentro do ouvinte (`Disparo::NA_HORA_CHAVES`, por chave do fluxo): o lead existe antes do SLA e dos fluxos comuns de Conversa nova; a origem, antes dos fluxos comuns de Mensagem recebida (provado pelo despachante real, nos dois modos). `lead.created` sai 1 vez.
- **Guardas antes da decisão, e de novo na rotina:** caixa com Criar lead + contato; há origem a anotar (1 execução por lead, não por mensagem); anexo imagem/arquivo; 20+ caracteres; nota @claude do Eduardo. A rotina confere a mesma guarda — a do agente (`Ramon::AgenteNotifyJob.chamado?`) é trava fixa que a tela não tira (a resposta do runner, nota por API, também dispara `nota_escrita`: sem a trava, laço).
- **Motor ganhou:** gatilho `nota_escrita` (nota privada de pessoa; notas de fluxo não têm autor e não disparam); `mensagem_id` no gatilho de mensagem; rotinas prontas `criar_lead`, `origem_do_lead`, `sugestao_documento`, `coach_objecao`, `agente_hub` em `Ramon::Fluxos::Rotinas::Leads` (`app/services/ramon/fluxos/rotinas/leads.rb`; `ROTINAS` com alvo `conversa`, espelhado no front em `automacoes/rotinas/leads.js`; chamam o corpo dos jobs de hoje, `Job.new.perform`). Código mudou de arquivo: `Ramon::LeadDaConversa`.
- **Diferenças aceitas:** balão "⚙ Fluxo" só no criar lead (N3); IA fora do ar ou anexo indisponível: 4 tentativas (1/5/15 min) e desiste em silêncio (N4); rajada de anexos/mensagens: o que chega com o fluxo ocupado é feito pelo código e não aparece em Execuções (N5); coach e documento rodam na fila `default` (antes `low`).
- **Fica para a limpeza (outro PR, 2 semanas depois em normal):** os JSON `sistema/{criar_lead_da_conversa,origem_do_lead,sugestao_documento,coach_objecao,agente_hub}.json` **e** as linhas `origem: sistema` deles, as 5 envs; o código de reserva (`Ramon::LeadDaConversa` e os `perform_later` do ouvinte) fica enquanto houver reserva.
- **Para a B5-externos (rebase):** reusar `Migracao.decidir` (+ `Disparo.externo`) em vez de um `Externos.evento` próprio; a linha de `DUAS_VEZES` e a lista fixada de `rotinasPara('lead')` no `fluxo.spec.js` se juntam no rebase de quem vier por último.

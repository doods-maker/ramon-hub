# Automações em fluxo — B3 (aba "Do sistema" e saída de Configurações → Automação) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mostrar em Inteligência → Automações, na aba **"Do sistema"**, as 6 automações que hoje rodam no código (cadência, SLA da 1ª resposta, lembretes de reunião, eventos do ADVBOX, lead ganho, resumo do dia) desenhadas como fluxos só-leitura que o motor nunca executa, e tirar "Configurações → Automação" do menu (o link antigo cai em Automações).

**Architecture:** Os 6 desenhos são JSON versionados em `db/seeds/ramon/fluxos/sistema/<chave>.json` (`{nome, descricao, limite_dia?, desenho}`). Um módulo novo `Ramon::Fluxos::Sistema` cria/atualiza, por conta, 1 `Fluxo` `origem: 'sistema'` por arquivo (`sistema_chave` = nome do arquivo) quando a lista abre (`GET ramon_fluxos`), sob o lock da conta, e dá o número "Hoje" de cada um a partir de um contador que o código já tem. O motor nunca os roda: `Fluxo.executaveis` já exclui a origem, e a B3 põe **uma** guarda em `Disparo#iniciar` (o funil comum de evento, relógio, "Rodar" e ensaio) + `ensaio` no `bloquear_sistema` da API. Front: abas na `Lista.vue`, painel "Como roda hoje" no `Editor.vue` (que já é só-leitura para `origem: sistema`), item do menu de Configurações removido e rota antiga redirecionando. Sem migração.

**Tech Stack:** Rails 7.1 / RSpec (só no CI), Postgres jsonb; Vue 3.5 `<script setup>`, vue-router 4, vue-i18n 9, Vitest 3 + @vue/test-utils, Histoire (story dos prints).

**Spec:** `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (§2 D6/D7, §7 tela, §8 migração, §10 fatia B3, §13 notas da B2b). Planos anteriores (estilo e decisões): `docs/superpowers/plans/2026-10-05-automacoes-fluxo-b1-motor.md`, `docs/superpowers/plans/2026-10-05-automacoes-fluxo-b2-quadro.md`, `docs/superpowers/plans/2026-10-06-automacoes-fluxo-b2b.md`.

## Escopo decidido pelo Eduardo em 06/10 (vence a spec)

1. **Sem conversor das regras nativas.** O rake `ramon:fluxos:converter_regras` da spec §8 **foi descartado**: produção tem **0 linhas** em `AutomationRule`, não há o que converter. Nenhuma task deste plano cria rake, `origem: 'convertido'` ou mapeamento `send_message → rascunho_texto`. A nota entra na spec (§14, Task 8).
2. **"Configurações → Automação" sai do menu** e a rota antiga redireciona para Inteligência → Automações. O motor nativo do Chatwoot (`AutomationRuleListener`, `AutomationRules::ActionService` — este continua servindo o passo `acao_chatwoot`) fica no código, sem tela. Pontos de entrada conferidos: só o item do `Sidebar.vue` e a rota `automation_list`; **não há** atalho no command bar (`useGoToCommandHotKeys.js` não tem automação), nem tecla, nem busca, nem outro `router.push` para `automation_list`.
3. **Aba "Do sistema", só leitura**, com as 6 automações desenhadas fielmente com os gatilhos e passos que já existem (`fluxo.js` / `grafo.rb`), para a B4+ migrar uma a uma.

## Global Constraints

- Base: produção **9cdd5c6** (B1 motor, B2 quadro e B2b no ar); branch `feat/fluxos-b3`, worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-fluxos-b3`. Nunca `git push`, nunca abrir PR (gate do Eduardo / sessão principal).
- **Sem migração.** `ramon_fluxos` já tem `origem`, `sistema_chave`, `descricao`, `limite_dia`, `rascunho` (`db/schema.rb:1525-1542`). Se alguma task achar que precisa de coluna/índice novo: pare e pergunte (última versão em `db/migrate`: `20261006100001`).
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `Metrics/MethodLength` 19, `Metrics/CyclomaticComplexity` 7, `Metrics/PerceivedComplexity` 8, `Metrics/ClassLength` 175, linha 150, `rubocop-rspec` (`RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50). `RSpec/SpecFilePathFormat`: spec de `A::B::C` fica em `spec/.../a/b/c_spec.rb` (ex.: `Ramon::Fluxos::Sistema` → `spec/services/ramon/fluxos/sistema_spec.rb`). **`app/models/lead.rb`, `app/services/ramon/advbox_event_processor.rb` e `app/finders/conversation_finder.rb` estão NO LIMITE de 175 linhas de classe: nenhuma linha nova neles** (este plano não toca nenhum dos três).
- **CI FOSS apaga `enterprise/`:** todo código que toque `Captain::*` fica atrás de `ChatwootApp.enterprise?` e o spec dele com `if: ChatwootApp.enterprise?`. A B3 não toca Captain — se precisar, pare.
- **Mensagem ao cliente SEMPRE rascunho.** Os textos ao cliente que aparecem nos desenhos do sistema são **cópia literal** do que o código já escreve hoje (notas "RASCUNHO (revisar antes de enviar)"); não são textos novos e nunca são enviados nem executados (é só desenho). Nenhuma task cria texto novo ao cliente.
- **Só admin edita/vê:** a API continua passando pelo `check_authorization` do `RamonFluxosController` (`RamonFluxoPolicy#gerenciar?`); fluxo do sistema não aceita `update`/`destroy`/`publicar`/`rodar`/`ensaio` (403).
- **i18n:** chaves novas só dentro de `CAPTAIN_RAMON.FLUXOS` em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, inseridas na **mesma posição** nos dois arquivos (a trava `specs/i18n.spec.js` compara a lista de chaves em ordem e compila tudo no vue-i18n de **produção**). Strings sem `@`, `|`, `{`, `}` crus; sem apóstrofo. Editar os JSON à mão (Edit), nunca regravar o arquivo inteiro por script.
- **Front:** Tailwind only (sem CSS próprio/scoped/inline, exceto o `:style` de largura que já existe); kit `ramon/helpers/ui.js` (`ABA`, `ABA_ATIVA`, `ABA_INATIVA`, `AVISO`, `CHIP`, `TOM`); evento custom em camelCase; toda `<ul>/<ol>` nova com `list-none` (a B3 não cria lista); sem texto cru no template; **não usar `watchDebounced` do vueuse** (o @vueuse/core 12 resolve outra cópia do vue).
- **Visual:** hub minimalista branco (claro) / preto (escuro), botões e etapas coloridos, fundos coloridos **translúcidos** (`TOM.*` do kit). Na aba Do sistema: aviso `TOM.blue`, selo "roda no código" `TOM.blue`, sem chave liga/desliga.
- **Testes locais:** não há Ruby nem Postgres local — specs Ruby são escritos e conferidos à mão (rastrear cada linha) e quem valida é o CI. Ao escrever spec que cria execução por helper `ctx` (padrão de `spec/services/ramon/fluxos/passos_spec.rb`), chame o `ctx` **uma vez por exemplo**: o índice único parcial `(fluxo_id, alvo_type, alvo_id) WHERE status IN ('rodando','esperando')` barra 2 execuções vivas no mesmo fluxo+alvo. Front:
  - `node_modules` é **junção** para `ramon-hub-wt-fluxos-b2\node_modules` (nunca `rm -rf node_modules`). Use o config local **já criado e fora do git** `vitest.local.config.ts` (raiz do worktree; não commitar):
    `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
    Baseline conferida na base: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs` = 11 arquivos, 86 testes verdes.
  - ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` já existem e são aceitos).
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv`
  Commitar só os caminhos da task (`git add <arquivos>`), nunca `git add -A`.

## Review Focus

1. **Duas abas (ou duas pessoas) abrindo a lista ao mesmo tempo logo depois do deploy** — os 6 fluxos do sistema aparecem uma vez só, e os 4 números (e o "de N") continuam contando só os Meus fluxos. Teste: Task 2 ("cria… e não duplica", "nada mudou: não trava a conta") e Task 3 ("os 4 números contam só os meus").
2. **Alguém liga ou publica um fluxo do sistema** (console, API antiga, B4 distraída) — mesmo assim nada roda: nem evento, nem relógio, nem "Rodar", nem ensaio. Teste: Task 3 (Disparo, Relógio e API).
3. **Desenho corrigido num deploy** (o JSON mudou) — a conta vê o desenho novo na próxima abertura da lista, sem duplicar nem mexer em nada além das colunas do desenho. Teste: Task 2 ("desenho corrigido no código chega à conta…").
4. **Virada do dia** — um lead ganho às 23:30 de ontem em São Paulo (02:30 UTC de hoje) não entra no "Hoje" de hoje. Teste: Task 2 ("o dia é o de São Paulo").
5. **Link salvo e caminho de volta** — quem tem `/settings/automation/list` nos favoritos cai em Automações; o "Voltar" de um desenho do sistema volta para a aba Do sistema (não para Meus fluxos). Teste: Task 6 (rotas) e Task 4 (`?aba=sistema`).

---

## Como os desenhos do sistema são guardados (decisão)

**Linhas `ramon_fluxos` `origem: 'sistema'` por conta, sincronizadas a partir dos JSON em `db/seeds/ramon/fluxos/sistema/` quando a lista abre.** Por quê:

- A B2 já construiu tudo em volta de linhas: o `Editor.vue` abre por `GET ramon_fluxos/:id` e já é só-leitura para `origem === 'sistema'` (`Editor.vue:113` `somenteLeitura`; `useFluxoEditor.js:27` nunca fica "sujo"; botão Excluir escondido `Editor.vue:405`); a API já recusa `update/destroy/publicar/rodar` (`ramon_fluxos_controller.rb:5`, `:79-81`); `Fluxo.executaveis` já exclui a origem (`app/models/fluxo.rb:23`, usado por `Disparo.call` `disparo.rb:10` e `Relogio` `relogio.rb:13`); a `Lista.vue:39` já filtrava `origem !== 'sistema'` esperando por eles. E a B4 precisa de `sistema_chave` numa linha para casar o fluxo em sombra com o código.
- **Não** como os modelos (`modelos.js`, "modelos = conteúdo semente em JS" da B2): modelos só o front consome; aqui quem lê é o Ruby (API, contador "Hoje", trava no Grafo) — a própria B2 registrou "os fluxos do sistema (B3) continuam em `db/seeds`" (divergência #9 do plano da B2). O app já lê `db/seeds/ramon` em produção (`Leads::SeedDefaultConfigService::THESES_SEED_PATH`, `Ramon::InteligenciaSeed::DIR`) e o `.dockerignore` não exclui `db/`.
- **Não** por rake no deploy: seria mais um passo manual do Eduardo e contas novas ficariam sem. A sincronização na lista custa 1 SELECT quando nada mudou e se conserta sozinha quando o JSON muda.
- **Não** como entradas "virtuais" na API: exigiria id falso, rota/endpoint novos no editor e quebraria o `show`/policy que já existem.

**Motor nunca executa — verificado e travado:** `Disparo.call` e `Relogio` passam por `executaveis` (exclui a origem); `Disparo.manual` e `Disparo.ensaiar` **não** checavam a origem (só a API barrava `rodar`, e `ensaio` nem isso). A Task 3 põe 1 guarda em `Disparo#iniciar` (todos os caminhos — evento, relógio, manual, ensaio — passam por ele) e `ensaio` no `bloquear_sistema`, com spec.

## Pontos conferidos no código (arquivo:linha na base 9cdd5c6)

| Automação (`sistema_chave`) | Onde vive | Gatilho escolhido | "Hoje" (fonte barata) |
|---|---|---|---|
| Cadência de retomada (`cadencia`) | `config/schedule.yml:87-90` (11:00 SP) → `Ramon::DailyFollowUpJob` → `Ramon::FollowUpDraftService#perform` (`follow_up_draft_service.rb:27`, teto `DAILY_CAP = 15` :6, `draft_for` :75, `summary_push` :161); botão do painel → `Ramon::FollowUpDraftJob` (`leads_controller.rb:50`) | `lead_parado` 11:00 (`LeadRadar.stalled_leads` = `Cadencia.parados`) | notas `RASCUNHO (revisar antes de enviar) — retomada…` criadas hoje |
| SLA da 1ª resposta (`sla_primeira_resposta`) | `RamonLeadListener#conversation_created` → `enqueue_first_response_sla` (`ramon_lead_listener.rb:21`, `:72`) → `Ramon::FirstResponseSlaJob#perform` (`first_response_sla_job.rb:12`, escalada 60 min, horário 7–21h) | `conversa_criada` | `Ramon::Cadencia.sla_conversations(conta, hoje).count` (conversas novas em caixa de lead) |
| Lembretes de reunião (`lembretes_reuniao`) | `Ramon::ReuniaoAgendamento.call` (`reuniao_agendamento.rb:17`, `#call` :73, `confirmation_draft` :108, `enqueue_reminders` :118, `notify` :52) + `Ramon::MeetingReminderJob#perform` (`meeting_reminder_job.rb:19`, offsets 24h/8h/1h/30min/5min) | `reuniao_marcada` | atividades `meeting_scheduled`/`meeting_rescheduled` de hoje |
| Eventos do ADVBOX (`eventos_advbox`) | `Ramon::AdvboxEventJob` → `Ramon::AdvboxEventProcessor#perform` (`advbox_event_processor.rb:40`, handlers :56-130, `RULES` :15-31) | `evento_advbox` + `escolha` por `regra` | `AdvboxEvent` `processed` atualizados hoje |
| Lead ganho (`lead_ganho`) | callbacks `after_update_commit … if: :saved_change_to_won_at?` (`app/models/lead.rb:51-54`): `Leads::HandoffNoteService`, `Ramon::AdvboxClosingJob`, `Ramon::NpsDraftJob`, `Ramon::DriveExportJob` | `lead_ganho` | leads com `won_at` hoje |
| Resumo do dia (`resumo_do_dia`) | `config/schedule.yml:108-111` (08:00 SP) → `Ramon::DailyDigestJob#perform` (`daily_digest_job.rb:7`) → `Ramon::DailyDigestService`, `RamonDigestMailer` | `relogio` 08:00 | **"—"** (nada é gravado ao mandar) |

Onde o código faz algo que nenhum passo expressa, o desenho usa o passo mais próximo com **rótulo descritivo** e a `descricao` do JSON lista a diferença (1ª linha = "No código: …", mostrada na lista; o resto aparece no painel "Como roda hoje" do desenho). Resumo das lacunas: esperas que contam **para trás** a partir da reunião (lembretes); rascunhos que vão para as **notas do lead** (`LeadNote`), não para a conversa; efeitos em **paralelo** (lead ganho); balão `EventoInline` (não nota privada); envs que ligam/desligam (`NTFY_TOPIC`, `SMTP_ADDRESS`, `ADVBOX_API_TOKEN`, Drive); regras sem campo (sem 1ª resposta, sem retomada aberta, reunião segue marcada); horário 7–21h do SLA ≠ horário comercial dos fluxos; `mover_etapa` sem `etapa_id` (a etapa é do funil de cada conta — a B4 escolhe ao migrar; é o **único** erro de validação aceito nos desenhos).

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `db/seeds/ramon/fluxos/sistema/{cadencia,sla_primeira_resposta,lembretes_reuniao,eventos_advbox,lead_ganho,resumo_do_dia}.json` (novos) | os 6 desenhos + nome + onde vive + lacunas (+ `limite_dia` 15 na cadência) |
| `app/services/ramon/fluxos/sistema.rb` (novo) | `desenhos`, `sincronizar(account)`, `hoje(account, chave)` |
| `app/services/ramon/fluxos/disparo.rb` | 1 guarda em `#iniciar`: origem `sistema` nunca roda |
| `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb` | `index` sincroniza, "Hoje" do sistema, resumo só dos meus; `ensaio` no `bloquear_sistema` |
| `app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue` | abas Meus fluxos / Do sistema (`?aba=sistema`) |
| `…/captain/automacoes/Editor.vue` | painel "Como roda hoje", sem Versões, Voltar → aba Do sistema |
| `…/captain/automacoes/fluxo.js` | `CAMPOS` + `regra` (o `escolha` do desenho do ADVBOX); comentário da B3 corrigido |
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` | `ABA_SISTEMA`, `SISTEMA.{EXPLICA,SEM_CONTADOR}`, `SELO.NO_CODIGO`, `EDITOR.COMO_RODA`, `CAMPOS.regra` |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | sai o item "Automação" de Configurações (FORK(ramon)) |
| `app/javascript/dashboard/routes/dashboard/settings/automation/automation.routes.js` | rota antiga → `captain_automacoes_index` |
| `…/captain/automacoes/Automacoes.story.vue` | variantes `DoSistema` e `SistemaLembretes` (prints) |
| `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` | §14 Notas da B3 |
| specs | Ruby: `spec/services/ramon/fluxos/sistema_spec.rb` (novo), `spec/services/ramon/fluxos/{disparo,relogio}_spec.rb`, `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`; front: `…/automacoes/specs/sistema.spec.js` (novo), `…/automacoes/specs/Lista.spec.js`, `…/settings/automation/specs/automation.routes.spec.js` (novo) |

---

### Task 1: Os 6 desenhos do sistema (JSON) + trava de desenho no front

**Files:**
- Create: `db/seeds/ramon/fluxos/sistema/cadencia.json`, `sla_primeira_resposta.json`, `lembretes_reuniao.json`, `eventos_advbox.json`, `lead_ganho.json`, `resumo_do_dia.json`
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js` (novo)

**Interfaces:**
- Consumes: `validar(desenho)` de `…/automacoes/validar.js` (espelho do `Ramon::Fluxos::Grafo#erros`; devolve `[{no, codigo, params}]`).
- Produces: formato do arquivo, usado pelas Tasks 2, 7 e pela B4:
  `{ "nome": String, "descricao": String /* 1ª linha começa com "No código: " */, "limite_dia"?: Integer, "desenho": { "nos": [{id, tipo, config, posicao}], "setas": [{de, saida, para}] } }`.
  Chaves (nome do arquivo sem `.json`): `cadencia`, `eventos_advbox`, `lead_ganho`, `lembretes_reuniao`, `resumo_do_dia`, `sla_primeira_resposta`. Todo passo (menos o gatilho) tem `config.rotulo`. Único erro de validação aceito: `FALTA etapa_id` (`mover_etapa`).

- [ ] **Step 1: Write the failing test** — `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js`:

```js
// Trava dos desenhos do sistema (db/seeds/ramon/fluxos/sistema/*.json, spec §8):
// o quadro abre cada um e a validação (espelho do Grafo) só deixa passar a
// etapa em aberto — a etapa é do funil de cada conta e a B4 escolhe ao migrar.
import { validar } from '../validar';

const ARQUIVOS = import.meta.glob(
  '../../../../../../../../db/seeds/ramon/fluxos/sistema/*.json',
  { eager: true, import: 'default' }
);
const DESENHOS = Object.entries(ARQUIVOS).map(([caminho, d]) => [
  caminho.split('/').pop(),
  d,
]);

describe('fluxos do sistema', () => {
  it('são os 6 da spec §8', () => {
    expect(DESENHOS.map(([arquivo]) => arquivo).sort()).toEqual([
      'cadencia.json',
      'eventos_advbox.json',
      'lead_ganho.json',
      'lembretes_reuniao.json',
      'resumo_do_dia.json',
      'sla_primeira_resposta.json',
    ]);
  });

  it.each(DESENHOS)(
    '%s: nome, onde vive no código e desenho válido (menos a etapa)',
    (_arquivo, d) => {
      expect(d.nome).toBeTruthy();
      expect(d.descricao.split('\n')[0]).toMatch(/^No código: /);
      const erros = validar(d.desenho).filter(
        e => !(e.codigo === 'FALTA' && e.params.campo === 'etapa_id')
      );
      expect(erros).toEqual([]);
    }
  );

  it.each(DESENHOS)(
    '%s: todo passo diz no rótulo o que o código faz',
    (_a, d) => {
      const semRotulo = d.desenho.nos
        .filter(n => n.tipo !== 'gatilho' && !n.config?.rotulo)
        .map(n => n.id);
      expect(semRotulo).toEqual([]);
    }
  );
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js --config vitest.local.config.ts`
Expected: FAIL — "são os 6 da spec §8" recebe `[]` (a pasta ainda não existe; o `import.meta.glob` volta vazio).

- [ ] **Step 3: Create the 6 JSON files** (UTF-8, exatamente como abaixo; os textos ao cliente são cópia do código — ver Global Constraints).

`db/seeds/ramon/fluxos/sistema/cadencia.json`:

```json
{
  "nome": "Cadência de retomada",
  "descricao": "No código: Ramon::DailyFollowUpJob (todo dia às 11:00) → Ramon::FollowUpDraftService; também roda na hora pelo botão Preparar retomada do painel do lead (Ramon::FollowUpDraftJob).\n\nO desenho não consegue mostrar:\n• o Se só confere se há conversa; as outras regras (nenhuma tarefa de retomada aberta e a última retomada há mais de 5 dias) estão só no rótulo;\n• o código roda todo dia para quem segue parado (o gatilho Lead parado dos fluxos dispara 1 vez por parada);\n• o teto é de 15 retomadas por dia por conta, na ordem do radar de parados;\n• o rascunho vai para as notas do lead (não para a conversa) e, se a IA falhar, entra um texto fixo de retomada;\n• o contador de tentativas fica em custom_attributes.follow_up (o passo Preencher campo grava em campos);\n• o aviso na conversa é um balão de evento (não nota privada) e o push é um só por conta, com o total do lote.",
  "limite_dia": 15,
  "desenho": {
    "nos": [
      { "id": "n1", "tipo": "gatilho", "config": { "tipo": "lead_parado", "hora": "11:00" }, "posicao": { "x": 0, "y": 0 } },
      { "id": "n2", "tipo": "se", "config": { "rotulo": "Pode retomar? (tem conversa, nenhuma retomada aberta, última há mais de 5 dias)", "juncao": "e", "condicoes": [{ "campo": "caixa", "operador": "existe", "valor": "" }] }, "posicao": { "x": 0, "y": 140 } },
      { "id": "n3", "tipo": "rascunho_ia", "config": { "rotulo": "Rascunho de retomada nº N (nas notas do lead)", "instrucao": "Mensagem de retomada de WhatsApp para um lead que parou de responder: 2 a 4 frases, tom de médico de confiança, sem pressão. O ângulo muda com a tentativa — 1ª: lembrete leve de que estamos à disposição; 2ª: uma informação nova e útil sobre a tese; 3ª em diante: pergunta direta sobre o interesse, deixando a porta aberta. Nunca prometa resultado do caso nem prazo do INSS. Não invente fatos que não estejam na conversa." }, "posicao": { "x": 0, "y": 300 } },
      { "id": "n4", "tipo": "criar_tarefa", "config": { "rotulo": "Tarefa de retomada para hoje", "titulo": "Retomada nº N", "tipo": "follow_up", "prazo_dias": 0 }, "posicao": { "x": 0, "y": 460 } },
      { "id": "n5", "tipo": "preencher_campo", "config": { "rotulo": "Conta a tentativa (custom_attributes.follow_up)", "chave": "follow_up", "valor": "tentativa nº N, hoje" }, "posicao": { "x": 0, "y": 600 } },
      { "id": "n6", "tipo": "nota_privada", "config": { "rotulo": "Balão na conversa: Cadência do hub", "texto": "⟳ Cadência do hub preparou o rascunho de retomada nº N — revise e envie pelo painel." }, "posicao": { "x": 0, "y": 740 } },
      { "id": "n7", "tipo": "avisar_push", "config": { "rotulo": "Push: retomadas prontas (1 por conta)", "titulo": "Retomadas prontas pra revisar", "texto": "N rascunho(s) de retomada esperando revisão no hub" }, "posicao": { "x": 0, "y": 880 } }
    ],
    "setas": [
      { "de": "n1", "saida": "s", "para": "n2" },
      { "de": "n2", "saida": "sim", "para": "n3" },
      { "de": "n3", "saida": "s", "para": "n4" },
      { "de": "n4", "saida": "s", "para": "n5" },
      { "de": "n5", "saida": "s", "para": "n6" },
      { "de": "n6", "saida": "s", "para": "n7" }
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/sla_primeira_resposta.json`:

```json
{
  "nome": "SLA da 1ª resposta",
  "descricao": "No código: RamonLeadListener#conversation_created (caixas com Criar lead ligado) agenda Ramon::FirstResponseSlaJob para N minutos depois; o próprio job agenda a escalada de 60 minutos.\n\nO desenho não consegue mostrar:\n• o tempo vem do SLA de cada caixa (padrão de 5 min no env RAMON_SLA_FIRST_RESPONSE_MINUTES) e a escalada conta 60 min desde a criação da conversa;\n• \"ainda sem 1ª resposta\" não tem campo — o Se só confere se a conversa segue aberta; o código também desiste se a conversa não tem lead;\n• o horário do código é das 7h às 21h, todos os dias — diferente do horário comercial dos fluxos (seg–sex, 8h–18h);\n• a escalada é agendada mesmo fora do horário; só o aviso respeita o horário;\n• o sino vai para o SDR do lead (sem SDR, para os gestores) e, na escalada, para os gestores — o passo Sino não escolhe por papel.",
  "desenho": {
    "nos": [
      { "id": "n1", "tipo": "gatilho", "config": { "tipo": "conversa_criada" }, "posicao": { "x": 0, "y": 0 } },
      { "id": "n2", "tipo": "esperar", "config": { "rotulo": "SLA da caixa (padrão 5 min)", "quantidade": 5, "unidade": "minutos" }, "posicao": { "x": 0, "y": 140 } },
      { "id": "n3", "tipo": "se", "config": { "rotulo": "Ainda sem 1ª resposta e aberta?", "juncao": "e", "condicoes": [{ "campo": "status", "operador": "igual", "valor": "open" }] }, "posicao": { "x": 0, "y": 280 } },
      { "id": "n4", "tipo": "se", "config": { "rotulo": "Entre 7h e 21h?", "juncao": "e", "condicoes": [{ "campo": "texto", "operador": "em_horario_comercial", "valor": "" }] }, "posicao": { "x": -130, "y": 440 } },
      { "id": "n5", "tipo": "avisar_sino", "config": { "rotulo": "Sino do SDR (sem SDR: gestores)", "texto": "Lead aguardando 1ª resposta há 5 min: {nome_completo}" }, "posicao": { "x": -260, "y": 600 } },
      { "id": "n6", "tipo": "avisar_push", "config": { "rotulo": "Push: lead aguardando", "titulo": "Lead aguardando 1a resposta", "texto": "Lead aguardando 1ª resposta há 5min: {nome_completo}" }, "posicao": { "x": -260, "y": 740 } },
      { "id": "n7", "tipo": "esperar", "config": { "rotulo": "Até 60 min da criação da conversa", "quantidade": 55, "unidade": "minutos" }, "posicao": { "x": 0, "y": 880 } },
      { "id": "n8", "tipo": "se", "config": { "rotulo": "Ainda sem 1ª resposta e aberta?", "juncao": "e", "condicoes": [{ "campo": "status", "operador": "igual", "valor": "open" }] }, "posicao": { "x": 0, "y": 1020 } },
      { "id": "n9", "tipo": "se", "config": { "rotulo": "Entre 7h e 21h?", "juncao": "e", "condicoes": [{ "campo": "texto", "operador": "em_horario_comercial", "valor": "" }] }, "posicao": { "x": -130, "y": 1180 } },
      { "id": "n10", "tipo": "avisar_sino", "config": { "rotulo": "Escalada: sino dos gestores", "texto": "Lead aguardando 1ª resposta há 60 min: {nome_completo}" }, "posicao": { "x": -260, "y": 1340 } }
    ],
    "setas": [
      { "de": "n1", "saida": "s", "para": "n2" },
      { "de": "n2", "saida": "s", "para": "n3" },
      { "de": "n3", "saida": "sim", "para": "n4" },
      { "de": "n4", "saida": "sim", "para": "n5" },
      { "de": "n5", "saida": "s", "para": "n6" },
      { "de": "n6", "saida": "s", "para": "n7" },
      { "de": "n4", "saida": "nao", "para": "n7" },
      { "de": "n7", "saida": "s", "para": "n8" },
      { "de": "n8", "saida": "sim", "para": "n9" },
      { "de": "n9", "saida": "sim", "para": "n10" }
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/lembretes_reuniao.json` (os 5 lembretes aparecem como **um** ciclo com rótulo — decisão E5):

```json
{
  "nome": "Lembretes de reunião",
  "descricao": "No código: Ramon::ReuniaoAgendamento.call (reunião marcada pelo painel do lead ou pelo Cal.com) e Ramon::MeetingReminderJob (os lembretes).\n\nO desenho não consegue mostrar:\n• os 5 lembretes (24h, 8h, 1h, 30 min e 5 min antes) contam para trás a partir da hora da reunião — a espera dos fluxos só conta para a frente; aqui eles aparecem como um ciclo só, e saem apenas os que ainda estão no futuro;\n• cada lembrete confere se a tarefa da reunião segue aberta naquele horário (cancelou ou remarcou → o lembrete antigo é descartado) e não repete o mesmo lembrete;\n• a tarefa da reunião vence na hora marcada; a etapa só anda para a frente (quem já está adiante fica onde está);\n• o Closer só é escolhido se o lead ainda não tem;\n• o rascunho de confirmação vai para as notas do lead (não para a conversa) e o sino de reunião marcada vai para toda a conta;\n• remarcar refaz atividade, rascunho, lembretes e sino (sem mexer em tarefa nova, etapa ou Closer); cancelar registra a atividade, apaga a tarefa e avisa no sino e no push.",
  "desenho": {
    "nos": [
      { "id": "n1", "tipo": "gatilho", "config": { "tipo": "reuniao_marcada" }, "posicao": { "x": 0, "y": 0 } },
      { "id": "n2", "tipo": "registrar_atividade", "config": { "rotulo": "Atividade: reunião agendada", "texto": "Reunião agendada para {quando}" }, "posicao": { "x": 0, "y": 140 } },
      { "id": "n3", "tipo": "criar_tarefa", "config": { "rotulo": "Tarefa da reunião (vence na hora marcada)", "titulo": "Reunião", "tipo": "meeting", "prazo_dias": 0 }, "posicao": { "x": 0, "y": 280 } },
      { "id": "n4", "tipo": "mover_etapa", "config": { "rotulo": "Mover para Reunião agendada (só para a frente)", "etapa_id": null }, "posicao": { "x": 0, "y": 420 } },
      { "id": "n5", "tipo": "trocar_responsavel", "config": { "rotulo": "Closer automático (se o lead ainda não tem)", "papel": "closer" }, "posicao": { "x": 0, "y": 560 } },
      { "id": "n6", "tipo": "rascunho_texto", "config": { "rotulo": "Rascunho de confirmação (nas notas do lead)", "texto": "Oi {nome}! Nossa conversa está confirmada pra {quando}. Vou te esperar, tá? Se não puder comparecer, me avise com antecedência que a gente remarca sem problema." }, "posicao": { "x": 0, "y": 700 } },
      { "id": "n7", "tipo": "avisar_sino", "config": { "rotulo": "Sino para toda a conta", "texto": "Reunião marcada: {nome_completo} — {quando}" }, "posicao": { "x": 0, "y": 860 } },
      { "id": "n8", "tipo": "avisar_push", "config": { "rotulo": "Push: reunião marcada", "titulo": "Reuniao marcada: {nome_completo}", "texto": "{quando}" }, "posicao": { "x": 0, "y": 1000 } },
      { "id": "n9", "tipo": "esperar", "config": { "rotulo": "Até 24h · 8h · 1h · 30 min · 5 min antes da reunião", "quantidade": 1, "unidade": "dias" }, "posicao": { "x": 0, "y": 1140 } },
      { "id": "n10", "tipo": "avisar_sino", "config": { "rotulo": "Lembrete ao Closer e ao SDR (se a reunião segue marcada)", "texto": "Reunião de {nome_completo}: {quando}" }, "posicao": { "x": 0, "y": 1280 } },
      { "id": "n11", "tipo": "avisar_push", "config": { "rotulo": "Push do lembrete", "titulo": "Reunião {nome_completo} em 24h antes", "texto": "{quando} — hora de mandar a mensagem de confirmação pro cliente" }, "posicao": { "x": 0, "y": 1420 } }
    ],
    "setas": [
      { "de": "n1", "saida": "s", "para": "n2" },
      { "de": "n2", "saida": "s", "para": "n3" },
      { "de": "n3", "saida": "s", "para": "n4" },
      { "de": "n4", "saida": "s", "para": "n5" },
      { "de": "n5", "saida": "s", "para": "n6" },
      { "de": "n6", "saida": "s", "para": "n7" },
      { "de": "n7", "saida": "s", "para": "n8" },
      { "de": "n8", "saida": "s", "para": "n9" },
      { "de": "n9", "saida": "s", "para": "n10" },
      { "de": "n10", "saida": "s", "para": "n11" }
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/eventos_advbox.json` (o `escolha` por `regra` abre 1 coluna por handler do `AdvboxEventProcessor::RULES`, na mesma ordem; a saída "outro" fica sem seta — o gatilho só nasce com regra):

```json
{
  "nome": "Eventos do ADVBOX",
  "descricao": "No código: Flowter → webhook do hub → Ramon::AdvboxEventJob → Ramon::AdvboxEventProcessor (cada regra é um método com o nome da chave).\n\nO desenho não consegue mostrar:\n• a regra sai do nome da etapa/tarefa no payload do Flowter, e o lead é achado pelo CPF ou pelo telefone (lead aberto; senão o mais recente do funil) — sem regra ou sem lead o evento fica guardado e nada roda;\n• cada atividade tem um tipo próprio (advbox_contrato_fechado, advbox_indeferido, …) e leva o nome da etapa do ADVBOX;\n• os rascunhos vão para as notas do lead (não para a conversa); a pesquisa NPS de êxito e de concessão sai uma vez só por lead;\n• os pushes só saem com o ntfy configurado (NTFY_TOPIC);\n• em Contrato fechado o lead vai para a etapa de ganho da conta (se ainda não estava); em Arquivado todas as tarefas abertas do lead são concluídas — não há passo para isso.",
  "desenho": {
    "nos": [
      {"id":"n1","tipo":"gatilho","config":{"tipo":"evento_advbox"},"posicao":{"x":0,"y":0}},
      {"id":"n2","tipo":"escolha","config":{"rotulo":"Qual regra do ADVBOX?","campo":"regra","casos":[{"chave":"c1","rotulo":"Contrato fechado","valores":["contrato_fechado"]},{"chave":"c2","rotulo":"Requerimento protocolado","valores":["requerimento_protocolado"]},{"chave":"c3","rotulo":"INSS negou","valores":["indeferimento"]},{"chave":"c4","rotulo":"Decisão","valores":["decisao"]},{"chave":"c5","rotulo":"Exigência","valores":["exigencia"]},{"chave":"c6","rotulo":"Benefício futuro","valores":["reativacao_futura"]},{"chave":"c7","rotulo":"Êxito","valores":["exito"]},{"chave":"c8","rotulo":"Marco","valores":["marco"]},{"chave":"c9","rotulo":"Concessão","valores":["concessao"]},{"chave":"c10","rotulo":"Arquivado","valores":["arquivado"]}]},"posicao":{"x":0,"y":140}},
      {"id":"n3","tipo":"mover_etapa","config":{"rotulo":"Marca o lead como ganho (etapa de ganho da conta)","etapa_id":null},"posicao":{"x":-1350,"y":320}},
      {"id":"n4","tipo":"registrar_atividade","config":{"rotulo":"Atividade: contrato fechado","texto":"ADVBOX: {texto}"},"posicao":{"x":-1350,"y":470}},
      {"id":"n5","tipo":"avisar_push","config":{"rotulo":"Push: contrato fechado","titulo":"Contrato fechado no ADVBOX","texto":"{nome_completo}: lead marcado como ganho no hub"},"posicao":{"x":-1350,"y":620}},
      {"id":"n6","tipo":"registrar_atividade","config":{"rotulo":"Atividade: requerimento protocolado","texto":"ADVBOX: {texto} (com a data de hoje)"},"posicao":{"x":-1050,"y":320}},
      {"id":"n7","tipo":"criar_tarefa","config":{"rotulo":"Follow-up de 45 dias","titulo":"Verificar decisão/exigência do INSS (protocolo ADVBOX)","tipo":"follow_up","prazo_dias":45},"posicao":{"x":-1050,"y":470}},
      {"id":"n8","tipo":"avisar_push","config":{"rotulo":"Push: requerimento protocolado","titulo":"Requerimento protocolado no INSS","texto":"{nome_completo}: follow-up de 45 dias criado"},"posicao":{"x":-1050,"y":620}},
      {"id":"n9","tipo":"registrar_atividade","config":{"rotulo":"Atividade: INSS negou","texto":"ADVBOX: {texto}"},"posicao":{"x":-750,"y":320}},
      {"id":"n10","tipo":"criar_tarefa","config":{"rotulo":"Avaliar judicialização em 1 dia","titulo":"Avaliar judicialização — INSS negou (ADVBOX)","tipo":"follow_up","prazo_dias":1},"posicao":{"x":-750,"y":470}},
      {"id":"n11","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: INSS negou (nas notas do lead)","texto":"Oi {nome}, tudo bem? Saiu a decisão do INSS sobre o seu pedido e, infelizmente, foi negativa. Isso não é o fim: muitos casos como o seu são revertidos na Justiça. Posso te explicar os próximos passos?"},"posicao":{"x":-750,"y":620}},
      {"id":"n12","tipo":"avisar_push","config":{"rotulo":"Push: INSS negou","titulo":"INSS NEGOU - avaliar judicializacao","texto":"{nome_completo}: tarefa na Esteira + rascunho de mensagem no caso"},"posicao":{"x":-750,"y":770}},
      {"id":"n13","tipo":"registrar_atividade","config":{"rotulo":"Atividade: decisão proferida","texto":"ADVBOX: {texto}"},"posicao":{"x":-450,"y":320}},
      {"id":"n14","tipo":"criar_tarefa","config":{"rotulo":"Analisar a decisão em 2 dias","titulo":"Analisar decisão registrada no ADVBOX","tipo":"follow_up","prazo_dias":2},"posicao":{"x":-450,"y":470}},
      {"id":"n15","tipo":"avisar_push","config":{"rotulo":"Push: decisão","titulo":"Decisao proferida (ADVBOX)","texto":"{nome_completo}: analisar e decidir comunicação"},"posicao":{"x":-450,"y":620}},
      {"id":"n16","tipo":"registrar_atividade","config":{"rotulo":"Atividade: carta de exigências","texto":"ADVBOX: {texto}"},"posicao":{"x":-150,"y":320}},
      {"id":"n17","tipo":"criar_tarefa","config":{"rotulo":"Cumprir a exigência em 2 dias","titulo":"Cumprir exigência do INSS — prazo curto (ADVBOX)","tipo":"follow_up","prazo_dias":2},"posicao":{"x":-150,"y":470}},
      {"id":"n18","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: exigência do INSS (nas notas do lead)","texto":"Oi {nome}! O INSS pediu um documento a mais no seu processo. Pode me mandar por aqui quando conseguir? Te ajudo com o que precisar."},"posicao":{"x":-150,"y":620}},
      {"id":"n19","tipo":"avisar_push","config":{"rotulo":"Push: exigência","titulo":"Carta de exigencias do INSS","texto":"{nome_completo}: prazo curto — tarefa + rascunho criados"},"posicao":{"x":-150,"y":770}},
      {"id":"n20","tipo":"registrar_atividade","config":{"rotulo":"Atividade: benefício futuro","texto":"ADVBOX: {texto}"},"posicao":{"x":150,"y":320}},
      {"id":"n21","tipo":"criar_tarefa","config":{"rotulo":"Retomar contato em 180 dias","titulo":"Reativação: benefício futuro — retomar contato","tipo":"follow_up","prazo_dias":180},"posicao":{"x":150,"y":470}},
      {"id":"n22","tipo":"registrar_atividade","config":{"rotulo":"Atividade: êxito (pagamento)","texto":"ADVBOX: {texto}"},"posicao":{"x":450,"y":320}},
      {"id":"n23","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: comunicado de êxito (nas notas do lead)","texto":"{nome}, ótima notícia! 🎉 Saiu o pagamento do seu processo. Foi uma alegria acompanhar seu caso até aqui. Se puder, sua avaliação no Google ajuda muito outras pessoas a nos encontrarem."},"posicao":{"x":450,"y":470}},
      {"id":"n24","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: pesquisa NPS de êxito (1 vez só)","texto":"{nome}, de 0 a 10, que nota você dá pro nosso atendimento até aqui? Sua opinião ajuda a gente a melhorar de verdade. E se a experiência foi boa, sua avaliação no Google ajuda outras pessoas a nos encontrarem: [link de avaliação do Google]"},"posicao":{"x":450,"y":620}},
      {"id":"n25","tipo":"avisar_push","config":{"rotulo":"Push: êxito","titulo":"Exito: pagamento no ADVBOX","texto":"{nome_completo}: rascunho de comunicado pronto no caso"},"posicao":{"x":450,"y":770}},
      {"id":"n26","tipo":"registrar_atividade","config":{"rotulo":"Atividade: marco processual","texto":"ADVBOX: {texto}"},"posicao":{"x":750,"y":320}},
      {"id":"n27","tipo":"avisar_push","config":{"rotulo":"Push: marco processual","titulo":"Marco processual (ADVBOX)","texto":"{nome_completo}: {texto}"},"posicao":{"x":750,"y":470}},
      {"id":"n28","tipo":"registrar_atividade","config":{"rotulo":"Atividade: benefício concedido","texto":"ADVBOX: {texto}"},"posicao":{"x":1050,"y":320}},
      {"id":"n29","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: benefício concedido (nas notas do lead)","texto":"{nome}, notícia boa! 🎉 O INSS CONCEDEU o seu benefício. Agora vamos conferir a implantação e os valores — te aviso de cada passo."},"posicao":{"x":1050,"y":470}},
      {"id":"n30","tipo":"rascunho_texto","config":{"rotulo":"Rascunho: pesquisa NPS de êxito (1 vez só)","texto":"{nome}, de 0 a 10, que nota você dá pro nosso atendimento até aqui? Sua opinião ajuda a gente a melhorar de verdade. E se a experiência foi boa, sua avaliação no Google ajuda outras pessoas a nos encontrarem: [link de avaliação do Google]"},"posicao":{"x":1050,"y":620}},
      {"id":"n31","tipo":"avisar_push","config":{"rotulo":"Push: concessão","titulo":"Beneficio CONCEDIDO (ADVBOX)","texto":"{nome_completo}: rascunho de boa notícia pronto no caso"},"posicao":{"x":1050,"y":770}},
      {"id":"n32","tipo":"registrar_atividade","config":{"rotulo":"Conclui as tarefas abertas do lead e registra a atividade","texto":"ADVBOX: {texto} — follow-ups do hub encerrados"},"posicao":{"x":1350,"y":320}}
    ],
    "setas": [
      {"de":"n1","saida":"s","para":"n2"},
      {"de":"n2","saida":"c1","para":"n3"},
      {"de":"n3","saida":"s","para":"n4"},
      {"de":"n4","saida":"s","para":"n5"},
      {"de":"n2","saida":"c2","para":"n6"},
      {"de":"n6","saida":"s","para":"n7"},
      {"de":"n7","saida":"s","para":"n8"},
      {"de":"n2","saida":"c3","para":"n9"},
      {"de":"n9","saida":"s","para":"n10"},
      {"de":"n10","saida":"s","para":"n11"},
      {"de":"n11","saida":"s","para":"n12"},
      {"de":"n2","saida":"c4","para":"n13"},
      {"de":"n13","saida":"s","para":"n14"},
      {"de":"n14","saida":"s","para":"n15"},
      {"de":"n2","saida":"c5","para":"n16"},
      {"de":"n16","saida":"s","para":"n17"},
      {"de":"n17","saida":"s","para":"n18"},
      {"de":"n18","saida":"s","para":"n19"},
      {"de":"n2","saida":"c6","para":"n20"},
      {"de":"n20","saida":"s","para":"n21"},
      {"de":"n2","saida":"c7","para":"n22"},
      {"de":"n22","saida":"s","para":"n23"},
      {"de":"n23","saida":"s","para":"n24"},
      {"de":"n24","saida":"s","para":"n25"},
      {"de":"n2","saida":"c8","para":"n26"},
      {"de":"n26","saida":"s","para":"n27"},
      {"de":"n2","saida":"c9","para":"n28"},
      {"de":"n28","saida":"s","para":"n29"},
      {"de":"n29","saida":"s","para":"n30"},
      {"de":"n30","saida":"s","para":"n31"},
      {"de":"n2","saida":"c10","para":"n32"}
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/lead_ganho.json` (IDs do ADVBOX = constantes de `Ramon::AdvboxClosingService`: `TASK_ID` 8745394, `USERS_ID` 266778):

```json
{
  "nome": "Lead ganho",
  "descricao": "No código: callbacks do Lead quando won_at muda (app/models/lead.rb: generate_handoff_note, enqueue_advbox_closing, enqueue_nps_draft, enqueue_drive_export).\n\nO desenho não consegue mostrar:\n• as 4 ações são independentes e rodam ao mesmo tempo (o quadro só desenha fila), cada uma com a sua trava;\n• o dossiê vai para as notas do lead e não se repete se já houver um dos últimos 5 minutos;\n• no ADVBOX o código cria o cliente, o processo (etapa CONTRATO FECHADO) e a tarefa 1º CONTATO COM O LEAD (Ramon::AdvboxClosingService) — o passo ADVBOX dos fluxos só cria tarefa num processo que já existe; só roda com o token do ADVBOX e tenta de novo até 3 vezes se o ADVBOX estiver fora;\n• a pesquisa NPS vai para as notas do lead e sai uma vez só por lead;\n• o Drive só roda com o Drive configurado e roda de novo a cada atualização dos documentos de um lead já ganho.",
  "desenho": {
    "nos": [
      { "id": "n1", "tipo": "gatilho", "config": { "tipo": "lead_ganho" }, "posicao": { "x": 0, "y": 0 } },
      { "id": "n2", "tipo": "nota_privada", "config": { "rotulo": "Dossiê de passagem para o jurídico (nas notas do lead)", "texto": "📋 DOSSIÊ — texto único de passagem do caso (Ramon::DossiePassagemTexto)" }, "posicao": { "x": 0, "y": 140 } },
      { "id": "n3", "tipo": "advbox", "config": { "rotulo": "ADVBOX: cliente, processo e tarefa 1º contato (só com token)", "acao": "tarefa", "tipo_tarefa_id": 8745394, "responsavel_id": 266778, "descricao": "Cliente + processo na etapa CONTRATO FECHADO + tarefa 1º CONTATO COM O LEAD" }, "posicao": { "x": 0, "y": 280 } },
      { "id": "n4", "tipo": "rascunho_texto", "config": { "rotulo": "Rascunho: pesquisa NPS (nas notas do lead, 1 vez só)", "texto": "{nome}, de 0 a 10, que nota você dá pro nosso atendimento até aqui? Sua opinião ajuda a gente a melhorar de verdade. E se a experiência foi boa, sua avaliação no Google ajuda outras pessoas a nos encontrarem: [link de avaliação do Google]" }, "posicao": { "x": 0, "y": 420 } },
      { "id": "n5", "tipo": "nota_privada", "config": { "rotulo": "Drive: exporta os documentos conferidos (só com o Drive ligado)", "texto": "Sobe para o Drive os documentos do lead já conferidos pela equipe" }, "posicao": { "x": 0, "y": 580 } }
    ],
    "setas": [
      { "de": "n1", "saida": "s", "para": "n2" },
      { "de": "n2", "saida": "s", "para": "n3" },
      { "de": "n3", "saida": "s", "para": "n4" },
      { "de": "n4", "saida": "s", "para": "n5" }
    ]
  }
}
```

`db/seeds/ramon/fluxos/sistema/resumo_do_dia.json`:

```json
{
  "nome": "Resumo do dia",
  "descricao": "No código: Ramon::DailyDigestJob (todo dia às 08:00) → Ramon::DailyDigestService; o e-mail sai pelo AdministratorNotifications::RamonDigestMailer.\n\nFica no código (spec §8): é relatório, não fluxo — o desenho é só para conferir.\n\nO desenho não consegue mostrar:\n• roda uma vez por conta, não uma vez por lead como o gatilho Relógio;\n• o push só sai se o dia tem algo (tarefas vencidas, conversas fora do SLA, reunião ainda hoje ou valor em jogo) e só com o ntfy configurado;\n• o e-mail de gestão (leads novos, ganhos, perdidos e 1ª resposta de ontem) só sai com SMTP configurado — o quadro não tem passo de e-mail.",
  "desenho": {
    "nos": [
      { "id": "n1", "tipo": "gatilho", "config": { "tipo": "relogio", "hora": "08:00", "rotulo": "Todo dia às 08:00 (1 vez por conta)" }, "posicao": { "x": 0, "y": 0 } },
      { "id": "n2", "tipo": "avisar_push", "config": { "rotulo": "Push: seu dia (só se houver algo)", "titulo": "Ramon Hub · seu dia", "texto": "N tarefas vencidas · N fora do SLA · reunião HH:MM (nome) · R$ em jogo" }, "posicao": { "x": 0, "y": 140 } },
      { "id": "n3", "tipo": "nota_privada", "config": { "rotulo": "E-mail de gestão: números de ontem (só com SMTP)", "texto": "Leads novos, ganhos, perdidos e tempo de 1ª resposta de ontem" }, "posicao": { "x": 0, "y": 280 } }
    ],
    "setas": [
      { "de": "n1", "saida": "s", "para": "n2" },
      { "de": "n2", "saida": "s", "para": "n3" }
    ]
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js --config vitest.local.config.ts`
Expected: PASS — 13 testes (1 + 6 + 6). Depois `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js` → limpo.

- [ ] **Step 5: Commit**

```bash
git add db/seeds/ramon/fluxos/sistema app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/sistema.spec.js
git commit -m "feat(fluxos): desenhos das 6 automações do sistema (só leitura)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 2: `Ramon::Fluxos::Sistema` — fluxos do sistema por conta + "Hoje"

**Files:**
- Create: `app/services/ramon/fluxos/sistema.rb`
- Test: `spec/services/ramon/fluxos/sistema_spec.rb` (novo)

**Interfaces:**
- Consumes: os JSON da Task 1; `Ramon::Fluxos::Grafo.new(desenho).gatilho` / `#erros`; `Ramon::Cadencia.sla_conversations(account, range)` (`app/services/ramon/cadencia.rb:45-49`); `Fluxo::ZONA` (`'America/Sao_Paulo'`).
- Produces (usado pela Task 3):
  - `Ramon::Fluxos::Sistema.desenhos → Hash{String chave => Hash do JSON}` (ordenado pela chave)
  - `Ramon::Fluxos::Sistema.sincronizar(account) → nil` — garante 1 `Fluxo` `origem: 'sistema'` por chave na conta, com `nome`, `descricao`, `limite_dia`, `rascunho` (= `desenho`) e `gatilho_tipo` do JSON; `ativo` fica `false` e `versao_publicada_id` `nil`. Nada mudou → só 1 SELECT, sem lock.
  - `Ramon::Fluxos::Sistema.hoje(account, chave) → Integer | nil` (nil = sem contador barato → front mostra "—"). Dia = hoje no fuso SP.

- [ ] **Step 1: Write the failing test** — `spec/services/ramon/fluxos/sistema_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Fluxos::Sistema do
  let(:account) { create(:account) }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  def do_sistema(chave) = account.fluxos.find_by(origem: 'sistema', sistema_chave: chave)

  it 'os 6 desenhos da spec §8 passam no Grafo (só a etapa fica em aberto: é do funil de cada conta)' do
    expect(described_class.desenhos.keys).to eq(%w[cadencia eventos_advbox lead_ganho lembretes_reuniao resumo_do_dia sla_primeira_resposta])
    described_class.desenhos.each do |chave, d|
      erros = Ramon::Fluxos::Grafo.new(d['desenho']).erros.grep_v(/: falta etapa_id\z/)
      expect([chave, d['nome'].present?, erros]).to eq([chave, true, []])
    end
  end

  it 'cria 1 fluxo do sistema por desenho, desligado e sem versão, e não duplica' do
    2.times { described_class.sincronizar(account) }
    fluxos = account.fluxos.where(origem: 'sistema')
    expect(fluxos.pluck(:sistema_chave)).to match_array(described_class.desenhos.keys)
    expect(fluxos.pluck(:ativo, :versao_publicada_id).uniq).to eq([[false, nil]])
    expect(do_sistema('lembretes_reuniao')).to have_attributes(nome: 'Lembretes de reunião', gatilho_tipo: 'reuniao_marcada')
    expect(do_sistema('cadencia').limite_dia).to eq(15)
    expect(Fluxo.executaveis).to be_empty
  end

  it 'desenho corrigido no código chega à conta na próxima lista, sem criar outro' do
    described_class.sincronizar(account)
    novo = described_class.desenhos.deep_dup
    novo['cadencia']['nome'] = 'Cadência (corrigida)'
    allow(described_class).to receive(:desenhos).and_return(novo)
    expect { described_class.sincronizar(account) }.not_to(change { account.fluxos.count })
    expect(do_sistema('cadencia').nome).to eq('Cadência (corrigida)')
  end

  it 'nada mudou: não trava a conta' do
    described_class.sincronizar(account)
    allow(account).to receive(:with_lock)
    described_class.sincronizar(account)
    expect(account).not_to have_received(:with_lock)
  end

  describe 'Hoje (fuso SP)' do
    let(:lead) { create(:lead, account: account) }
    let(:ganho) { account.lead_stages.find_by(is_won: true) }

    it 'conta só onde há fonte barata; resumo do dia fica sem número' do
      travel_to(sp('2026-10-06 10:00')) do
        lead.lead_notes.create!(account: account, body: "RASCUNHO (revisar antes de enviar) — retomada nº 1:\noi")
        lead.lead_notes.create!(account: account, body: 'outra nota')
        lead.lead_activities.create!(account: account, kind: 'meeting_scheduled', to_value: 'Reunião')
        AdvboxEvent.create!(account: account, event_key: 'e1', status: 'processed')
        AdvboxEvent.create!(account: account, event_key: 'e2', status: 'ignored')
        create(:lead, account: account, lead_stage: ganho)
        create(:conversation, account: account, inbox: create(:inbox, account: account, auto_create_lead: true))
        chaves = %w[cadencia lembretes_reuniao eventos_advbox lead_ganho sla_primeira_resposta resumo_do_dia]
        expect(chaves.map { |c| described_class.hoje(account, c) }).to eq([1, 1, 1, 1, 1, nil])
      end
    end

    it 'o dia é o de São Paulo' do
      travel_to(sp('2026-10-05 23:30')) { create(:lead, account: account, lead_stage: ganho) }
      travel_to(sp('2026-10-06 09:00')) { expect(described_class.hoje(account, 'lead_ganho')).to eq(0) }
    end
  end
end
```

Notas para conferir à mão (sem Ruby local): a conta nasce com as etapas padrão (`Account` after_create → `Leads::SeedDefaultConfigService`), por isso `find_by(is_won: true)` existe (mesmo padrão de `leads_controller_spec.rb:536`); lead criado direto em etapa de ganho grava `won_at` no `track_stage_cycle` (`lead.rb` `before_save`, `new_record?`); a nota de lead cria uma atividade `note_added` (não conta como reunião); o `RamonLeadListener` é assíncrono (não roda no spec), então a conversa nova não cria lead extra.

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/services/ramon/fluxos/sistema_spec.rb` (no CI — sem Ruby local).
Expected: FAIL — `uninitialized constant Ramon::Fluxos::Sistema`.

- [ ] **Step 3: Write minimal implementation** — `app/services/ramon/fluxos/sistema.rb`:

```ruby
# Fluxos do sistema (spec §8, D7): o desenho só-leitura de cada automação que ainda roda no código.
# Fonte = db/seeds/ramon/fluxos/sistema/<chave>.json ({nome, descricao, limite_dia?, desenho}).
# Cada conta tem 1 Fluxo origem 'sistema' por arquivo (sistema_chave = nome do arquivo), criado ou
# atualizado quando a lista abre. O motor nunca os executa (Fluxo.executaveis e Disparo#iniciar) e a
# API recusa editar, publicar, ensaiar e rodar. Migrar um deles (B4+) = fluxo próprio em modo sombra.
module Ramon::Fluxos::Sistema
  PASTA = Rails.root.join('db/seeds/ramon/fluxos/sistema')
  CAMPOS = %w[nome descricao limite_dia rascunho].freeze
  RETOMADA = 'RASCUNHO (revisar antes de enviar) — retomada%'.freeze # Ramon::FollowUpDraftService#draft_for
  REUNIAO = %w[meeting_scheduled meeting_rescheduled].freeze # Ramon::ReuniaoAgendamento#call / #remarcar

  # "Hoje" da aba Do sistema (spec §7): só onde o código já deixa rastro barato (1 count); sem fonte → nil ("—").
  HOJE = {
    'cadencia' => ->(conta, dia) { conta.lead_notes.where(created_at: dia).where('body LIKE ?', RETOMADA).count },
    'sla_primeira_resposta' => ->(conta, dia) { Ramon::Cadencia.sla_conversations(conta, dia).count },
    'lembretes_reuniao' => ->(conta, dia) { conta.lead_activities.where(kind: REUNIAO, created_at: dia).count },
    'eventos_advbox' => ->(conta, dia) { AdvboxEvent.where(account: conta, status: 'processed', updated_at: dia).count },
    'lead_ganho' => ->(conta, dia) { conta.leads.where(won_at: dia).count }
  }.freeze

  module_function

  def desenhos
    @desenhos ||= PASTA.glob('*.json').sort.to_h { |arquivo| [arquivo.basename('.json').to_s, JSON.parse(arquivo.read)] }
  end

  # Chamado pela lista: nada mudou = 1 SELECT. Criar/atualizar sob o lock da conta: duas abas abertas
  # ao mesmo tempo logo depois do deploy não duplicam. Linha cujo JSON sumiu fica (a B4 decide).
  def sincronizar(account)
    return if em_dia?(account)

    account.with_lock { gravar(account) }
  end

  def hoje(account, chave)
    HOJE[chave]&.call(account, Time.find_zone!(Fluxo::ZONA).now.all_day)
  end

  def em_dia?(account)
    atuais = account.fluxos.where(origem: 'sistema').pluck(:sistema_chave, *CAMPOS).to_h { |chave, *resto| [chave, resto] }
    desenhos.all? { |chave, d| atuais[chave] == atributos(d).values_at(*CAMPOS) }
  end

  def gravar(account)
    existentes = account.fluxos.where(origem: 'sistema').index_by(&:sistema_chave)
    desenhos.each do |chave, d|
      (existentes[chave] || account.fluxos.new(origem: 'sistema', sistema_chave: chave)).update!(atributos(d))
    end
  end

  def atributos(desenho)
    {
      'nome' => desenho['nome'], 'descricao' => desenho['descricao'], 'limite_dia' => desenho['limite_dia'],
      'rascunho' => desenho['desenho'], 'gatilho_tipo' => Ramon::Fluxos::Grafo.new(desenho['desenho']).gatilho&.dig('config', 'tipo')
    }
  end
end
```

Conferência à mão: `pluck` de jsonb devolve Hash com chaves string, igual ao `JSON.parse` (inclusive `"etapa_id": null`), então `em_dia?` compara Hash com Hash (ordem das chaves não importa); `update!` em registro novo cria, e em registro igual não grava nada; o stub do spec troca `desenhos` no próprio módulo (chamadas internas de `module_function` vão para o singleton). Linhas < 150; `em_dia?`/`gravar`/`atributos` bem abaixo de AbcSize 26.

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/services/ramon/fluxos/sistema_spec.rb` + `bundle exec rubocop app/services/ramon/fluxos/sistema.rb spec/services/ramon/fluxos/sistema_spec.rb` (CI).
Expected: PASS, rubocop sem ofensas.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/sistema.rb spec/services/ramon/fluxos/sistema_spec.rb
git commit -m "feat(fluxos): fluxos do sistema por conta, sincronizados dos desenhos" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 3: API e motor — a lista traz os do sistema; o motor nunca os roda

**Files:**
- Modify: `app/services/ramon/fluxos/disparo.rb:61-69` (`#iniciar`)
- Modify: `app/controllers/api/v1/accounts/ramon_fluxos_controller.rb:5` (before_action), `:7-11` (`index`), seção `private` (novo `item`)
- Test: `spec/services/ramon/fluxos/disparo_spec.rb`, `spec/services/ramon/fluxos/relogio_spec.rb`, `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Fluxos::Sistema.sincronizar(account)` e `.hoje(account, chave)` (Task 2).
- Produces: `GET /api/v1/accounts/:id/ramon_fluxos` → `payload` inclui os 6 fluxos do sistema (`origem: 'sistema'`, `sistema_chave`, `descricao`, `ativo: false`, `versao: nil`, `hoje: Integer|nil`, `limite_dia`); `resumo` (ligados/total/hoje/esperando/falharam_24h) conta **só** os não-sistema. `POST …/:id/ensaio` de fluxo do sistema → 403. `Disparo#iniciar` devolve `nil` para fluxo do sistema (vale para `call`, `manual`, `ensaiar` e `Relogio`).

- [ ] **Step 1: Write the failing tests**

Em `spec/services/ramon/fluxos/disparo_spec.rb`, acrescentar depois do exemplo `'modo sombra cria execução de ensaio'`:

```ruby
  it 'fluxo do sistema nunca roda pelo motor, nem ligado e publicado (D7: quem roda é o código)' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota), origem: 'sistema')
    expect(described_class.call('manual', lead)).to eq([])
    expect(described_class.manual(fluxo, lead)).to be_nil
    expect(described_class.ensaiar(fluxo, lead)).to be_nil
    expect(fluxo.execucoes.count).to eq(0)
  end
```

Em `spec/services/ramon/fluxos/relogio_spec.rb`, acrescentar depois de `'relógio perdido no minuto exato dispara quando voltar, no mesmo dia'`:

```ruby
  it 'fluxo do sistema com relógio nunca dispara (o resumo do dia é do código)' do
    create(:lead, account: account, lead_stage: etapa)
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'relogio', 'hora' => '08:00', 'etapa_ids' => [etapa.id] }, nota),
                            origem: 'sistema')
    travel_to(sp('2026-10-06 09:00')) { described_class.disparar_do_dia }
    expect(fluxo.execucoes.count).to eq(0)
    expect(fluxo.reload.ultimo_disparo_em).to be_nil
  end
```

Em `spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`:

(a) no exemplo `'cria, edita o rascunho, publica e lista com contadores'`, a lista agora traz os do sistema primeiro (`order(:origem, :nome)`: `sistema` < `usuario`) — trocar

```ruby
    expect(response.parsed_body['payload'].first).to include('nome' => 'Pós-contrato', 'gatilho_tipo' => 'manual', 'versao' => 1,
                                                             'ativo' => true, 'hoje' => 0)
```

por

```ruby
    meu = response.parsed_body['payload'].find { |f| f['origem'] == 'usuario' }
    expect(meu).to include('nome' => 'Pós-contrato', 'gatilho_tipo' => 'manual', 'versao' => 1, 'ativo' => true, 'hoje' => 0)
```

(b) substituir o exemplo `'fluxo do sistema é só leitura'` inteiro por:

```ruby
  it 'fluxo do sistema é só leitura: não edita, não publica, não roda e não ensaia' do
    fluxo = fluxo_publicado(account, grafo, origem: 'sistema')
    lead = create(:lead, account: account)
    patch "#{url}/#{fluxo.id}", params: { nome: 'Y' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{url}/#{fluxo.id}/publicar", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{url}/#{fluxo.id}/ensaio", params: { lead_id: lead.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{url}/#{fluxo.id}/rodar", params: { lead_id: lead.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(fluxo.execucoes.count).to eq(0)
  end

  it 'a lista traz os 6 do sistema (Hoje do código) e os 4 números contam só os meus' do
    fluxo_publicado(account, grafo)
    get url, headers: admin.create_new_auth_token, as: :json
    sistema = response.parsed_body['payload'].select { |f| f['origem'] == 'sistema' }
    expect(sistema.pluck('sistema_chave')).to match_array(Ramon::Fluxos::Sistema.desenhos.keys)
    expect(sistema.find { |f| f['sistema_chave'] == 'resumo_do_dia' }).to include('hoje' => nil, 'ativo' => false, 'versao' => nil)
    expect(sistema.find { |f| f['sistema_chave'] == 'lead_ganho' }).to include('hoje' => 0)
    expect(response.parsed_body['resumo']).to include('ligados' => 1, 'total' => 1)
  end
```

- [ ] **Step 2: Run to verify they fail**

Run (CI): `bundle exec rspec spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/relogio_spec.rb spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb`
Expected: FAIL — `manual`/`ensaiar` criam execução; ensaio do sistema devolve 200; a lista não traz os do sistema. (O exemplo do relógio já passa hoje — `executaveis` — e fica como trava.)

- [ ] **Step 3: Implementation**

`app/services/ramon/fluxos/disparo.rb` — `#iniciar` ganha a guarda na 1ª linha:

```ruby
  def iniciar
    return if @fluxo.origem == 'sistema' # D7: desenho só-leitura; quem roda é o código de hoje

    execucao = @fluxo.execucoes.create!(atributos)
    return Ramon::Fluxos::Executor.new(execucao).avancar! if @ensaio

    Ramon::FluxoAvancarJob.perform_later(execucao.id)
    execucao
  rescue ActiveRecord::RecordNotUnique
    nil # já existe execução viva desse fluxo nesse alvo
  end
```

`app/controllers/api/v1/accounts/ramon_fluxos_controller.rb`:

```ruby
  before_action :bloquear_sistema, only: [:update, :destroy, :publicar, :rodar, :ensaio]

  def index
    Ramon::Fluxos::Sistema.sincronizar(Current.account)
    payload = Current.account.fluxos.includes(:versao_publicada).order(:origem, :nome).map { |fluxo| item(fluxo) }
    render json: { payload: payload, resumo: resumo(payload.reject { |f| f[:origem] == 'sistema' }) }
  end
```

e, na seção `private`, logo antes de `def resumo(payload)`:

```ruby
  # Do sistema: o "Hoje" vem do rastro do código (Sistema.hoje), não das execuções do motor (que não existem).
  def item(fluxo)
    json = fluxo.resumo_json
    fluxo.origem == 'sistema' ? json.merge(hoje: Ramon::Fluxos::Sistema.hoje(Current.account, fluxo.sistema_chave)) : json
  end
```

(`ensaio` sem o 403 chamaria `Disparo.ensaiar` → `nil.resumo_json`; o 403 vem antes.)

- [ ] **Step 4: Run to verify they pass** — mesmos 3 arquivos + `bundle exec rubocop app/services/ramon/fluxos/disparo.rb app/controllers/api/v1/accounts/ramon_fluxos_controller.rb` (CI). Expected: PASS, sem ofensas (controller vai de 102 para ~110 linhas).

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/fluxos/disparo.rb app/controllers/api/v1/accounts/ramon_fluxos_controller.rb spec/services/ramon/fluxos/disparo_spec.rb spec/services/ramon/fluxos/relogio_spec.rb spec/controllers/api/v1/accounts/ramon_fluxos_controller_spec.rb
git commit -m "feat(fluxos): lista traz os fluxos do sistema e o motor nunca os executa" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 4: Front — aba "Do sistema" na lista + textos + campo `regra`

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue` (arquivo inteiro abaixo)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js` (`CAMPOS` e 1 comentário)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`, `app/javascript/dashboard/i18n/locale/en/ramon.json`
- Test: `app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js` (arquivo inteiro abaixo); a trava `specs/i18n.spec.js` cobre as chaves novas sem mudar (mesmas chaves en/pt na mesma ordem, compilação de produção, `CAMPOS` inteiro)

**Interfaces:**
- Consumes: payload da Task 3 (`origem`, `descricao`, `hoje`, `limite_dia`, `gatilho_tipo`); rota `captain_automacoes_editor` (B2).
- Produces: `Lista.vue` lê `route.query.aba === 'sistema'` (usado pela Task 5); `data-testid` `aba-meus`, `aba-sistema`, `sistema-explica`, `sistema-linha`; chaves i18n `CAPTAIN_RAMON.FLUXOS.ABA_SISTEMA`, `.SISTEMA.EXPLICA`, `.SISTEMA.SEM_CONTADOR`, `.SELO.NO_CODIGO`, `.EDITOR.COMO_RODA` (usada pela Task 5), `.CAMPOS.regra`; `CAMPOS` de `fluxo.js` termina em `'regra'`.

- [ ] **Step 1: Write the failing test** — substituir `specs/Lista.spec.js` inteiro por:

```js
import { mount, flushPromises } from '@vue/test-utils';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import Lista from '../Lista.vue';

const push = vi.fn();
const rota = { query: {} };
vi.mock('vue-router', () => ({
  useRouter: () => ({ push }),
  useRoute: () => rota,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/ramonFluxos', () => ({
  default: { get: vi.fn(), update: vi.fn(), create: vi.fn() },
}));

const FLUXO = {
  id: 1,
  nome: 'Pós-contrato',
  gatilho_tipo: 'lead_mudou_etapa',
  ativo: true,
  limite_dia: 20,
  origem: 'usuario',
  versao: 3,
  editado_em: '2026-10-04T12:00:00Z',
  hoje: 3,
  esperando: 8,
  falharam_24h: 0,
  ultima_em: null,
};
// do sistema (B3): desligado, sem versão; "Hoje" vem do código (null = sem contador)
const SISTEMA = {
  ...FLUXO,
  id: 3,
  nome: 'Cadência de retomada',
  descricao:
    'No código: Ramon::DailyFollowUpJob (todo dia às 11:00)\n\nO desenho não consegue mostrar: o teto de 15 por dia',
  gatilho_tipo: 'lead_parado',
  ativo: false,
  limite_dia: 15,
  origem: 'sistema',
  sistema_chave: 'cadencia',
  versao: null,
  hoje: 2,
  esperando: 0,
};

describe('Lista de automações', () => {
  beforeEach(() => {
    rota.query = {};
    RamonFluxosAPI.get.mockResolvedValue({
      data: {
        payload: [
          FLUXO,
          {
            ...FLUXO,
            id: 2,
            nome: 'Rascunho',
            ativo: false,
            versao: null,
            gatilho_tipo: null,
            falharam_24h: 1,
          },
          SISTEMA,
          {
            ...SISTEMA,
            id: 4,
            nome: 'Resumo do dia',
            sistema_chave: 'resumo_do_dia',
            descricao: 'No código: Ramon::DailyDigestJob',
            gatilho_tipo: 'relogio',
            limite_dia: null,
            hoje: null,
          },
        ],
        resumo: {
          ligados: 1,
          total: 2,
          hoje: 3,
          esperando: 8,
          falharam_24h: 1,
        },
      },
    });
    RamonFluxosAPI.update.mockResolvedValue({ data: {} });
  });

  it('mostra os 4 números e só "Meus fluxos" (sem os do sistema)', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.findAll('[data-testid="fluxo-linha"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="fluxos-resumo"]').text()).toContain('1');
    expect(wrapper.text()).toContain('3 / 20');
    expect(wrapper.text()).toContain('1 failed');
    expect(wrapper.find('[data-testid="sistema-linha"]').exists()).toBe(false);
  });

  it('clicar na linha abre o editor', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper.find('[data-testid="fluxo-linha"]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'captain_automacoes_editor',
      params: { fluxoId: 1 },
    });
  });

  it('a chave liga/desliga sem abrir o editor', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper
      .find('[data-testid="fluxo-linha"] [role="switch"]')
      .trigger('click');
    expect(RamonFluxosAPI.update).toHaveBeenCalledWith(1, { ativo: false });
    expect(push).not.toHaveBeenCalled();
  });

  it('fluxo nunca publicado: chave desabilitada; erro ao ligar avisa e recarrega', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    const [publicado, rascunho] = wrapper.findAll(
      '[data-testid="fluxo-linha"] [role="switch"]'
    );
    expect(rascunho.attributes('disabled')).toBeDefined();
    RamonFluxosAPI.update.mockRejectedValueOnce(new Error('422'));
    RamonFluxosAPI.get.mockClear();
    await publicado.trigger('click');
    await flushPromises();
    expect(RamonFluxosAPI.get).toHaveBeenCalled();
  });

  it('aba Do sistema: explica, só os do sistema, sem chave nem números; "—" sem contador; clicar abre o desenho', async () => {
    const wrapper = mount(Lista);
    await flushPromises();
    await wrapper.find('[data-testid="aba-sistema"]').trigger('click');
    expect(wrapper.find('[data-testid="sistema-explica"]').exists()).toBe(true);
    const linhas = wrapper.findAll('[data-testid="sistema-linha"]');
    expect(linhas).toHaveLength(2);
    expect(linhas[0].text()).toContain(
      'No código: Ramon::DailyFollowUpJob (todo dia às 11:00)'
    );
    expect(linhas[0].text()).not.toContain('O desenho não consegue');
    expect(linhas[0].text()).toContain('2 / 15');
    expect(linhas[1].text()).toContain('—');
    expect(wrapper.find('[role="switch"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="fluxos-resumo"]').exists()).toBe(false);
    await linhas[0].trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'captain_automacoes_editor',
      params: { fluxoId: 3 },
    });
  });

  it('?aba=sistema (volta do desenho do sistema) abre direto na aba Do sistema', async () => {
    rota.query = { aba: 'sistema' };
    const wrapper = mount(Lista);
    await flushPromises();
    expect(wrapper.findAll('[data-testid="sistema-linha"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="fluxo-linha"]').exists()).toBe(false);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js --config vitest.local.config.ts`
Expected: FAIL — os 2 testes novos (não há `aba-sistema`).

- [ ] **Step 3: Implementation**

(a) `Lista.vue` — substituir o arquivo inteiro por:

```vue
<script setup>
// Automações (mockup tela 1). Aba "Meus fluxos": 4 números, a lista com
// liga/desliga e o que rodou hoje. Aba "Do sistema" (B3, spec §7/§8): o
// desenho só-leitura do que ainda roda no código — sem chave liga/desliga e
// "Hoje" só onde o código tem contador barato (senão "—").
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import {
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
  AVISO,
  CHIP,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { gatilhoInfo } from './fluxo';
import NovoFluxo from './NovoFluxo.vue';

defineOptions({ name: 'CaptainAutomacoes' });

const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const fluxos = ref([]);
const resumo = ref({});
const erro = ref(false);
const novo = ref(false);
const criando = ref(false);
// ?aba=sistema: o "Voltar" do desenho do sistema cai de novo nesta aba
const aba = ref(route.query.aba === 'sistema' ? 'sistema' : 'meus');
const meus = computed(() => fluxos.value.filter(f => f.origem !== 'sistema'));
const doSistema = computed(() =>
  fluxos.value.filter(f => f.origem === 'sistema')
);

const carregar = async () => {
  erro.value = false;
  try {
    const { data } = await RamonFluxosAPI.get();
    fluxos.value = data.payload;
    resumo.value = data.resumo;
  } catch (e) {
    erro.value = true;
  }
};
onMounted(carregar);

const abrir = id =>
  router.push(accountScopedRoute('captain_automacoes_editor', { fluxoId: id }));

const ligar = async (fluxo, ativo) => {
  try {
    await RamonFluxosAPI.update(fluxo.id, { ativo });
  } catch (e) {
    useAlert(t(`${K}.EDITOR.ERRO_SALVAR`));
  } finally {
    carregar();
  }
};

// clique duplo no modelo não cria dois fluxos
const criar = async modelo => {
  if (criando.value) return;
  criando.value = true;
  try {
    const { data } = await RamonFluxosAPI.create({
      nome: t(`${K}.MODELOS.${modelo.chave}.NOME`),
      limite_dia: modelo.limite_dia ?? null,
      rascunho: modelo.desenho,
    });
    abrir(data.id);
  } catch (e) {
    useAlert(t(`${K}.ERRO_CRIAR`));
  } finally {
    criando.value = false;
  }
};

const TRACO = '—';
const selo = f => {
  if (f.falharam_24h)
    return {
      classe: TOM.ruby,
      icone: 'i-lucide-triangle-alert',
      texto: t(`${K}.SELO.FALHOU`, { n: f.falharam_24h }),
    };
  if (!f.ativo)
    return { classe: TOM.slate, icone: '', texto: t(`${K}.SELO.DESLIGADO`) };
  return { classe: TOM.teal, icone: '', texto: t(`${K}.SELO.OK`) };
};
const subtitulo = f =>
  f.versao
    ? t(`${K}.VERSAO_EDITADO`, {
        versao: f.versao,
        data: new Date(f.editado_em).toLocaleDateString('pt-BR'),
      })
    : t(`${K}.NUNCA_PUBLICADO`);
const hojeLimite = f => `${f.hoje} / ${f.limite_dia ?? TRACO}`;
const largura = f =>
  `${Math.min(100, Math.round((f.hoje / f.limite_dia) * 100))}%`;
const ultima = iso =>
  iso ? dynamicTime(Math.floor(new Date(iso).getTime() / 1000)) : TRACO;
const gatilho = tipo => (tipo ? t(`${K}.GATILHOS.${tipo}`) : TRACO);
// do sistema: sem contador barato o back manda hoje = null
const hojeSistema = f => {
  if (f.hoje == null) return TRACO;
  return f.limite_dia ? `${f.hoje} / ${f.limite_dia}` : String(f.hoje);
};
// 1ª linha da descrição = onde vive no código (o resto aparece no desenho)
const ondeVive = f => (f.descricao || '').split('\n')[0];
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <div
      class="flex h-14 shrink-0 items-center gap-2.5 border-b border-n-weak px-7"
    >
      <h1 class="text-[15px] font-semibold text-n-slate-12">
        {{ t(`${K}.TITULO`) }}
      </h1>
      <span class="hidden text-[13px] text-n-slate-10 md:inline">
        {{ t(`${K}.DICA`) }}
      </span>
      <Button
        class="ml-auto"
        sm
        icon="i-lucide-plus"
        :label="t(`${K}.NOVO`)"
        @click="novo = true"
      />
    </div>
    <div class="flex gap-1 border-b border-n-weak px-7 pt-3">
      <button
        type="button"
        data-testid="aba-meus"
        :class="[ABA, aba === 'meus' ? ABA_ATIVA : ABA_INATIVA]"
        @click="aba = 'meus'"
      >
        {{ t(`${K}.ABA_MEUS`) }}
        <span class="font-mono text-[11.5px] text-n-slate-10">
          {{ meus.length }}
        </span>
      </button>
      <button
        type="button"
        data-testid="aba-sistema"
        :class="[ABA, aba === 'sistema' ? ABA_ATIVA : ABA_INATIVA]"
        @click="aba = 'sistema'"
      >
        {{ t(`${K}.ABA_SISTEMA`) }}
        <span class="font-mono text-[11.5px] text-n-slate-10">
          {{ doSistema.length }}
        </span>
      </button>
    </div>

    <div class="flex-1 overflow-y-auto px-7 pb-12 pt-5">
      <div v-if="erro" class="text-sm text-n-ruby-11">
        {{ t('CAPTAIN_RAMON.LOAD_ERROR') }}
        <button
          type="button"
          class="ml-1 text-n-blue-11 hover:underline"
          @click="carregar"
        >
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>

      <template v-else-if="aba === 'meus'">
        <div
          data-testid="fluxos-resumo"
          class="mb-5 grid max-w-[1100px] grid-cols-2 gap-3 md:grid-cols-4"
        >
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.LIGADOS`) }}
            </span>
            <b class="font-mono text-xl font-medium text-n-slate-12">
              {{ resumo.ligados ?? 0 }}
              <small class="text-xs font-normal text-n-slate-10">
                {{ t(`${K}.RESUMO.DE`, { total: meus.length }) }}
              </small>
            </b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.HOJE`) }}
            </span>
            <b class="font-mono text-xl font-medium text-n-slate-12">
              {{ resumo.hoje ?? 0 }}
            </b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.ESPERANDO`) }}
            </span>
            <b class="font-mono text-xl font-medium text-n-slate-12">
              {{ resumo.esperando ?? 0 }}
            </b>
          </div>
          <div class="rounded-xl border border-n-weak px-3.5 py-3">
            <span class="block text-xs text-n-slate-10">
              {{ t(`${K}.RESUMO.FALHARAM`) }}
            </span>
            <b
              class="font-mono text-xl font-medium"
              :class="
                resumo.falharam_24h ? 'text-n-ruby-11' : 'text-n-slate-12'
              "
            >
              {{ resumo.falharam_24h ?? 0 }}
            </b>
          </div>
        </div>

        <p v-if="!meus.length" class="text-sm text-n-slate-10">
          {{ t(`${K}.VAZIO`) }}
        </p>

        <table v-else class="w-full max-w-[1100px] border-collapse">
          <thead>
            <tr
              class="border-b border-n-weak text-left text-xs font-medium text-n-slate-10"
            >
              <th class="w-11 p-2" />
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.FLUXO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.GATILHO`) }}</th>
              <th class="p-2 font-medium">
                {{ t(`${K}.TABELA.HOJE_LIMITE`) }}
              </th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.ESPERANDO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.ULTIMA`) }}</th>
              <th class="p-2" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="f in meus"
              :key="f.id"
              data-testid="fluxo-linha"
              class="cursor-pointer border-b border-n-weak text-[13.5px] hover:bg-n-alpha-2"
              @click="abrir(f.id)"
            >
              <td class="p-2" @click.stop>
                <span
                  :title="f.versao ? '' : t(`${K}.PUBLIQUE_ANTES`)"
                  :class="f.versao ? '' : 'opacity-50'"
                >
                  <Switch
                    :disabled="!f.versao"
                    :model-value="f.ativo"
                    @update:model-value="v => ligar(f, v)"
                  />
                </span>
              </td>
              <td class="p-2">
                <b class="block font-medium text-n-slate-12">{{ f.nome }}</b>
                <span class="text-[12.5px] text-n-slate-11">
                  {{ subtitulo(f) }}
                </span>
              </td>
              <td class="p-2">
                <span
                  class="inline-flex items-center gap-1.5 text-[12.5px] text-n-slate-11"
                >
                  <i
                    v-if="f.gatilho_tipo"
                    :class="gatilhoInfo(f.gatilho_tipo)?.icone"
                    class="size-3.5 text-n-blue-11"
                  />
                  {{ gatilho(f.gatilho_tipo) }}
                </span>
              </td>
              <td class="p-2 font-mono text-[12.5px]">
                {{ hojeLimite(f) }}
                <span
                  v-if="f.limite_dia"
                  class="ml-1.5 inline-block h-[5px] w-14 overflow-hidden rounded-full bg-n-alpha-2 align-middle"
                >
                  <i
                    class="block h-full bg-n-blue-9"
                    :style="{ width: largura(f) }"
                  />
                </span>
              </td>
              <td class="p-2 font-mono text-[12.5px]">{{ f.esperando }}</td>
              <td class="p-2 font-mono text-[12.5px]">
                {{ ultima(f.ultima_em) }}
              </td>
              <td class="p-2">
                <span :class="[CHIP, selo(f).classe]" class="font-mono">
                  <i
                    v-if="selo(f).icone"
                    :class="selo(f).icone"
                    class="size-3"
                  />
                  {{ selo(f).texto }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </template>

      <template v-else>
        <p
          data-testid="sistema-explica"
          :class="[AVISO, TOM.blue]"
          class="mb-5 max-w-[1100px] leading-relaxed"
        >
          {{ t(`${K}.SISTEMA.EXPLICA`) }}
        </p>
        <table class="w-full max-w-[1100px] border-collapse">
          <thead>
            <tr
              class="border-b border-n-weak text-left text-xs font-medium text-n-slate-10"
            >
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.FLUXO`) }}</th>
              <th class="p-2 font-medium">{{ t(`${K}.TABELA.GATILHO`) }}</th>
              <th class="p-2 font-medium">
                {{ t(`${K}.TABELA.HOJE_LIMITE`) }}
              </th>
              <th class="p-2" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="f in doSistema"
              :key="f.id"
              data-testid="sistema-linha"
              class="cursor-pointer border-b border-n-weak text-[13.5px] hover:bg-n-alpha-2"
              @click="abrir(f.id)"
            >
              <td class="p-2">
                <b class="block font-medium text-n-slate-12">{{ f.nome }}</b>
                <span class="text-[12.5px] text-n-slate-11">
                  {{ ondeVive(f) }}
                </span>
              </td>
              <td class="p-2">
                <span
                  class="inline-flex items-center gap-1.5 text-[12.5px] text-n-slate-11"
                >
                  <i
                    v-if="f.gatilho_tipo"
                    :class="gatilhoInfo(f.gatilho_tipo)?.icone"
                    class="size-3.5 text-n-blue-11"
                  />
                  {{ gatilho(f.gatilho_tipo) }}
                </span>
              </td>
              <td
                class="p-2 font-mono text-[12.5px]"
                :title="f.hoje == null ? t(`${K}.SISTEMA.SEM_CONTADOR`) : ''"
              >
                {{ hojeSistema(f) }}
              </td>
              <td class="p-2">
                <span :class="[CHIP, TOM.blue]" class="font-mono">
                  {{ t(`${K}.SELO.NO_CODIGO`) }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <NovoFluxo
      v-if="novo"
      :ocupado="criando"
      @criar="criar"
      @fechar="novo = false"
    />
  </section>
</template>
```

(b) `fluxo.js` — em `CAMPOS`, acrescentar `'regra'` depois de `'documentos_completos'` (o `escolha` do desenho do ADVBOX olha esse campo; vale também para fluxos do usuário com gatilho `evento_advbox`):

```js
  'documentos_completos',
  'regra',
];
export const OPERADORES = [
```

e trocar o comentário acima de `CHATWOOT_PERMITIDAS`:

```js
// = Grafo.permitidas_chatwoot (inclui as que vêm de regras convertidas na B3)
```

por

```js
// = Grafo.permitidas_chatwoot (o que a regra nativa aceita, menos as proibidas)
```

(c) `pt_BR/ramon.json` — 5 inserções com Edit (dentro de `CAPTAIN_RAMON.FLUXOS`):

- depois de `      "ABA_MEUS": "Meus fluxos",` → `      "ABA_SISTEMA": "Do sistema",`
- depois de `      "ERRO_CRIAR": "Não consegui criar o fluxo.",` →

```json
      "SISTEMA": {
        "EXPLICA": "Estas automações rodam hoje pelo código do hub, não pelo quadro. Aqui você vê o desenho de cada uma, só para leitura, para conferir o que o hub faz sozinho. Elas vão virar fluxos editáveis uma a uma: primeiro rodam lado a lado em modo ensaio, comparamos com o código e, se baterem, o fluxo assume.",
        "SEM_CONTADOR": "Sem contador barato para hoje"
      },
```

- em `SELO`: `"DESLIGADO": "desligado"` → `"DESLIGADO": "desligado",` + nova linha `        "NO_CODIGO": "roda no código"`
- em `EDITOR`: `"SELECIONE": "Clique num passo para configurar."` → com vírgula + nova linha `        "COMO_RODA": "Como roda hoje"`
- em `CAMPOS`: `"documentos_completos": "Documentos completos (sim ou não)"` → com vírgula + nova linha `        "regra": "Regra do ADVBOX (evento)"`

(d) `en/ramon.json` — as mesmas 5 inserções, nas mesmas posições:

- depois de `      "ABA_MEUS": "My flows",` → `      "ABA_SISTEMA": "Built-in",`
- depois de `      "ERRO_CRIAR": "Could not create the flow.",` →

```json
      "SISTEMA": {
        "EXPLICA": "These automations run today in the hub code, not on the board. Here you see each one drawn, read-only, so you can check what the hub does on its own. They will become editable flows one by one: first they run side by side as a dry run, we compare them with the code and, if they match, the flow takes over.",
        "SEM_CONTADOR": "No cheap counter for today"
      },
```

- em `SELO`: `"DESLIGADO": "off"` → com vírgula + `        "NO_CODIGO": "runs in code"`
- em `EDITOR`: `"SELECIONE": "Click a step to configure it."` → com vírgula + `        "COMO_RODA": "How it runs today"`
- em `CAMPOS`: `"documentos_completos": "Documents complete (yes or no)"` → com vírgula + `        "regra": "ADVBOX rule (event)"`

- [ ] **Step 4: Run to verify it passes**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts`
Expected: PASS — 12 arquivos, 101 testes (86 da base + 13 da Task 1 + 2 novos da Lista), inclusive `i18n.spec.js`.
Depois: `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js` → sem `error` (só os warnings `no-dynamic-keys` de sempre).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Lista.vue app/javascript/dashboard/routes/dashboard/captain/automacoes/fluxo.js app/javascript/dashboard/routes/dashboard/captain/automacoes/specs/Lista.spec.js app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json
git commit -m "feat(fluxos): aba Do sistema na lista de automações" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 5: Front — o desenho do sistema mostra "Como roda hoje"

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue` (3 trechos do template; o `<script>` não muda)

**Interfaces:**
- Consumes: `somenteLeitura` (já existe, `Editor.vue:113`), `fluxo.descricao` (payload do `show`, `Fluxo#resumo_json`), chave `CAPTAIN_RAMON.FLUXOS.EDITOR.COMO_RODA` (Task 4), `?aba=sistema` lido pela `Lista.vue` (Task 4).
- Produces: `data-testid="sistema-descricao"` no painel direito do desenho do sistema (usado pelos prints da Task 7).

- [ ] **Step 1: Voltar cai na aba certa** — trocar

```vue
      <router-link
        :to="accountScopedRoute('captain_automacoes_index')"
```

por

```vue
      <router-link
        :to="
          accountScopedRoute(
            'captain_automacoes_index',
            {},
            somenteLeitura ? { aba: 'sistema' } : {}
          )
        "
```

- [ ] **Step 2: Sem "Versões" no desenho do sistema** (nunca há versão) — trocar

```vue
          <div ref="versoesRef" class="relative">
```

por

```vue
          <div v-if="!somenteLeitura" ref="versoesRef" class="relative">
```

- [ ] **Step 3: Painel "Como roda hoje"** — no `<aside>`, entre o `<PainelPasso … />` e `<div v-else class="flex min-h-0 flex-1 flex-col px-4 py-3.5">`, inserir:

```vue
        <div
          v-else-if="somenteLeitura"
          data-testid="sistema-descricao"
          class="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 py-3.5"
        >
          <h4
            class="mb-2 text-[11px] font-medium uppercase tracking-wider text-n-slate-10"
          >
            {{ t(`${K}.EDITOR.COMO_RODA`) }}
          </h4>
          <p
            class="whitespace-pre-line text-[13px] leading-relaxed text-n-slate-11"
          >
            {{ fluxo.descricao }}
          </p>
        </div>
```

(o fluxo do sistema não seleciona passo — `@selecionar` já põe `null` quando `somenteLeitura` —, então este bloco sempre aparece no lugar de "Clique num passo" + execuções vazias; enquanto `fluxo` é `null`, `somenteLeitura` é `false` e o bloco não monta.)

- [ ] **Step 4: Run** — `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue` → sem `error`; `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs --config vitest.local.config.ts` → 12 arquivos / 101 testes verdes (o Editor não tem spec próprio — a prova visual é o print da Task 7).

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Editor.vue
git commit -m "feat(fluxos): desenho do sistema mostra como roda hoje e volta para a aba" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 6: "Configurações → Automação" sai do menu e a rota antiga redireciona

**Files:**
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:807-812` (item `'Settings Automation'`)
- Modify: `app/javascript/dashboard/routes/dashboard/settings/automation/automation.routes.js` (arquivo inteiro)
- Test: `app/javascript/dashboard/routes/dashboard/settings/automation/specs/automation.routes.spec.js` (novo)

**Interfaces:**
- Consumes: rota `captain_automacoes_index` (`captain.routes.js:147-152`, `metaAdmin`).
- Produces: `/app/accounts/:accountId/settings/automation` e `…/settings/automation/list` → `{ name: 'captain_automacoes_index', params: { accountId } }`. A rota nomeada `automation_list` deixa de existir (o único uso era o `Sidebar.vue:811`). `Index.vue`, `AutomationRuleForm.vue` etc. ficam no código, sem rota (merge com o upstream).

- [ ] **Step 1: Write the failing test** — `app/javascript/dashboard/routes/dashboard/settings/automation/specs/automation.routes.spec.js`:

```js
import automation from '../automation.routes';

describe('Configurações → Automação (FORK ramon)', () => {
  it('o link antigo cai em Inteligência → Automações', () => {
    expect(automation.routes.map(r => r.path)).toEqual([
      '/app/accounts/:accountId/settings/automation',
      '/app/accounts/:accountId/settings/automation/list',
    ]);
    automation.routes.forEach(r =>
      expect(r.redirect({ params: { accountId: '7' } })).toEqual({
        name: 'captain_automacoes_index',
        params: { accountId: '7' },
      })
    );
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/settings/automation/specs --config vitest.local.config.ts`
Expected: FAIL — hoje há 1 rota com `children` e sem `redirect` de topo.

- [ ] **Step 3: Implementation**

`automation.routes.js` — substituir o arquivo inteiro por:

```js
import { frontendURL } from '../../../../helper/URLHelper';

// FORK(ramon): a Automação nativa saiu de Configurações (B3 das Automações em
// fluxo, decisão do Eduardo 06/10). O motor nativo segue no código, sem tela; o
// link antigo cai em Inteligência → Automações. Index.vue e o formulário ficam
// no código (sem rota) para o merge com o upstream.
const paraAutomacoes = to => ({
  name: 'captain_automacoes_index',
  params: { accountId: to.params.accountId },
});

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/automation'),
      redirect: paraAutomacoes,
    },
    {
      path: frontendURL('accounts/:accountId/settings/automation/list'),
      redirect: paraAutomacoes,
    },
  ],
};
```

`Sidebar.vue` — trocar o item

```js
        {
          name: 'Settings Automation',
          label: t('SIDEBAR.AUTOMATION'),
          icon: 'i-lucide-repeat',
          to: accountScopedRoute('automation_list'),
        },
```

por

```js
        // FORK(ramon): a "Automação" nativa saiu daqui — as automações vivem em
        // Inteligência → Automações (fluxos, fatia B3); o link antigo redireciona.
```

(`SIDEBAR.AUTOMATION` fica no `settings.json` — arquivo do upstream, sem uso não quebra nada.)

- [ ] **Step 4: Run to verify it passes**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/settings/automation/specs --config vitest.local.config.ts` → PASS (1 teste).
`./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/settings/automation app/javascript/dashboard/components-next/sidebar/Sidebar.vue` → sem `error`.
`grep -rn "automation_list" app/javascript` → vazio.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/components-next/sidebar/Sidebar.vue app/javascript/dashboard/routes/dashboard/settings/automation/automation.routes.js app/javascript/dashboard/routes/dashboard/settings/automation/specs/automation.routes.spec.js
git commit -m "feat(configuracoes): Automação nativa sai do menu e cai em Inteligência → Automações" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 7: Story — aba "Do sistema" e um desenho do sistema aberto (para os prints)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue`

**Interfaces:**
- Consumes: os JSON da Task 1 (via `import.meta.glob`, 7 níveis acima da pasta `automacoes/` = raiz do repo); `Lista.vue` (`?aba=sistema`, Task 4); `Editor.vue` (painel "Como roda hoje", Task 5).
- Produces: variantes `DoSistema` (lista na aba Do sistema) e `SistemaLembretes` (desenho `lembretes_reuniao` aberto, só leitura). **Quem tira os prints é o controlador** (o harness Vite + Chrome headless vive no `tmp/` não versionado de outro worktree); esta task só acrescenta as variantes.

- [ ] **Step 1: Dados do sistema** — logo depois do fechamento de `const FLUXO = { … };` e antes de `const API = {`, inserir:

```js
// B3: a aba "Do sistema" e o desenho aberto vêm dos JSON de verdade
// (db/seeds/ramon/fluxos/sistema); "Hoje" FICTÍCIO, resumo do dia sem contador.
const DESENHOS_SISTEMA = import.meta.glob(
  '../../../../../../../db/seeds/ramon/fluxos/sistema/*.json',
  { eager: true, import: 'default' }
);
const HOJE_SISTEMA = {
  cadencia: 6,
  sla_primeira_resposta: 9,
  lembretes_reuniao: 2,
  eventos_advbox: 4,
  lead_ganho: 1,
};
const SISTEMA = Object.entries(DESENHOS_SISTEMA).map(([arquivo, d], i) => {
  const chave = arquivo.split('/').pop().replace('.json', '');
  return {
    ...FLUXO,
    id: 101 + i,
    nome: d.nome,
    descricao: d.descricao,
    gatilho_tipo: d.desenho.nos.find(n => n.tipo === 'gatilho').config.tipo,
    ativo: false,
    limite_dia: d.limite_dia ?? null,
    origem: 'sistema',
    sistema_chave: chave,
    versao: null,
    hoje: HOJE_SISTEMA[chave] ?? null,
    esperando: 0,
    falharam_24h: 0,
    ultima_em: null,
    rascunho: d.desenho,
    versoes: [],
  };
});
```

- [ ] **Step 2: API fictícia responde por eles** — no `API`, (a) no fim do array `ramon_fluxos.payload`, depois do item `id: 4` ("Rodar na mão: pedir documentos"), acrescentar `...SISTEMA,`; (b) logo depois de `'ramon_fluxos/1': FLUXO,` acrescentar:

```js
  ...Object.fromEntries(SISTEMA.map(f => [`ramon_fluxos/${f.id}`, f])),
```

(`ramon_fluxos/<id>/execucoes` cai no `{ payload: [] }` padrão do `responder`.)

- [ ] **Step 3: Variantes** — no fim do `<script setup>`, depois de `const paletaAoFim = …;`:

```js
// B3: a lista abre na aba "Do sistema" (como na volta do desenho do sistema)
const abaSistema = () => {
  rota.query = { aba: 'sistema' };
};
// B3: o editor abre um desenho do sistema (só leitura + "Como roda hoje")
const abreSistema = chave => () => {
  rota.params.fluxoId = String(SISTEMA.find(f => f.sistema_chave === chave).id);
};
```

e no template, antes de `<Variant title="Execucao">`:

```vue
    <Variant title="DoSistema" :init-state="abaSistema">
      <div class="h-screen"><Lista /></div>
    </Variant>
    <Variant
      title="SistemaLembretes"
      :init-state="abreSistema('lembretes_reuniao')"
    >
      <div class="h-screen"><Editor /></div>
    </Variant>
```

- [ ] **Step 4: Run** — `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue` → sem `error`. Checklist para o controlador conferir nos prints (claro e escuro): aba "Do sistema 6" ativa em azul; aviso azul translúcido com a explicação; 6 linhas (nome + "No código: …"), gatilho com ícone azul, "Hoje" `6 / 15` na cadência e `—` no resumo do dia, selo azul "roda no código", nenhuma chave liga/desliga; no `SistemaLembretes`, 11 passos de cima para baixo, selo "Fluxo do sistema · só leitura", sem Testar/Publicar/Versões/Excluir, painel direito "Como roda hoje" com a descrição em parágrafos.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/automacoes/Automacoes.story.vue
git commit -m "test(fluxos): story da aba Do sistema para os prints de aprovação" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

---

### Task 8: Verificação final + notas na spec (§14 Notas da B3) + texto do PR

**Files:**
- Modify: `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` (acrescentar §14 no fim)

- [ ] **Step 1: Front inteiro**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/automacoes/specs app/javascript/dashboard/routes/dashboard/settings/automation/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/automacoes app/javascript/dashboard/routes/dashboard/settings/automation app/javascript/dashboard/components-next/sidebar/Sidebar.vue
```
Expected: 13 arquivos / 102 testes verdes; eslint sem `error`. `git status --short` não pode listar `vitest.local.config.ts`.

- [ ] **Step 2: Varredura de regras**

```bash
git diff 9cdd5c6 --stat -- app/models/lead.rb app/services/ramon/advbox_event_processor.rb app/finders/conversation_finder.rb enterprise db/migrate db/schema.rb
grep -rn "automation_list" app/javascript
grep -rn "converter_regras" lib app
```
Expected: os três vazios.

- [ ] **Step 3: Notas da B3 na spec** — acrescentar ao fim de `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md`:

```markdown
## 14. Notas da B3 (06/10/2026)

- **Conversor das regras nativas descartado** (decisão do Eduardo, 06/10): produção tem 0 `AutomationRule`, então o rake `ramon:fluxos:converter_regras` do §8 não existe e não há `origem: convertido` em uso. "Configurações → Automação" saiu do menu e o link antigo (`/settings/automation`, `/settings/automation/list`) cai em Inteligência → Automações; o motor nativo do Chatwoot segue no código, sem tela (o `AutomationRules::ActionService` continua servindo o passo `acao_chatwoot`).
- **Fluxos do sistema**: 6 JSON em `db/seeds/ramon/fluxos/sistema/<chave>.json` (`{nome, descricao, limite_dia?, desenho}`); `Ramon::Fluxos::Sistema.sincronizar` cria/atualiza 1 `Fluxo` `origem: sistema` por conta quando a lista abre (sob lock da conta; nada mudou = 1 SELECT). Nunca rodam: `Fluxo.executaveis` exclui a origem, `Disparo#iniciar` recusa (evento, relógio, manual e ensaio) e a API devolve 403 em editar/publicar/ensaiar/rodar.
- A 1ª linha da `descricao` diz onde a automação vive no código; o resto lista o que o desenho não expressa (esperas para trás, rascunho nas notas do lead, ações em paralelo, envs que ligam/desligam). `mover_etapa` dos desenhos vem sem `etapa_id` (a etapa é do funil de cada conta) — a B4 escolhe ao migrar. Os 5 lembretes de reunião aparecem como um ciclo só.
- "Hoje" na aba Do sistema: cadência = retomadas preparadas; SLA = conversas novas em caixa de lead; lembretes = reuniões marcadas/remarcadas; ADVBOX = eventos processados; lead ganho = ganhos do dia (fuso SP); resumo do dia = "—".
- **B4**: o fluxo em sombra é um fluxo próprio (origem `usuario`), porque o motor recusa `origem: sistema`; quando assumir, apagar o JSON **e** a linha do sistema (a sincronização não apaga linha cujo JSON sumiu).
```

- [ ] **Step 4: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Automações em fluxo — B3: Inteligência → Automações ganha a aba "Do sistema", com as 6 automações que hoje rodam no código do hub (cadência de retomada, SLA da 1ª resposta, lembretes de reunião, eventos do ADVBOX, lead ganho e resumo do dia) desenhadas como fluxos só para leitura: dá para abrir cada uma, ver o caminho e ler, ao lado, onde ela vive no código e o que o desenho ainda não consegue mostrar. Nada disso roda pelo motor — continua tudo pelo código, e cada uma vai virar fluxo editável depois (B4, uma a uma, em modo ensaio). "Configurações → Automação" saiu do menu: quem tiver o link antigo cai em Automações.

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §7 (abas da lista), §8 (fluxos do sistema) e §10 (fatia B3); o conversor das regras nativas foi descartado (0 regras em produção) — ver §14.

## How to test
1. Inteligência → Automações → aba "Do sistema": 6 linhas com "No código: …", "Hoje" (resumo do dia mostra "—") e o selo "roda no código"; nenhuma chave liga/desliga; os 4 números de "Meus fluxos" não mudam.
2. Abra "Lembretes de reunião": quadro só leitura, sem Testar/Publicar/Versões/Excluir, e o painel "Como roda hoje" à direita. "Voltar" volta para a aba "Do sistema".
3. Configurações: o item "Automação" sumiu. Abra `/app/accounts/<id>/settings/automation/list`: cai em Automações.

## What changed
- `Ramon::Fluxos::Sistema` (novo) + 6 desenhos em `db/seeds/ramon/fluxos/sistema/*.json`; `GET ramon_fluxos` sincroniza os do sistema e dá o "Hoje" de cada um; o resumo conta só os seus fluxos.
- `Disparo#iniciar` recusa fluxo do sistema; `POST …/ensaio` de fluxo do sistema → 403.
- Front: abas na lista (`?aba=sistema`), painel "Como roda hoje" no desenho, campo "Regra do ADVBOX" nas condições/escolha; item "Automação" fora de Configurações e rota antiga redirecionando.
- Sem migração, sem env nova.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv
```

- [ ] **Step 5: Smoke em bloco (para o Eduardo, depois do deploy)** — anotar no relatório: (1) abrir a lista uma vez (cria os 6 na conta) e conferir a aba Do sistema; (2) abrir os 6 desenhos e ler o "Como roda hoje" de cada um — é aqui que o Eduardo aprova se o desenho bate com o que ele sabe da operação; (3) Configurações sem "Automação" + link antigo; (4) conferir que "Meus fluxos" e seus números não mudaram.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md
git commit -m "docs(fluxos): notas da B3 na spec" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Rmo1LYQby9qHNStGHn6AYv"
```

Sem push.

---

## Divergências registradas (spec × este plano)

| # | Onde | Divergência | Motivo |
|---|---|---|---|
| 1 | Spec §8 / §2 D6 | Sem rake `ramon:fluxos:converter_regras`, sem `origem: convertido` | Decisão do Eduardo 06/10: 0 `AutomationRule` em produção |
| 2 | Spec §8 | Desenhos do sistema = JSON em `db/seeds` **sincronizados em linhas por conta** (não lidos direto pela tela) | Editor, policy, `show` e `executaveis` já funcionam por linha; a B4 precisa da `sistema_chave` numa linha |
| 3 | Spec §7 | Aba Do sistema sem chave liga/desliga, sem "Esperando"/"Última"; 4 números só na aba Meus fluxos | Nada disso existe para o que roda no código; os números são do motor |
| 4 | Spec §8 | Lembretes de reunião = 1 ciclo com rótulo "24h · 8h · 1h · 30 min · 5 min" (não 5 ciclos) | Legibilidade; a espera dos fluxos só conta para a frente — a B4 precisa de "esperar até X antes de {quando}" de qualquer jeito (E5) |
| 5 | Spec §8 | `mover_etapa` sem `etapa_id` nos desenhos (único erro de validação aceito) | A etapa é do funil de cada conta |
| 6 | Spec §6 | `ensaio` também recusado para fluxo do sistema (a spec só falava do disparo) | "Nunca executados pelo motor" — ensaio também cria execução |
| 7 | Spec §7 | "Rodar fluxo…" no menu ⋯ do lead/conversa continua fora | Não estava no escopo da B3 decidido em 06/10 (era B2→B2b e não entrou) — E8 |

## Decisões que dependem do Eduardo (o plano já segue a recomendação; mudar = trocar 1 constante/linha/arquivo)

| # | Decisão | Recomendação no plano |
|---|---|---|
| E1 | Conversor das regras nativas | Descartado (0 regras em produção); se um dia alguém criar regra nativa pela API, ela roda sem tela |
| E2 | "Configurações → Automação" | Sai do menu; link antigo → Inteligência → Automações; telas antigas ficam no código sem rota (Task 6) |
| E3 | Onde vivem os desenhos do sistema | JSON em `db/seeds` + 1 linha por conta sincronizada ao abrir a lista (Task 2) |
| E4 | Quais automações aparecem | Só as 6 da spec; ficam de fora copiloto noturno, contrato limpo, avisos e espelho do Painel do Cliente, publicação de peças, sugestão de documento, coach de objeção, sync etapa↔etiqueta, retrato do funil e fechamento do extrato — acrescentar = 1 JSON + 1 linha em `HOJE` |
| E5 | Lembretes de reunião desenhados como 1 ciclo com rótulo (não 5 ciclos) | Sim (Task 1) |
| E6 | O que é "Hoje" no sistema | Quantas vezes disparou hoje: retomadas preparadas, conversas novas em caixa de lead, reuniões marcadas/remarcadas, eventos do ADVBOX processados, leads ganhos; resumo do dia "—" (Task 2) |
| E7 | Ensaio de fluxo do sistema | Bloqueado (403 + guarda no motor); a B4 ensaia pela cópia em sombra (Task 3) |
| E8 | "Rodar fluxo…" no menu do lead/conversa (spec §7) | Fora da B3; fatia própria depois |

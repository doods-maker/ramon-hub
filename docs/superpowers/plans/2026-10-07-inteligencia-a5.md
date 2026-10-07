# Inteligência A5 — itens restantes da lista — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fechar a lista de 67 itens da área Inteligência: o que faltou depois de A1–A4, #213, #214 e #215 — seletor de assistente só onde faz sentido, kit visual nas telas que faltavam, nomes certos dos assistentes, "Testar esta skill", uso das skills em 30 dias, skills por papel, ferramentas usadas debaixo de cada resposta do Testar, conversa do Testar guardada, "testar com o caso…", textos das Caixas, período e "carregar mais" nas Execuções, Vigia com conversa e cor por gravidade, Configurações por público com zona de risco e texto final, FAQs sempre do Atendimento com "usada N×", aviso do link em Documentos, `CONTEXT.md` certo, **Memória do contato ligável**, **caderno de provas automático** e "o que a IA fez neste caso" no painel do lead.

**Architecture:** Backend pequeno e local a cada tela: 2 migrações só de colunas (`captain_scenarios.exemplo/papeis`, `captain_assistant_responses.usos/usada_em`), ações novas no `AssistantsController` (ferramentas no Testar, texto final), filtros novos em dois controllers de leitura, um módulo FOSS novo (`Ramon::MemoriaContato`, testado no CI) e um serviço enterprise novo (`Captain::CadernoNoturno`) chamado por um job FOSS com cron. Front: todas as chaves novas no arquivo da área (`ramonIntel.json`, raiz `INTEL`), telas no kit `ramon/helpers/ui.js`, uma task por tela (nenhum `.vue` em duas tasks). Aprovação por prints antes × depois (harness Vite + Chrome headless, como A3).

**Tech Stack:** Rails 7.1 / RSpec (só no CI; `spec/enterprise` não roda no CI FOSS), Postgres, Sidekiq + sidekiq-cron; Vue 3.5 `<script setup>`, vue-router 4, vue-i18n 9, Vitest 3 + @vue/test-utils.

**Spec:** `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-05-inteligencia-tela-a-tela.md` (backlog de 67 itens). Planos anteriores (o padrão visual e o que já existe): `docs/superpowers/plans/2026-10-05-inteligencia-a1-faxina.md`, `…-a2-telas-verdadeiras.md`, `2026-10-07-inteligencia-a3.md`, `2026-10-07-inteligencia-a4.md`. Briefing do controlador: `plan-writer-common.md` (07/10).

---

## Decisões para o Eduardo

**N1 — Memória do contato: o que a IA pode anotar?** (a IA lê o fim da conversa resolvida e grava uma nota com o que aprendeu)
- (a) **Fatos do caso, sem nada de saúde** — benefício de interesse, trabalho/profissão/ramo do empregador, quando aconteceu (mês/ano do acidente, afastamento, demissão), benefício do INSS que já recebeu ou teve negado, documentos que tem ou vai mandar, "tem laudo/atestado: sim/não", melhor horário, dúvidas e objeções. **Nunca**: doença, CID, lesão, remédio, exame, tratamento, CPF, telefone, endereço, dados de familiares. ← **recomendo**
- (b) Os mesmos fatos **e** CID/diagnóstico/lesão (mais útil para a tese, mas é dado sensível de saúde; a memória roda em conversa de **lead**, que ainda não assinou contrato nem procuração — a base "o consentimento vem do contrato + procuração" ainda não existe nessa hora).
- (c) Não ligar agora.

**N2 — Memória do contato: onde a nota aparece?**
- (a) **No lead** — painel do lead → Notas, com o título "MEMÓRIA DA IA (conversa #N)"; é a lista de notas que a equipe já usa. ← **recomendo**
- (b) No contato (painel de contato do Chatwoot, que a equipe quase não abre).

**N3 — Caderno de provas automático: quando roda?** (roda os casos de teste ativos de cada assistente, em modo teste — só consulta executa, nada é gravado nem enviado; estimativa do #214: ≈ US$ 0,05 por caso → ≈ US$ 2,15 por rodada do caderno inteiro de 43 casos; o custo real aparece em Uso e custo, origem "Casos de teste")
- (a) **Toda madrugada às 05:30, mas só se algo mudou** (skill, FAQ aprovada, configuração ou caso de teste) desde a última rodada; pula no dia em que o gasto já passou do teto do alerta. Na prática, 1–3 rodadas por semana (≈ US$ 2–7/semana). ← **recomendo**
- (b) Toda madrugada, sempre (≈ US$ 65/mês).
- (c) Uma vez por semana (domingo 05:30), mudou ou não (≈ US$ 9/mês).
Em todos: nasce **desligado**; você liga em Inteligência → Testar → Casos de teste ("Rodar sozinho de madrugada").

**N4 — Caderno automático e o quadro de Automações:** as rotinas da conta estão virando passo "rotina" com gatilho "horário da conta" (B5-conta, em paralelo). O caderno noturno:
- (a) **Entra agora como rotina fixa do servidor (05:30) e vira rotina do quadro na limpeza (E7), junto das outras** — sem esperar o B5-conta. ← **recomendo**
- (b) Esperar o B5-conta e já nascer como rotina do quadro (a A5 fica presa à ordem de merge do B5).

**N5 — FAQs e Documentos sem o seletor de assistente (sempre do Atendimento)?** As FAQs só servem ao assistente que fala com o lead; hoje, com o Copiloto escolhido no seletor, a tela fica vazia.
- (a) **Sim**: o menu FAQs/Documentos abre sempre no assistente que atende leads (o que tem caixa conectada) e a tela não mostra seletor. O seletor fica em Skills, Testar e Configurações. ← **recomendo**
- (b) Manter o seletor também em FAQs e Documentos.

**N6 — Papéis das skills do Copiloto** (o Testar mostra primeiro as do seu papel; papel = time do hub de que a pessoa participa; dá para mudar na tela de Skills depois):

| Skill | Papéis |
|---|---|
| Situação do processo | recepção, controladoria, advogados |
| Consultas no AdvBox | controladoria, advogados |
| Escrever no AdvBox | controladoria, advogados |
| Anotar atendimento ou pedir por tarefa | recepção, controladoria, advogados |
| Lançar andamento do INSS | controladoria |
| Explicar andamento ao cliente | recepção, controladoria |
| Preparar reunião | comercial |
| Histórico da pessoa | recepção, comercial |
| Revisão de documentos do caso | comercial, controladoria |
| Funil hoje | comercial |
| Agenda do dia | recepção, comercial, advogados |
| Playbook da tese | comercial |
- (a) **Aceitar a tabela.** ← **recomendo**
- (b) Ajustar (diga quais).

**N7 — "Testar esta skill" e as falas sugeridas no Testar:**
- (a) **Só escrevem a fala no campo; você confere (e põe o caso) e aperta Enviar.** Nada roda sem clique — o Copiloto escreve no AdvBox depois do "ok", e cada envio custa. ← **recomendo**
- (b) Enviam a fala direto.

## Escolhas técnicas (registradas, sem pergunta)

1. **I-PG3:** a conversa do Testar fica na **memória da página** (trocar de tela ou de assistente não apaga; F5 ou fechar a aba limpa). Nada do caso fica gravado no navegador (LGPD).
2. **I-SK7:** "uso" = quantas vezes as **ferramentas da skill** rodaram no atendimento de verdade em 30 dias (Testar e Casos de teste não contam). Ferramenta usada por duas skills conta nas duas — a ajuda do chip diz isso.
3. **I-SK6:** a fala de exemplo é um campo novo da skill (`exemplo`), semeado pelo `assistentes.yml` e editável na tela; skill sem fala não mostra o botão.
4. **I-X5:** papel = **nome do time** (Configurações → Times: `recepção`, `controladoria`, `advogados`, `comercial`, e `sdr`/`closer` quando existirem). Sem tabela nova; coluna `papeis` (lista) na skill.
5. **I-EX3:** período "Hoje / 7 dias / 30 dias / Todo o período" (padrão: todo o período, como hoje) + "Carregar mais" de 100 em 100 pelo id (cursor), mantendo os filtros.
6. **I-WD4:** gravidade pela régua de retomada (3 ângulos no `FollowUpDraftService#angle_for`): 1–2 retomadas = âmbar, 3 ou mais = vermelho ("No limite da régua").
7. **I-CF3:** "Nome do escritório" vem preenchido com "Ramon Antonio Advogados" (sem acento — padrão da casa) quando o assistente não tem.
8. **I-CF4:** a chave "citações" some das duas telas (no modo atual, o do agente, ela não muda nada; citação numerada não cabe em WhatsApp) e é salva desligada; para o Copiloto (público equipe) somem também as mensagens ao cliente e as chaves que só valem em conversa com lead (FAQ de conversa, memória, dados do contato), com um aviso de uma linha.
9. **I-CF5:** "Zona de risco" é um `<details>` recolhido, só para administrador; o botão vermelho só libera depois de digitar o nome exato do assistente.
10. **I-CF6:** "texto final" = `agent_instructions` do assistente (o que o liquid monta: diretrizes, proteções, lista de skills) + o de cada skill ligada, numa janela só de leitura.
11. **I-FQ6:** o contador sobe na ferramenta `faq_lookup` quando ela devolve a FAQ no atendimento de verdade (Testar e Casos de teste não contam), com `update_all` (não mexe em `updated_at` nem em "editada").
12. **I-AS4/I-AS5:** a troca de nome é feita pelo **seed** (`rake ramon:inteligencia:seed[2]`), que acha o assistente pelo nome novo **ou** pelo antigo (campo `antes:` no yml) — nunca cria um segundo. O seed também apaga a chave morta `ramon_modo_rascunho` do `config`.
13. **I-X7:** modelo da memória = o mesmo das "FAQs geradas" (escolha "documentos" em Uso e custo); custo em linha própria "Memória do contato"; sem lead na conversa, sem memória; até 6 itens por nota, nota de até 1.000 caracteres; a IA recebe as 3 últimas memórias do lead para não repetir.
14. **I-X6:** `Captain::IaRodada` sem `disparado_por` = rodada da madrugada; a Visão geral mostra a última rodada concluída por assistente (de qualquer origem).
15. **I-X8:** "O que a IA fez neste caso" fica no fim da aba Atividade do painel do lead (as 10 mais novas, ferramentas + agente Claude, mesma permissão das Execuções).
16. **I-T5:** telas da área que faltavam no kit: Testar (bolhas sem roxo), Skills (link de ferramenta sem roxo), Configurações (chaves `Switch` no lugar de checkbox cru), criar assistente, Caixas, ferramentas HTTP (aviso e resultado do teste translúcidos) e Casos de teste (checkbox). Uso e custo e Registro de ações **não** mudam (o chip roxo da "assinatura" em Uso e custo é proposital).

## Escopo × o que já existe (conferido no código da base `0a31e02`)

| Item | Situação na base | Onde neste plano |
|---|---|---|
| I-T4 seletor só onde faz sentido | **a fazer** — `PageLayout` mostra o seletor por padrão (Documentos, Caixas, ferramentas HTTP, FAQs) | Tasks 5, 9, 11, 12 |
| I-T5 kit em todas as telas | **parcial** — A2/A3 puseram Ferramentas, Assistentes, Visão geral, Execuções, Documentos (form), FAQs (chips); faltam as da Escolha 16 | Tasks 5, 7, 8, 9, 12 |
| I-AS4 marca morta + "Atendimento" | **a fazer** (`assistant.rb:39-49`, `assistentes.yml:8,15`) | Task 3 |
| I-AS5 "Copiloto do Escritório" | **a fazer** (`assistentes.yml:126`) | Task 3 |
| I-SK6 "Testar esta skill" | **a fazer** | Tasks 4, 5, 8 |
| I-SK7 uso em 30 dias | **a fazer** | Tasks 4, 5 |
| I-PG2 ferramentas debaixo da resposta | **a fazer** (o #214 coleta ferramentas só nos Casos de teste) | Tasks 6, 7 |
| I-PG3 guardar a conversa | **a fazer** (`AssistantPlayground.vue:35-45` zera ao trocar) | Task 7 |
| I-PG4 testar com o caso | **a fazer** | Task 8 |
| I-PG5 nome e frase dos créditos | **já existe** (A1: menu "Testar", frase dos créditos fora; Eduardo aprovou "Testar") | — |
| I-CX3 textos das Caixas | **parcial** — falta "Sim, excluir" → desconectar, descrição vazia e "implantar" (`integrations.json:1055,1068`) | Tasks 2, 12 |
| I-EX3 período + carregar mais | **a fazer** (teto fixo de 100) | Task 13 |
| I-EX5 "só erros de hoje" | **a fazer** | Task 13 |
| I-WD3 abrir conversa no Vigia | **a fazer** (a API manda só o id interno) | Task 14 |
| I-WD4 cor por gravidade | **a fazer** (chip sempre âmbar) | Task 14 |
| I-CF3 nome do escritório / criatividade | **a fazer** | Tasks 2, 9 |
| I-CF4 configuração por público | **a fazer** | Task 9 |
| I-CF5 zona de risco | **a fazer** (botão vermelho à vista) | Task 9 |
| I-CF6 texto final | **a fazer** | Tasks 6, 9 |
| I-FQ4 abrir conversa da FAQ | **já existe** (`ResponseCard.vue` → `navigate` → `inbox_conversation`; texto "Conversa #" do A1) | — |
| I-FQ5 FAQs sempre do Atendimento | **a fazer** | Task 11 |
| I-FQ6 "usada X vezes" | **a fazer** | Tasks 10, 11 |
| I-DO4 aviso do link | **a fazer** (`crawl_job.rb:26-40` segue todos os links) | Task 11 |
| I-DO5 `CONTEXT.md` × D4 | **a fazer** (`CONTEXT.md:165-168`) | Task 11 |
| I-X4 uso/custo | **já entregue** (#215) — não mexer além do rótulo da função nova (Task 2) | — |
| I-X5 skills por papel | **a fazer** | Tasks 4, 5, 8 |
| I-X6 caderno automático | **a fazer** (o #214 só roda por clique) | Tasks 17, 18 |
| I-X7 memória do contato | **a fazer** — `feature_memory` existe mas grava nota do contato com prompt em inglês, conversa inteira sem máscara; está OFF de propósito | Tasks 9, 16 |
| I-X8 execuções dentro do caso | **a fazer** | Tasks 13, 15 |
| Registro de ações (#213) | **já entregue** — não mexer | — |

Os outros 39 itens foram entregues em A1 (#198), A2 (#201), A3 (#220), A4 (#221), #214 e #215.

## Global Constraints

- Worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-intel-a5`, branch `feat/inteligencia-a5`, base `origin/ramon` **0a31e02**. Todo `arquivo:linha` é do commit base; se uma task anterior mexeu no arquivo, use o trecho citado como âncora. Nunca `git push`, nunca abrir PR, nunca `git stash`, nunca `git add -A` (gate do Eduardo / sessão principal).
- **Migrações (2, só colunas), faixa reservada à A5: `2026100780xxxx`:** `20261007800001_add_exemplo_e_papeis_to_captain_scenarios.rb` (Task 4) e `20261007800002_add_uso_to_captain_assistant_responses.rb` (Task 10). Sem Postgres local: o executor edita o `db/schema.rb` **à mão no formato exato do dump** (colunas no fim do bloco da tabela, na ordem do `add_column`; linha `define(version: …)` = a maior migração, `2026_10_07_800002` no fim). Se outra frente mergear migração antes, a `define(version:)` fica com a maior das duas.
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `MethodLength` 19, `CyclomaticComplexity` 7, `PerceivedComplexity` 8, `ClassLength` 175, `ModuleLength` 100, `BlockLength` 30 (fora de spec), linha 150, `Style/HashSyntax` `EnforcedShorthandSyntax: never` (sempre `chave: valor`), `Naming/MethodParameterName` mínimo 3 letras, `Layout/EmptyLineAfterGuardClause`, `Style/StringLiterals`, `RSpec/ContextWording` (`context` só começa com when/with/without — frase em pt-BR vai em `describe`), `RSpec/MultipleExpectations` 7 (use `:aggregate_failures`), `RSpec/SpecFilePathFormat`, `RSpec/SortMetadata`. **`app/models/lead.rb`, `app/services/ramon/advbox_event_processor.rb`, `app/finders/conversation_finder.rb` estão no limite: nenhuma linha nova** (a A5 não toca nenhum). **`enterprise/app/models/captain/scenario.rb` (177 linhas) e `enterprise/app/services/captain/assistant/agent_runner_service.rb` (teto): não tocar.**
- **Postgres:** nada de `.distinct.pluck` em modelo com `default_scope` ordenado (`LeadNote`, `Message`, `Lead` têm) — `.reorder(...)` antes de `pluck/limit`; nada de `NOW()` no SQL (binds com `Time.current`); `travel_to` só em sequência.
- **CI FOSS apaga `enterprise/` e `spec/enterprise/`:** código em `app/`/`lib/` não referencia `Captain::*` (exceto `Captain::ToolRun`, que é FOSS em `app/models/captain/tool_run.rb`) sem `ChatwootApp.enterprise?`; spec FOSS que use `create(:captain_assistant)` leva `if: ChatwootApp.enterprise?`. Specs em `spec/enterprise` são documentação + prova manual.
- **Sem Ruby local:** specs Ruby escritos e conferidos à mão (rastrear cada linha); quem valida é o CI.
- **Regras da casa:** mensagem ao cliente sempre rascunho (nada nesta fatia envia mensagem); honorário 30% + 3 nas FAQs; DeepSeek é o motor; FAQ por busca de texto (sem embeddings). Toda chamada nova de LLM passa pelo `Ramon::LlmUso` (função própria) e as rotinas automáticas param no dia em que o gasto passa do teto do alerta (`Ramon::IaGastoAlerta`). LGPD: texto ao LLM sempre pelo `Ramon::Pseudonymizer` (via `Ramon::FaqDeConversa.texto`).
- **Front — i18n:** toda chave nova vai em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramonIntel.json` (raiz `INTEL`), **criadas todas na Task 2** (mesma ordem nos dois; a trava `captain/pages/specs/IntelI18n.spec.js` compara a ordem e compila no vue-i18n de produção). Valores trocados em `integrations.json` (só en e pt_BR) e 1 rótulo em `ramonIaUso.json`, também na Task 2. **Não tocar `ramon.json`** (B5 mexe). Placeholders só `{n}`, `{id}`, `{nome}`, `{teto}`, `{tipo}`, `{total}`, `{quando}`; sem `@`, `|`, `{`, `}` crus; editar JSON com Edit.
- **Front — visual:** Tailwind only, kit `ramon/helpers/ui.js` (`CARTAO`, `CHIP`, `TOM`, `ABA*`, `CAMPO`, `SELECT`, `TITULO`, `AVISO`, `LINHA`, `MENU`, `FUNDO_JANELA`, `JANELA`…), destaque azul (`text-n-blue-11`; nunca `iris` em coisa nova), **fundos coloridos sempre translúcidos**, botões e etapas coloridos, evento custom camelCase, toda `<ul>/<ol>` nova com `list-none`, sem texto cru no template (montar no script).
- **Vitest:** `node_modules` é junção para `ramon-hub-wt-fluxos-b2\node_modules` (nunca `rm -rf node_modules`). Config local fora do git: `vitest.local.config.ts` na raiz do worktree.
  `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
  Os testes rodam com locale **en** (`vitest.setup.js`); specs novos mockam `vue-i18n` com `t: key => key` quando só precisam da chave. ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` aceitos).
- **Bash deste Windows come barra invertida em heredoc:** arquivos (inclusive `.sh`/`.mjs` do harness) são criados com a ferramenta Write.
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR`
  Commitar só os caminhos da task (`git add <arquivos>`).
- **Rito de telas:** prints claro/escuro antes × depois em `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a5\comparar.html`; **merge só com o "aprovado" do Eduardo** (um PR, aprovação e deploy por pacote).

## Review Focus

1. **Skill editada na tela e o seed roda de novo trazendo fala de exemplo e papéis** — esperado: só preenche o que está vazio; fala/papéis escolhidos na tela nunca são sobrescritos; nada duplica. Teste: Task 4 ("skill editada só ganha o que está vazio").
2. **Memória do contato com conversa sem lead, JSON inválido, item com dado de saúde, nada novo ou teto estourado** — esperado: nenhuma nota quando não há o que gravar; item de saúde/CID cai fora mesmo se a IA escrever; teto estourado não chama a IA. Teste: Task 16 (`Ramon::MemoriaContato` — "gravar! filtra saúde…", ".itens com JSON quebrado", "sem itens não grava"; `Ramon::IaGastoAlerta.passou_do_teto?`).
3. **Caderno da madrugada com rodada em andamento/travada, nada mudou, chave desligada ou teto estourado** — esperado: não enfileira; uma conta com erro não derruba as outras. Teste: Task 17 (spec enterprise `caderno_noturno_spec.rb` e FOSS `caderno_noturno_job_spec.rb`).
4. **"Carregar mais" nas Execuções com filtros e período ligados** — esperado: a próxima página respeita ferramenta, status, período e caso, sem repetir linha; "Carregar mais" some quando acabou. Teste: Task 13 (request spec "filtra por caso e período e pagina com antes_de" + vitest "carregar mais pede antes_de com os mesmos filtros").
5. **Trocar de assistente no Testar com a resposta ainda chegando** — esperado: a resposta entra na conversa do assistente que perguntou (não na do outro), e cada assistente guarda a sua. Teste: Task 7 (vitest "resposta atrasada vai para a conversa de quem perguntou").

---

## Pontos de conflito com as frentes em paralelo (B5-conta, B5-leads, B5-externos)

| Arquivo | Quem mais pode tocar | Como resolver |
|---|---|---|
| `config/routes.rb` | B5 (rotas novas) | A5 acrescenta `get :texto_final` no `member` de `captain/assistants` e `patch :noturno` dentro de `ia_rodadas` — manter todas |
| `config/schedule.yml` | B5-conta (pode tirar crons das rotinas que viram fluxo) | A5 acrescenta **um bloco no fim** (`ramon_caderno_noturno_job`); conflito de texto puro |
| `db/schema.rb` | qualquer frente com migração | `define(version:)` = a maior; blocos de tabela não se cruzam (A5 só mexe em `captain_scenarios` e `captain_assistant_responses`) |
| `lib/ramon/llm_uso.rb` | B5 (se criar função nova) | A5 acrescenta **no fim** do hash `FUNCOES` |
| `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramonIaUso.json` | B5 (rótulo de função nova) | A5 acrescenta no fim de `FUNCOES` |
| `routes/dashboard/ramon/components/lead/LeadPanelBody.vue` | B5-leads (coach de objeção / sugestão de documento podem mexer no painel) | A5 só acrescenta 1 import e 1 linha na aba Atividade |
| `db/seeds/ramon/inteligencia/assistentes.yml`, `lib/ramon/inteligencia_seed.rb` | B5-leads (agente do hub / skills) | A5 renomeia 2 assistentes e acrescenta `exemplo:`/`papeis:` por skill; quem vier depois rebaseia |

## Operação depois do deploy (o Eduardo roda os comandos com `!`)

1. **Antes do `up`:** `docker compose run --rm chatwoot-web bundle exec rails db:migrate` (2 migrações só de coluna, rápidas).
2. Deploy de sempre (`docker compose pull chatwoot-web chatwoot-worker && docker compose up -d chatwoot-web chatwoot-worker`). **Sem env nova.** O cron novo (05:30) entra sozinho (sidekiq-cron lê o `schedule.yml` no boot) e não faz nada enquanto a chave da conta estiver desligada.
3. **Seed:** `docker compose exec chatwoot-web bundle exec rake ramon:inteligencia:seed[2]` — renomeia "Atendimento (rascunho)" → "Atendimento" e "Copiloto do Escritorio" → "Copiloto do Escritório" (sem criar outro), apaga a chave morta, e preenche fala de exemplo e papéis das skills (as editadas na tela só ganham o que estiver vazio). Conferir na saída: `assistentes_criados` **ausente** ou 0.
4. **Memória do contato (I-X7):** Inteligência → Configurações → Atendimento → ligar "Memória do contato" → Atualizar. Teste ao vivo: numa conversa de teste da caixa conectada (com lead), trocar algumas mensagens e **resolver** → em até 1 minuto o painel do lead → Notas mostra "MEMÓRIA DA IA (conversa #N)"; Uso e custo mostra a linha "Memória do contato". **Desligar:** a mesma chave. Sem lead na conversa, nada é gravado.
5. **Caderno automático (I-X6):** Inteligência → Testar → Casos de teste → ligar "Rodar sozinho de madrugada" (vale para todos os assistentes da conta). Na manhã seguinte: Visão geral → bloco "Caderno de provas" com a rodada das 05:30 (se algo tinha mudado). **Desligar:** a mesma chave. Voltar ao "só por clique" não exige deploy.
6. Smoke em bloco por tela (Task 20, passo 4) — sem formulário passo a passo.

---

## Mapa de arquivos

| Arquivo | Task | Responsabilidade |
|---|---|---|
| `tmp/intel-a5-harness/*` (não versionado) | 1, 19 | harness Vite (porta 6197), `shots.sh`, `telas-{antes,depois}.txt`, `comparar.mjs` |
| `i18n/locale/{en,pt_BR}/ramonIntel.json`, `IntelI18n.spec.js`, `integrations.json`, `ramonIaUso.json` | 2 | todos os textos da A5 |
| `db/seeds/ramon/inteligencia/assistentes.yml`, `lib/ramon/inteligencia_seed.rb`, `db/seeds/ramon/ia_casos.yml`, `enterprise/app/models/captain/assistant.rb` + specs | 3, 4 | nomes, marca morta; fala de exemplo e papéis |
| `db/migrate/20261007800001_add_exemplo_e_papeis_to_captain_scenarios.rb`, `db/schema.rb`, `scenarios_controller.rb`, `_scenario.json.jbuilder`, `scenarios/index.json.jbuilder` | 4 | colunas, uso em 30 dias |
| `captain/assistants/scenarios/Index.vue`, `components-next/captain/assistant/ScenariosCard.vue` (+ specs) | 5 | tela Skills |
| `enterprise/.../captain/assistants_controller.rb`, `assistant_policy.rb`, `config/routes.rb`, `api/captain/assistant.js` | 6 | ferramentas no Testar, texto final |
| `components-next/captain/assistant/{AssistantPlayground,MessageList}.vue`, `testarConversas.js` (novo) | 7 | conversa do Testar |
| `captain/assistants/playground/{Index.vue,TestarComCaso.vue (novo),testar.js (novo)}`, `captain/casos/CasoForm.vue` | 8 | página do Testar |
| `captain/assistants/settings/Settings.vue`, `pageComponents/assistant/settings/{AssistantBasicSettingsForm,AssistantSystemSettingsForm,TextoFinal (novo)}.vue`, `pageComponents/assistant/AssistantForm.vue` | 9 | Configurações |
| `db/migrate/20261007800002_add_uso_to_captain_assistant_responses.rb`, `faq_lookup_tool.rb`, `_assistant_response.json.jbuilder` | 10 | contador de uso da FAQ |
| `components-next/captain/PageLayout.vue`, `captain/pages/{AssistantsIndexPage.vue,assistenteDasFaqs.js (novo)}`, `ResponseCard.vue`, `responses/Index.vue`, `DocumentForm.vue`, `CONTEXT.md` | 11 | FAQs e Documentos |
| `captain/assistants/inboxes/Index.vue`, `captain/tools/Index.vue`, `customTool/CustomToolForm.vue` | 12 | Caixas e ferramentas HTTP |
| `captain_tool_runs_controller.rb` (+ jbuilder), `ramon_agente_execucoes_controller.rb`, `api/ramonAgenteExecucoes.js`, `captain/pages/Execucoes.vue` | 13 | Execuções |
| `ramon_watchdog_controller.rb`, `captain/pages/VigiaBloco.vue` | 14 | Vigia |
| `ramon/components/lead/{LeadIaExecucoes.vue (novo),LeadPanelBody.vue}` | 15 | o que a IA fez no caso |
| `app/services/ramon/memoria_contato.rb` (novo), `app/services/ramon/ia_gasto_alerta.rb`, `app/services/ramon/faq_de_conversa.rb`, `lib/ramon/llm_uso.rb`, `enterprise/.../contact_notes_service.rb` | 16 | memória do contato |
| `enterprise/app/services/captain/caderno_noturno.rb` (novo), `app/jobs/ramon/caderno_noturno_job.rb` (novo), `config/schedule.yml`, `ia_rodadas_controller.rb`, `ramon_inteligencia_controller.rb` | 17 | caderno automático (backend) |
| `captain/casos/CasosTeste.vue`, `api/captain/iaCasos.js`, `captain/pages/VisaoGeral.vue` | 18 | caderno automático (tela) |
| `captain/pages/Inteligencia.story.vue`, `captain/casos/CasosTeste.story.vue` | 19 | variantes dos prints |

Tasks **mecânicas** (código completo no plano, executor só aplica e roda): 1, 2, 3, 4, 6, 10, 12, 13, 14, 15, 17. Tasks com **julgamento** (layout/integração em tela grande; conferir no print): 5, 7, 8, 9, 11, 16, 18, 19.

---

### Task 1: Harness + prints "antes" (mecânica)

Roda **antes de qualquer mudança de código** (o "antes" é a base 0a31e02).

**Files:**
- Create (não versionado — `tmp/` está no `.gitignore`): `tmp/intel-a5-harness/{index.html,ConversationBoxStub.vue,BackButtonStub.vue,main.js,vite.config.mts,shots.sh,telas-antes.txt}`
- Output: `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a5\antes-*.png`

**Interfaces:**
- Produces: harness em `http://localhost:6197/?story=intel|casos&variant=<Título>&tema=claro|escuro`; `sh tmp/intel-a5-harness/shots.sh antes|depois` lê `telas-<fase>.txt` (linhas `story:Variante:arquivo:LxA`).

- [ ] **Step 1: Copiar o harness da A3** (Bash — o sed não tem barra invertida):

```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-intel-a5
mkdir -p tmp/intel-a5-harness
H=../ramon-hub-wt-intel-a3/tmp/intel-a3-harness
cp $H/index.html $H/ConversationBoxStub.vue $H/BackButtonStub.vue $H/main.js $H/vite.config.mts $H/shots.sh tmp/intel-a5-harness/
sed -i 's/intel-a3-harness/intel-a5-harness/g; s/inteligencia-a3/inteligencia-a5/g; s/6196/6197/g' tmp/intel-a5-harness/shots.sh tmp/intel-a5-harness/vite.config.mts
grep -n "6197\|inteligencia-a5\|intel-a5" tmp/intel-a5-harness/shots.sh tmp/intel-a5-harness/vite.config.mts
```
Expected: o grep mostra a porta 6197 no `vite.config.mts` e `inteligencia-a5`/`intel-a5-harness` no `shots.sh`.

- [ ] **Step 2: Story dos Casos de teste no harness** — em `tmp/intel-a5-harness/main.js` (Edit), trocar

```js
  centro: () => import('dashboard/routes/dashboard/ramon/pages/CentroComando.story.vue'),
```
por
```js
  centro: () => import('dashboard/routes/dashboard/ramon/pages/CentroComando.story.vue'),
  casos: () => import('dashboard/routes/dashboard/captain/casos/CasosTeste.story.vue'),
```

- [ ] **Step 3: `tmp/intel-a5-harness/telas-antes.txt`** (Write):

```
intel:Testar:testar:1440,1000
intel:Skills:skills:1440,1600
intel:Configuracoes:configuracoes:1440,1400
intel:FAQs:faqs:1440,1300
intel:Documentos novo:documentos-novo:1440,900
intel:Caixas:caixas:1440,800
intel:Caixas conectar:caixas-conectar:1440,800
intel:Ferramentas HTTP:ferramentas-http:1440,800
intel:Execucoes:execucoes:1440,1100
intel:Visao geral:visao-geral:1440,2100
casos:Casos:casos:1440,1300
```

- [ ] **Step 4: Subir o harness** (Bash, `run_in_background: true`): `cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-intel-a5 && npx vite --config tmp/intel-a5-harness/vite.config.mts`. Conferir: `curl -s -o /dev/null -w "%{http_code}" "http://localhost:6197/?story=intel&variant=Testar"` → `200`.

- [ ] **Step 5: Prints "antes"** — `cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-intel-a5 && sh tmp/intel-a5-harness/shots.sh antes`. Expected: 22 arquivos `antes-{claro,escuro}-*.png`. Abrir com Read `antes-claro-testar.png`, `antes-escuro-configuracoes.png` e `antes-claro-casos.png`: tela desenhada, fonte Geist, nada de página branca (se vier branca: olhar o log do Vite em segundo plano — import que falta no alias é a causa típica).

- [ ] **Step 6: Sem commit** (nada versionado mudou). Deixar o harness no ar (a Task 19 usa).

---

### Task 2: Textos da A5 (i18n) — tudo de uma vez (mecânica)

**Files:**
- Modify (substituir o conteúdo inteiro): `app/javascript/dashboard/i18n/locale/pt_BR/ramonIntel.json`, `app/javascript/dashboard/i18n/locale/en/ramonIntel.json`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js`, `app/javascript/dashboard/i18n/locale/{en,pt_BR}/integrations.json`, `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramonIaUso.json`

**Interfaces:**
- Produces: as chaves `INTEL.*` usadas pelas Tasks 5–18 (nomes exatos abaixo); placeholders novos `{total}` e `{quando}`.

- [ ] **Step 1: Trava aceita os placeholders novos (teste falha antes do JSON)** — em `IntelI18n.spec.js` (Edit), trocar

```js
    const params = { n: 1, id: 1, nome: 'x', teto: 30, tipo: 'x' };
```
por
```js
    const params = {
      n: 1,
      id: 1,
      nome: 'x',
      teto: 30,
      tipo: 'x',
      total: 2,
      quando: 'x',
    };
```
e, no fim do `describe`, antes do `});` final, acrescentar:

```js
  it('chaves da A5 existem nos dois idiomas', () => {
    const A5 = [
      'INTEL.TESTAR.FERRAMENTAS',
      'INTEL.CONFIG.ZONA_RISCO',
      'INTEL.CAIXAS.TITULO',
      'INTEL.VIGIA.CONVERSA',
      'INTEL.CASO_IA.TITULO',
      'INTEL.CADERNO.NOTURNO',
      'INTEL.VISAO_GERAL.CADERNO.LINHA',
      'INTEL.EXECUCOES.PERIODO.D7',
      'INTEL.SKILLS.TESTAR',
      'INTEL.FAQ.USADA',
      'INTEL.DOCUMENTOS.LINK_AVISO',
    ];
    const chavesPt = folhas(pt).map(([k]) => k);
    expect(A5.filter(chave => !chavesPt.includes(chave))).toEqual([]);
  });
```

- [ ] **Step 2: Rodar e ver falhar**

`TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js --config vitest.local.config.ts`
Expected: FAIL em "chaves da A5 existem" (lista com as 11 chaves).

- [ ] **Step 3: `pt_BR/ramonIntel.json`** (Write — conteúdo inteiro; os blocos de antes ficam iguais):

```json
{
  "INTEL": {
    "TESE": {
      "auxilio-acidente": "Auxílio-acidente",
      "auxilio-doenca": "Auxílio-doença",
      "aposentadoria-invalidez": "Aposentadoria por invalidez",
      "bpc-loas": "BPC/LOAS",
      "acrescimo-25": "Acréscimo de 25%",
      "geral": "Geral"
    },
    "DOCUMENTOS": {
      "MODO_LINK": "Link de página",
      "MODO_TEXTO": "Colar texto",
      "TITULO_LABEL": "Título",
      "TITULO_PLACEHOLDER": "Ex.: Regras do BPC — resumo da equipe",
      "TITULO_ERRO": "Dê um título ao texto",
      "TEXTO_LABEL": "Texto",
      "TEXTO_PLACEHOLDER": "Cole aqui o texto (de um PDF, e-mail, manual...)",
      "TEXTO_ERRO": "Cole o texto (até 200 mil caracteres)",
      "TEXTO_COLADO": "Texto colado",
      "LINK_AVISO": "Vai ler esta página e as páginas ligadas a ela no mesmo site — o link da página inicial pode trazer o site inteiro. Para um texto só, use Colar texto."
    },
    "FAQ": {
      "TESE_LABEL": "Tese",
      "TODAS_TESES": "Todas as teses",
      "SEM_TESE": "Sem tese",
      "TESTAR": {
        "TITULO": "Testar pergunta",
        "AJUDA": "Escreva como o lead perguntaria. A lista mostra as FAQs que o assistente acharia, na ordem em que ele recebe.",
        "PLACEHOLDER": "Ex.: posso trabalhar recebendo auxílio-acidente?",
        "BOTAO": "Testar",
        "NADA": "O assistente não acharia nenhuma FAQ para essa pergunta. Vale criar uma.",
        "ERRO": "Não foi possível testar agora. Tente de novo."
      },
      "USADA": "Usada {n}×",
      "NUNCA_USADA": "Ainda não usada",
      "USADA_AJUDA": "Quantas vezes o assistente usou esta FAQ no atendimento de verdade (o Testar não conta). Última vez: {quando}."
    },
    "SKILLS": {
      "ABA_LIGADAS": "Ligadas ({n})",
      "ABA_DESLIGADAS": "Desligadas ({n})",
      "NENHUMA_DESLIGADA": "Nenhuma skill desligada.",
      "LIGAR": "Ligar ou desligar esta skill",
      "LIGADA": "Skill ligada: o assistente volta a usar.",
      "DESLIGADA": "Skill desligada: o assistente para de usar.",
      "EDITADA": "Editada aqui",
      "EDITADA_AJUDA": "Editada na tela: a carga automática das skills não muda nem desliga esta.",
      "TESTAR": "Testar esta skill",
      "USO_30D": "Rodou {n}× em 30 dias",
      "SEM_USO_30D": "Não rodou em 30 dias",
      "USO_AJUDA": "Quantas vezes as ferramentas desta skill rodaram no atendimento de verdade nos últimos 30 dias. O Testar e os Casos de teste não contam; ferramenta usada por duas skills conta nas duas.",
      "EXEMPLO_LABEL": "Fala de exemplo (aparece no Testar)",
      "EXEMPLO_PLACEHOLDER": "Ex.: O que falta de documento deste caso?",
      "PAPEIS_LABEL": "Papéis que mais usam (aparecem primeiro no Testar)"
    },
    "EXECUCOES": {
      "ABA_FERRAMENTAS": "Ferramentas da IA",
      "ABA_AGENTE": "Agente Claude",
      "STATUS": {
        "ok": "OK",
        "erro": "Erro",
        "limite": "Limite",
        "cap": "Teto do dia",
        "timeout": "Tempo esgotado"
      },
      "CASO": "Caso #{id}",
      "CASO_NOME": "Caso #{id} · {nome}",
      "CONVERSA": "Conversa #{id}",
      "AGENTE": {
        "SUBTITULO": "Cada pedido feito ao agente numa nota: o que pediu, o que ele respondeu e fez, e quanto demorou. O custo fica em Uso e custo.",
        "HOJE": "Hoje: {n} de {teto} pedidos",
        "PROBLEMAS": "Com problema hoje: {n}",
        "VAZIO": "Nenhum pedido ao agente ainda.",
        "VER_RESULTADO": "ver o que o agente respondeu",
        "ESCONDER": "esconder",
        "SEM_RESUMO": "Sem resposta registrada.",
        "ACOES": "O que o agente fez",
        "NENHUMA_ACAO": "Nenhuma escrita (só respondeu na nota)."
      },
      "PERIODO": {
        "TUDO": "Todo o período",
        "HOJE": "Hoje",
        "D7": "Últimos 7 dias",
        "D30": "Últimos 30 dias"
      },
      "SO_ERROS_HOJE": "Só erros de hoje",
      "CARREGAR_MAIS": "Carregar mais"
    },
    "VISAO_GERAL": {
      "VER_TRILHA": "Ver a trilha do agente",
      "CADERNO": {
        "TITULO": "Caderno de provas",
        "LINHA": "{nome}: {n} de {total} ok",
        "QUANDO": "Última rodada: {quando}",
        "NUNCA": "Nenhuma rodada concluída ainda.",
        "ABRIR": "Abrir os casos de teste"
      }
    },
    "SUGESTOES": {
      "SO_TIPO": "Só: {tipo}",
      "VER_TODAS": "ver todas",
      "NENHUMA_DO_TIPO": "Nenhuma sugestão desse tipo agora."
    },
    "TESTAR": {
      "FERRAMENTAS": "Ferramentas usadas:",
      "FERRAMENTA_ERRO": "{nome} (erro)",
      "SUGESTOES": "Experimente (as do seu papel primeiro):",
      "CASO_PLACEHOLDER": "Testar com o caso… (nome do lead)",
      "CASO_AJUDA": "Escolher um lead põe o nº do caso na sua mensagem.",
      "CASO_NENHUM": "Nenhum lead com esse nome."
    },
    "CONFIG": {
      "SO_EQUIPE": "Este assistente fala só com a equipe: mensagens ao cliente, FAQs de conversa e memória do contato não se aplicam a ele.",
      "MEMORIA_AJUDA": "Ao resolver a conversa, a IA anota no lead (painel → Notas) o que aprendeu: benefício de interesse, trabalho, datas, documentos e objeções. Nunca anota dado de saúde, CPF, telefone ou endereço. Para no dia em que o gasto passa do teto.",
      "ZONA_RISCO": "Zona de risco",
      "DIGITE_NOME": "Digite {nome} para liberar a exclusão",
      "TEXTO_FINAL": "Ver o texto final que o assistente recebe",
      "TEXTO_FINAL_AJUDA": "Diretrizes, proteções e a lista de skills juntas, do jeito que vão para a IA, e o texto de cada skill ligada. Só leitura.",
      "TEXTO_FINAL_ASSISTENTE": "Assistente",
      "TEXTO_FINAL_SKILL": "Skill: {nome}",
      "TEXTO_FINAL_ERRO": "Não foi possível carregar o texto agora.",
      "FECHAR": "Fechar"
    },
    "CAIXAS": {
      "TITULO": "Caixas conectadas — {nome}"
    },
    "VIGIA": {
      "CONVERSA": "Abrir a conversa",
      "NO_LIMITE": "No limite da régua de retomada"
    },
    "CASO_IA": {
      "TITULO": "O que a IA fez neste caso",
      "AGENTE": "Agente Claude: {nome}",
      "VAZIO": "A IA ainda não fez nada neste caso.",
      "ERRO": "Não foi possível carregar agora."
    },
    "CADERNO": {
      "NOTURNO": "Rodar sozinho de madrugada (05:30), se algo mudou",
      "NOTURNO_AJUDA": "Vale para todos os assistentes. Roda os casos ativos quando uma skill, FAQ, configuração ou caso mudou desde a última rodada, e não roda no dia em que o gasto passou do teto (Uso e custo). Estimativa: {n} por rodada deste assistente.",
      "NOTURNO_LIGADO": "Rodada da madrugada ligada.",
      "NOTURNO_DESLIGADO": "Rodada da madrugada desligada."
    }
  }
}
```
(Se o Eduardo escolher N3 (b) ou (c), ajustar só `CADERNO.NOTURNO` e `CADERNO.NOTURNO_AJUDA` — e os equivalentes en.)

- [ ] **Step 4: `en/ramonIntel.json`** (Write — mesmas chaves, mesma ordem):

```json
{
  "INTEL": {
    "TESE": {
      "auxilio-acidente": "Accident benefit",
      "auxilio-doenca": "Sickness benefit",
      "aposentadoria-invalidez": "Disability retirement",
      "bpc-loas": "BPC/LOAS",
      "acrescimo-25": "25% supplement",
      "geral": "General"
    },
    "DOCUMENTOS": {
      "MODO_LINK": "Page link",
      "MODO_TEXTO": "Paste text",
      "TITULO_LABEL": "Title",
      "TITULO_PLACEHOLDER": "E.g.: BPC rules — team summary",
      "TITULO_ERRO": "Give the text a title",
      "TEXTO_LABEL": "Text",
      "TEXTO_PLACEHOLDER": "Paste the text here (from a PDF, e-mail, manual...)",
      "TEXTO_ERRO": "Paste the text (up to 200 thousand characters)",
      "TEXTO_COLADO": "Pasted text",
      "LINK_AVISO": "It reads this page and the pages linked from it on the same site — a home page link can pull the whole site. For a single text, use Paste text."
    },
    "FAQ": {
      "TESE_LABEL": "Thesis",
      "TODAS_TESES": "All theses",
      "SEM_TESE": "No thesis",
      "TESTAR": {
        "TITULO": "Test a question",
        "AJUDA": "Write it the way a lead would ask. The list shows the FAQs the assistant would find, in the order it gets them.",
        "PLACEHOLDER": "E.g.: can I keep working while on accident benefit?",
        "BOTAO": "Test",
        "NADA": "The assistant would not find any FAQ for this question. Consider creating one.",
        "ERRO": "Could not test right now. Try again."
      },
      "USADA": "Used {n}×",
      "NUNCA_USADA": "Not used yet",
      "USADA_AJUDA": "How many times the assistant used this FAQ in real conversations (Test does not count). Last time: {quando}."
    },
    "SKILLS": {
      "ABA_LIGADAS": "On ({n})",
      "ABA_DESLIGADAS": "Off ({n})",
      "NENHUMA_DESLIGADA": "No skill is off.",
      "LIGAR": "Turn this skill on or off",
      "LIGADA": "Skill on: the assistant uses it again.",
      "DESLIGADA": "Skill off: the assistant stops using it.",
      "EDITADA": "Edited here",
      "EDITADA_AJUDA": "Edited on screen: the automatic skill load does not change or turn off this one.",
      "TESTAR": "Test this skill",
      "USO_30D": "Ran {n}× in 30 days",
      "SEM_USO_30D": "Did not run in 30 days",
      "USO_AJUDA": "How many times this skill's tools ran in real conversations in the last 30 days. Test and test cases do not count; a tool used by two skills counts in both.",
      "EXEMPLO_LABEL": "Sample message (shown in Test)",
      "EXEMPLO_PLACEHOLDER": "E.g.: What documents are missing in this case?",
      "PAPEIS_LABEL": "Roles that use it most (shown first in Test)"
    },
    "EXECUCOES": {
      "ABA_FERRAMENTAS": "AI tools",
      "ABA_AGENTE": "Claude agent",
      "STATUS": {
        "ok": "OK",
        "erro": "Error",
        "limite": "Limit",
        "cap": "Daily cap",
        "timeout": "Timed out"
      },
      "CASO": "Case #{id}",
      "CASO_NOME": "Case #{id} · {nome}",
      "CONVERSA": "Conversation #{id}",
      "AGENTE": {
        "SUBTITULO": "Every request made to the agent in a note: what was asked, what it answered and did, and how long it took. Cost lives in Usage and cost.",
        "HOJE": "Today: {n} of {teto} requests",
        "PROBLEMAS": "With problems today: {n}",
        "VAZIO": "No agent requests yet.",
        "VER_RESULTADO": "show what the agent answered",
        "ESCONDER": "hide",
        "SEM_RESUMO": "No answer recorded.",
        "ACOES": "What the agent did",
        "NENHUMA_ACAO": "No writes (only answered in the note)."
      },
      "PERIODO": {
        "TUDO": "All time",
        "HOJE": "Today",
        "D7": "Last 7 days",
        "D30": "Last 30 days"
      },
      "SO_ERROS_HOJE": "Only today's errors",
      "CARREGAR_MAIS": "Load more"
    },
    "VISAO_GERAL": {
      "VER_TRILHA": "See the agent trail",
      "CADERNO": {
        "TITULO": "Test notebook",
        "LINHA": "{nome}: {n} of {total} ok",
        "QUANDO": "Last run: {quando}",
        "NUNCA": "No finished run yet.",
        "ABRIR": "Open the test cases"
      }
    },
    "SUGESTOES": {
      "SO_TIPO": "Only: {tipo}",
      "VER_TODAS": "see all",
      "NENHUMA_DO_TIPO": "No suggestion of this kind right now."
    },
    "TESTAR": {
      "FERRAMENTAS": "Tools used:",
      "FERRAMENTA_ERRO": "{nome} (error)",
      "SUGESTOES": "Try one (your role's first):",
      "CASO_PLACEHOLDER": "Test with the case… (lead name)",
      "CASO_AJUDA": "Picking a lead adds the case number to your message.",
      "CASO_NENHUM": "No lead with that name."
    },
    "CONFIG": {
      "SO_EQUIPE": "This assistant only talks to the team: customer messages, conversation FAQs and contact memory do not apply to it.",
      "MEMORIA_AJUDA": "When the conversation is resolved, the AI notes on the lead (panel → Notes) what it learned: benefit of interest, work, dates, documents and objections. It never notes health data, ID numbers, phone or address. Stops on the day spending passes the cap.",
      "ZONA_RISCO": "Danger zone",
      "DIGITE_NOME": "Type {nome} to unlock deletion",
      "TEXTO_FINAL": "See the final text the assistant receives",
      "TEXTO_FINAL_AJUDA": "Guidelines, guardrails and the skill list together, the way they go to the AI, plus the text of each skill that is on. Read only.",
      "TEXTO_FINAL_ASSISTENTE": "Assistant",
      "TEXTO_FINAL_SKILL": "Skill: {nome}",
      "TEXTO_FINAL_ERRO": "Could not load the text right now.",
      "FECHAR": "Close"
    },
    "CAIXAS": {
      "TITULO": "Connected inboxes — {nome}"
    },
    "VIGIA": {
      "CONVERSA": "Open the conversation",
      "NO_LIMITE": "At the end of the follow-up ladder"
    },
    "CASO_IA": {
      "TITULO": "What the AI did in this case",
      "AGENTE": "Claude agent: {nome}",
      "VAZIO": "The AI has not done anything in this case yet.",
      "ERRO": "Could not load right now."
    },
    "CADERNO": {
      "NOTURNO": "Run by itself at dawn (05:30), if something changed",
      "NOTURNO_AJUDA": "Applies to every assistant. Runs the active cases when a skill, FAQ, setting or case changed since the last run, and skips the day spending passed the cap (Usage and cost). Estimate: {n} per run of this assistant.",
      "NOTURNO_LIGADO": "Dawn run on.",
      "NOTURNO_DESLIGADO": "Dawn run off."
    }
  }
}
```

- [ ] **Step 5: Valores trocados em `integrations.json`** (Edit, só o valor; os dois arquivos):

| Chave (`CAPTAIN.…`) | pt_BR hoje → novo | en hoje → novo |
|---|---|---|
| `ASSISTANTS.FORM.PRODUCT_NAME.LABEL` | "Nome do Produto" → "Nome do escritório" | "Product Name" → "Firm name" |
| `ASSISTANTS.FORM.PRODUCT_NAME.PLACEHOLDER` | "Digite o nome do produto" → "Ex.: Ramon Antonio Advogados" | "Enter product name" → "E.g.: Ramon Antonio Advogados" |
| `ASSISTANTS.FORM.PRODUCT_NAME.ERROR` | "O nome do produto é obrigatório" → "O nome do escritório é obrigatório" | "The product name is required" → "The firm name is required" |
| `ASSISTANTS.FORM.TEMPERATURE.LABEL` | "Temperatura da resposta" → "Criatividade (baixa = mais previsível)" | "Response Temperature" → "Creativity (low = more predictable)" |
| `ASSISTANTS.FORM.TEMPERATURE.DESCRIPTION` | "Ajuste o quão criativo ou restritivo as respostas do assistente devem ser. Valores mais baixos produzem respostas mais focadas e deterministas, enquanto valores mais altos permitem resultados mais criativos e variados." → "Mais baixa: respostas parecidas e presas às regras. Mais alta: textos mais variados. Para atendimento jurídico, prefira entre 0,2 e 0,4." | "Adjust how creative or restrictive the assistant's responses should be. Lower values produce more focused and deterministic responses, while higher values allow for more creative and varied outputs." → "Lower: similar answers that stick to the rules. Higher: more varied text. For legal service, prefer 0.2 to 0.4." |
| `ASSISTANTS.FORM.FEATURES.ALLOW_MEMORIES` | "Capture os principais detalhes como memórias de interações do cliente." → "Memória do contato: ao resolver a conversa, anotar no lead o que a IA aprendeu" | "Capture key details as memories from customer interactions." → "Contact memory: when the conversation is resolved, note on the lead what the AI learned" |
| `INBOXES.DELETE.DESCRIPTION` | "" → "O assistente para de agir nas conversas desta caixa. Dá para conectar de novo quando quiser." | "" → "The assistant stops acting on this inbox's conversations. You can connect it again anytime." |
| `INBOXES.DELETE.CONFIRM` (pt_BR linha ~1055; en no mesmo bloco) | "Sim, excluir" → "Sim, desconectar" | "Yes, delete" → "Yes, disconnect" |
| `INBOXES.FORM.INBOX.PLACEHOLDER` | "Selecione a caixa de entrada para implantar o assistente." → "Escolha a caixa onde o assistente vai atuar." | "Choose the inbox to deploy the assistant." → "Choose the inbox where the assistant will work." |

`"Sim, excluir"` aparece em vários blocos: no Edit, use como âncora as 3 linhas do bloco `INBOXES.DELETE` (`"TITLE": "Tem certeza que deseja desconectar a caixa de entrada?",` / `"DESCRIPTION": "",` / `"CONFIRM": "Sim, excluir",`) — idem no en (`"TITLE": "Are you sure to disconnect the inbox?",`). As descrições longas da `TEMPERATURE` são trocadas inteiras (âncora = a linha toda). Conferir antes de editar que cada valor "hoje" bate com o arquivo (`grep -n` do texto).

- [ ] **Step 6: Rótulo da função nova em Uso e custo** — `pt_BR/ramonIaUso.json` (Edit): `"teste": "Casos de teste"` → `"teste": "Casos de teste",` + nova linha `"memoria_contato": "Memória do contato"`; `en/ramonIaUso.json`: `"teste": "Test cases"` → `"teste": "Test cases",` + `"memoria_contato": "Contact memory"`.

- [ ] **Step 7: Rodar e ver passar**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js app/javascript/dashboard/routes/dashboard/captain/pages/specs/UsoCustoI18n.spec.js --config vitest.local.config.ts
node -e "for (const l of ['en','pt_BR']) { JSON.parse(require('fs').readFileSync('app/javascript/dashboard/i18n/locale/'+l+'/integrations.json','utf8')); } console.log('json ok')"
```
Expected: os dois specs verdes; `json ok`.

- [ ] **Step 8: Commit**

```bash
git add app/javascript/dashboard/i18n/locale/en/ramonIntel.json app/javascript/dashboard/i18n/locale/pt_BR/ramonIntel.json app/javascript/dashboard/routes/dashboard/captain/pages/specs/IntelI18n.spec.js app/javascript/dashboard/i18n/locale/en/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/integrations.json app/javascript/dashboard/i18n/locale/en/ramonIaUso.json app/javascript/dashboard/i18n/locale/pt_BR/ramonIaUso.json
git commit -m "feat(inteligencia): textos da A5 (Testar, Skills, Configurações, Caixas, Vigia, caderno e memória)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 3: Assistentes — "Atendimento" e "Copiloto do Escritório", sem a marca morta (I-AS4, I-AS5) (mecânica)

**Files:**
- Modify: `db/seeds/ramon/inteligencia/assistentes.yml:8,15,126`, `lib/ramon/inteligencia_seed.rb:6,32-43`, `db/seeds/ramon/ia_casos.yml:16,196`, `enterprise/app/models/captain/assistant.rb:39-49`
- Test: `spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb`, `spec/lib/tasks/rake/task_ramon_ia_spec.rb`, `spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb:212-217`

**Interfaces:**
- Produces: assistentes do seed chamados `Atendimento` e `Copiloto do Escritório`; campo `antes:` (lista de nomes antigos) no yml; `Ramon::InteligenciaSeed::ATENDIMENTO = 'Atendimento'`.

- [ ] **Step 1: Specs (falham antes)** — em `spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb`, trocar `find_by!(name: 'Atendimento (rascunho)')` por `find_by!(name: 'Atendimento')` (linha 11) e acrescentar, dentro do `describe 'ramon:inteligencia:seed'`, depois do 1º `it`:

```ruby
    it 'renomeia o assistente pelo nome antigo e tira a marca morta (I-AS4, I-AS5)', :aggregate_failures do
      antigo = create(:captain_assistant, account: account, name: 'Atendimento (rascunho)',
                                          config: { 'ramon_modo_rascunho' => true })
      copiloto = create(:captain_assistant, account: account, name: 'Copiloto do Escritorio')

      rodar
      rodar

      expect(antigo.reload.name).to eq('Atendimento')
      expect(antigo.config).not_to have_key('ramon_modo_rascunho')
      expect(copiloto.reload.name).to eq('Copiloto do Escritório')
      expect(account.captain_assistants.count).to eq(2)
    end
```
Em `spec/lib/tasks/rake/task_ramon_ia_spec.rb`: linhas 11–12 viram `name: 'Atendimento'` e `name: 'Copiloto do Escritório'`; linha 51 `rodar('Atendimento')`.
Em `spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb`, trocar

```ruby
    context 'when the ramon draft mode is on' do
      before do
        allow(account).to receive(:feature_enabled?).and_return(false)
        allow(account).to receive(:feature_enabled?).with('captain_integration_v2').and_return(true)
        assistant.update!(config: assistant.config.merge('ramon_modo_rascunho' => true))
      end
```
por
```ruby
    # ramon: o rascunho vem do modo da conversa (Ramon::CopilotoModo, padrão rascunho) — não de marca no assistente
    context 'when the conversation uses the default draft mode' do
      before do
        allow(account).to receive(:feature_enabled?).and_return(false)
        allow(account).to receive(:feature_enabled?).with('captain_integration_v2').and_return(true)
      end
```

- [ ] **Step 2: yml** — `db/seeds/ramon/inteligencia/assistentes.yml`:
  - linha 8 `  - name: Atendimento (rascunho)` vira as 3 linhas:
    ```yaml
      - name: Atendimento
        # nome antigo: o seed renomeia em vez de criar outro (I-AS4)
        antes: ['Atendimento (rascunho)']
    ```
  - apagar a linha 15 `      ramon_modo_rascunho: true`.
  - linha 126 `  - name: Copiloto do Escritorio` vira:
    ```yaml
      - name: Copiloto do Escritório
        antes: ['Copiloto do Escritorio']
    ```
  - acrescentar ao comentário do topo (linha 2) a frase: `# Renomear assistente: troque name e ponha o nome velho em antes: (o seed acha pelos dois).`
  `db/seeds/ramon/ia_casos.yml`: linha 16 `  - nome: Atendimento`; linha 196 `  - nome: Copiloto do Escritório`.

- [ ] **Step 3: Seed** — `lib/ramon/inteligencia_seed.rb`: linha 6 `ATENDIMENTO = 'Atendimento'.freeze`; trocar o método `seed_assistente` (linhas 32–43) por:

```ruby
  def seed_assistente(dados)
    assistant = achar_assistente(dados)
    @contagem[assistant.new_record? ? :assistentes_criados : :assistentes_atualizados] += 1
    assistant.assign_attributes(
      name: dados['name'],
      description: dados['description'],
      # ramon_modo_rascunho: marca morta (ninguém lia; o modo é por conversa — I-AS4)
      config: (assistant.config || {}).except('ramon_modo_rascunho').merge(dados['config'] || {}),
      response_guidelines: dados['response_guidelines'],
      guardrails: dados['guardrails']
    )
    assistant.save!
    seed_skills(assistant, dados['skills'] || [])
  end

  # Renomear no yml não cria outro assistente: acha pelo nome de hoje ou por um dos antigos (campo antes:).
  def achar_assistente(dados)
    @account.captain_assistants.find_by(name: [dados['name'], *dados['antes']]) ||
      @account.captain_assistants.new(name: dados['name'])
  end
```
E no comentário do topo da classe (linha 3), `assistente por name` vira `assistente por name (ou antes:)`.

- [ ] **Step 4: Modelo** — `enterprise/app/models/captain/assistant.rb`, trocar as linhas 39–49:

```ruby
  store_accessor :config, :temperature, :feature_faq, :feature_memory, :feature_contact_attributes, :product_name,
                 :ramon_modo_rascunho

  # ramon: agente de atendimento com humano no meio (Fatia 2 da area de IA).
  # Ligado, nada que o agente escreve chega ao cliente — a resposta vira nota
  # privada RASCUNHO na conversa e quem envia e o atendente. Sem tela: ligar e
  # desligar e operacao de console, de proposito (desligar solta a IA no
  # cliente, e isso e decisao do Eduardo, nao de um clique).
  def modo_rascunho?
    ActiveModel::Type::Boolean.new.cast(ramon_modo_rascunho).present?
  end
```
por
```ruby
  # ramon: o modo (rascunho / piloto) é por conversa — Ramon::CopilotoModo; não há marca no assistente.
  store_accessor :config, :temperature, :feature_faq, :feature_memory, :feature_contact_attributes, :product_name
```
Conferir que ninguém chama `modo_rascunho?`/`ramon_modo_rascunho`: `grep -rn "modo_rascunho" app enterprise lib spec db config` → só o comentário novo.

- [ ] **Step 5: Rastrear à mão (sem Ruby local)** — no spec novo: 1ª `rodar` acha `antigo` por `find_by(name: ['Atendimento', 'Atendimento (rascunho)'])`, troca o nome e tira a chave; acha o copiloto por `['Copiloto do Escritório', 'Copiloto do Escritorio']`; 2ª `rodar` acha pelos nomes novos → `count == 2`. `upsert_faq` usa `ATENDIMENTO = 'Atendimento'` → acha. Rubocop: `achar_assistente` 3 linhas; `seed_assistente` 13 linhas, AbcSize ~17.

- [ ] **Step 6: Commit**

```bash
git add db/seeds/ramon/inteligencia/assistentes.yml lib/ramon/inteligencia_seed.rb db/seeds/ramon/ia_casos.yml enterprise/app/models/captain/assistant.rb spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb spec/lib/tasks/rake/task_ramon_ia_spec.rb spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb
git commit -m "feat(inteligencia): assistentes Atendimento e Copiloto do Escritório, sem a marca morta do rascunho (I-AS4, I-AS5)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 4: Skills (backend) — fala de exemplo, papéis e uso em 30 dias (I-SK6, I-SK7, I-X5) (mecânica)

**Files:**
- Create: `db/migrate/20261007800001_add_exemplo_e_papeis_to_captain_scenarios.rb`
- Modify: `db/schema.rb` (bloco `captain_scenarios` e `define(version:)`), `enterprise/app/controllers/api/v1/accounts/captain/scenarios_controller.rb`, `enterprise/app/views/api/v1/models/captain/_scenario.json.jbuilder`, `enterprise/app/views/api/v1/accounts/captain/scenarios/index.json.jbuilder`, `lib/ramon/inteligencia_seed.rb` (`seed_skill`), `db/seeds/ramon/inteligencia/assistentes.yml` (uma `exemplo:` por skill e `papeis:` nas do Copiloto)
- Test: `spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb`, `spec/enterprise/controllers/api/v1/accounts/captain/scenarios_controller_spec.rb`

**Interfaces:**
- Consumes: Task 3 (nomes novos no yml).
- Produces: `captain_scenarios.exemplo` (text) e `captain_scenarios.papeis` (jsonb, lista de nomes de time, default `[]`); JSON da skill ganha `exemplo`, `papeis`; o `index` ganha `uso_30d` (inteiro) por skill; `scenario_params` aceita `exemplo` e `papeis: []`.

- [ ] **Step 1: Specs (falham antes)** — em `task_ramon_inteligencia_spec.rb`, acrescentar:

```ruby
    it 'grava fala de exemplo e papeis do yml; skill editada so ganha o que esta vazio (A5)', :aggregate_failures do
      rodar
      copiloto = account.captain_assistants.find_by!(name: 'Copiloto do Escritório')
      skill = copiloto.scenarios.find_by!(seed_titulo: 'Funil hoje')
      expect(skill).to have_attributes(exemplo: 'Como está o funil hoje?', papeis: ['comercial'])

      skill.update!(edited: true, exemplo: 'Minha fala')
      skill.update_columns(papeis: []) # rubocop:disable Rails/SkipsModelValidations
      rodar

      expect(skill.reload).to have_attributes(exemplo: 'Minha fala', papeis: ['comercial'])
      expect(account.captain_assistants.find_by!(name: 'Atendimento').scenarios.where(exemplo: nil).count).to eq(0)
    end
```
Em `spec/enterprise/controllers/api/v1/accounts/captain/scenarios_controller_spec.rb`, no `describe` do `GET index` (seguir o padrão de `let`/headers do arquivo):

```ruby
    it 'soma o uso de 30 dias das ferramentas de cada skill, sem Testar nem caso de teste (I-SK7)' do
      # tools vem da instrução (Captain::Scenario#resolve_tool_references)
      skill = create(:captain_scenario, assistant: assistant, account: account,
                                        instruction: 'Use [Mover](tool://mover_etapa) e [FAQ](tool://faq_lookup).')
      base = { account_id: account.id, assistant_id: assistant.id, status: 'ok' }
      Captain::ToolRun.create!(base.merge(tool_name: 'mover_etapa'))
      Captain::ToolRun.create!(base.merge(tool_name: 'faq_lookup'))
      Captain::ToolRun.create!(base.merge(tool_name: 'faq_lookup', source: 'playground'))
      Captain::ToolRun.create!(base.merge(tool_name: 'faq_lookup', source: 'teste'))
      Captain::ToolRun.create!(base.merge(tool_name: 'mover_etapa', created_at: 31.days.ago))

      get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/scenarios",
          headers: admin.create_new_auth_token, as: :json

      linha = response.parsed_body['payload'].find { |item| item['id'] == skill.id }
      expect(linha).to include('uso_30d' => 2, 'papeis' => [], 'exemplo' => nil)
    end
```
(O arquivo já tem `let(:account)`, `let(:admin)` e `let(:assistant)`; o exemplo vai dentro do `describe 'GET …/scenarios'`.)

- [ ] **Step 2: Migração** — `db/migrate/20261007800001_add_exemplo_e_papeis_to_captain_scenarios.rb`:

```ruby
# Skills (Inteligência A5): fala de exemplo para "Testar esta skill" (I-SK6) e papéis (nomes de time)
# que mais usam a skill — o Testar mostra primeiro as do seu papel (I-X5).
class AddExemploEPapeisToCaptainScenarios < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_scenarios, :exemplo, :text
    add_column :captain_scenarios, :papeis, :jsonb, default: [], null: false
  end
end
```
`db/schema.rb`: no bloco `create_table "captain_scenarios"`, depois de `    t.string "seed_titulo"`, acrescentar:

```ruby
    t.text "exemplo"
    t.jsonb "papeis", default: [], null: false
```
e a 1ª linha `ActiveRecord::Schema[7.1].define(version: 2026_10_07_500002) do` vira `…define(version: 2026_10_07_800001) do`.

- [ ] **Step 3: Controller e JSON** — `scenarios_controller.rb`:

```ruby
  def index
    # ramon: ligadas e desligadas (I-SK4) — a tela separa em abas; o agente segue só com as ligadas.
    @scenarios = assistant_scenarios.order(enabled: :desc, id: :asc)
    @uso = uso_30d
  end
```
e, em `private`, antes de `scenario_params`:

```ruby
  # ramon (I-SK7): quantas vezes cada ferramenta deste assistente rodou no atendimento de verdade em 30 dias —
  # Testar (playground) e Casos de teste não contam. A tela soma as ferramentas de cada skill.
  def uso_30d
    Captain::ToolRun.fora_de_teste
                    .where(account_id: Current.account.id, assistant_id: @assistant.id, created_at: 30.days.ago..)
                    .where("#{Captain::ToolRun.table_name}.source IS DISTINCT FROM 'playground'")
                    .group(:tool_name).count
  end
```
`scenario_params`: `params.require(:scenario).permit(:title, :description, :instruction, :enabled, :exemplo, tools: [], papeis: [])`.
`_scenario.json.jbuilder`, depois de `json.edited scenario.edited`:

```ruby
json.exemplo scenario.exemplo
json.papeis scenario.papeis
```
`scenarios/index.json.jbuilder`, dentro do `json.array!`:

```ruby
json.payload do
  json.array! @scenarios do |scenario|
    json.partial! 'api/v1/models/captain/scenario', scenario: scenario
    json.uso_30d scenario.tools.to_a.sum { |tool| @uso[tool].to_i }
  end
end
```

- [ ] **Step 4: Seed** — `lib/ramon/inteligencia_seed.rb`, trocar `seed_skill` por:

```ruby
  # Acha pela origem no yml (sobrevive a renomear na tela) e, nas antigas, pelo título.
  def seed_skill(assistant, skill)
    scenario = assistant.scenarios.find_by(seed_titulo: skill['title']) ||
               assistant.scenarios.find_or_initialize_by(title: skill['title'])
    return completar_editada(scenario, skill) if scenario.edited?

    @contagem[scenario.new_record? ? :skills_criadas : :skills_atualizadas] += 1
    scenario.update!(account: @account, description: skill['description'], instruction: skill['instruction'],
                     enabled: true, seed_titulo: skill['title'], exemplo: skill['exemplo'], papeis: skill['papeis'] || [])
  end

  # Editada na tela (I-SK5): o seed não mexe — só preenche fala de exemplo e papéis ainda vazios (A5).
  def completar_editada(scenario, skill)
    scenario.update_columns(exemplo: scenario.exemplo.presence || skill['exemplo'], # rubocop:disable Rails/SkipsModelValidations
                            papeis: scenario.papeis.presence || skill['papeis'] || [])
    @contagem[:skills_puladas_editadas] += 1
  end
```

- [ ] **Step 5: yml** — em `db/seeds/ramon/inteligencia/assistentes.yml`, logo depois da linha `description:` de cada skill, acrescentar (8 espaços de recuo, como `description:`):

| Skill (`title:` no yml) | `exemplo:` | `papeis:` |
|---|---|---|
| Triagem e qualificação do lead novo | `'Oi, me machuquei no trabalho ano passado e fiquei com limitação na mão. Tenho direito a alguma coisa?'` | — |
| Dúvidas do lead e objeções | `'Quanto vocês cobram? Tenho medo de pagar e não dar em nada.'` | — |
| Estimar valor do benefício e honorário | `'Quanto eu vou receber de auxílio-acidente?'` | — |
| Agendar conversa com o advogado | `'Pode ser, quero conversar com o advogado. Que dia tem?'` | — |
| Fechar contrato | `'Decidi, quero fechar com vocês. Como faço?'` | — |
| Pós-venda — cobrar e receber documentos | `'Já assinei o contrato. Quais documentos eu preciso mandar?'` | — |
| Situacao do processo | `'Qual a situação do processo deste cliente?'` | `[recepção, controladoria, advogados]` |
| Consultas no AdvBox | `'Quais prazos vencem esta semana no AdvBox?'` | `[controladoria, advogados]` |
| Escrever no AdvBox | `'Crie uma tarefa no AdvBox para conferir o laudo deste caso amanhã.'` | `[controladoria, advogados]` |
| Anotar atendimento ou pedir por tarefa | `'Anote no processo deste caso que a cliente ligou pedindo notícia da perícia.'` | `[recepção, controladoria, advogados]` |
| Lancar andamento do INSS | `'Lance no AdvBox as novidades do INSS desta semana.'` | `[controladoria]` |
| Explicar andamento ao cliente | `'Escreva a mensagem para o cliente deste caso explicando o andamento.'` | `[recepção, controladoria]` |
| Preparar reuniao | `'Prepare a reunião deste caso.'` | `[comercial]` |
| Historico da pessoa | `'Mostre o histórico da pessoa deste caso.'` | `[recepção, comercial]` |
| Revisao de documentos do caso | `'O que falta de documento neste caso?'` | `[comercial, controladoria]` |
| Funil hoje | `'Como está o funil hoje?'` | `[comercial]` |
| Agenda do dia | `'O que tenho na agenda hoje?'` | `[recepção, comercial, advogados]` |
| Playbook da tese | `'Quais os critérios do auxílio-acidente?'` | `[comercial]` |

Exemplo do resultado:

```yaml
      - title: Funil hoje
        description: Números do funil e do dia — meta, conversão por etapa, SLA, perdas por tese.
        exemplo: 'Como está o funil hoje?'
        papeis: [comercial]
```
(Papéis = a tabela da decisão **N6**; se o Eduardo ajustar, mudar aqui. Os nomes têm de ser **idênticos** aos dos times do hub — `recepção` com acento, como `Chegada::RECEPCAO`.) Sem Ruby local, o YAML é validado pelo spec do seed no CI; à mão, conferir que todo `exemplo:` novo está entre aspas simples e que nenhum tem aspas simples dentro.

- [ ] **Step 6: Rastrear à mão** — spec do seed: 1ª `rodar` cria "Funil hoje" com `exemplo` e `papeis: ['comercial']`; `update!(edited: true, exemplo:)` passa pela validação (instrução do seed é válida); `update_columns(papeis: [])`; 2ª `rodar` cai em `completar_editada`: `exemplo` fica 'Minha fala' (presente), `papeis` vazio → `['comercial']`. Todas as skills do Atendimento ganharam `exemplo` → `where(exemplo: nil).count == 0`. Spec do controller: `fora_de_teste` tira 'teste'; o `where` tira 'playground'; 31 dias fica fora → mover_etapa 1 + faq_lookup 1 = 2. Rubocop: `uso_30d` 4 linhas; `seed_skill` 8; linhas < 150.

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20261007800001_add_exemplo_e_papeis_to_captain_scenarios.rb db/schema.rb enterprise/app/controllers/api/v1/accounts/captain/scenarios_controller.rb enterprise/app/views/api/v1/models/captain/_scenario.json.jbuilder enterprise/app/views/api/v1/accounts/captain/scenarios/index.json.jbuilder lib/ramon/inteligencia_seed.rb db/seeds/ramon/inteligencia/assistentes.yml spec/lib/tasks/rake/task_ramon_inteligencia_spec.rb spec/enterprise/controllers/api/v1/accounts/captain/scenarios_controller_spec.rb
git commit -m "feat(skills): fala de exemplo, papéis e uso em 30 dias por skill (I-SK6, I-SK7, I-X5)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 5: Tela Skills — "Testar esta skill", uso em 30 dias, papéis, seletor e kit (I-SK6, I-SK7, I-X5, I-T4, I-T5) (julgamento: layout no print)

**Files:**
- Modify: `app/javascript/dashboard/components-next/captain/assistant/ScenariosCard.vue`, `app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/Index.vue`
- Test: `app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js`, `app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/specs/Index.spec.js`

**Interfaces:**
- Consumes: Task 4 (`exemplo`, `papeis`, `uso_30d` no JSON da skill); Task 2 (`INTEL.SKILLS.*`); getter `teams/getTeams` (lista `{ id, name }`).
- Produces: `ScenariosCard` com props novas `exemplo: String`, `papeis: Array`, `usoMes: Number|null` e evento `testar`; o `update` emitido passa a levar `exemplo` e `papeis`. A tela abre `captain_assistants_playground_index` com `query: { fala: <exemplo> }` (a Task 8 lê).

- [ ] **Step 1: Specs (falham antes)** — em `ScenariosCard.spec.js` acrescentar:

```js
describe('ScenariosCard — A5', () => {
  it('"Testar esta skill" só com fala de exemplo e emite testar', async () => {
    expect(
      montar([]).find('[data-testid="skill-testar"]').exists()
    ).toBe(false);
    const wrapper = montar([], { exemplo: 'Como está o funil hoje?' });
    await wrapper.find('[data-testid="skill-testar"]').trigger('click');
    expect(wrapper.emitted('testar')).toHaveLength(1);
  });

  it('mostra o uso de 30 dias e os papéis', () => {
    const wrapper = montar([], { usoMes: 4, papeis: ['comercial'] });
    expect(wrapper.find('[data-testid="skill-uso"]').text()).toBe(
      'INTEL.SKILLS.USO_30D'
    );
    expect(
      wrapper.findAll('[data-testid="skill-papel"]').map(c => c.text())
    ).toEqual(['comercial']);
    expect(
      montar([], { usoMes: 0 }).find('[data-testid="skill-uso"]').text()
    ).toBe('INTEL.SKILLS.SEM_USO_30D');
  });
});
```
Em `Index.spec.js`: no topo, `const { push } = vi.hoisted(() => ({ push: vi.fn() }));` (o `vi.mock` é içado — a variável tem de vir de `vi.hoisted`); no `vi.mock('vue-router', …)` acrescentar `useRouter: () => ({ push })`; no `createStore` acrescentar o módulo

```js
      teams: {
        namespaced: true,
        getters: { getTeams: () => [] },
        actions: { get: () => {} },
      },
```
e o teste:

```js
describe('Skills — Testar esta skill', () => {
  it('abre o Testar do mesmo assistente com a fala de exemplo', async () => {
    const wrapper = montar();
    wrapper
      .findAllComponents({ name: 'ScenariosCard' })[0]
      .vm.$emit('testar');
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'captain_assistants_playground_index',
        query: { fala: 'Fala A' },
      })
    );
  });
});
```
(e no `scenarios` do `montar`, a 1ª skill ganha `exemplo: 'Fala A'`.)

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/specs/Index.spec.js --config vitest.local.config.ts` → FAIL nos testes novos.

- [ ] **Step 3: `ScenariosCard.vue`**
  - props, depois de `podeLigar`:
    ```js
      // ramon (A5): fala de exemplo (I-SK6), papéis = nomes de time (I-X5), uso em 30 dias (I-SK7; null = não veio)
      exemplo: { type: String, default: '' },
      papeis: { type: Array, default: () => [] },
      usoMes: { type: Number, default: null },
    ```
  - `defineEmits(['select', 'hover', 'delete', 'update', 'toggle', 'testar'])`.
  - `state` ganha `exemplo: ''` e `papeis: []`; `startEdit` copia `exemplo: props.exemplo || ''` e `papeis: [...props.papeis]`.
  - logo depois de `const ferramentas = computed(...)`:
    ```js
    const timesGetter = useMapGetter('teams/getTeams');
    const times = computed(() => timesGetter.value || []);
    const marcarPapel = (nome, marcado) => {
      state.papeis = marcado
        ? [...state.papeis, nome]
        : state.papeis.filter(papel => papel !== nome);
    };
    const usoTexto = computed(() =>
      props.usoMes
        ? t('INTEL.SKILLS.USO_30D', { n: props.usoMes })
        : t('INTEL.SKILLS.SEM_USO_30D')
    );
    ```
  - `LINK_INSTRUCTION_CLASS`: `text-n-iris-11` → `text-n-blue-11` (I-T5).
  - template, modo leitura: logo depois do `<span class="text-sm text-n-slate-11 mt-2">{{ description }}</span>`, ainda dentro de `<div class="flex flex-col items-start">`:
    ```vue
          <div class="flex flex-wrap items-center gap-1.5 mt-2">
            <span
              v-for="papel in papeis"
              :key="papel"
              data-testid="skill-papel"
              :class="[CHIP, TOM.slate]"
            >
              {{ papel }}
            </span>
            <span
              v-if="usoMes !== null"
              data-testid="skill-uso"
              :class="[CHIP, usoMes ? TOM.blue : TOM.slate]"
              :title="t('INTEL.SKILLS.USO_AJUDA')"
            >
              {{ usoTexto }}
            </span>
            <button
              v-if="exemplo && enabled"
              type="button"
              data-testid="skill-testar"
              class="hover:brightness-110"
              :class="[CHIP, TOM.blue]"
              :title="exemplo"
              @click="emit('testar')"
            >
              <span class="i-lucide-flask-conical size-3" />
              {{ t('INTEL.SKILLS.TESTAR') }}
            </button>
          </div>
    ```
  - template, modo edição: depois do `<Editor …/>` e antes do bloco dos botões:
    ```vue
      <Input
        v-model="state.exemplo"
        :label="t('INTEL.SKILLS.EXEMPLO_LABEL')"
        :placeholder="t('INTEL.SKILLS.EXEMPLO_PLACEHOLDER')"
      />
      <fieldset v-if="times.length" class="flex flex-col gap-1.5">
        <legend class="mb-1 text-sm text-n-slate-12">
          {{ t('INTEL.SKILLS.PAPEIS_LABEL') }}
        </legend>
        <label
          v-for="time in times"
          :key="time.id"
          class="flex items-center gap-2 text-sm text-n-slate-11"
        >
          <Checkbox
            :model-value="state.papeis.includes(time.name)"
            @update:model-value="marcado => marcarPapel(time.name, marcado)"
          />
          {{ time.name }}
        </label>
      </fieldset>
    ```

- [ ] **Step 4: `scenarios/Index.vue`**
  - `import { useRoute, useRouter } from 'vue-router';` e `const router = useRouter();`.
  - `LINK_INSTRUCTION_CLASS`: `text-n-iris-11` → `text-n-blue-11`.
  - depois de `alternarSkill`:
    ```js
    // I-SK6: abre o Testar do mesmo assistente com a fala de exemplo no campo (quem envia é você — N7).
    const testarSkill = scenario =>
      router.push({
        name: 'captain_assistants_playground_index',
        params: { ...route.params },
        query: { fala: scenario.exemplo },
      });
    ```
  - `onMounted`: acrescentar `store.dispatch('teams/get');` (papéis no editar).
  - `<PageLayout …>`: acrescentar `show-assistant-switcher` (I-T4 — a Task 11 muda o padrão do `PageLayout` para "sem seletor").
  - no `<ScenariosCard …>`: acrescentar `:exemplo="scenario.exemplo || ''"`, `:papeis="scenario.papeis || []"`, `:uso-mes="scenario.uso_30d ?? null"` e `@testar="testarSkill(scenario)"`.

- [ ] **Step 5: Rodar e ver passar** — o mesmo comando do Step 2 (todos verdes, inclusive os antigos) + `./node_modules/.bin/eslint app/javascript/dashboard/components-next/captain/assistant/ScenariosCard.vue app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/Index.vue` sem `error`.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/components-next/captain/assistant/ScenariosCard.vue app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/Index.vue app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/specs/Index.spec.js
git commit -m "feat(skills): Testar esta skill, uso em 30 dias e papéis na tela de Skills (I-SK6, I-SK7, I-X5)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 6: Assistente (backend) — ferramentas usadas no Testar e texto final (I-PG2, I-CF6) (mecânica)

**Files:**
- Modify: `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb`, `enterprise/app/policies/captain/assistant_policy.rb`, `config/routes.rb` (member de `captain/assistants`), `app/javascript/dashboard/api/captain/assistant.js`
- Test: `spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb`

**Interfaces:**
- Produces: `POST captain/assistants/:id/playground` devolve, além do de antes, `ferramentas: [{ id, title, nivel, status: 'ok'|'erro' }]` (na ordem em que rodaram; só no modo agente/v2). `GET captain/assistants/:id/texto_final` → `{ assistente: String, skills: [{ title, texto }] }`. Front: `CaptainAssistant.textoFinal(assistantId)`.

- [ ] **Step 1: Specs (documentação — `spec/enterprise` não roda no CI FOSS)** — no `describe '…/playground'`, contexto `'when captain v2 is enabled'`: nos dois `allow(Captain::Assistant::AgentRunnerService).to receive(:new).with(assistant: assistant, source: 'playground')` trocar o `.with(...)` por `.with(hash_including(assistant: assistant, source: 'playground'))`, e acrescentar:

```ruby
      it 'devolve as ferramentas que rodaram, com nome e erro (I-PG2)' do
        allow(Captain::Assistant::AgentRunnerService).to receive(:new) do |**args|
          coletor = args[:callbacks][:on_tool_complete]
          coletor.call('captain-tools-mover_etapa', 'movido', nil)
          coletor.call('captain-tools-checar_prescricao', Captain::Tools::BasePublicTool::ERRO_NA_TOOL, nil)
          agent_runner_service
        end
        allow(agent_runner_service).to receive(:generate_response).and_return({ 'response' => 'ok' })

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: valid_params, headers: agent.create_new_auth_token, as: :json

        expect(json_response[:ferramentas]).to eq(
          [{ id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao', status: 'ok' },
           { id: 'checar_prescricao', title: 'Checar prescrição', nivel: 'consulta', status: 'erro' }]
        )
      end
```
(Conferir os `title`/`nivel` exatos de `mover_etapa` e `checar_prescricao` em `config/agents/tools.yml` e ajustar o esperado.) E um `describe` novo:

```ruby
  describe 'GET /api/v1/accounts/{account.id}/captain/assistants/{id}/texto_final' do
    it 'junta o texto do assistente e o de cada skill ligada (I-CF6)', :aggregate_failures do
      assistant = create(:captain_assistant, account: account, guardrails: ['Nunca prometa prazo do INSS.'])
      create(:captain_scenario, assistant: assistant, account: account, title: 'Funil hoje')
      create(:captain_scenario, assistant: assistant, account: account, title: 'Desligada', enabled: false)

      get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/texto_final",
          headers: agent.create_new_auth_token, as: :json

      expect(json_response[:assistente]).to include('Nunca prometa prazo do INSS.')
      expect(json_response[:skills].pluck(:title)).to eq(['Funil hoje'])
    end
  end
```

- [ ] **Step 2: Controller** — `before_action :set_assistant, only: [:show, :update, :destroy, :playground, :buscar_faq, :texto_final]`. Trocar o método `playground` (linhas 26–39) por:

```ruby
  def playground
    return render(json: playground_legado) unless captain_v2_enabled?

    # ramon (I-PG2): as ferramentas que rodaram nesta resposta vão junto, para o Testar mostrar debaixo dela.
    ferramentas = []
    coletor = ->(nome, retorno, *) { ferramentas << ferramenta_usada(nome, retorno) }
    runner = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, source: 'playground',
                                                        callbacks: { on_tool_complete: coletor })
    render json: runner.generate_response(message_history: playground_message_history).merge('ferramentas' => ferramentas)
  end
```
Depois de `buscar_faq`:

```ruby
  # ramon (I-CF6): o texto final que o assistente recebe — o dele (diretrizes, proteções e a lista de skills,
  # montados pelo liquid) e o de cada skill ligada. Só leitura.
  def texto_final
    skills = @assistant.scenarios.enabled.order(:id).map { |skill| { title: skill.title, texto: skill.agent_instructions } }
    render json: { assistente: @assistant.agent_instructions, skills: skills }
  end
```
Em `private`, depois de `set_assistant`:

```ruby
  def playground_legado
    Captain::Llm::AssistantChatService.new(assistant: @assistant, source: 'playground').generate_response(
      additional_message: playground_params[:message_content], message_history: message_history
    )
  end

  # RubyLLM::Tool#name = "captain-tools-<id>"; erro = o aviso que o BasePublicTool devolve quando a ferramenta falha.
  def ferramenta_usada(nome, retorno)
    id = nome.to_s.split('-').last
    info = Captain::Assistant.built_in_agent_tools.find { |tool| tool[:id] == id } || {}
    { id: id, title: info[:title] || id, nivel: info[:nivel],
      status: retorno.to_s == Captain::Tools::BasePublicTool::ERRO_NA_TOOL ? 'erro' : 'ok' }
  end
```

- [ ] **Step 3: Policy e rota** — `assistant_policy.rb`, depois de `buscar_faq?`:

```ruby
  def texto_final?
    true
  end
```
`config/routes.rb`, no `member` de `resources :assistants` (depois de `get :buscar_faq`): `get :texto_final`.
`api/captain/assistant.js`, depois de `buscarFaq`:

```js
  // ramon: texto final que o assistente recebe (I-CF6).
  textoFinal(assistantId) {
    return axios.get(`${this.url}/${assistantId}/texto_final`);
  }
```

- [ ] **Step 4: Rastrear à mão** — `generate_response` devolve Hash (com chaves string do `process_agent_result` ou símbolo no stub); `.merge('ferramentas' => …)` funciona nos dois; o coletor recebe `(tool_name, tool_result, context_wrapper)` (mesma assinatura do `IaRodadaService#executar`). Rubocop: `playground` 7 linhas; `ferramenta_usada` 4; `texto_final` linha < 150. ClassLength: o controller passa de ~110 para ~130 linhas de código.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb enterprise/app/policies/captain/assistant_policy.rb config/routes.rb app/javascript/dashboard/api/captain/assistant.js spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb
git commit -m "feat(ia): Testar devolve as ferramentas usadas e endpoint do texto final do assistente (I-PG2, I-CF6)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 7: Testar — conversa: ferramentas debaixo da resposta, conversa guardada, bolhas no kit (I-PG2, I-PG3, I-T5) (julgamento: bolhas no print)

**Files:**
- Create: `app/javascript/dashboard/components-next/captain/assistant/testarConversas.js`, `app/javascript/dashboard/components-next/captain/assistant/specs/testarConversas.spec.js`, `app/javascript/dashboard/components-next/captain/assistant/specs/AssistantPlayground.spec.js`
- Modify: `app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue`, `app/javascript/dashboard/components-next/captain/assistant/MessageList.vue`

**Interfaces:**
- Consumes: Task 6 (`data.ferramentas`); Task 2 (`INTEL.TESTAR.FERRAMENTAS`, `INTEL.TESTAR.FERRAMENTA_ERRO`).
- Produces: `AssistantPlayground` expõe `escrever(texto)` (troca o texto do campo) e `anexar(texto)` (acrescenta no fim) — a Task 8 usa por `ref`. Mensagem do assistente ganha `ferramentas: [{ id, title, nivel, status }]`.

- [ ] **Step 1: Specs (falham antes)** — `specs/testarConversas.spec.js`:

```js
import {
  conversaDe,
  garantirConversa,
  limparConversa,
} from '../testarConversas';

describe('conversas do Testar (I-PG3)', () => {
  beforeEach(() => {
    limparConversa(1);
    limparConversa(2);
  });

  it('cada assistente guarda a sua; limpar zera só a dele', () => {
    garantirConversa(1);
    garantirConversa(2);
    conversaDe(1).push({ content: 'oi' });
    expect(conversaDe(1)).toHaveLength(1);
    expect(conversaDe(2)).toHaveLength(0);
    limparConversa(1);
    expect(conversaDe(1)).toHaveLength(0);
  });

  it('garantir não apaga o que já existe', () => {
    garantirConversa(1);
    conversaDe(1).push({ content: 'oi' });
    garantirConversa(1);
    expect(conversaDe(1)).toHaveLength(1);
  });
});
```
`specs/AssistantPlayground.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import AssistantPlayground from '../AssistantPlayground.vue';
import { conversaDe, limparConversa } from '../testarConversas';

vi.mock('dashboard/api/captain/assistant', () => ({
  default: { playground: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const enviar = async (wrapper, texto) => {
  const campo = wrapper.find('input');
  await campo.setValue(texto);
  await campo.trigger('keydown', { key: 'Enter' });
};

describe('AssistantPlayground', () => {
  beforeEach(() => {
    limparConversa(1);
    limparConversa(2);
    CaptainAssistant.playground.mockReset();
  });

  it('mostra as ferramentas usadas debaixo da resposta (I-PG2)', async () => {
    CaptainAssistant.playground.mockResolvedValue({
      data: {
        response: 'Pronto',
        ferramentas: [
          { id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao', status: 'ok' },
          { id: 'checar_prescricao', title: 'Checar prescrição', nivel: 'consulta', status: 'erro' },
        ],
      },
    });
    const wrapper = mount(AssistantPlayground, { props: { assistantId: 1 } });
    await enviar(wrapper, 'prepare a reunião');
    await flushPromises();
    const chips = wrapper.findAll('[data-testid="testar-ferramenta"]');
    expect(chips.map(chip => chip.text())).toEqual([
      'Mover de etapa',
      'INTEL.TESTAR.FERRAMENTA_ERRO',
    ]);
  });

  it('trocar de assistente e voltar mantém a conversa (I-PG3)', async () => {
    CaptainAssistant.playground.mockResolvedValue({ data: { response: 'Oi' } });
    const wrapper = mount(AssistantPlayground, { props: { assistantId: 1 } });
    await enviar(wrapper, 'olá');
    await flushPromises();
    await wrapper.setProps({ assistantId: 2 });
    expect(conversaDe(2)).toHaveLength(0);
    await wrapper.setProps({ assistantId: 1 });
    expect(conversaDe(1)).toHaveLength(2);
  });

  it('resposta atrasada vai para a conversa de quem perguntou', async () => {
    let responder;
    CaptainAssistant.playground.mockReturnValue(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    const wrapper = mount(AssistantPlayground, { props: { assistantId: 1 } });
    await enviar(wrapper, 'olá');
    await wrapper.setProps({ assistantId: 2 });
    responder({ data: { response: 'Oi' } });
    await flushPromises();
    expect(conversaDe(1).map(m => m.sender)).toEqual(['user', 'assistant']);
    expect(conversaDe(2)).toHaveLength(0);
  });

  it('escrever e anexar mexem só no campo', async () => {
    const wrapper = mount(AssistantPlayground, { props: { assistantId: 1 } });
    wrapper.vm.escrever('Prepare a reunião deste caso.');
    wrapper.vm.anexar('caso 12 (Maria)');
    await flushPromises();
    expect(wrapper.find('input').element.value).toBe(
      'Prepare a reunião deste caso. caso 12 (Maria)'
    );
    expect(CaptainAssistant.playground).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain/assistant/specs/testarConversas.spec.js app/javascript/dashboard/components-next/captain/assistant/specs/AssistantPlayground.spec.js --config vitest.local.config.ts` → FAIL (arquivo novo não existe).

- [ ] **Step 3: `testarConversas.js`** (Write):

```js
// Conversas do Testar (I-PG3): ficam guardadas enquanto a página do hub estiver aberta — trocar de tela
// ou de assistente não apaga. ponytail: memória da página (F5 ou fechar a aba limpa); nada do caso fica
// gravado no navegador. Upgrade, se pedirem sobreviver ao F5: sessionStorage por assistente.
import { reactive } from 'vue';

const conversas = reactive({});

export const garantirConversa = id => {
  if (!conversas[id]) conversas[id] = [];
};

export const conversaDe = id => conversas[id] || [];

export const limparConversa = id => {
  conversas[id] = [];
};
```

- [ ] **Step 4: `AssistantPlayground.vue`** — script:
  - `import { computed, ref, watch } from 'vue';` e `import { conversaDe, garantirConversa, limparConversa } from './testarConversas';`
  - trocar `const messages = ref([]);` por:
    ```js
    // I-PG3: a conversa é do assistente, guardada fora do componente (não some ao trocar de tela).
    watch(() => assistantId, id => garantirConversa(id), { immediate: true });
    const messages = computed(() => conversaDe(assistantId));
    ```
  - `resetConversation` vira `limparConversa(assistantId); newMessage.value = '';` e **apagar** o `watch` antigo que zerava a conversa ao trocar de assistente.
  - `sendMessage`: capturar `const conversa = conversaDe(assistantId);` logo no começo (depois do `if`), usar `conversa.push(userMessage)` e, na resposta,
    ```js
        conversa.push({
          content: data.response,
          sender: 'assistant',
          agentName: data.agent_name,
          ferramentas: data.ferramentas || [],
          timestamp: new Date().toISOString(),
        });
    ```
    (`formatMessagesForApi` continua lendo `messages.value`, calculado antes do `await`.)
  - antes de `</script>`:
    ```js
    // A página do Testar põe a fala de uma skill (escrever) ou o nº do caso (anexar) — nada é enviado sozinho (N7).
    const escrever = texto => {
      newMessage.value = texto;
    };
    const anexar = texto => {
      newMessage.value = [newMessage.value.trim(), texto].filter(Boolean).join(' ');
    };
    defineExpose({ escrever, anexar });
    ```
  - template: sem mudança (o botão de recomeçar já chama `resetConversation`, que agora limpa só a conversa deste assistente).

- [ ] **Step 5: `MessageList.vue`**
  - imports: `import { CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';` e `import { NIVEL_TOM } from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';`
  - `getMessageStyle` (I-T5 — sem roxo, fundos translúcidos):
    ```js
    const getMessageStyle = sender =>
      isUserMessage(sender)
        ? 'bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16] text-n-slate-12 rounded-br-sm rounded-bl-xl rounded-t-xl'
        : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-sm rounded-br-xl rounded-t-xl';

    // I-PG2: cor do nível (consulta azul, sugestão âmbar, rascunho verde, interna cinza); erro sempre vermelho.
    const tomFerramenta = ferramenta =>
      ferramenta.status === 'erro'
        ? TOM.ruby
        : NIVEL_TOM[ferramenta.nivel] || TOM.slate;
    const rotuloFerramenta = ferramenta =>
      ferramenta.status === 'erro'
        ? t('INTEL.TESTAR.FERRAMENTA_ERRO', { nome: ferramenta.title })
        : ferramenta.title;
    ```
  - no "pensando": `bg-n-solid-iris` → `bg-n-alpha-2`; os 3 pontos `bg-n-iris-10` → `bg-n-blue-9`.
  - a bolha do assistente passa a ficar numa coluna com as ferramentas embaixo: trocar
    ```vue
        <div
          class="px-4 py-3 text-sm [overflow-wrap:break-word]"
          :class="getMessageStyle(message.sender)"
        >
          <div v-html="formatMessage(message.content)" />
        </div>
    ```
    por
    ```vue
        <div class="flex flex-col gap-1 min-w-0">
          <div
            class="px-4 py-3 text-sm [overflow-wrap:break-word]"
            :class="getMessageStyle(message.sender)"
          >
            <div v-html="formatMessage(message.content)" />
          </div>
          <div
            v-if="message.ferramentas?.length"
            data-testid="testar-ferramentas"
            class="flex flex-wrap items-center gap-1"
          >
            <span class="text-[11px] text-n-slate-10">
              {{ t('INTEL.TESTAR.FERRAMENTAS') }}
            </span>
            <span
              v-for="(ferramenta, i) in message.ferramentas"
              :key="i"
              data-testid="testar-ferramenta"
              :class="[CHIP, tomFerramenta(ferramenta)]"
            >
              {{ rotuloFerramenta(ferramenta) }}
            </span>
          </div>
        </div>
    ```

- [ ] **Step 6: Rodar e ver passar** — o comando do Step 2 (verde) + `./node_modules/.bin/eslint app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue app/javascript/dashboard/components-next/captain/assistant/MessageList.vue app/javascript/dashboard/components-next/captain/assistant/testarConversas.js` sem `error`.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/dashboard/components-next/captain/assistant/testarConversas.js app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue app/javascript/dashboard/components-next/captain/assistant/MessageList.vue app/javascript/dashboard/components-next/captain/assistant/specs/testarConversas.spec.js app/javascript/dashboard/components-next/captain/assistant/specs/AssistantPlayground.spec.js
git commit -m "feat(testar): ferramentas usadas debaixo da resposta e conversa guardada ao trocar de tela (I-PG2, I-PG3)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 8: Testar — página: falas do seu papel, testar com o caso, fala vinda da skill (I-X5, I-PG4, I-SK6, I-T5) (julgamento: arrumação no print)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/assistants/playground/testar.js`, `.../playground/TestarComCaso.vue`, `.../playground/specs/testar.spec.js`, `.../playground/specs/TestarComCaso.spec.js`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/playground/Index.vue`, `app/javascript/dashboard/routes/dashboard/captain/casos/CasoForm.vue:214-217`

**Interfaces:**
- Consumes: Task 7 (`escrever`, `anexar` via `ref`); Task 4/5 (`exemplo`, `papeis` nas skills do store `captainScenarios`); getter `teams/getMyTeams`; `LeadsAPI.get({ q })` → `{ payload: [{ id, name }] }`; `route.query.fala` (Task 5).
- Produces: `skillsDoPapel(skills, meusTimes)` e `referenciaCaso(lead)` em `testar.js`; `TestarComCaso` emite `escolher(lead)`.
- Se o Eduardo escolher **N7 (b)** (enviar direto): expor também `enviar()` no `AssistantPlayground` (chama `sendMessage`) e, nas falas sugeridas e no `?fala=`, chamar `escrever(...)` seguido de `enviar()`.

- [ ] **Step 1: Specs (falham antes)** — `specs/testar.spec.js`:

```js
import { referenciaCaso, skillsDoPapel } from '../testar';

const SKILLS = [
  { id: 1, title: 'Funil hoje', enabled: true, exemplo: 'Como está o funil?', papeis: ['comercial'] },
  { id: 2, title: 'Agenda do dia', enabled: true, exemplo: 'Agenda?', papeis: ['recepção'] },
  { id: 3, title: 'Desligada', enabled: false, exemplo: 'x', papeis: ['recepção'] },
  { id: 4, title: 'Sem fala', enabled: true, exemplo: '', papeis: [] },
  { id: 5, title: 'Consultas no AdvBox', enabled: true, exemplo: 'Prazos?', papeis: [] },
];

describe('skillsDoPapel (I-X5)', () => {
  it('só ligadas com fala; as do seu papel primeiro, depois pelo título', () => {
    const lista = skillsDoPapel(SKILLS, [{ name: 'recepção' }]);
    expect(lista.map(skill => [skill.id, skill.meu])).toEqual([
      [2, true],
      [5, false],
      [1, false],
    ]);
  });

  it('sem time (ex.: administrador), todas pelo título', () => {
    expect(skillsDoPapel(SKILLS, []).map(skill => skill.id)).toEqual([2, 5, 1]);
  });
});

describe('referenciaCaso (I-PG4)', () => {
  it('nº do caso no formato que as skills entendem', () => {
    expect(referenciaCaso({ id: 12, name: 'Maria Souza' })).toBe(
      'caso 12 (Maria Souza)'
    );
  });
});
```
`specs/TestarComCaso.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import LeadsAPI from 'dashboard/api/leads';
import TestarComCaso from '../TestarComCaso.vue';

vi.mock('dashboard/api/leads', () => ({ default: { get: vi.fn() } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useDebounceFn: fn => fn,
}));

describe('TestarComCaso (I-PG4)', () => {
  it('busca pelo nome e devolve o lead escolhido; limpa a busca', async () => {
    LeadsAPI.get.mockResolvedValue({
      data: { payload: [{ id: 12, name: 'Maria Souza' }] },
    });
    const wrapper = mount(TestarComCaso);
    await wrapper.find('[data-testid="testar-caso-busca"]').setValue('mar');
    await flushPromises();
    expect(LeadsAPI.get).toHaveBeenCalledWith({ q: 'mar' });
    await wrapper.find('[data-testid="testar-caso-opcao"]').trigger('click');
    expect(wrapper.emitted('escolher')[0][0]).toEqual({ id: 12, name: 'Maria Souza' });
    expect(wrapper.find('[data-testid="testar-caso-opcao"]').exists()).toBe(false);
  });

  it('menos de 2 letras não busca', async () => {
    LeadsAPI.get.mockClear();
    const wrapper = mount(TestarComCaso);
    await wrapper.find('[data-testid="testar-caso-busca"]').setValue('m');
    await flushPromises();
    expect(LeadsAPI.get).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/assistants/playground/specs --config vitest.local.config.ts` → FAIL.

- [ ] **Step 3: `testar.js`** (Write):

```js
// Regras puras da página do Testar.

// I-X5: skills ligadas e com fala de exemplo; as do seu papel (times de que você participa) primeiro,
// depois pelo título. Sem time (ex.: administrador), todas pelo título.
export const skillsDoPapel = (skills, meusTimes) => {
  const meus = new Set((meusTimes || []).map(time => time.name));
  return (skills || [])
    .filter(skill => skill.enabled && skill.exemplo)
    .map(skill => ({
      ...skill,
      meu: (skill.papeis || []).some(papel => meus.has(papel)),
    }))
    .sort(
      (a, b) =>
        Number(b.meu) - Number(a.meu) ||
        a.title.localeCompare(b.title, 'pt-BR')
    );
};

// I-PG4: "caso N" é o lead_id que as skills do Copiloto entendem (assistentes.yml, regra de identificação);
// o nome ajuda a busca do processo no AdvBox (mesma regra do painel do Copiloto, A4 N8).
export const referenciaCaso = lead => `caso ${lead.id} (${lead.name})`;
```

- [ ] **Step 4: `TestarComCaso.vue`** (Write):

```vue
<script setup>
// "Testar com o caso…" (I-PG4): acha o lead pelo nome e devolve para a página pôr o nº do caso na mensagem.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import LeadsAPI from 'dashboard/api/leads';
import {
  CAMPO,
  LINHA,
  MENU,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const emit = defineEmits(['escolher']);
const { t } = useI18n();

const busca = ref('');
const leads = ref([]);
const buscou = ref(false);

// só a última busca vale (mesmo cuidado do "Testar com um lead" das Automações)
let pedido = 0;
const buscar = useDebounceFn(async () => {
  pedido += 1;
  const meu = pedido;
  const termo = busca.value.trim();
  if (termo.length < 2) {
    leads.value = [];
    buscou.value = false;
    return;
  }
  try {
    const { data } = await LeadsAPI.get({ q: termo });
    if (meu !== pedido) return;
    leads.value = data.payload.slice(0, 6);
    buscou.value = true;
  } catch (e) {
    if (meu === pedido) leads.value = [];
  }
}, 300);

const escolher = lead => {
  emit('escolher', lead);
  busca.value = '';
  leads.value = [];
  buscou.value = false;
};
</script>

<template>
  <div class="relative">
    <input
      v-model="busca"
      data-testid="testar-caso-busca"
      :class="CAMPO"
      :placeholder="t('INTEL.TESTAR.CASO_PLACEHOLDER')"
      :title="t('INTEL.TESTAR.CASO_AJUDA')"
      @input="buscar"
    />
    <ul
      v-if="buscou"
      class="absolute z-10 w-full mt-1 list-none"
      :class="MENU"
    >
      <li v-for="lead in leads" :key="lead.id">
        <button
          type="button"
          data-testid="testar-caso-opcao"
          :class="LINHA"
          @click="escolher(lead)"
        >
          {{ lead.name }}
          <span class="font-mono text-xs text-n-slate-10">#{{ lead.id }}</span>
        </button>
      </li>
      <li v-if="!leads.length" class="px-2 py-1.5 text-xs text-n-slate-10">
        {{ t('INTEL.TESTAR.CASO_NENHUM') }}
      </li>
    </ul>
  </div>
</template>
```
(O teste "menos de 2 letras" passa porque `setValue` dispara `input` e o `useDebounceFn` mockado roda na hora; o `#` antes do id segue o padrão de `TestarComLead.vue`, que já passa no eslint.)

- [ ] **Step 5: `playground/Index.vue`** (Write — arquivo inteiro):

```vue
<script setup>
// Testar: a conversa avulsa com o assistente (AssistantPlayground) + atalhos da A5 — falas das skills
// (as do seu papel primeiro, I-X5), "Testar com o caso…" (I-PG4) e a fala vinda de "Testar esta skill"
// (?fala=, I-SK6). Nada é enviado sozinho: os atalhos só escrevem no campo (N7).
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import AssistantPlayground from 'dashboard/components-next/captain/assistant/AssistantPlayground.vue';
import AbasTestar from '../../casos/AbasTestar.vue';
import TestarComCaso from './TestarComCaso.vue';
import { referenciaCaso, skillsDoPapel } from './testar';
import {
  CHIP,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const VISIVEIS = 8;

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const assistantId = computed(() => Number(route.params.assistantId));
const playground = ref(null);

const skills = useMapGetter('captainScenarios/getRecords');
const meusTimes = useMapGetter('teams/getMyTeams');
const sugestoes = computed(() =>
  skillsDoPapel(skills.value, meusTimes.value).slice(0, VISIVEIS)
);

watch(
  assistantId,
  id => store.dispatch('captainScenarios/get', { assistantId: id }),
  { immediate: true }
);

onMounted(async () => {
  store.dispatch('teams/get');
  await nextTick();
  if (route.query?.fala) playground.value?.escrever(String(route.query.fala));
});

const usarCaso = lead => playground.value?.anexar(referenciaCaso(lead));
</script>

<template>
  <PageLayout
    show-assistant-switcher
    :show-pagination-footer="false"
    class="h-full"
  >
    <template #subHeader>
      <AbasTestar ativa="conversa" />
    </template>
    <template #body>
      <div class="flex flex-col h-full gap-3">
        <div class="flex flex-wrap items-start gap-3">
          <TestarComCaso class="w-72 shrink-0" @escolher="usarCaso" />
          <div
            v-if="sugestoes.length"
            data-testid="testar-sugestoes"
            class="flex flex-wrap items-center flex-1 min-w-0 gap-1.5"
          >
            <span :class="TITULO">{{ t('INTEL.TESTAR.SUGESTOES') }}</span>
            <button
              v-for="skill in sugestoes"
              :key="skill.id"
              type="button"
              data-testid="testar-sugestao"
              class="hover:brightness-110"
              :class="[CHIP, skill.meu ? TOM.blue : TOM.slate]"
              :title="skill.exemplo"
              @click="playground?.escrever(skill.exemplo)"
            >
              {{ skill.title }}
            </button>
          </div>
        </div>
        <AssistantPlayground
          ref="playground"
          :assistant-id="assistantId"
          class="flex-1 min-h-0 bg-n-solid-1"
        />
      </div>
    </template>
  </PageLayout>
</template>
```

- [ ] **Step 6: Casos de teste no kit (I-T5)** — `casos/CasoForm.vue`: importar `import Switch from 'dashboard/components-next/switch/Switch.vue';` e trocar

```vue
            <input v-model="form.ativo" type="checkbox" class="reset-base" />
```
por
```vue
            <Switch v-model="form.ativo" />
```

- [ ] **Step 7: Rodar e ver passar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/assistants/playground/specs app/javascript/dashboard/routes/dashboard/captain/casos/specs --config vitest.local.config.ts` (verde) + `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/assistants/playground app/javascript/dashboard/routes/dashboard/captain/casos/CasoForm.vue` sem `error`.

- [ ] **Step 8: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/assistants/playground app/javascript/dashboard/routes/dashboard/captain/casos/CasoForm.vue
git commit -m "feat(testar): falas das skills do seu papel, testar com o caso e fala vinda da skill (I-X5, I-PG4, I-SK6)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 9: Configurações — por público, nome do escritório, criatividade, zona de risco, texto final e a chave da memória (I-CF3, I-CF4, I-CF5, I-CF6, I-X7, I-T4, I-T5) (julgamento: arrumação no print)

**Files:**
- Create: `app/javascript/dashboard/components-next/captain/pageComponents/assistant/settings/TextoFinal.vue`, specs `.../settings/specs/{AssistantBasicSettingsForm,AssistantSystemSettingsForm,TextoFinal}.spec.js`, `app/javascript/dashboard/routes/dashboard/captain/assistants/settings/specs/Settings.spec.js`
- Modify: `.../settings/AssistantBasicSettingsForm.vue`, `.../settings/AssistantSystemSettingsForm.vue`, `app/javascript/dashboard/routes/dashboard/captain/assistants/settings/Settings.vue`, `app/javascript/dashboard/components-next/captain/pageComponents/assistant/AssistantForm.vue`

**Interfaces:**
- Consumes: Task 6 (`CaptainAssistant.textoFinal`); `CaptainAssistant.stats()` → `payload: [{ id, publico: 'lead'|'equipe' }]`; Task 2 (`INTEL.CONFIG.*`, rótulos trocados em `integrations.json`).
- Produces: forms com prop `publico: 'lead'|'equipe'`; `TextoFinal` (props `assistantId`, evento `fechar`).

- [ ] **Step 1: Specs (falham antes)** — `settings/specs/AssistantBasicSettingsForm.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import AssistantBasicSettingsForm from '../AssistantBasicSettingsForm.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const ASSISTENTE = {
  name: 'Atendimento',
  description: 'Fala com o lead',
  config: { feature_memory: false, feature_citation: true },
};
const montar = (publico, assistant = ASSISTENTE) =>
  mount(AssistantBasicSettingsForm, {
    props: { assistant, publico },
    global: {
      stubs: {
        Input: true,
        Editor: true,
        Switch: true,
        Button: {
          emits: ['click'],
          template: '<button data-testid="salvar" @click="clicar" />',
          methods: {
            clicar() {
              this.$emit('click');
            },
          },
        },
      },
    },
  });

describe('Configurações básicas por público (I-CF3, I-CF4, I-X7)', () => {
  it('lead: 3 chaves (FAQ de conversa, memória, contato), sem citação', () => {
    const chaves = montar('lead').findAll('[data-testid="config-chave"]');
    expect(chaves.map(c => c.text())).toEqual([
      'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONVERSATION_FAQS',
      expect.stringContaining('CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_MEMORIES'),
      'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONTACT_ATTRIBUTES',
    ]);
  });

  it('equipe: nenhuma chave, só o aviso', () => {
    const wrapper = montar('equipe');
    expect(wrapper.findAll('[data-testid="config-chave"]')).toHaveLength(0);
    expect(wrapper.text()).toContain('INTEL.CONFIG.SO_EQUIPE');
  });

  it('nome do escritório pré-preenchido; salva citação desligada', async () => {
    const wrapper = montar('lead');
    await wrapper.find('[data-testid="salvar"]').trigger('click');
    await flushPromises();
    const { config } = wrapper.emitted('submit')[0][0];
    expect(config).toMatchObject({
      product_name: 'Ramon Antonio Advogados',
      feature_citation: false,
    });
  });
});
```
`settings/specs/AssistantSystemSettingsForm.spec.js`:

```js
import { mount } from '@vue/test-utils';
import AssistantSystemSettingsForm from '../AssistantSystemSettingsForm.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));

const montar = publico =>
  mount(AssistantSystemSettingsForm, {
    props: { assistant: { config: { temperature: 0.3 } }, publico },
    global: { stubs: { Editor: true, Button: true } },
  });

describe('Configurações do sistema por público (I-CF4)', () => {
  it('lead vê as mensagens de transferência e encerramento', () => {
    expect(montar('lead').findAllComponents({ name: 'Editor' })).toHaveLength(2);
  });

  it('equipe (Copiloto) não vê mensagem ao cliente', () => {
    expect(montar('equipe').findAllComponents({ name: 'Editor' })).toHaveLength(0);
  });
});
```
`settings/specs/TextoFinal.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import TextoFinal from '../TextoFinal.vue';

vi.mock('dashboard/api/captain/assistant', () => ({
  default: { textoFinal: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

describe('TextoFinal (I-CF6)', () => {
  it('mostra o texto do assistente e o de cada skill', async () => {
    CaptainAssistant.textoFinal.mockResolvedValue({
      data: {
        assistente: 'Você é o Atendimento.',
        skills: [{ title: 'Funil hoje', texto: 'Use funil_hoje.' }],
      },
    });
    const wrapper = mount(TextoFinal, {
      props: { assistantId: 1 },
      global: { stubs: { Button: true } },
    });
    await flushPromises();
    expect(CaptainAssistant.textoFinal).toHaveBeenCalledWith(1);
    expect(wrapper.findAll('pre').map(pre => pre.text())).toEqual([
      'Você é o Atendimento.',
      'Use funil_hoje.',
    ]);
  });

  it('erro vira aviso, sem quebrar', async () => {
    CaptainAssistant.textoFinal.mockRejectedValue(new Error('x'));
    const wrapper = mount(TextoFinal, {
      props: { assistantId: 1 },
      global: { stubs: { Button: true } },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('INTEL.CONFIG.TEXTO_FINAL_ERRO');
  });
});
```
`routes/.../assistants/settings/specs/Settings.spec.js` (zona de risco — I-CF5):

```js
import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import Settings from '../Settings.vue';

const { abrir } = vi.hoisted(() => ({ abrir: vi.fn() }));
const ASSISTENTE = { id: 1, name: 'Atendimento', config: {} };

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1, assistantId: '1' } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => true }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: { 'captainAssistants/getRecord': () => ASSISTENTE },
    dispatch: vi.fn(),
  }),
  useMapGetter: nome =>
    ({
      'captainAssistants/getUIFlags': ref({}),
      'captainAssistants/getRecords': ref([ASSISTENTE]),
    })[nome],
}));
vi.mock('dashboard/api/captain/assistant', () => ({
  default: {
    stats: vi.fn().mockResolvedValue({
      data: { payload: [{ id: 1, publico: 'lead' }] },
    }),
  },
}));

const montar = () =>
  mount(Settings, {
    global: {
      stubs: {
        PageLayout: { template: '<div><slot name="body" /><slot /></div>' },
        Policy: { template: '<div><slot /></div>' },
        SettingsHeader: true,
        AssistantBasicSettingsForm: true,
        AssistantSystemSettingsForm: true,
        AssistantControlItems: true,
        TextoFinal: true,
        Button: {
          props: ['disabled'],
          emits: ['click'],
          template: '<button :disabled="disabled" @click="clicar" />',
          methods: {
            clicar() {
              this.$emit('click');
            },
          },
        },
        DeleteDialog: {
          setup(_, { expose }) {
            expose({ dialogRef: { open: abrir } });
          },
          template: '<i />',
        },
      },
    },
  });

describe('Configurações — zona de risco (I-CF5)', () => {
  it('excluir só libera depois de digitar o nome exato', async () => {
    const wrapper = montar();
    await flushPromises();
    const botao = wrapper.find('[data-testid="zona-de-risco-excluir"]');
    expect(botao.attributes('disabled')).toBeDefined();
    await wrapper.find('[data-testid="zona-de-risco-nome"]').setValue('atendimento');
    expect(botao.attributes('disabled')).toBeDefined();
    await wrapper.find('[data-testid="zona-de-risco-nome"]').setValue('Atendimento');
    expect(botao.attributes('disabled')).toBeUndefined();
    await botao.trigger('click');
    expect(abrir).toHaveBeenCalled();
  });

  it('passa o público do assistente para os formulários', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'AssistantBasicSettingsForm' }).attributes('publico')
    ).toBe('lead');
  });
});
```
(O `data-testid` do botão vai **no componente** `Button`; com o stub acima ele chega ao `<button>`.)

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain/pageComponents/assistant/settings/specs app/javascript/dashboard/routes/dashboard/captain/assistants/settings/specs --config vitest.local.config.ts` → FAIL.

- [ ] **Step 3: `AssistantBasicSettingsForm.vue`** (Write — arquivo inteiro):

```vue
<script setup>
import { reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { AVISO, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';

// ramon (I-CF3): o nome do escritório já vem preenchido quando o assistente não tem.
const ESCRITORIO = 'Ramon Antonio Advogados';
// ramon (I-CF4): chaves que só valem em conversa com lead. "Citações" sai da tela: no modo do agente não muda
// nada e citação numerada não cabe em WhatsApp — é salva desligada.
const CHAVES_DO_LEAD = [
  {
    campo: 'conversationFaqs',
    rotulo: 'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONVERSATION_FAQS',
  },
  {
    campo: 'memories',
    rotulo: 'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_MEMORIES',
    ajuda: 'INTEL.CONFIG.MEMORIA_AJUDA',
  },
  {
    campo: 'contactAttributes',
    rotulo: 'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONTACT_ATTRIBUTES',
  },
];

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
  // 'lead' (tem caixa conectada) | 'equipe' (só Testar e painel do Copiloto)
  publico: {
    type: String,
    default: 'lead',
  },
});

const emit = defineEmits(['submit']);

const { t } = useI18n();

const state = reactive({
  name: '',
  description: '',
  productName: '',
  features: {
    conversationFaqs: false,
    memories: false,
    contactAttributes: false,
  },
});

const validationRules = {
  name: { required, minLength: minLength(1) },
  description: { required, minLength: minLength(1) },
  productName: { required, minLength: minLength(1) },
};

const v$ = useVuelidate(validationRules, state);

const getErrorMessage = field => {
  return v$.value[field].$error ? v$.value[field].$errors[0].$message : '';
};

const formErrors = computed(() => ({
  name: getErrorMessage('name'),
  description: getErrorMessage('description'),
  productName: getErrorMessage('productName'),
}));

const updateStateFromAssistant = assistant => {
  const { config = {} } = assistant;
  state.name = assistant.name;
  state.description = assistant.description;
  state.productName = config.product_name || ESCRITORIO;
  state.features = {
    conversationFaqs: config.feature_faq || false,
    memories: config.feature_memory || false,
    contactAttributes: config.feature_contact_attributes || false,
  };
};

const handleBasicInfoUpdate = async () => {
  const result = await Promise.all([
    v$.value.name.$validate(),
    v$.value.description.$validate(),
    v$.value.productName.$validate(),
  ]).then(results => results.every(Boolean));
  if (!result) return;

  emit('submit', {
    name: state.name,
    description: state.description,
    config: {
      ...props.assistant.config,
      product_name: state.productName,
      feature_faq: state.features.conversationFaqs,
      feature_memory: state.features.memories,
      feature_citation: false,
      feature_contact_attributes: state.features.contactAttributes,
    },
  });
};

watch(
  () => props.assistant,
  newAssistant => {
    if (newAssistant) updateStateFromAssistant(newAssistant);
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <Input
      v-model="state.name"
      :label="t('CAPTAIN.ASSISTANTS.FORM.NAME.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.NAME.PLACEHOLDER')"
      :message="formErrors.name"
      :message-type="formErrors.name ? 'error' : 'info'"
    />

    <Input
      v-model="state.productName"
      :label="t('CAPTAIN.ASSISTANTS.FORM.PRODUCT_NAME.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.PRODUCT_NAME.PLACEHOLDER')"
      :message="formErrors.productName"
      :message-type="formErrors.productName ? 'error' : 'info'"
    />

    <Editor
      v-model="state.description"
      :label="t('CAPTAIN.ASSISTANTS.FORM.DESCRIPTION.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.DESCRIPTION.PLACEHOLDER')"
      :message="formErrors.description"
      :message-type="formErrors.description ? 'error' : 'info'"
      class="z-0"
    />

    <div class="flex flex-col gap-3">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.TITLE') }}
      </span>
      <template v-if="publico === 'lead'">
        <div
          v-for="chave in CHAVES_DO_LEAD"
          :key="chave.campo"
          data-testid="config-chave"
          class="flex items-start gap-3"
        >
          <Switch v-model="state.features[chave.campo]" class="mt-0.5" />
          <div class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-12">{{ t(chave.rotulo) }}</span>
            <span v-if="chave.ajuda" class="text-xs text-n-slate-10">
              {{ t(chave.ajuda) }}
            </span>
          </div>
        </div>
      </template>
      <p v-else :class="[AVISO, TOM.slate]">
        {{ t('INTEL.CONFIG.SO_EQUIPE') }}
      </p>
    </div>

    <div>
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleBasicInfoUpdate"
      />
    </div>
  </div>
</template>
```
(No teste "lead", o 2º item tem a ajuda junto — por isso `stringContaining`.)

- [ ] **Step 4: `AssistantSystemSettingsForm.vue`** — props ganham `publico: { type: String, default: 'lead' }` (mesmo comentário); `const ehLead = computed(() => props.publico === 'lead');`; em `handleSystemMessagesUpdate`, as duas validações de mensagem só entram com `ehLead.value`:

```js
  const validations = ehLead.value
    ? [
        v$.value.handoffMessage.$validate(),
        v$.value.resolutionMessage.$validate(),
      ]
    : [];
```
e no payload `handoff_message`/`resolution_message` continuam saindo do `state` (para a equipe ficam como estavam no `config`). Template: os dois `<Editor>` de transferência/encerramento ganham `v-if="ehLead"`; o `<input type="range" …>` ganha a classe `accent-n-brand` (I-T5 — azul do hub no controle); o `<p class="text-sm text-n-slate-11 italic">` perde o `italic`.

- [ ] **Step 5: `TextoFinal.vue`** (Write):

```vue
<script setup>
// Texto final que o assistente recebe (I-CF6): o dele (diretrizes, proteções e a lista de skills, do jeito
// que vão para a IA) e o de cada skill ligada. Só leitura.
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import CaptainAssistant from 'dashboard/api/captain/assistant';
import {
  FUNDO_JANELA,
  JANELA,
  RODAPE_JANELA,
  TITULO,
  TITULO_JANELA,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  assistantId: { type: Number, required: true },
});
const emit = defineEmits(['fechar']);
const { t } = useI18n();
onKeyStroke('Escape', () => emit('fechar'));

const PRE =
  'mt-1 max-h-72 overflow-auto whitespace-pre-wrap rounded-lg bg-n-alpha-2 p-2 font-mono text-[11px] text-n-slate-11';

const texto = ref(null);
const erro = ref(false);

onMounted(async () => {
  try {
    const { data } = await CaptainAssistant.textoFinal(props.assistantId);
    texto.value = data;
  } catch (e) {
    erro.value = true;
  }
});
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('fechar')">
    <div :class="JANELA" class="!w-[44rem]" data-testid="texto-final">
      <h3 :class="TITULO_JANELA">{{ t('INTEL.CONFIG.TEXTO_FINAL') }}</h3>
      <p class="mb-3 text-xs text-n-slate-11">
        {{ t('INTEL.CONFIG.TEXTO_FINAL_AJUDA') }}
      </p>
      <p v-if="erro" class="text-sm text-n-ruby-11">
        {{ t('INTEL.CONFIG.TEXTO_FINAL_ERRO') }}
      </p>
      <template v-else-if="texto">
        <p :class="TITULO">{{ t('INTEL.CONFIG.TEXTO_FINAL_ASSISTENTE') }}</p>
        <pre :class="PRE">{{ texto.assistente }}</pre>
        <template v-for="skill in texto.skills" :key="skill.title">
          <p class="mt-3" :class="TITULO">
            {{ t('INTEL.CONFIG.TEXTO_FINAL_SKILL', { nome: skill.title }) }}
          </p>
          <pre :class="PRE">{{ skill.texto }}</pre>
        </template>
      </template>
      <div :class="RODAPE_JANELA">
        <Button
          sm
          slate
          faded
          :label="t('INTEL.CONFIG.FECHAR')"
          @click="emit('fechar')"
        />
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 6: `Settings.vue`**
  - imports: `import { computed, onMounted, ref, watch } from 'vue';`, `import Policy from 'dashboard/components/policy.vue';`, `import CaptainAssistantAPI from 'dashboard/api/captain/assistant';`, `import TextoFinal from 'dashboard/components-next/captain/pageComponents/assistant/settings/TextoFinal.vue';`, `import { CAMPO, CARTAO } from 'dashboard/routes/dashboard/ramon/helpers/ui';`
  - depois de `const assistant = computed(...)`:
    ```js
    // I-CF4: público de cada assistente (lead = tem caixa conectada) — muda o que os formulários mostram.
    const cartoes = ref([]);
    onMounted(async () => {
      try {
        const { data } = await CaptainAssistantAPI.stats();
        cartoes.value = data.payload;
      } catch (e) {
        cartoes.value = [];
      }
    });
    const publico = computed(
      () =>
        cartoes.value.find(item => item.id === assistantId.value)?.publico ||
        'lead'
    );

    // I-CF5: excluir só depois de digitar o nome exato (zona de risco recolhida, só administrador).
    const confirmaNome = ref('');
    watch(assistantId, () => {
      confirmaNome.value = '';
    });
    const podeExcluir = computed(
      () => !!assistant.value?.name && confirmaNome.value.trim() === assistant.value.name
    );

    // I-CF6
    const textoFinalAberto = ref(false);
    ```
  - `<PageLayout …>`: acrescentar `show-assistant-switcher` (I-T4).
  - os dois formulários ganham `:publico="publico"`.
  - trocar a `<div class="flex items-end justify-between w-full gap-4">…</div>` inteira (a do excluir, depois do 2º separador `<span class="h-px w-full bg-n-weak mt-2" />`, que fica) por:
    ```vue
          <Policy :permissions="['administrator']">
            <details data-testid="zona-de-risco" :class="CARTAO">
              <summary
                class="text-sm font-medium cursor-pointer text-n-ruby-11"
              >
                {{ t('INTEL.CONFIG.ZONA_RISCO') }}
              </summary>
              <p class="mt-2 text-sm text-n-slate-11">
                {{ t('CAPTAIN.ASSISTANTS.SETTINGS.DELETE.DESCRIPTION') }}
              </p>
              <input
                v-model="confirmaNome"
                data-testid="zona-de-risco-nome"
                class="mt-3"
                :class="CAMPO"
                :placeholder="
                  t('INTEL.CONFIG.DIGITE_NOME', { nome: assistant?.name })
                "
              />
              <Button
                data-testid="zona-de-risco-excluir"
                class="mt-3 max-w-56 !w-fit"
                color="ruby"
                size="sm"
                :disabled="!podeExcluir"
                :label="
                  t('CAPTAIN.ASSISTANTS.SETTINGS.DELETE.BUTTON_TEXT', {
                    assistantName: assistant?.name,
                  })
                "
                @click="handleDelete"
              />
            </details>
          </Policy>
    ```
  - na coluna da direita (`<div v-if="isCaptainV2Enabled" …>`), depois dos `AssistantControlItems`:
    ```vue
          <Button
            variant="link"
            size="sm"
            icon="i-lucide-file-text"
            class="self-start"
            data-testid="ver-texto-final"
            :label="t('INTEL.CONFIG.TEXTO_FINAL')"
            @click="textoFinalAberto = true"
          />
    ```
  - antes do `<DeleteDialog …>`: `<TextoFinal v-if="textoFinalAberto" :assistant-id="assistantId" @fechar="textoFinalAberto = false" />`.

- [ ] **Step 7: Criar assistente no kit (I-T5)** — `AssistantForm.vue`: importar `Switch` (`dashboard/components-next/switch/Switch.vue`); nos dois `<label class="flex items-center gap-2">` de `featureFaq` e `featureMemory`, trocar `<input v-model="state.X" type="checkbox" />` por `<Switch v-model="state.X" />`; **apagar** o `<label>` inteiro de `featureCitation` e, no payload (linha ~74), `feature_citation: state.featureCitation` vira `feature_citation: false` (mesma regra da Escolha 8).

- [ ] **Step 8: Rodar e ver passar** — o comando do Step 2 + `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain --config vitest.local.config.ts` (nada antigo quebrou) + `./node_modules/.bin/eslint app/javascript/dashboard/components-next/captain/pageComponents/assistant app/javascript/dashboard/routes/dashboard/captain/assistants/settings` sem `error`.

- [ ] **Step 9: Commit**

```bash
git add app/javascript/dashboard/components-next/captain/pageComponents/assistant app/javascript/dashboard/routes/dashboard/captain/assistants/settings
git commit -m "feat(configuracoes): por público, nome do escritório, criatividade, zona de risco, texto final e chave da memória (I-CF3 a I-CF6, I-X7)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 10: FAQs (backend) — contador "usada N×" (I-FQ6) (mecânica)

**Files:**
- Create: `db/migrate/20261007800002_add_uso_to_captain_assistant_responses.rb`
- Modify: `db/schema.rb`, `enterprise/lib/captain/tools/faq_lookup_tool.rb`, `enterprise/app/views/api/v1/models/captain/_assistant_response.json.jbuilder`
- Test: `spec/enterprise/lib/captain/tools/faq_lookup_tool_spec.rb`

**Interfaces:**
- Produces: `captain_assistant_responses.usos` (inteiro, default 0) e `usada_em` (datetime); JSON da FAQ ganha `usos` e `usada_em` (epoch em segundos, ou `null`).

- [ ] **Step 1: Spec (documentação — `spec/enterprise`)** — no `describe '#perform'`, acrescentar:

```ruby
    describe 'contador de uso (I-FQ6)' do
      let!(:faq) do
        create(:captain_assistant_response, assistant: assistant, question: 'Quanto custa o honorário?',
                                            answer: '30% dos atrasados + 3 parcelas do benefício', status: 'approved')
      end

      def buscar(source)
        with_modified_env(RAMON_FAQ_BUSCA: 'texto') do
          tool.perform(Struct.new(:state).new({ source: source }), query: 'honorário')
        end
      end

      it 'conta no atendimento de verdade e nao no Testar nem no caso de teste', :aggregate_failures do
        buscar(nil)
        buscar('playground')
        buscar('teste')

        expect(faq.reload.usos).to eq(1)
        expect(faq.usada_em).to be_present
        expect(faq.edited).to be(false)
      end
    end
```

- [ ] **Step 2: Migração** — `db/migrate/20261007800002_add_uso_to_captain_assistant_responses.rb`:

```ruby
# FAQ "usada X vezes" (Inteligência A5 — I-FQ6): quantas vezes a ferramenta faq_lookup devolveu a FAQ no
# atendimento de verdade, e quando foi a última.
class AddUsoToCaptainAssistantResponses < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_assistant_responses, :usos, :integer, default: 0, null: false
    add_column :captain_assistant_responses, :usada_em, :datetime
  end
end
```
`db/schema.rb`: no bloco `create_table "captain_assistant_responses"`, depois de `    t.string "tese"`:

```ruby
    t.integer "usos", default: 0, null: false
    t.datetime "usada_em"
```
e `define(version: 2026_10_07_800001)` → `define(version: 2026_10_07_800002)`.

- [ ] **Step 3: Ferramenta** — `faq_lookup_tool.rb`: `def perform(_tool_context, query:)` vira `def perform(tool_context, query:)`; no `else`, antes de `log_tool_usage('found_results', …)`, chamar `contar_uso(tool_context, responses)`; em `private`, no topo:

```ruby
  # ramon (I-FQ6): "usada X vezes" — conta só o atendimento de verdade (Testar e Casos de teste ficam de fora).
  # update_all: não mexe em updated_at nem marca a FAQ como editada.
  def contar_uso(tool_context, responses)
    return if %w[playground teste].include?(tool_context&.state&.dig(:source).to_s)

    ::Captain::AssistantResponse.where(id: responses.map(&:id))
                                .update_all(['usos = usos + 1, usada_em = ?', Time.current]) # rubocop:disable Rails/SkipsModelValidations
  end
```

- [ ] **Step 4: JSON** — `_assistant_response.json.jbuilder`, no fim:

```ruby
json.usos resource.usos
json.usada_em resource.usada_em&.to_i
```

- [ ] **Step 5: Rastrear à mão** — `buscar(nil)`: `state = { source: nil }` → `''` não está na lista → conta; os outros dois saem no `return`. `update_all` com array é SQL sanitizado. Linha do `update_all` < 150.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20261007800002_add_uso_to_captain_assistant_responses.rb db/schema.rb enterprise/lib/captain/tools/faq_lookup_tool.rb enterprise/app/views/api/v1/models/captain/_assistant_response.json.jbuilder spec/enterprise/lib/captain/tools/faq_lookup_tool_spec.rb
git commit -m "feat(faq): contador de uso da FAQ no atendimento de verdade (I-FQ6)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 11: FAQs e Documentos — sempre do Atendimento, "usada N×", aviso do link e `CONTEXT.md` (I-FQ5, I-FQ6, I-DO4, I-DO5, I-T4) (julgamento leve)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/pages/assistenteDasFaqs.js`, `.../pages/specs/assistenteDasFaqs.spec.js`, `app/javascript/dashboard/components-next/captain/assistant/specs/ResponseCard.spec.js`
- Modify: `app/javascript/dashboard/components-next/captain/PageLayout.vue:57-60`, `app/javascript/dashboard/routes/dashboard/captain/pages/AssistantsIndexPage.vue`, `app/javascript/dashboard/components-next/captain/assistant/ResponseCard.vue`, `app/javascript/dashboard/routes/dashboard/captain/responses/Index.vue`, `app/javascript/dashboard/components-next/captain/pageComponents/document/DocumentForm.vue`, `CONTEXT.md:165-168`
- Test: `app/javascript/dashboard/components-next/captain/pageComponents/document/specs/DocumentForm.spec.js`

**Interfaces:**
- Consumes: Task 10 (`usos`, `usada_em`); `CaptainAssistant.stats()`; Tasks 5, 8 e 9 já passam `show-assistant-switcher` em Skills, Testar e Configurações (Casos de teste já passava).
- Produces: `assistenteDasFaqs(stats)` → `{ id, … } | null`; `ROTAS_DAS_FAQS`; `PageLayout` **sem seletor por padrão**.
- Se o Eduardo escolher **N5 (b)** (manter o seletor em FAQs e Documentos): pular os Steps 3–4 (e o spec do `assistenteDasFaqs`) e passar `show-assistant-switcher` em `responses/Index.vue`, `responses/Pending.vue` e `documents/Index.vue`.

- [ ] **Step 1: Specs (falham antes)** — `pages/specs/assistenteDasFaqs.spec.js`:

```js
import { assistenteDasFaqs } from '../assistenteDasFaqs';

describe('assistenteDasFaqs (I-FQ5)', () => {
  it('o que fala com o lead (tem caixa conectada)', () => {
    expect(
      assistenteDasFaqs([
        { id: 2, publico: 'equipe', faqs_aprovadas: 90 },
        { id: 1, publico: 'lead', faqs_aprovadas: 62 },
      ]).id
    ).toBe(1);
  });

  it('sem caixa conectada: o que tem mais FAQs aprovadas; sem nenhum, null', () => {
    expect(
      assistenteDasFaqs([
        { id: 2, publico: 'equipe', faqs_aprovadas: 0 },
        { id: 1, publico: 'equipe', faqs_aprovadas: 62 },
      ]).id
    ).toBe(1);
    expect(assistenteDasFaqs([])).toBeNull();
  });
});
```
`components-next/captain/assistant/specs/ResponseCard.spec.js`:

```js
import { mount } from '@vue/test-utils';
import ResponseCard from '../ResponseCard.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const montar = props =>
  mount(ResponseCard, {
    props: {
      id: 1,
      question: 'Quanto custa?',
      answer: '30% + 3',
      createdAt: 1,
      updatedAt: 1,
      ...props,
    },
    global: {
      stubs: {
        CardLayout: { template: '<div><slot /></div>' },
        Policy: true,
        DropdownMenu: true,
        Button: true,
        Checkbox: true,
        Icon: true,
      },
    },
  });

describe('ResponseCard — uso (I-FQ6)', () => {
  it('aprovada mostra quantas vezes foi usada', () => {
    expect(montar({ usos: 3 }).find('[data-testid="faq-uso"]').text()).toBe(
      'INTEL.FAQ.USADA'
    );
    expect(montar({ usos: 0 }).find('[data-testid="faq-uso"]').text()).toBe(
      'INTEL.FAQ.NUNCA_USADA'
    );
  });

  it('pendente não mostra uso', () => {
    expect(
      montar({ status: 'pending', usos: 3 }).find('[data-testid="faq-uso"]').exists()
    ).toBe(false);
  });
});
```
Em `DocumentForm.spec.js` (A3), acrescentar:

```js
  it('link avisa que lê as páginas ligadas; colar texto não (I-DO4)', async () => {
    const wrapper = montar();
    expect(wrapper.find('[data-testid="documento-link-aviso"]').exists()).toBe(true);
    await wrapper.find('[data-testid="documento-modo-texto"]').trigger('click');
    expect(wrapper.find('[data-testid="documento-link-aviso"]').exists()).toBe(false);
  });
```
(usar o `montar` que o arquivo já tem; se o nome for outro, adaptar.)

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/pages/specs/assistenteDasFaqs.spec.js app/javascript/dashboard/components-next/captain/assistant/specs/ResponseCard.spec.js app/javascript/dashboard/components-next/captain/pageComponents/document/specs/DocumentForm.spec.js --config vitest.local.config.ts` → FAIL.

- [ ] **Step 3: `assistenteDasFaqs.js`** (Write):

```js
// FAQs e Documentos são do assistente que fala com o lead (I-FQ5): o primeiro com caixa conectada; sem
// nenhum, o que tem mais FAQs aprovadas. null = conta sem assistente. Entrada = captain/assistants/stats.
export const assistenteDasFaqs = (stats = []) =>
  stats.find(item => item.publico === 'lead') ||
  [...stats].sort((a, b) => b.faqs_aprovadas - a.faqs_aprovadas)[0] ||
  null;

export const ROTAS_DAS_FAQS = [
  'captain_assistants_responses_index',
  'captain_assistants_documents_index',
];
```

- [ ] **Step 4: Abrir FAQs/Documentos no assistente do lead** — `AssistantsIndexPage.vue`:
  - imports: `import { computed, nextTick, onMounted, ref } from 'vue';`, `import CaptainAssistantAPI from 'dashboard/api/captain/assistant';`, `import { ROTAS_DAS_FAQS, assistenteDasFaqs } from './assistenteDasFaqs';`
  - depois de `const assistants = computed(...)`: `const daFaq = ref(null);`
  - `generateRouterParams` começa com:
    ```js
      // I-FQ5: FAQs e Documentos abrem sempre no assistente que fala com o lead.
      if (daFaq.value) return { assistantId: daFaq.value };
    ```
  - `performRouting` vira:
    ```js
    const performRouting = async () => {
      await store.dispatch('captainAssistants/get');
      if (ROTAS_DAS_FAQS.includes(route.params.navigationPath)) {
        try {
          const { data } = await CaptainAssistantAPI.stats();
          daFaq.value = assistenteDasFaqs(data.payload)?.id ?? null;
        } catch (e) {
          daFaq.value = null;
        }
      }
      nextTick(() => routeToLastActiveAssistant());
    };
    ```

- [ ] **Step 5: Seletor só onde faz sentido (I-T4)** — `PageLayout.vue`, prop `showAssistantSwitcher`: `default: true` → `default: false`, com o comentário `// ramon (I-T4): seletor só em Skills, Testar, Casos de teste e Configurações — elas passam show-assistant-switcher.` Conferir: `grep -rn "show-assistant-switcher" app/javascript/dashboard/routes/dashboard/captain` → `scenarios/Index.vue`, `playground/Index.vue`, `casos/CasosTeste.vue`, `settings/Settings.vue` (as 3 que passavam `false` podem ficar como estão).

- [ ] **Step 6: "Usada N×" (I-FQ6)** — `ResponseCard.vue`:
  - props, depois de `tese`: `usos: { type: Number, default: 0 },` e `usadaEm: { type: Number, default: null },`
  - script:
    ```js
    const usoTexto = computed(() =>
      props.usos
        ? t('INTEL.FAQ.USADA', { n: props.usos })
        : t('INTEL.FAQ.NUNCA_USADA')
    );
    const usoAjuda = computed(() =>
      props.usadaEm
        ? t('INTEL.FAQ.USADA_AJUDA', {
            quando: new Date(props.usadaEm * 1000).toLocaleDateString('pt-BR'),
          })
        : ''
    );
    ```
  - template, logo depois do chip da tese (`data-testid="faq-tese-chip"`):
    ```vue
          <span
            v-if="status === 'approved'"
            data-testid="faq-uso"
            class="shrink-0"
            :class="[CHIP, usos ? TOM.blue : TOM.slate]"
            :title="usoAjuda"
          >
            {{ usoTexto }}
          </span>
    ```
  `responses/Index.vue`, no `<ResponseCard …>`: acrescentar `:usos="response.usos || 0"` e `:usada-em="response.usada_em || null"`.

- [ ] **Step 7: Aviso do link (I-DO4)** — `DocumentForm.vue`: importar `AVISO` e `TOM` do kit (junto de `ABA*`); no `<template v-else>` (modo link), depois do 1º `<Input>` (URL):

```vue
      <p data-testid="documento-link-aviso" :class="[AVISO, TOM.amber]">
        {{ t('INTEL.DOCUMENTOS.LINK_AVISO') }}
      </p>
```

- [ ] **Step 8: `CONTEXT.md` (I-DO5)** — trocar

```markdown
**Documento (da Inteligência)**:
Material de referência que o *Assistente* consulta (guia da tese, política de
honorários, checklist) — distinto de Documento do cliente no Checklist.
```
por
```markdown
**Documento (da Inteligência)**:
Página da web ou texto colado que o administrador cadastra para **gerar FAQs
pendentes**. O *Assistente* não lê o documento: ele só usa as FAQs depois de
aprovadas (decisão D4, 16/08/2026). Distinto de Documento do cliente no Checklist.
```

- [ ] **Step 9: Rodar e ver passar** — o comando do Step 2 + `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/captain --config vitest.local.config.ts` (nada antigo quebrou com o seletor desligado por padrão) + `./node_modules/.bin/eslint app/javascript/dashboard/components-next/captain/PageLayout.vue app/javascript/dashboard/routes/dashboard/captain/pages app/javascript/dashboard/components-next/captain/assistant/ResponseCard.vue app/javascript/dashboard/routes/dashboard/captain/responses/Index.vue app/javascript/dashboard/components-next/captain/pageComponents/document/DocumentForm.vue` sem `error`.

- [ ] **Step 10: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/pages/assistenteDasFaqs.js app/javascript/dashboard/routes/dashboard/captain/pages/specs/assistenteDasFaqs.spec.js app/javascript/dashboard/routes/dashboard/captain/pages/AssistantsIndexPage.vue app/javascript/dashboard/components-next/captain/PageLayout.vue app/javascript/dashboard/components-next/captain/assistant/ResponseCard.vue app/javascript/dashboard/components-next/captain/assistant/specs/ResponseCard.spec.js app/javascript/dashboard/routes/dashboard/captain/responses/Index.vue app/javascript/dashboard/components-next/captain/pageComponents/document/DocumentForm.vue app/javascript/dashboard/components-next/captain/pageComponents/document/specs/DocumentForm.spec.js CONTEXT.md
git commit -m "feat(faq): FAQs e Documentos sempre do Atendimento, usada N vezes, aviso do link e seletor só onde faz sentido (I-FQ5, I-FQ6, I-DO4, I-DO5, I-T4)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 12: Caixas e ferramentas HTTP — textos, nome do assistente, kit (I-CX3, I-T4, I-T5) (mecânica)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/inboxes/Index.vue`, `app/javascript/dashboard/routes/dashboard/captain/tools/Index.vue:113-118`, `app/javascript/dashboard/components-next/captain/pageComponents/customTool/CustomToolForm.vue:300-307`

**Interfaces:**
- Consumes: Task 2 (`INTEL.CAIXAS.TITULO`; "Sim, desconectar", descrição e placeholder novos em `integrations.json` — esses aparecem sozinhos na janela de desconectar e no formulário de conectar).

- [ ] **Step 1: Caixas com o nome do assistente (sem seletor)** — `inboxes/Index.vue`:
  - `import { useI18n } from 'vue-i18n';` e `const { t } = useI18n();`
  - depois de `const assistantId = computed(...)`:
    ```js
    // I-T4: sem seletor — o título diz de qual assistente são as caixas (a tela abre pelo cartão dele).
    const titulo = computed(() =>
      t('INTEL.CAIXAS.TITULO', {
        nome:
          store.getters['captainAssistants/getRecord'](Number(assistantId.value))
            ?.name || '',
      })
    );
    ```
  - `<PageLayout :header-title="$t('CAPTAIN.INBOXES.HEADER')" …>` → `:header-title="titulo"`.

- [ ] **Step 2: Ferramentas HTTP no kit (I-T5)** — `tools/Index.vue`: importar `import { AVISO, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';` e trocar

```vue
          class="flex items-center gap-2 px-4 py-3 text-sm rounded-lg bg-n-amber-2 text-n-amber-11"
```
por
```vue
          class="flex items-center gap-2"
          :class="[AVISO, TOM.amber]"
```
`CustomToolForm.vue`: importar `TOM` do mesmo kit e trocar

```vue
        :class="
          testResult.success
            ? 'bg-n-teal-2 text-n-teal-11'
            : 'bg-n-ruby-2 text-n-ruby-11'
        "
```
por
```vue
        :class="testResult.success ? TOM.teal : TOM.ruby"
```

- [ ] **Step 3: Conferir** — `TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain --config vitest.local.config.ts` verde; `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/assistants/inboxes/Index.vue app/javascript/dashboard/routes/dashboard/captain/tools/Index.vue app/javascript/dashboard/components-next/captain/pageComponents/customTool/CustomToolForm.vue` sem `error`. (Sem spec novo: troca de classe e de título — o print da Task 19 confere.)

- [ ] **Step 4: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/assistants/inboxes/Index.vue app/javascript/dashboard/routes/dashboard/captain/tools/Index.vue app/javascript/dashboard/components-next/captain/pageComponents/customTool/CustomToolForm.vue
git commit -m "feat(caixas): título com o assistente, desconectar sem 'excluir' e ferramentas HTTP no kit (I-CX3, I-T4, I-T5)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 13: Execuções — período, "carregar mais", "só erros de hoje" e filtro por caso na API (I-EX3, I-EX5, I-X8) (mecânica)

**Files:**
- Modify: `app/controllers/api/v1/accounts/captain_tool_runs_controller.rb`, `app/views/api/v1/accounts/captain_tool_runs/index.json.jbuilder`, `app/controllers/api/v1/accounts/ramon_agente_execucoes_controller.rb`, `app/javascript/dashboard/api/ramonAgenteExecucoes.js`, `app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue`
- Test: `spec/controllers/api/v1/accounts/captain_tool_runs_controller_spec.rb`, `spec/controllers/api/v1/accounts/ramon_agente_execucoes_controller_spec.rb`, `app/javascript/dashboard/routes/dashboard/captain/pages/specs/Execucoes.spec.js`

**Interfaces:**
- Produces: `GET captain_tool_runs` aceita `periodo` (`hoje` | `7d` | `30d`), `lead_id` e `antes_de` (id; devolve as mais antigas que ele) e responde `mais: Boolean`; `GET ramon_agente_execucoes` aceita `lead_id`; `RamonAgenteExecucoesAPI.list(params = {})`. A Task 15 usa os dois com `lead_id`.

- [ ] **Step 1: Specs (falham antes)** — em `captain_tool_runs_controller_spec.rb`:

```ruby
  it 'filtra por caso e por periodo e pagina com antes_de (I-EX3, I-X8)', :aggregate_failures do
    lead = create(:lead, account: account)
    velha = Captain::ToolRun.create!(account_id: account.id, tool_name: 'checar_prescricao', status: 'ok',
                                     lead_id: lead.id, created_at: 10.days.ago)
    nova = Captain::ToolRun.create!(account_id: account.id, tool_name: 'mover_etapa', status: 'ok', lead_id: lead.id)
    registrar('calcular_beneficio')

    get url, params: { lead_id: lead.id }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['items'].pluck('id')).to eq([nova.id, velha.id])
    expect(response.parsed_body['mais']).to be(false)

    get url, params: { lead_id: lead.id, periodo: '7d' }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['items'].pluck('id')).to eq([nova.id])

    get url, params: { lead_id: lead.id, antes_de: nova.id }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['items'].pluck('id')).to eq([velha.id])
  end
```
Em `ramon_agente_execucoes_controller_spec.rb` (no nível de cima do `RSpec.describe`):

```ruby
  it 'filtra pelo caso (I-X8)' do
    admin = create(:user, account: account, role: :administrator)
    lead = create(:lead, account: account)
    account.agente_execucoes.create!(pedido: 'do caso', status: 'ok', lead: lead)
    account.agente_execucoes.create!(pedido: 'de outro', status: 'ok')

    get url, params: { lead_id: lead.id }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['items'].pluck('pedido')).to eq(['do caso'])
  end
```
(Se `AgenteExecucao` não tiver `belongs_to :lead`, usar `lead_id: lead.id` — o controller já faz `includes(:lead)`, então a associação existe.)
Em `Execucoes.spec.js`, acrescentar:

```js
describe('Execuções — período e páginas (I-EX3, I-EX5)', () => {
  it('período e "só erros de hoje" vão na API', async () => {
    const wrapper = await montar();
    await wrapper.find('[data-testid="execucoes-periodo"]').setValue('7d');
    expect(CaptainToolRunsAPI.list).toHaveBeenLastCalledWith({ periodo: '7d' });
    await wrapper.find('[data-testid="execucoes-so-erros-hoje"]').trigger('click');
    expect(CaptainToolRunsAPI.list).toHaveBeenLastCalledWith({
      status: 'erro',
      periodo: 'hoje',
    });
  });

  it('carregar mais pede antes_de com os mesmos filtros e soma as linhas', async () => {
    const wrapper = await montar({ mais: true });
    await wrapper.find('[data-testid="execucoes-periodo"]').setValue('30d');
    await flushPromises();
    CaptainToolRunsAPI.list.mockResolvedValueOnce({
      data: { resumo: {}, items: [{ ...RUN, id: 99 }], catalogo: [], mais: false },
    });
    await wrapper.find('[data-testid="execucoes-mais"]').trigger('click');
    await flushPromises();
    expect(CaptainToolRunsAPI.list).toHaveBeenLastCalledWith({
      periodo: '30d',
      antes_de: 2,
    });
    expect(wrapper.findAll('[data-testid="execucoes-linha"]')).toHaveLength(3);
    expect(wrapper.find('[data-testid="execucoes-mais"]').exists()).toBe(false);
  });
});
```
e o `montar` do arquivo passa a aceitar um extra: `const montar = async (extra = {}) => { CaptainToolRunsAPI.list.mockResolvedValue({ data: { …o que já tem…, ...extra } }); … }` (o `mockResolvedValue` atual vira a base; `extra` entra no fim do objeto `data`).

- [ ] **Step 2: Rodar o vitest e ver falhar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/pages/specs/Execucoes.spec.js --config vitest.local.config.ts` → FAIL nos 2 novos.

- [ ] **Step 3: Backend** — `captain_tool_runs_controller.rb`:

```ruby
class Api::V1::Accounts::CaptainToolRunsController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 100
  FILTROS = %i[tool_name status lead_id].freeze
  # I-EX3: período da lista ("hoje" no fuso de Brasília — o servidor roda em UTC)
  PERIODOS = {
    'hoje' => -> { Time.find_zone!('America/Sao_Paulo').now.all_day },
    '7d' => -> { 7.days.ago..Time.current },
    '30d' => -> { 30.days.ago..Time.current }
  }.freeze
```
`index`: depois de `@tool_runs = …`: `@mais = @tool_runs.size == LIST_LIMIT`. `escopo` vira:

```ruby
  # I-EX3/I-X8: ferramenta, status, caso, período e "carregar mais" (antes_de = id da última linha da tela).
  def escopo
    runs = Captain::ToolRun.fora_de_teste.where(account_id: Current.account.id)
    FILTROS.each { |campo| runs = runs.where(campo => params[campo]) if params[campo].present? }
    runs = runs.where(created_at: PERIODOS[params[:periodo]].call) if PERIODOS.key?(params[:periodo])
    params[:antes_de].present? ? runs.where(id: ...params[:antes_de].to_i) : runs
  end
```
`index.json.jbuilder`, no topo: `json.mais @mais`.
`ramon_agente_execucoes_controller.rb`, `index`:

```ruby
  def index
    execucoes = visiveis.includes(:lead, :conversation).order(created_at: :desc, id: :desc).limit(LIMITE)
    # I-X8: "o que a IA fez neste caso" (painel do lead)
    execucoes = execucoes.where(lead_id: params[:lead_id]) if params[:lead_id].present?
    render json: { resumo: resumo, items: execucoes.map { |execucao| linha(execucao) } }
  end
```
`api/ramonAgenteExecucoes.js`: `list() { return axios.get(this.url); }` → `list(params = {}) { return axios.get(this.url, { params }); }`.

- [ ] **Step 4: Front `Execucoes.vue`**
  - script: depois de `const aberto = ref(null);`:
    ```js
    const periodo = ref('');
    const linhas = ref([]);
    const carregandoMais = ref(false);
    const PERIODOS = [
      { valor: '', rotulo: 'INTEL.EXECUCOES.PERIODO.TUDO' },
      { valor: 'hoje', rotulo: 'INTEL.EXECUCOES.PERIODO.HOJE' },
      { valor: '7d', rotulo: 'INTEL.EXECUCOES.PERIODO.D7' },
      { valor: '30d', rotulo: 'INTEL.EXECUCOES.PERIODO.D30' },
    ];

    const montarParams = antesDe => {
      const params = {};
      if (filtroTool.value) params.tool_name = filtroTool.value;
      if (filtroStatus.value) params.status = filtroStatus.value;
      if (periodo.value) params.periodo = periodo.value;
      if (antesDe) params.antes_de = antesDe;
      return params;
    };
    ```
  - `fetchData`: trocar o bloco que monta `params` por `const response = await CaptainToolRunsAPI.list(montarParams());` e, depois de `data.value = response.data;`, `linhas.value = response.data.items;`.
  - depois de `onMounted(fetchData);`:
    ```js
    // I-EX3: mais 100, a partir da última linha, com os mesmos filtros.
    const carregarMais = async () => {
      carregandoMais.value = true;
      try {
        const { data: pagina } = await CaptainToolRunsAPI.list(
          montarParams(linhas.value[linhas.value.length - 1].id)
        );
        linhas.value = [...linhas.value, ...pagina.items];
        data.value = { ...data.value, mais: pagina.mais };
      } catch (e) {
        error.value = true;
      } finally {
        carregandoMais.value = false;
      }
    };

    // I-EX5: atalho "só erros de hoje".
    const soErrosDeHoje = () => {
      filtroStatus.value = 'erro';
      periodo.value = 'hoje';
      fetchData();
    };
    ```
  - apagar `const items = computed(() => data.value?.items ?? []);` e trocar no template `items` → `linhas` (`v-else-if="!linhas.length"` e `v-for="run in linhas"`).
  - template, na `<div class="flex flex-wrap gap-2 mt-5">` dos filtros, depois do 2º `<select>`:
    ```vue
            <select
              v-model="periodo"
              data-testid="execucoes-periodo"
              class="!w-44"
              :class="SELECT"
              @change="fetchData"
            >
              <option v-for="item in PERIODOS" :key="item.valor" :value="item.valor">
                {{ t(item.rotulo) }}
              </option>
            </select>
            <button
              type="button"
              data-testid="execucoes-so-erros-hoje"
              class="hover:brightness-110"
              :class="[CHIP, TOM.ruby]"
              @click="soErrosDeHoje"
            >
              {{ t('INTEL.EXECUCOES.SO_ERROS_HOJE') }}
            </button>
    ```
  - depois do `</ul>` da lista (ainda dentro do `<template v-else>` da aba ferramentas):
    ```vue
          <button
            v-if="data?.mais && linhas.length"
            type="button"
            data-testid="execucoes-mais"
            class="mt-3"
            :class="LINK"
            :disabled="carregandoMais"
            @click="carregarMais"
          >
            {{ t('INTEL.EXECUCOES.CARREGAR_MAIS') }}
          </button>
    ```
    (O `setValue` do select no spec dispara `change` — o `@change="fetchData"` roda.)

- [ ] **Step 5: Rastrear backend à mão** — `escopo`: 3 filtros no `each` (só os presentes), período por lambda, cursor `id < antes_de`; CyclomaticComplexity 5; AbcSize ~18. Spec: sem filtro = `[nova, velha]` (`recentes` = created_at desc); `7d` corta a de 10 dias; `antes_de: nova.id` → só ids menores (velha foi criada antes → id menor). `mais` false (2 < 100). Agente: `where(lead_id:)` depois do `limit` é aceito pelo AR (vira `WHERE … LIMIT`).

- [ ] **Step 6: Rodar e ver passar** — o vitest do Step 2 (todos verdes) + `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue app/javascript/dashboard/api/ramonAgenteExecucoes.js` sem `error`.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/accounts/captain_tool_runs_controller.rb app/views/api/v1/accounts/captain_tool_runs/index.json.jbuilder app/controllers/api/v1/accounts/ramon_agente_execucoes_controller.rb app/javascript/dashboard/api/ramonAgenteExecucoes.js app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue app/javascript/dashboard/routes/dashboard/captain/pages/specs/Execucoes.spec.js spec/controllers/api/v1/accounts/captain_tool_runs_controller_spec.rb spec/controllers/api/v1/accounts/ramon_agente_execucoes_controller_spec.rb
git commit -m "feat(execucoes): período, carregar mais, só erros de hoje e filtro por caso (I-EX3, I-EX5, I-X8)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 14: Vigia — abrir a conversa e cor pela régua (I-WD3, I-WD4) (mecânica)

**Files:**
- Modify: `app/controllers/api/v1/accounts/ramon_watchdog_controller.rb` (`em_alerta`), `app/javascript/dashboard/routes/dashboard/captain/pages/VigiaBloco.vue`
- Test: `spec/controllers/api/v1/accounts/ramon_watchdog_controller_spec.rb`, `app/javascript/dashboard/routes/dashboard/captain/pages/specs/VigiaBloco.spec.js`

**Interfaces:**
- Consumes: `useAbrir()` de `captain/pages/execucoes.js` (`abrirCaso(id)`, `abrirConversa(displayId)`).
- Produces: cada caso parado ganha `conversa_display_id` (nº da conversa ou `null`).

- [ ] **Step 1: Specs (falham antes)** — `ramon_watchdog_controller_spec.rb`:

```ruby
  it 'devolve o numero da conversa de cada caso parado (I-WD3)' do
    conversa = create(:conversation, account: account)
    parado = create(:lead, account: account, lead_stage: stage, conversation: conversa)
    Lead.where(id: parado.id).update_all(stage_entered_at: 10.days.ago) # rubocop:disable Rails/SkipsModelValidations

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['items'].first).to include('conversa_display_id' => conversa.display_id)
  end
```
`VigiaBloco.spec.js` — acrescentar (com o mesmo `vi.mock` do arquivo; o `useRouter` mockado passa a ser `const push = vi.fn()` compartilhado via `vi.hoisted`):

```js
const montarCom = async items => {
  RamonWatchdogAPI.get.mockResolvedValue({
    data: { thresholds: { ...BASE, teto_diario: 15 }, counters: {}, items },
  });
  const wrapper = mount(VigiaBloco);
  await flushPromises();
  return wrapper;
};
const ITEM = {
  lead_id: 12,
  name: 'Maria',
  stage_name: 'Qualificação',
  dias_parado: 6,
  tentativas: 1,
  conversa_display_id: 482,
};

describe('Vigia: conversa e gravidade (I-WD3, I-WD4)', () => {
  it('abre a conversa pelo nº', async () => {
    const wrapper = await montarCom([ITEM]);
    await wrapper.find('[data-testid="watchdog-conversa"]').trigger('click');
    expect(push).toHaveBeenCalledWith('inbox_conversation');
  });

  it('âmbar até 2 retomadas; vermelho no limite da régua (3+)', async () => {
    const wrapper = await montarCom([ITEM, { ...ITEM, lead_id: 13, tentativas: 3 }]);
    const chips = wrapper.findAll('[data-testid="watchdog-tentativas"]');
    expect(chips[0].classes()).toContain('text-n-amber-11');
    expect(chips[1].classes()).toContain('text-n-ruby-11');
  });

  it('sem conversa, sem botão', async () => {
    const wrapper = await montarCom([{ ...ITEM, conversa_display_id: null }]);
    expect(wrapper.find('[data-testid="watchdog-conversa"]').exists()).toBe(false);
  });
});
```
(O mock de `useAccount` do arquivo devolve `accountScopedRoute: n => n` — por isso `push` recebe o nome da rota.)

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/pages/specs/VigiaBloco.spec.js --config vitest.local.config.ts` → FAIL.

- [ ] **Step 3: Backend** — `ramon_watchdog_controller.rb`, `em_alerta` vira:

```ruby
  # Em alerta = parado no funil, ordenado por quem já levou mais tentativa de
  # retomada sem responder (é onde a régua está no limite). I-WD3: nº da conversa
  # (o que a rota da tela usa) só das linhas que vão para a tela — 1 consulta.
  def em_alerta
    linhas = parados.map { |lead| row_for(lead) }
                    .sort_by { |row| [-row[:tentativas], -row[:dias_parado]] }
                    .first(LIST_LIMIT)
    numeros = Current.account.conversations.where(id: linhas.filter_map { |linha| linha[:conversation_id] })
                     .pluck(:id, :display_id).to_h
    linhas.each { |linha| linha[:conversa_display_id] = numeros[linha[:conversation_id]] }
  end
```

- [ ] **Step 4: Front `VigiaBloco.vue`**
  - imports: trocar `useRouter`, `useStore`, `useAccount` pelo `import { useAbrir } from './execucoes';` e `import Button from 'dashboard/components-next/button/Button.vue';`; `const { abrirCaso, abrirConversa } = useAbrir();` e **apagar** `openLead` (o template usa `abrirCaso`).
  - script:
    ```js
    // I-WD4: a régua de retomada tem 3 ângulos (FollowUpDraftService#angle_for) — da 3ª em diante está no limite.
    const REGUA = 3;
    const tomRegua = tentativas => (tentativas >= REGUA ? TOM.ruby : TOM.amber);
    ```
  - cada linha da lista vira (o `<button>` com `LINHA` passa a ficar dentro de uma `div`, ao lado do botão da conversa — botão dentro de botão não vale em HTML):
    ```vue
        <div
          v-for="item in visiveis"
          :key="item.lead_id"
          data-testid="watchdog-linha"
          class="flex items-start gap-1"
        >
          <button
            type="button"
            class="flex-1 min-w-0"
            :class="LINHA"
            @click="abrirCaso(item.lead_id)"
          >
            <!-- conteúdo atual do botão (VigiaBloco.vue:140-164), sem mudança, exceto o chip das tentativas -->
          </button>
          <Button
            v-if="item.conversa_display_id"
            data-testid="watchdog-conversa"
            icon="i-lucide-message-circle"
            size="xs"
            variant="ghost"
            color="slate"
            class="mt-1 shrink-0"
            :title="t('INTEL.VIGIA.CONVERSA')"
            :aria-label="t('INTEL.VIGIA.CONVERSA')"
            @click="abrirConversa(item.conversa_display_id)"
          />
        </div>
    ```
  - o chip das tentativas (hoje `<span v-if="item.tentativas" :class="[CHIP, TOM.amber]">`) vira:
    ```vue
            <span
              v-if="item.tentativas"
              data-testid="watchdog-tentativas"
              :class="[CHIP, tomRegua(item.tentativas)]"
              :title="item.tentativas >= REGUA ? t('INTEL.VIGIA.NO_LIMITE') : ''"
            >
    ```
    (o texto de dentro — `CAPTAIN_RAMON.WATCHDOG.TENTATIVAS` — fica igual).
  - `useAbrir` usa `useStore` de `dashboard/composables/store` e `useRouter` — o spec já mocka os dois.

- [ ] **Step 5: Rodar e ver passar** — o vitest do Step 2 (os 2 antigos + 3 novos) + eslint em `VigiaBloco.vue` sem `error`. Rastrear o spec Ruby: o lead com `conversation:` entra em `parados` (stage com `stalled_after_days: 3`, 10 dias parado) → `numeros = { conversa.id => conversa.display_id }`.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/accounts/ramon_watchdog_controller.rb app/javascript/dashboard/routes/dashboard/captain/pages/VigiaBloco.vue app/javascript/dashboard/routes/dashboard/captain/pages/specs/VigiaBloco.spec.js spec/controllers/api/v1/accounts/ramon_watchdog_controller_spec.rb
git commit -m "feat(vigia): abrir a conversa do caso parado e cor pela régua de retomada (I-WD3, I-WD4)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 15: Caso — "O que a IA fez neste caso" no painel do lead (I-X8) (mecânica)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadIaExecucoes.vue`, `.../lead/specs/LeadIaExecucoes.spec.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue` (1 import + 1 linha na aba Atividade)

**Interfaces:**
- Consumes: Task 13 (`lead_id` nos dois endpoints); `ferramentaInfo` (`ramon/helpers/ferramentas`), `STATUS_TOM` e `fmtHora` (`captain/pages/execucoes.js`).

- [ ] **Step 1: Spec (falha antes)** — `specs/LeadIaExecucoes.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';
import RamonAgenteExecucoesAPI from 'dashboard/api/ramonAgenteExecucoes';
import LeadIaExecucoes from '../LeadIaExecucoes.vue';

vi.mock('dashboard/api/captainToolRuns', () => ({ default: { list: vi.fn() } }));
vi.mock('dashboard/api/ramonAgenteExecucoes', () => ({
  default: { list: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: n => n }),
}));

describe('LeadIaExecucoes (I-X8)', () => {
  it('junta ferramentas e agente do caso, mais nova primeiro', async () => {
    CaptainToolRunsAPI.list.mockResolvedValue({
      data: {
        items: [
          { id: 1, tool_name: 'mover_etapa', status: 'ok', created_at: '2026-10-07T10:00:00Z' },
        ],
        catalogo: [{ id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao' }],
      },
    });
    RamonAgenteExecucoesAPI.list.mockResolvedValue({
      data: {
        items: [
          { id: 7, pedido: 'anote a ligação', status: 'ok', created_at: '2026-10-07T11:00:00Z' },
        ],
      },
    });
    const wrapper = mount(LeadIaExecucoes, { props: { leadId: 12 } });
    await flushPromises();
    expect(CaptainToolRunsAPI.list).toHaveBeenCalledWith({ lead_id: 12 });
    expect(RamonAgenteExecucoesAPI.list).toHaveBeenCalledWith({ lead_id: 12 });
    expect(
      wrapper.findAll('[data-testid="caso-ia-linha"]').map(l => l.text())
    ).toEqual([
      expect.stringContaining('INTEL.CASO_IA.AGENTE'),
      expect.stringContaining('Mover de etapa'),
    ]);
  });

  it('nada no caso: aviso', async () => {
    CaptainToolRunsAPI.list.mockResolvedValue({ data: { items: [], catalogo: [] } });
    RamonAgenteExecucoesAPI.list.mockResolvedValue({ data: { items: [] } });
    const wrapper = mount(LeadIaExecucoes, { props: { leadId: 12 } });
    await flushPromises();
    expect(wrapper.text()).toContain('INTEL.CASO_IA.VAZIO');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadIaExecucoes.spec.js --config vitest.local.config.ts` → FAIL.

- [ ] **Step 3: `LeadIaExecucoes.vue`** (Write):

```vue
<script setup>
// "O que a IA fez neste caso" (I-X8): as ferramentas que a IA rodou e os pedidos ao agente Claude com este
// lead — as mesmas trilhas das Execuções, filtradas pelo caso (as 10 mais novas). Leitura pura.
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';
import RamonAgenteExecucoesAPI from 'dashboard/api/ramonAgenteExecucoes';
import { CHIP, SECAO, TITULO, TOM } from '../../helpers/ui';
import { ferramentaInfo } from '../../helpers/ferramentas';
import {
  STATUS_TOM,
  fmtHora,
} from 'dashboard/routes/dashboard/captain/pages/execucoes';

const props = defineProps({
  leadId: { type: Number, required: true },
});

const VISIVEIS = 10;
const { t } = useI18n();
const linhas = ref([]);
const carregando = ref(true);
const erro = ref(false);

const carregar = async () => {
  carregando.value = true;
  erro.value = false;
  try {
    const [ferramentas, agente] = await Promise.all([
      CaptainToolRunsAPI.list({ lead_id: props.leadId }),
      RamonAgenteExecucoesAPI.list({ lead_id: props.leadId }),
    ]);
    const catalogo = ferramentas.data.catalogo || [];
    linhas.value = [
      ...ferramentas.data.items.map(run => ({
        id: `f${run.id}`,
        em: run.created_at,
        status: run.status,
        texto: ferramentaInfo(run.tool_name, catalogo).title,
      })),
      ...agente.data.items.map(item => ({
        id: `a${item.id}`,
        em: item.created_at,
        status: item.status,
        texto: t('INTEL.CASO_IA.AGENTE', { nome: item.pedido }),
      })),
    ]
      .sort((a, b) => new Date(b.em) - new Date(a.em))
      .slice(0, VISIVEIS);
  } catch (e) {
    erro.value = true;
  } finally {
    carregando.value = false;
  }
};
onMounted(carregar);
watch(() => props.leadId, carregar);
</script>

<template>
  <section data-testid="caso-ia" :class="SECAO">
    <h3 :class="TITULO">{{ t('INTEL.CASO_IA.TITULO') }}</h3>
    <p v-if="erro" class="mt-2 text-xs text-n-ruby-11">
      {{ t('INTEL.CASO_IA.ERRO') }}
    </p>
    <p
      v-else-if="!carregando && !linhas.length"
      class="mt-2 text-xs text-n-slate-10"
    >
      {{ t('INTEL.CASO_IA.VAZIO') }}
    </p>
    <ul v-else class="flex flex-col gap-1.5 mt-2 list-none">
      <li
        v-for="linha in linhas"
        :key="linha.id"
        data-testid="caso-ia-linha"
        class="flex items-center gap-2 text-xs"
      >
        <span :class="[CHIP, STATUS_TOM[linha.status] || TOM.slate]">
          {{ t(`INTEL.EXECUCOES.STATUS.${linha.status}`) }}
        </span>
        <span class="flex-1 min-w-0 truncate text-n-slate-12">
          {{ linha.texto }}
        </span>
        <span class="shrink-0 text-[11px] text-n-slate-10">
          {{ fmtHora(linha.em) }}
        </span>
      </li>
    </ul>
  </section>
</template>
```
(Status desconhecido cai em `INTEL.EXECUCOES.STATUS.<x>` — os 5 que existem cobrem ferramentas e agente.)

- [ ] **Step 4: Painel do lead** — `LeadPanelBody.vue`: depois de `import LeadHistory from '../conversation/LeadHistory.vue';` acrescentar `import LeadIaExecucoes from './LeadIaExecucoes.vue';`; na aba Atividade, logo depois de `<LeadHistory :lead-id="lead.id" />`: `<LeadIaExecucoes :lead-id="lead.id" />`.

- [ ] **Step 5: Rodar e ver passar** — o vitest do Step 2 + `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/ramon/components/lead --config vitest.local.config.ts` (os specs do painel continuam verdes — se algum montar `LeadPanelBody` na aba Atividade e reclamar de chamada de API, acrescentar `LeadIaExecucoes: true` nos stubs dele) + eslint dos 2 arquivos sem `error`.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadIaExecucoes.vue app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadIaExecucoes.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue
git commit -m "feat(lead): o que a IA fez neste caso, na aba Atividade do painel (I-X8)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 16: Memória do contato — a IA anota no lead o que aprendeu (I-X7) (julgamento: prompt e filtro de saúde)

**Files:**
- Create: `app/services/ramon/memoria_contato.rb`, `spec/services/ramon/memoria_contato_spec.rb`, `spec/enterprise/services/captain/llm/contact_notes_service_spec.rb`
- Modify: `enterprise/app/services/captain/llm/contact_notes_service.rb` (reescrito), `app/services/ramon/ia_gasto_alerta.rb`, `app/services/ramon/faq_de_conversa.rb` (`pausada?`), `lib/ramon/llm_uso.rb` (`FUNCOES`)
- Test: `spec/services/ramon/ia_gasto_alerta_spec.rb`, `spec/lib/ramon/llm_uso_spec.rb`

**Interfaces:**
- Consumes: `Ramon::FaqDeConversa.texto(conversa)` (A4 — fim da conversa, sem nota privada, mascarado); `Ramon::LlmEscolha.para(account, 'documentos')`; `CaptainListener#conversation_resolved` (chama `ContactNotesService#generate_and_update_notes` quando `feature_memory` está ligado — **não muda**); chave na tela (Task 9).
- Produces: `Ramon::MemoriaContato.texto(conversa, lead)`, `.itens(conteudo) → Array<String>`, `.gravar!(lead, numero_conversa, itens) → LeadNote|nil`, `PROMPT`, `CABECALHO`; `Ramon::IaGastoAlerta.passou_do_teto?(account)` (a Task 17 usa); função `memoria_contato` em Uso e custo.
- Se o Eduardo escolher **N2 (b)** (nota no contato): em `gravar!`, trocar `lead.lead_notes.create!(account: lead.account, body: …)` por `lead.contact.notes.create!(content: …)` (modelo `Note`), e em `texto` ler as anteriores de `lead.contact.notes`; os specs mudam de `LeadNote` para `Note`. Se **N1 (c)**: pular esta task e o item da chave na Task 9 (Step 3 continua, só sem a linha `memories`).

- [ ] **Step 1: Specs FOSS (falham antes)** — `spec/services/ramon/memoria_contato_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::MemoriaContato do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria Souza') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:lead) { create(:lead, account: account, conversation: conversa, name: 'Maria Souza') }

  describe '.itens' do
    it 'le a lista do JSON, mesmo com texto em volta' do
      expect(described_class.itens('ok {"memoria": ["Interesse: auxílio-acidente"]} fim')).to eq(['Interesse: auxílio-acidente'])
    end

    it 'JSON quebrado, sem a chave ou nada vira lista vazia', :aggregate_failures do
      expect(described_class.itens('{"memoria": [')).to eq([])
      expect(described_class.itens('{"faqs": []}')).to eq([])
      expect(described_class.itens(nil)).to eq([])
    end
  end

  describe '.gravar!' do
    it 'grava uma nota no lead com os itens, sem os de saude', :aggregate_failures do
      nota = described_class.gravar!(lead, 482, ['Interesse: auxílio-acidente', 'CID M54, lombalgia', 'Trabalha como pedreiro'])

      expect(nota.body).to eq("MEMÓRIA DA IA (conversa #482):\n- Interesse: auxílio-acidente\n- Trabalha como pedreiro")
      expect(nota.user_id).to be_nil
    end

    it 'sem itens, ou so com item de saude, nao grava' do
      expect { described_class.gravar!(lead, 1, ['', 'Tem depressão', 'Fez cirurgia no joelho']) }.not_to change(LeadNote, :count)
    end

    it 'no maximo 6 itens e 1000 caracteres', :aggregate_failures do
      nota = described_class.gravar!(lead, 1, Array.new(9) { |numero| "Fato #{numero} #{'x' * 200}" })

      expect(nota.body.scan(/^- /).size).to be <= 6
      expect(nota.body.length).to be <= 1000
    end
  end

  describe '.texto' do
    it 'leva as memorias anteriores e a conversa mascarada', :aggregate_failures do
      described_class.gravar!(lead, 1, ['Interesse: BPC'])
      create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming,
                       content: 'Sou a Maria Souza, meu CPF é 123.456.789-09')

      texto = described_class.texto(conversa, lead)

      expect(texto).to include('Interesse: BPC')
      expect(texto).not_to include('Maria Souza')
      expect(texto).not_to include('123.456.789-09')
    end
  end

  it 'o prompt proibe saude e documentos' do
    expect(described_class::PROMPT).to include('NUNCA anote').and include('CID').and include('CPF')
  end
end
```
Em `spec/services/ramon/ia_gasto_alerta_spec.rb` acrescentar:

```ruby
  describe '.passou_do_teto?' do
    it 'so com teto definido e gasto do dia no teto ou acima', :aggregate_failures do
      expect(described_class.passou_do_teto?(account)).to be(false)
      account.update!(settings: (account.settings || {}).merge(described_class::CHAVE_TETO => '1.00'))
      chamada(0.5)
      expect(described_class.passou_do_teto?(account)).to be(false)
      chamada(0.5)
      expect(described_class.passou_do_teto?(account)).to be(true)
    end
  end
```
Em `spec/lib/ramon/llm_uso_spec.rb`, junto do exemplo de `de_instrumentacao` com `conversation_faq` (linha ~78), acrescentar:

```ruby
  it 'a memoria do contato tem funcao propria em Uso e custo' do
    dados = described_class.de_instrumentacao(account_id: 1, feature_name: 'contact_notes', model: 'deepseek-chat')

    expect(dados[:funcao]).to eq('memoria_contato')
  end
```

- [ ] **Step 2: Rodar** — sem Ruby local: rastrear à mão e seguir (o CI valida). Conferir que os 3 arquivos de spec usam `describe` (nunca `context` com frase em pt-BR).

- [ ] **Step 3: `app/services/ramon/memoria_contato.rb`** (Write):

```ruby
# Memória do contato (Inteligência A5 — I-X7): ao resolver uma conversa numa caixa do assistente com a chave
# "Memória do contato" ligada, a IA lê o fim da conversa (mascarado, sem notas privadas — Ramon::FaqDeConversa.texto)
# e grava UMA nota no lead (painel → Notas) com o que aprendeu. As peças sem Captain ficam aqui (o CI testa); a
# chamada ao LLM fica no Captain::Llm::ContactNotesService (enterprise).
# O que pode ser anotado: PROMPT (decisão N1 do Eduardo — sem dado de saúde). SAUDE é a rede de segurança.
module Ramon::MemoriaContato
  CABECALHO = 'MEMÓRIA DA IA'.freeze
  MAX_ITENS = 6
  ANTERIORES = 3
  # ponytail: lista de palavras — cobre o comum; a regra principal é o PROMPT. Se escapar algo, somar aqui.
  SAUDE = /\b(cid|diagn[oó]stic\w*|doen[cç]a\w*|les[aã]o|les[oõ]es|sequela\w*|fratur\w*|cirurgi\w*|rem[eé]di\w*|
            medica\w*|tratament\w*|exame\w*|depress\w*|ansiedade|c[aâ]ncer|h[eé]rnia|tendinite|lombalgia|amputa\w*|
            psiqui\w*|fisioterapi\w*)\b/ix
  PROMPT = <<~TXT.freeze
    Você lê o fim de uma conversa de WhatsApp entre um escritório de advocacia previdenciária e trabalhista
    (Support Agent) e um lead (User) e anota, para a equipe, o que vale lembrar sobre ESTA pessoa na próxima conversa.
    Responda APENAS JSON válido, sem markdown: {"memoria": ["...", "..."]}.
    Anote só fatos que a pessoa disse ou confirmou, um por item, curtos (até 15 palavras):
    - benefício ou assunto de interesse (ex.: auxílio-acidente, BPC, aposentadoria, trabalhista);
    - situação de trabalho (trabalhando, afastado, desempregado), profissão e ramo do empregador;
    - quando aconteceu o fato principal (mês/ano do acidente, do afastamento, da demissão);
    - benefício do INSS que já recebeu ou recebe (espécie e período) e se teve pedido negado;
    - documentos que já tem ou disse que vai mandar; se tem laudo ou atestado (só sim ou não);
    - melhor horário ou canal para falar; dúvidas e objeções que levantou (preço, prazo, desconfiança).
    NUNCA anote: doença, diagnóstico, CID, lesão, parte do corpo, remédio, exame, tratamento ou qualquer detalhe de
    saúde; CPF, RG, telefone, e-mail ou endereço; nome ou dados de outras pessoas (familiares, colegas).
    Não repita o que está em "Já anotado antes". Não invente; na dúvida, deixe de fora.
    No máximo 6 itens. Se não houver nada novo, responda {"memoria": []}.
    Escreva em português do Brasil.
  TXT

  module_function

  # O que vai ao LLM: as últimas memórias do lead (para não repetir) + o fim da conversa, mascarado.
  def texto(conversa, lead)
    ja_sabe = lead.lead_notes.where('body LIKE ?', "#{CABECALHO}%").reorder(id: :desc).limit(ANTERIORES).pluck(:body).reverse
    partes = ja_sabe.any? ? ["Já anotado antes:\n#{ja_sabe.join("\n")}"] : []
    (partes << "Conversa:\n#{Ramon::FaqDeConversa.texto(conversa)}").join("\n\n")
  end

  # {"memoria": [...]} da resposta da IA; qualquer outra coisa vira lista vazia.
  def itens(conteudo)
    dados = JSON.parse(conteudo.to_s[/\{.*\}/m] || '{}')
    Array(dados['memoria']).map(&:to_s)
  rescue JSON::ParserError
    []
  end

  # Uma nota no lead (sem autor: foi a IA). Nada a gravar (vazio, ou só item de saúde) → nil.
  def gravar!(lead, numero_conversa, itens)
    limpos = itens.map(&:strip).compact_blank.grep_v(SAUDE).first(MAX_ITENS)
    return if limpos.empty?

    corpo = "#{CABECALHO} (conversa ##{numero_conversa}):\n#{limpos.map { |item| "- #{item}" }.join("\n")}"
    lead.lead_notes.create!(account: lead.account, body: corpo.truncate(1000))
  end
end
```
(Regex com `/x`: os espaços e a quebra de linha dentro dela são ignorados. Se o Eduardo escolher N1 (b), tirar `cid|diagn…|lesão…` do `SAUDE` e a frase de saúde do `NUNCA anote` — e trocar os specs de saúde.)

- [ ] **Step 4: Teto em um lugar só** — `app/services/ramon/ia_gasto_alerta.rb`, depois de `gasto_hoje`:

```ruby
  # O gasto do dia já chegou ao teto (sem teto = nunca): as rotinas automáticas de IA param no dia
  # (FAQ de conversa, memória do contato, caderno da madrugada).
  def passou_do_teto?(account)
    limite = teto(account)
    limite.to_f.positive? && gasto_hoje(account.id) >= limite
  end
```
`app/services/ramon/faq_de_conversa.rb`, `pausada?` vira só `def pausada?(account) = Ramon::IaGastoAlerta.passou_do_teto?(account)` (o spec dele continua igual).
`lib/ramon/llm_uso.rb`, `FUNCOES`: depois de `'conversation_faq' => 'faq_conversa'` acrescentar `, 'contact_notes' => 'memoria_contato'` (mesma linha ou linha nova com o alinhamento do hash).

- [ ] **Step 5: `enterprise/app/services/captain/llm/contact_notes_service.rb`** (Write — arquivo inteiro):

```ruby
# FORK-PONTO (ramon, A5 — I-X7): "Memória do contato". Ao resolver a conversa (CaptainListener, chave feature_memory),
# anota no LEAD (painel → Notas) o que a IA aprendeu. Prompt, texto mascarado e o que pode ser gravado:
# Ramon::MemoriaContato (FOSS, testado no CI). Sem lead, sem memória. Para no dia em que o gasto chega ao teto.
# Modelo = o das "FAQs geradas" (Uso e custo); custo em linha própria (função memoria_contato).
class Captain::Llm::ContactNotesService < Llm::BaseAiService
  include Integrations::LlmInstrumentation

  def initialize(assistant, conversation)
    super()
    @assistant = assistant
    @conversation = conversation
    @lead = conversation.account.leads.find_by(conversation_id: conversation.id)
    @model = Ramon::LlmEscolha.para(conversation.account, 'documentos')[:model]
  end

  def generate_and_update_notes
    return if @lead.nil? || Ramon::IaGastoAlerta.passou_do_teto?(@conversation.account)

    Ramon::MemoriaContato.gravar!(@lead, @conversation.display_id, generate_notes)
  end

  private

  def generate_notes
    @content = Ramon::MemoriaContato.texto(@conversation, @lead)
    response = instrument_llm_call(instrumentation_params) do
      chat.with_params(response_format: { type: 'json_object' }).with_instructions(Ramon::MemoriaContato::PROMPT).ask(@content)
    end
    Ramon::MemoriaContato.itens(response.content)
  rescue RubyLLM::Error => e
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    []
  end

  def instrumentation_params
    {
      span_name: 'llm.captain.contact_notes', model: @model, temperature: @temperature,
      account_id: @conversation.account_id, conversation_id: @conversation.display_id, feature_name: 'contact_notes',
      messages: [{ role: 'system', content: Ramon::MemoriaContato::PROMPT }, { role: 'user', content: @content }],
      metadata: { assistant_id: @assistant.id }
    }
  end
end
```
`spec/enterprise/services/captain/llm/contact_notes_service_spec.rb` (documentação; mesmo jeito do `conversation_faq_service_spec.rb`):

```ruby
require 'rails_helper'

RSpec.describe Captain::Llm::ContactNotesService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:resposta) { instance_double(RubyLLM::Message, content: { memoria: ['Interesse: BPC', 'CID F32'] }.to_json) }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive_messages(with_temperature: mock_chat, with_params: mock_chat, with_instructions: mock_chat,
                                         ask: resposta)
  end

  it 'grava a memoria no lead da conversa, sem o item de saude' do
    lead = create(:lead, account: account, conversation: conversation)

    described_class.new(assistant, conversation).generate_and_update_notes

    expect(lead.lead_notes.last.body).to eq("MEMÓRIA DA IA (conversa ##{conversation.display_id}):\n- Interesse: BPC")
  end

  it 'sem lead nao chama a IA' do
    described_class.new(assistant, conversation).generate_and_update_notes

    expect(mock_chat).not_to have_received(:ask)
  end

  it 'com o gasto do dia no teto nao chama a IA' do
    create(:lead, account: account, conversation: conversation)
    allow(Ramon::IaGastoAlerta).to receive(:passou_do_teto?).and_return(true)

    described_class.new(assistant, conversation).generate_and_update_notes

    expect(mock_chat).not_to have_received(:ask)
  end
end
```

- [ ] **Step 6: Rastrear à mão** — `gravar!` com `['Interesse: auxílio-acidente', 'CID M54, lombalgia', 'Trabalha como pedreiro']`: `grep_v(SAUDE)` tira o 2º (`\bcid\b`); corpo bate com o esperado. `'Fez cirurgia no joelho'` cai por `cirurgi\w*`; `'Tem depressão'` por `depress\w*`. `texto`: `LeadNote` tem `default_scope` ordenado → `reorder` antes do `limit` (lição do `.distinct.pluck`); `Ramon::FaqDeConversa.texto` mascara o nome do contato e do lead e o CPF. ModuleLength: ~40 linhas de código. `instrumentation_params` 6 linhas, AbcSize baixo. A listener `captain_listener_spec.rb` (enterprise) continua válida: ela só confere que o serviço é chamado.

- [ ] **Step 7: Commit**

```bash
git add app/services/ramon/memoria_contato.rb app/services/ramon/ia_gasto_alerta.rb app/services/ramon/faq_de_conversa.rb lib/ramon/llm_uso.rb enterprise/app/services/captain/llm/contact_notes_service.rb spec/services/ramon/memoria_contato_spec.rb spec/services/ramon/ia_gasto_alerta_spec.rb spec/lib/ramon/llm_uso_spec.rb spec/enterprise/services/captain/llm/contact_notes_service_spec.rb
git commit -m "feat(ia): memória do contato — nota no lead com o que a IA aprendeu, sem dado de saúde, com teto e custo próprio (I-X7)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 17: Caderno de provas automático (backend) — rodada da madrugada (I-X6) (mecânica)

**Files:**
- Create: `app/jobs/ramon/caderno_noturno_job.rb`, `enterprise/app/services/captain/caderno_noturno.rb`, `spec/jobs/ramon/caderno_noturno_job_spec.rb`, `spec/enterprise/services/captain/caderno_noturno_spec.rb`
- Modify: `config/schedule.yml` (bloco novo no fim), `enterprise/app/controllers/api/v1/accounts/captain/ia_rodadas_controller.rb`, `config/routes.rb` (`ia_rodadas`), `app/controllers/api/v1/accounts/ramon_inteligencia_controller.rb`
- Test: `spec/enterprise/controllers/api/v1/accounts/captain/ia_rodadas_controller_spec.rb`, `spec/controllers/api/v1/accounts/ramon_inteligencia_controller_spec.rb`

**Interfaces:**
- Consumes: Task 16 (`Ramon::IaGastoAlerta.passou_do_teto?`); `Captain::IaRodada` (`ativas`, `destravar!`, `create!`), `Captain::IaCaso.ativos`, `Captain::IaRodadaJob` (#214).
- Produces: `Ramon::CadernoNoturnoJob::CHAVE = 'ramon_caderno_noturno'` (em `accounts.settings`); `Captain::CadernoNoturno.ligado?(account)`, `#perform → Array<IaRodada>`; `GET …/ia_rodadas` ganha `noturno: Boolean`; `PATCH …/ia_rodadas/noturno` com `{ ligado: Boolean }` → `{ noturno: Boolean }` (admin); `GET ramon_inteligencia` ganha `caderno: [{ assistant_id, nome, passou, total, em (epoch s) }]`.

- [ ] **Step 1: Specs** — FOSS `spec/jobs/ramon/caderno_noturno_job_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::CadernoNoturnoJob do
  it 'so chama o caderno nas contas com a chave ligada', if: ChatwootApp.enterprise? do
    ligada = create(:account, settings: { described_class::CHAVE => true })
    create(:account)
    servico = instance_double(Captain::CadernoNoturno, perform: [])
    allow(Captain::CadernoNoturno).to receive(:new).and_return(servico)

    described_class.perform_now

    expect(Captain::CadernoNoturno).to have_received(:new).with(ligada).once
  end

  it 'uma conta com erro nao derruba as outras', if: ChatwootApp.enterprise? do
    create_list(:account, 2, settings: { described_class::CHAVE => true })
    servico = instance_double(Captain::CadernoNoturno)
    allow(servico).to receive(:perform).and_raise(StandardError, 'quebrou')
    allow(Captain::CadernoNoturno).to receive(:new).and_return(servico)

    expect { described_class.perform_now }.not_to raise_error
    expect(servico).to have_received(:perform).twice
  end

  it 'sem o codigo enterprise nao faz nada', unless: ChatwootApp.enterprise? do
    create(:account, settings: { described_class::CHAVE => true })

    expect { described_class.perform_now }.not_to raise_error
  end
end
```
Enterprise (documentação) `spec/enterprise/services/captain/caderno_noturno_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Captain::CadernoNoturno do
  let(:account) { create(:account, settings: { Ramon::CadernoNoturnoJob::CHAVE => true }) }
  let(:assistant) { create(:captain_assistant, account: account) }

  before do
    Captain::IaCaso.create!(account: account, assistant: assistant, titulo: 'A1', mensagens: [{ role: 'user', content: 'oi' }])
  end

  def concluida(quando)
    Captain::IaRodada.create!(account: account, assistant: assistant, status: 'concluida', created_at: quando)
  end

  it 'sem rodada anterior enfileira a da madrugada', :aggregate_failures do
    expect { described_class.new(account).perform }.to have_enqueued_job(Captain::IaRodadaJob)
    expect(Captain::IaRodada.last).to have_attributes(status: 'fila', total: 1, disparado_por_id: nil)
  end

  it 'nada mudou desde a ultima rodada: nao enfileira' do
    assistant.update_column(:updated_at, 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
    Captain::IaCaso.update_all(updated_at: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
    concluida(1.day.ago)

    expect { described_class.new(account).perform }.not_to have_enqueued_job(Captain::IaRodadaJob)
  end

  it 'chave desligada, teto estourado ou rodada em andamento: nao enfileira', :aggregate_failures do
    account.update!(settings: { Ramon::CadernoNoturnoJob::CHAVE => false })
    expect(described_class.new(account).perform).to eq([])

    account.update!(settings: { Ramon::CadernoNoturnoJob::CHAVE => true })
    allow(Ramon::IaGastoAlerta).to receive(:passou_do_teto?).and_return(true)
    expect(described_class.new(account).perform).to eq([])

    allow(Ramon::IaGastoAlerta).to receive(:passou_do_teto?).and_return(false)
    Captain::IaRodada.create!(account: account, assistant: assistant, status: 'rodando')
    expect(described_class.new(account).perform).to eq([])
  end
end
```
Em `ia_rodadas_controller_spec.rb` (enterprise):

```ruby
  it 'admin liga a rodada da madrugada; o index conta (I-X6)', :aggregate_failures do
    patch "#{url}/noturno", params: { ligado: true }, headers: admin.create_new_auth_token, as: :json

    expect(json_response[:noturno]).to be(true)
    expect(account.reload.settings[Ramon::CadernoNoturnoJob::CHAVE]).to be(true)
    get url, headers: admin.create_new_auth_token, as: :json
    expect(json_response[:noturno]).to be(true)
  end

  it 'agente nao liga a rodada da madrugada' do
    patch "#{url}/noturno", params: { ligado: true }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
```
FOSS `ramon_inteligencia_controller_spec.rb`:

```ruby
  # ramon_ia_rodadas e captain_assistants são do enterprise: as linhas entram por SQL (roda no CI FOSS).
  def inserir(sql, *binds)
    ActiveRecord::Base.connection.select_value(ActiveRecord::Base.sanitize_sql_array([sql, *binds]))
  end

  it 'mostra a ultima rodada concluida do caderno por assistente (I-X6)' do
    agora = Time.current
    assistente = inserir('INSERT INTO captain_assistants (name, account_id, created_at, updated_at) VALUES (?, ?, ?, ?) RETURNING id',
                         'Atendimento', account.id, agora, agora)
    sql = 'INSERT INTO ramon_ia_rodadas (account_id, assistant_id, status, total, passou, falhou, created_at, updated_at) ' \
          "VALUES (?, ?, 'concluida', 43, ?, ?, ?, ?) RETURNING id"
    inserir(sql, account.id, assistente, 40, 3, 2.days.ago, 2.days.ago)
    inserir(sql, account.id, assistente, 41, 2, 1.hour.ago, 1.hour.ago)

    expect(visao['caderno']).to match([a_hash_including('assistant_id' => assistente.to_i, 'nome' => 'Atendimento',
                                                        'passou' => 41, 'total' => 43)])
  end
```

- [ ] **Step 2: Job FOSS** — `app/jobs/ramon/caderno_noturno_job.rb` (Write):

```ruby
# Caderno de provas automático (Inteligência A5 — I-X6): 05:30 de Brasília, nas contas com a chave ligada
# (Inteligência → Testar → Casos de teste). A regra (o que mudou, teto, rodada em andamento) mora no
# Captain::CadernoNoturno (enterprise); no CI FOSS o job não faz nada.
# Decisão N4: vira rotina do quadro de Automações na limpeza (E7), junto das outras rotinas da conta.
class Ramon::CadernoNoturnoJob < ApplicationJob
  CHAVE = 'ramon_caderno_noturno'.freeze

  queue_as :scheduled_jobs

  def perform
    return unless ChatwootApp.enterprise?

    Account.where("settings ->> ? = 'true'", CHAVE).find_each do |account|
      Captain::CadernoNoturno.new(account).perform
    rescue StandardError => e
      # uma conta com dado venenoso não pode abortar as demais nem virar retry-loop
      Rails.logger.error("CadernoNoturnoJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end
end
```

- [ ] **Step 3: Serviço enterprise** — `enterprise/app/services/captain/caderno_noturno.rb` (Write):

```ruby
# Caderno de provas automático (Inteligência A5 — I-X6): para cada assistente com casos ativos, enfileira uma rodada
# dos Casos de teste (modo teste: só consulta executa, nada é gravado nem enviado) — se a chave da conta estiver
# ligada, se o gasto do dia não passou do teto e se algo mudou desde a última rodada concluída (decisão N3).
# Sem disparado_por = rodada da madrugada.
class Captain::CadernoNoturno
  def self.ligado?(account)
    ActiveModel::Type::Boolean.new.cast(account.settings&.dig(Ramon::CadernoNoturnoJob::CHAVE)) == true
  end

  def initialize(account)
    @account = account
  end

  def perform
    return [] unless self.class.ligado?(@account)
    return [] if Ramon::IaGastoAlerta.passou_do_teto?(@account)

    Captain::Assistant.for_account(@account.id).order(:id).filter_map { |assistant| enfileirar(assistant) }
  end

  private

  def enfileirar(assistant)
    Captain::IaRodada.destravar!(assistant.id)
    return if Captain::IaRodada.ativas.exists?(assistant_id: assistant.id)

    total = Captain::IaCaso.ativos.where(assistant_id: assistant.id).count
    return if total.zero? || !mudou?(assistant)

    rodada = Captain::IaRodada.create!(account: @account, assistant: assistant, total: total)
    Captain::IaRodadaJob.perform_later(rodada.id)
    rodada
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Mudou = o assistente (configurações, regras), uma skill, uma FAQ aprovada ou um caso de teste mexidos depois
  # da última rodada concluída. Sem rodada anterior conta como mudou. (O contador de uso da FAQ não mexe em updated_at.)
  def mudou?(assistant)
    ultima = Captain::IaRodada.where(assistant_id: assistant.id, status: 'concluida').maximum(:created_at)
    return true if ultima.nil?

    [assistant.updated_at, assistant.scenarios.maximum(:updated_at), assistant.responses.approved.maximum(:updated_at),
     Captain::IaCaso.where(assistant_id: assistant.id).maximum(:updated_at)].compact.max > ultima
  end
end
```
(Se o Eduardo escolher N3 (b), apagar `|| !mudou?(assistant)` e o `mudou?`; se (c), trocar só o cron do Step 4 para `'30 8 * * 0'`.)

- [ ] **Step 4: Cron** — `config/schedule.yml`, **no fim**:

```yaml

# executed daily at 0830 UTC = 05:30 America/Sao_Paulo (UTC-3), depois do copiloto noturno (05:00)
# caderno de provas automático (Inteligência A5 — I-X6): só nas contas com a chave ligada
ramon_caderno_noturno_job:
  cron: '30 8 * * *'
  class: 'Ramon::CadernoNoturnoJob'
  queue: scheduled_jobs
```

- [ ] **Step 5: Liga/desliga na tela** — `ia_rodadas_controller.rb`: `index` vira

```ruby
  def index
    render json: { payload: escopo.recentes.limit(LIMITE).map(&:resumo), noturno: Captain::CadernoNoturno.ligado?(Current.account) }
  end
```
e, depois de `create`:

```ruby
  # I-X6: liga/desliga a rodada da madrugada da conta (vale para todos os assistentes).
  def noturno
    ligado = ActiveModel::Type::Boolean.new.cast(params[:ligado]) == true
    Current.account.update!(settings: (Current.account.settings || {}).merge(Ramon::CadernoNoturnoJob::CHAVE => ligado))
    render json: { noturno: ligado }
  end
```
`config/routes.rb`: `resources :ia_rodadas, only: [:index, :show, :create]` vira

```ruby
              resources :ia_rodadas, only: [:index, :show, :create] do
                patch :noturno, on: :collection
              end
```
(O `before_action -> { authorize(Captain::IaCaso, :gerenciar?) }` já vale para a ação nova: só admin.)

- [ ] **Step 6: Visão geral** — `ramon_inteligencia_controller.rb`: depois de `SQL_TRANSFERENCIAS`:

```ruby
  # I-X6: a última rodada concluída do caderno de provas, por assistente (SQL: ramon_ia_rodadas é do enterprise).
  SQL_CADERNO = <<~SQL.squish.freeze
    SELECT DISTINCT ON (r.assistant_id) r.assistant_id, a.name, r.passou, r.total,
           EXTRACT(EPOCH FROM r.created_at)::bigint AS em
    FROM ramon_ia_rodadas r JOIN captain_assistants a ON a.id = r.assistant_id
    WHERE r.account_id = ? AND r.status = 'concluida'
    ORDER BY r.assistant_id, r.created_at DESC
  SQL
```
`show`: acrescentar `caderno: caderno` ao hash (`transferencias: transferencias, aprovacoes: aprovacoes, agente: agente, caderno: caderno`); e, depois de `agente`:

```ruby
  def caderno
    linhas(SQL_CADERNO, Current.account.id).map do |linha|
      { assistant_id: linha['assistant_id'].to_i, nome: linha['name'], passou: linha['passou'].to_i,
        total: linha['total'].to_i, em: linha['em'].to_i }
    end
  end
```

- [ ] **Step 7: Rastrear à mão** — job FOSS: no CI FOSS (`unless: enterprise?`) sai no `return`; no enterprise, `settings->>'ramon_caderno_noturno'` de JSON `true` é a string `'true'`. Serviço: rodada com `RecordNotUnique` (índice parcial de ativa) vira `nil`; `mudou?` compara `Time` com `Time`. `SQL_CADERNO` sem `NOW()`. Rubocop: `enfileirar` 10 linhas, AbcSize ~17; `mudou?` 5; linhas < 150; `RSpec/SpecFilePathFormat`: `Ramon::CadernoNoturnoJob` em `spec/jobs/ramon/caderno_noturno_job_spec.rb`, `Captain::CadernoNoturno` em `spec/enterprise/services/captain/caderno_noturno_spec.rb`.

- [ ] **Step 8: Commit**

```bash
git add app/jobs/ramon/caderno_noturno_job.rb enterprise/app/services/captain/caderno_noturno.rb config/schedule.yml enterprise/app/controllers/api/v1/accounts/captain/ia_rodadas_controller.rb config/routes.rb app/controllers/api/v1/accounts/ramon_inteligencia_controller.rb spec/jobs/ramon/caderno_noturno_job_spec.rb spec/enterprise/services/captain/caderno_noturno_spec.rb spec/enterprise/controllers/api/v1/accounts/captain/ia_rodadas_controller_spec.rb spec/controllers/api/v1/accounts/ramon_inteligencia_controller_spec.rb
git commit -m "feat(ia): caderno de provas automático de madrugada, só se algo mudou e dentro do teto (I-X6)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 18: Caderno automático (tela) — chave nos Casos de teste e bloco na Visão geral (I-X6) (julgamento: lugar do bloco no print)

**Files:**
- Modify: `app/javascript/dashboard/api/captain/iaCasos.js`, `app/javascript/dashboard/routes/dashboard/captain/casos/CasosTeste.vue`, `app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue`
- Test: `app/javascript/dashboard/routes/dashboard/captain/casos/specs/CasosTeste.spec.js`

**Interfaces:**
- Consumes: Task 17 (`noturno` no index das rodadas, `PATCH …/noturno`, `caderno` na Visão geral); Task 2 (`INTEL.CADERNO.*`, `INTEL.VISAO_GERAL.CADERNO.*`).

- [ ] **Step 1: Spec (falha antes)** — em `CasosTeste.spec.js`, o mock de `IaCasosAPI` ganha `noturno: vi.fn().mockResolvedValue({ data: { noturno: true } })` e o `rodadas` mockado devolve também `noturno: false`; acrescentar:

```js
  it('liga a rodada da madrugada (I-X6)', async () => {
    const wrapper = await montar();
    wrapper
      .findComponent('[data-testid="casos-noturno-chave"]')
      .vm.$emit('update:modelValue', true);
    await flushPromises();
    expect(IaCasosAPI.noturno).toHaveBeenCalledWith(1, true);
  });
```
(usar o `montar`/`flushPromises` que o arquivo já tem; o `assistantId` da rota mockada é o do arquivo — ajustar o `1` se for outro.)

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/casos/specs/CasosTeste.spec.js --config vitest.local.config.ts` → FAIL.

- [ ] **Step 3: API** — `iaCasos.js`, depois de `rodar`:

```js
  // Caderno automático (I-X6): liga/desliga a rodada da madrugada da conta.
  noturno(assistantId, ligado) {
    return axios.patch(`${this.url}/${assistantId}/ia_rodadas/noturno`, {
      ligado,
    });
  }
```

- [ ] **Step 4: `CasosTeste.vue`**
  - `import Switch from 'dashboard/components-next/switch/Switch.vue';`
  - `const noturno = ref(false);` junto dos outros `ref`; em `carregarRodadas`, depois de `rodadas.value = data.payload;`: `noturno.value = !!data.noturno;`
  - depois de `carregarRodadas`:
    ```js
    // I-X6: rodada da madrugada (vale para todos os assistentes da conta); erro volta a chave.
    const alternarNoturno = async ligado => {
      noturno.value = ligado;
      try {
        await IaCasosAPI.noturno(assistantId.value, ligado);
        aviso.value = ligado
          ? t('INTEL.CADERNO.NOTURNO_LIGADO')
          : t('INTEL.CADERNO.NOTURNO_DESLIGADO');
      } catch (e) {
        noturno.value = !ligado;
      }
    };
    ```
  - template, logo depois do `<p class="text-sm text-n-slate-10">{{ t('CAPTAIN_RAMON.CASOS.SUBTITLE') }}</p>`:
    ```vue
        <div
          data-testid="casos-noturno"
          class="flex items-start gap-3"
          :class="CARTAO"
        >
          <Switch
            data-testid="casos-noturno-chave"
            class="mt-0.5"
            :model-value="noturno"
            @update:model-value="alternarNoturno"
          />
          <div class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-12">
              {{ t('INTEL.CADERNO.NOTURNO') }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{
                t('INTEL.CADERNO.NOTURNO_AJUDA', {
                  n: fmtUsd(estimativa.custo_usd),
                })
              }}
            </span>
          </div>
        </div>
    ```

- [ ] **Step 5: `VisaoGeral.vue`** — script: `import { useAdmin } from 'dashboard/composables/useAdmin';`, `const { isAdmin } = useAdmin();`, `const caderno = computed(() => visao.value.caderno || []);`. Template: antes de `<VigiaBloco class="lg:col-span-2" />`:

```vue
        <!-- I-X6: caderno de provas (última rodada concluída por assistente) -->
        <section data-testid="vg-caderno" :class="CARTAO">
          <h2 :class="TITULO">
            {{ t('INTEL.VISAO_GERAL.CADERNO.TITULO') }}
          </h2>
          <p v-if="!caderno.length" class="mt-2 text-sm text-n-slate-10">
            {{ t('INTEL.VISAO_GERAL.CADERNO.NUNCA') }}
          </p>
          <ul v-else class="flex flex-col gap-2 mt-2 list-none">
            <li
              v-for="item in caderno"
              :key="item.assistant_id"
              data-testid="vg-caderno-linha"
            >
              <div class="flex flex-wrap items-center gap-2">
                <span
                  :class="[
                    CHIP,
                    item.passou === item.total ? TOM.teal : TOM.ruby,
                  ]"
                >
                  {{
                    t('INTEL.VISAO_GERAL.CADERNO.LINHA', {
                      nome: item.nome,
                      n: item.passou,
                      total: item.total,
                    })
                  }}
                </span>
                <Button
                  v-if="isAdmin"
                  size="xs"
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-arrow-right"
                  :label="t('INTEL.VISAO_GERAL.CADERNO.ABRIR')"
                  @click="
                    ir('captain_assistants_casos_teste_index', {
                      assistantId: item.assistant_id,
                    })
                  "
                />
              </div>
              <p class="mt-1 text-xs text-n-slate-10">
                {{
                  t('INTEL.VISAO_GERAL.CADERNO.QUANDO', {
                    quando: fmtHora(item.em * 1000),
                  })
                }}
              </p>
            </li>
          </ul>
        </section>
```
(Se a grade ficar com um buraco no print, mover o bloco para perto do "Agente Claude" — decidir olhando o print da Task 19.)

- [ ] **Step 6: Rodar e ver passar** — o vitest do Step 2 + `TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain --config vitest.local.config.ts` + eslint de `CasosTeste.vue`, `VisaoGeral.vue`, `iaCasos.js` sem `error`.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/dashboard/api/captain/iaCasos.js app/javascript/dashboard/routes/dashboard/captain/casos/CasosTeste.vue app/javascript/dashboard/routes/dashboard/captain/casos/specs/CasosTeste.spec.js app/javascript/dashboard/routes/dashboard/captain/pages/VisaoGeral.vue
git commit -m "feat(ia): chave da rodada da madrugada nos Casos de teste e caderno na Visão geral (I-X6)" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 19: Story + prints "depois" + `comparar.html` (julgamento: conferir cada print)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue`, `app/javascript/dashboard/routes/dashboard/captain/casos/CasosTeste.story.vue`
- Create (fora do git): `tmp/intel-a5-harness/{telas-depois.txt,comparar.mjs}`, `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a5\{depois-*.png,comparar.html}`

**Interfaces:**
- Consumes: todas as tasks de tela (5, 7, 8, 9, 11, 12, 13, 14, 15, 18) e o harness da Task 1 (no ar, porta 6197).

- [ ] **Step 1: Fixtures do `Inteligencia.story.vue`** (dados fictícios):
  - `ATENDIMENTO.name` → `'Atendimento'`.
  - `SKILLS[0]` ganha `exemplo: 'Oi, me machuquei no trabalho. Tenho direito?'`, `papeis: []`, `uso_30d: 12`; `SKILLS[1]` ganha `exemplo: 'O que falta de documento deste caso?'`, `papeis: ['comercial']`, `uso_30d: 0`; `SKILLS[2]` ganha `uso_30d: 3`.
  - `FAQS`: a 1ª ganha `usos: 7, usada_em: unix(1)`; as outras `usos: 0`.
  - `API` ganha:
    ```js
      teams: [
        { id: 1, name: 'comercial', is_member: true },
        { id: 2, name: 'recepção', is_member: false },
      ],
      'captain/assistants/1/texto_final': {
        assistente:
          'Você é o Atendimento da Ramon Antonio Advogados...\n\nProteções:\n- Não dê garantia de êxito nem estimativa de prazo.',
        skills: [
          { title: 'Lead quer saber se tem direito', texto: 'Busque a resposta com a FAQ e o playbook da tese...' },
        ],
      },
    ```
    `captain_tool_runs` ganha `mais: true`; `ramon_inteligencia` ganha
    ```js
      caderno: [
        { assistant_id: 1, nome: 'Atendimento', passou: 41, total: 43, em: unix(0.3) },
        { assistant_id: 2, nome: 'Copiloto do Escritório', passou: 10, total: 10, em: unix(0.3) },
      ],
    ```
    e no `ramon_watchdog.items` o caso existente ganha `conversa_display_id: 482` e entra um 2º com `lead_id: 13, name: 'João Pereira', tentativas: 3, dias_parado: 12, conversa_display_id: null` (resto igual ao 1º).
  - imports novos: `import LeadIaExecucoes from 'dashboard/routes/dashboard/ramon/components/lead/LeadIaExecucoes.vue';` e `import { conversaDe, garantirConversa } from 'dashboard/components-next/captain/assistant/testarConversas';`
  - funções de estado:
    ```js
    // Testar com a conversa já respondida (I-PG2): mensagens na memória da página.
    const testarRespondido = () => {
      garantirConversa(1);
      conversaDe(1).push(
        { content: 'Prepare a reunião deste caso. caso 123 (Maria Souza)', sender: 'user' },
        {
          content: 'Caso 123 — falta o CNIS e o laudo. Honorário: 30% dos atrasados + 3 parcelas. Prescrição: sem risco.',
          sender: 'assistant',
          ferramentas: [
            { id: 'documentacao_faltante', title: 'O que falta no caso', nivel: 'consulta', status: 'ok' },
            { id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao', status: 'ok' },
            { id: 'consultar_dossie_advbox', title: 'Consultar dossiê no AdvBox', nivel: 'consulta', status: 'erro' },
          ],
        }
      );
    };
    const copiloto = () => {
      rota.params.assistantId = 2;
    };
    const abrirZona = () =>
      setTimeout(
        () => document.querySelector('[data-testid="zona-de-risco"]')?.setAttribute('open', ''),
        2000
      );
    ```
    (Conferir que `STATS` tem o Atendimento com `publico: 'lead'` e o Copiloto com `publico: 'equipe'` — A2 já monta assim; se não, acertar.)
  - variantes novas (no fim do `<Story>`):
    ```vue
        <Variant title="Testar respondeu" :init-state="testarRespondido">
          <div class="h-screen"><PlaygroundIndex /></div>
        </Variant>
        <Variant title="Configuracoes copiloto" :init-state="copiloto">
          <div class="h-screen"><SettingsIndex /></div>
        </Variant>
        <Variant title="Configuracoes zona" :init-state="abrirZona">
          <div class="h-screen"><SettingsIndex /></div>
        </Variant>
        <Variant title="Texto final" :init-state="clicarEm('Ver o texto final')">
          <div class="h-screen"><SettingsIndex /></div>
        </Variant>
        <Variant title="Caso IA">
          <div class="w-[420px] p-4"><LeadIaExecucoes :lead-id="123" /></div>
        </Variant>
    ```
  `CasosTeste.story.vue`: na resposta mockada de `…/ia_rodadas` (index), acrescentar `noturno: true`.
  Rodar `./node_modules/.bin/eslint --fix` nos dois e depois sem `--fix` → sem `error`. Commit:

```bash
git add app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue app/javascript/dashboard/routes/dashboard/captain/casos/CasosTeste.story.vue
git commit -m "test(inteligencia): story da A5 para os prints de aprovação" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

- [ ] **Step 2: `tmp/intel-a5-harness/telas-depois.txt`** (Write):

```
intel:Testar:testar:1440,1000
intel:Testar respondeu:testar-respondeu:1440,1100
intel:Skills:skills:1440,1600
intel:Configuracoes:configuracoes:1440,1400
intel:Configuracoes copiloto:configuracoes-copiloto:1440,1400
intel:Configuracoes zona:configuracoes-zona:1440,1700
intel:Texto final:texto-final:1440,1000
intel:FAQs:faqs:1440,1300
intel:Documentos novo:documentos-novo:1440,900
intel:Caixas:caixas:1440,800
intel:Caixas conectar:caixas-conectar:1440,800
intel:Ferramentas HTTP:ferramentas-http:1440,800
intel:Execucoes:execucoes:1440,1100
intel:Visao geral:visao-geral:1440,2300
intel:Caso IA:caso-ia:480,700
casos:Casos:casos:1440,1300
```

- [ ] **Step 3: Prints "depois"** — `cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-intel-a5 && sh tmp/intel-a5-harness/shots.sh depois` → 32 PNGs. Abrir com Read e conferir, claro **e** escuro: (1) **nenhum roxo** nas telas da área (bolhas do Testar, links de ferramenta nas Skills); (2) fundos coloridos **translúcidos** (chips, avisos, bolhas, resultado do teste HTTP); (3) botões/estados **coloridos** (chip azul "Testar esta skill", vermelho "Só erros de hoje", verde/vermelho no caderno); (4) seletor de assistente **só** em Testar, Skills, Configurações e Casos; (5) nada em inglês no pt_BR; (6) Configurações do Copiloto sem mensagens ao cliente e com o aviso de uma linha; (7) zona de risco recolhida no padrão e aberta na variante. Se algo falhar, corrigir na task da tela (commit `fix(...)`) e tirar o print de novo.

- [ ] **Step 4: `tmp/intel-a5-harness/comparar.mjs`** (Write) — mesmo formato do da A3, com:

```js
// Gera comparar.html (antes x depois, claro/escuro) na pasta dos prints da A5.
import { writeFileSync } from 'node:fs';

const OUT =
  'C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-07-inteligencia-a5';
// [nome, arquivo antes (null = tela nova), arquivo depois, itens do backlog]
const TELAS = [
  ['Testar', 'testar', 'testar', 'I-PG4, I-X5, I-T4'],
  ['Testar — resposta com ferramentas', null, 'testar-respondeu', 'I-PG2, I-PG3, I-T5'],
  ['Skills', 'skills', 'skills', 'I-SK6, I-SK7, I-X5, I-T5'],
  ['Configurações — Atendimento', 'configuracoes', 'configuracoes', 'I-CF3, I-CF4, I-X7, I-T5'],
  ['Configurações — Copiloto (equipe)', null, 'configuracoes-copiloto', 'I-CF4'],
  ['Configurações — zona de risco aberta', null, 'configuracoes-zona', 'I-CF5'],
  ['Configurações — texto final', null, 'texto-final', 'I-CF6'],
  ['FAQs', 'faqs', 'faqs', 'I-FQ5, I-FQ6, I-T4'],
  ['Documentos — novo (link)', 'documentos-novo', 'documentos-novo', 'I-DO4, I-T4'],
  ['Caixas', 'caixas', 'caixas', 'I-CX3, I-T4'],
  ['Caixas — conectar', 'caixas-conectar', 'caixas-conectar', 'I-CX3'],
  ['Ferramentas HTTP', 'ferramentas-http', 'ferramentas-http', 'I-T4, I-T5'],
  ['Execuções', 'execucoes', 'execucoes', 'I-EX3, I-EX5'],
  ['Visão geral', 'visao-geral', 'visao-geral', 'I-X6, I-WD3, I-WD4'],
  ['Painel do lead — o que a IA fez no caso', null, 'caso-ia', 'I-X8'],
  ['Casos de teste', 'casos', 'casos', 'I-X6, I-T5'],
];

const fig = (rotulo, arq, nome, tema) =>
  `<figure><figcaption>${rotulo}</figcaption><img src="${arq}" alt="${rotulo}, ${nome}, tema ${tema}"></figure>`;
const secoes = TELAS.flatMap(([nome, antes, depois, itens]) =>
  ['claro', 'escuro'].map(tema => {
    const figAntes = antes
      ? fig('Antes', `antes-${tema}-${antes}.png`, nome, tema)
      : '<figure><figcaption>Antes</figcaption><p>Tela nova.</p></figure>';
    return `<section><h2>${nome} · ${itens} · tema ${tema}</h2><div class="par">${figAntes}${fig('Depois (A5)', `depois-${tema}-${depois}.png`, nome, tema)}</div></section>`;
  })
).join('');
const semPrint =
  '<section><h2>O que não tem print</h2><ul>' +
  '<li><b>Desconectar caixa</b>: a janela diz "Sim, desconectar" e explica que dá para conectar de novo (I-CX3).</li>' +
  '<li><b>Nomes</b>: "Atendimento (rascunho)" vira "Atendimento" e "Copiloto do Escritorio" vira "Copiloto do Escritório" quando o seed roda depois do deploy (I-AS4, I-AS5).</li>' +
  '<li><b>Memória do contato</b> (desligada até você ligar): ao resolver a conversa, nota "MEMÓRIA DA IA (conversa #N)" no painel do lead → Notas, sem dado de saúde; linha "Memória do contato" em Uso e custo (I-X7).</li>' +
  '<li><b>Caderno da madrugada</b> (desligado até você ligar): 05:30, só se algo mudou, dentro do teto (I-X6).</li>' +
  '<li><b>Vigia</b>: no fim da Visão geral — botão de conversa e chip vermelho no 2º caso (3 retomadas).</li>' +
  '</ul></section>';
const css =
  'body{font:14px system-ui,sans-serif;margin:24px;background:#f4f4f4;color:#111}h1{font-size:20px}h2{font-size:15px;margin:28px 0 8px}.par{display:flex;gap:24px;align-items:flex-start;flex-wrap:wrap}figure{margin:0;background:#fff;padding:8px;border:1px solid #ddd;border-radius:8px}figcaption{font-weight:600;margin-bottom:6px}img{width:700px;max-width:100%;display:block}@media (max-width:760px){body{margin:16px}}';

writeFileSync(
  `${OUT}/comparar.html`,
  `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Inteligência A5 — antes e depois</title><style>${css}</style></head><body><h1>Inteligência — pacote A5: antes e depois</h1><p>Itens restantes da lista. Dados das telas são fictícios (story). Decisões N1–N7 no topo do plano.</p>${secoes}${semPrint}</body></html>`
);
console.log(`ok ${OUT}/comparar.html`);
```
Rodar `node tmp/intel-a5-harness/comparar.mjs` → `ok …/comparar.html`. Abrir no navegador e conferir que todas as imagens carregam.

- [ ] **Step 5:** entregar o caminho `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a5\comparar.html` (com a pasta clicável) ao Eduardo. **Merge só com o "aprovado" dele.**

---

### Task 20: Verificação final + texto do PR + smoke em bloco

**Files:** nenhum novo.

- [ ] **Step 1: Front inteiro tocado**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/routes/dashboard/ramon/components/lead --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadIaExecucoes.vue app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue app/javascript/dashboard/api
git status --short
```
Expected: tudo verde; eslint sem `error`; `git status` limpo (sem `vitest.local.config.ts` nem `tmp/`).

- [ ] **Step 2: Varredura de regras**

```bash
git diff 0a31e02 --stat -- app/models/lead.rb app/services/ramon/advbox_event_processor.rb app/finders/conversation_finder.rb enterprise/app/models/captain/scenario.rb enterprise/app/services/captain/assistant/agent_runner_service.rb app/javascript/dashboard/i18n/locale/pt_BR/ramon.json .env.example
grep -rn "Captain::" app/services/ramon/memoria_contato.rb app/jobs/ramon/caderno_noturno_job.rb
grep -rn "iris" app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/captain --include=*.vue | grep -v "automacoes\|AnimatingImg\|story\|UsoCusto"
ls db/migrate | grep 2026100780
grep -n "define(version" db/schema.rb
```
Expected: 1º vazio; 2º só a linha do job com `Captain::CadernoNoturno` (atrás do `ChatwootApp.enterprise?`); 3º vazio; 4º as 2 migrações; 5º `2026_10_07_800002` (ou a maior, se outra frente mergeou depois).

- [ ] **Step 3: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Inteligência A5 — o que faltava da lista da área (I-T4, I-T5, I-AS4, I-AS5, I-SK6, I-SK7, I-PG2, I-PG3, I-PG4, I-CX3, I-EX3, I-EX5, I-WD3, I-WD4, I-CF3–I-CF6, I-FQ5, I-FQ6, I-DO4, I-DO5, I-X5–I-X8).

1. **Testar:** debaixo de cada resposta, as ferramentas que rodaram (cor pelo nível; erro em vermelho); a conversa fica guardada ao trocar de tela ou de assistente; "Testar com o caso…" põe o nº do caso na mensagem; falas sugeridas das skills, as do seu papel primeiro. Nada é enviado sozinho.
2. **Skills:** "Testar esta skill" (abre o Testar com a fala de exemplo), "rodou N× em 30 dias" e os papéis de cada skill (editáveis).
3. **Configurações:** cada assistente mostra só o que vale para o público dele (Copiloto sem mensagens ao cliente); "Nome do escritório" e "Criatividade"; excluir assistente numa zona de risco recolhida que pede o nome; "Ver o texto final que o assistente recebe"; chave **Memória do contato**.
4. **Memória do contato (desligada até ligar):** ao resolver a conversa, a IA anota no lead o que aprendeu — benefício, trabalho, datas, documentos, objeções; nunca saúde, CPF, telefone ou endereço; para no teto do dia; custo em linha própria.
5. **Caderno de provas automático (desligado até ligar):** 05:30, roda os casos de teste se algo mudou, dentro do teto; a Visão geral mostra "41 de 43 ok".
6. **FAQs e Documentos** sempre do Atendimento (sem seletor), "usada N×" em cada FAQ, aviso de que o link lê o site; **Execuções** com período, "carregar mais" e "só erros de hoje"; **Vigia** com botão da conversa e cor pela régua; **painel do lead** com "o que a IA fez neste caso"; **Caixas** sem "excluir"/"implantar"; seletor de assistente só onde faz sentido; telas que faltavam no kit (sem roxo, fundos translúcidos).
7. Assistentes renomeados para **Atendimento** e **Copiloto do Escritório** pelo seed (sem criar outro); a marca morta `ramon_modo_rascunho` sai.

2 migrações só de coluna (`captain_scenarios.exemplo/papeis`, `captain_assistant_responses.usos/usada_em`); sem env nova; 1 cron novo (05:30, sem efeito com a chave desligada).

## Closes
- Backlog `comercial\docs\2026-10-05-inteligencia-tela-a-tela.md`: todos os itens restantes (I-PG5 e I-FQ4 já existiam; I-X4 = #215).

## How to test
Ver "Operação depois do deploy" no plano `docs/superpowers/plans/2026-10-07-inteligencia-a5.md` e o smoke em bloco abaixo.

## What changed
- `Ramon::MemoriaContato` (FOSS) + `Captain::Llm::ContactNotesService` reescrito; `Ramon::IaGastoAlerta.passou_do_teto?`; função `memoria_contato` em Uso e custo.
- `Captain::CadernoNoturno` + `Ramon::CadernoNoturnoJob` (cron 05:30) + `PATCH ia_rodadas/noturno`; `caderno` na Visão geral.
- `AssistantsController`: ferramentas no `playground`, `texto_final`; `ScenariosController`: `uso_30d`, `exemplo`, `papeis`; `faq_lookup` conta uso; filtros `periodo`/`lead_id`/`antes_de` nas Execuções; `conversa_display_id` no Vigia.
- Front: Testar, Skills, Configurações, FAQs, Documentos, Caixas, ferramentas HTTP, Execuções, Vigia, Casos de teste, Visão geral, painel do lead.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
```

- [ ] **Step 4: Smoke em bloco (para o Eduardo, depois do deploy)** — anotar no relatório, por seção, sem perguntas passo a passo:
  **A. Testar** — escolher "Funil hoje" nas falas sugeridas → Enviar → chips das ferramentas debaixo da resposta; ir a Skills e voltar → conversa continua; "Testar com o caso…" → escolher um lead → "caso N (Nome)" no campo.
  **B. Skills** — "Testar esta skill" abre o Testar com a fala; chips "Rodou N× em 30 dias" e papéis; editar uma skill → fala e papéis aparecem no formulário.
  **C. Configurações** — Atendimento: "Nome do escritório", "Criatividade", 3 chaves (sem citações); Copiloto: sem mensagens ao cliente, com o aviso; zona de risco só libera com o nome; "Ver o texto final".
  **D. Memória** — ligar no Atendimento, resolver conversa de teste com lead → nota "MEMÓRIA DA IA" no painel; Uso e custo com "Memória do contato". Desligar se não gostar.
  **E. Caderno** — ligar em Casos de teste; no dia seguinte, Visão geral com a rodada das 05:30 (se algo mudou).
  **F. Resto** — FAQs sem seletor e com "Usada N×"; Documentos → Link com o aviso; Execuções com período, "Carregar mais" e "Só erros de hoje"; Vigia com botão de conversa; painel do lead → Atividade → "O que a IA fez neste caso"; Caixas → desconectar diz "Sim, desconectar"; nomes "Atendimento" e "Copiloto do Escritório" depois do seed.

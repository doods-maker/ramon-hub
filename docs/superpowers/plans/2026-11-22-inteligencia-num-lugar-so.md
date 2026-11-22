# Inteligência num lugar só — plano

**Pedido (Eduardo, 22/11/2026):** a IA do hub está espalhada (menu Inteligência no mundo Conversas + Playbooks,
Funil e Registro em Intranet → Configurações) e os nomes confundem. Juntar tudo num ponto só.

**Regra de engenharia:** skills do Matt em todo o PR — `mattpocock-skills:tdd` (spec primeiro onde houver lógica),
`mattpocock-skills:codebase-design` (costura abaixo), `mattpocock-skills:code-review` antes do merge (nunca revisão
genérica), `mattpocock-skills:pr` no corpo do PR. 1 PR único (decisão dele).

## Decisões (formulário 22/11)

| # | Decisão |
|---|---|
| 1 | Automações **ficam** na Inteligência |
| 2 | Teses/Playbooks **entram** na Inteligência |
| 3 | Painel dos agentes (esteira) **fica onde está**; Visão geral ganha atalho |
| 4 | Documentos saem do menu: botão "Gerar FAQs de um texto ou página" dentro de FAQs |
| 5 | Execuções + Uso e custo + Mudanças da IA = item **Histórico** |
| 6 | Nomes: **Skills** fica; **Ferramentas → Ações da IA**; a skill mostra as ações que usa (já mostra) e os 3 nomes repetidos (skill × ação) deixam de colidir: ação começa com verbo |
| 7 | 1 PR único |

## Costura

O módulo que já decide menu + abas é `ramon/helpers/navIntranet.js` (`SECOES` → `secoesIntranet`, `grupoDaRota`),
consumido por `IntranetSidebar.vue` e `AbasIntranet.vue`. A Inteligência entra ali como **nova seção**; as rotas
do Captain ganham `world: 'intranet'`; o bloco Captain sai de `components-next/sidebar/Sidebar.vue`.
Nenhuma rota muda de caminho (deep-links e avisos continuam valendo).

O que a aba precisa a mais (interface pequena, tudo no `aba()`):
- `assistente: true` → a aba é de rota com `:assistantId`. Com assistente na rota atual, o link leva o mesmo
  `assistantId`; sem ele, vai por `captain_assistants_index` + `navigationPath` (o resolvedor que o menu já usa hoje).
- `query` → a aba só acende quando a query bate (Mudanças da IA = Registro com `tipo=ia`); o Registro de
  Configurações acende quando **não** bate. `grupoDaRota(routeName, isAdmin, painel, query)`.

Visibilidade: cada aba espelha o guard da rota de hoje (Captain = admin + agente com a feature; Playbooks/Registro
= admin). Não abrir nada a quem não via.

## Mapa novo — seção INTELIGÊNCIA

| Item (grupo) | Abas (rota → acende também) |
|---|---|
| Visão geral | `captain_visao_geral_index` |
| Como atende | `captain_como_ia_atende_index` |
| Teses | Teses `ramon_playbooks` · FAQs `captain_assistants_responses_index` (→ pending, documents) |
| Assistentes | Assistentes `captain_assistants_create_index` · Regras gerais `captain_assistants_settings_index` (→ guidelines, guardrails) · Skills `captain_assistants_scenarios_index` · Ações da IA `captain_ferramentas_index` (→ tools) · Caixas `captain_assistants_inboxes_index` |
| Automações | `captain_automacoes_index` (→ editor, execução) |
| Testar | Testar `captain_assistants_playground_index` · Casos de teste `captain_assistants_casos_teste_index` |
| Histórico | Execuções `captain_execucoes_index` · Uso e custo `captain_ia_uso_index` · Mudanças da IA `ramon_registro_acoes?tipo=ia` |

Configurações (Intranet) fica com **Funil** e **Registro de ações**.

## Tarefas

1. **Menu** (spec primeiro em `ramon/helpers/specs/navIntranet.spec.js`): seção, grupos, `assistente`, `query`,
   visibilidade; `world: 'intranet'` nas rotas do Captain; tirar o bloco Captain do `Sidebar.vue`;
   `AbasIntranet`/`IntranetSidebar` montam o link pela aba. Atalhos que apontavam para o Captain no mundo Conversas
   continuam funcionando (mesmas rotas).
2. **Teses**: título da página "Teses"; 3ª aba de detalhe **FAQs** → FAQs filtradas pela tese (`?tese=<id>`,
   a tela de FAQs já filtra).
3. **Documentos**: botão "Gerar FAQs de um texto ou página" no topo de FAQs abre o cadastro de documento; link
   "documentos já usados" leva à lista (que acende a aba FAQs). Texto de ajuda: "o hub escreve rascunhos de FAQ;
   a IA só usa as FAQs que você aprovar".
4. **Assistente por etapa**: o seletor sai de `FunilConfig.vue` e vai para a etapa em Como atende
   (`LimitesDaEtapa.vue`, mesma chamada `captain_assistant_id` do estágio). Funil ganha uma linha apontando para lá.
5. **Nomes**: rótulo Ferramentas → "Ações da IA" (+ frase no topo: "o que a IA consegue fazer no sistema; as
   Skills dizem quando usar"); Skills ganha a frase "situação que a IA sabe conduzir". `config/agents/tools.yml`:
   "Playbook da tese" → "Ler o playbook da tese", "Funil de hoje" → "Ver o funil de hoje", "Consulta de andamento"
   → "Buscar andamento do cliente". Conferir specs que citam os títulos.
6. **Histórico** e **Visão geral**: abas acima; atalho "Painel dos agentes" na Visão geral só para quem o backend
   libera (`usePainelAgentes`).
7. **Prova**: vitest dos specs tocados; prints antes/depois (harness `tmp/design-harness`); smoke em bloco no
   consolidado; deploy só web (sem migração, sem seed — exceto se `tools.yml` exigir; conferir).

## Fora deste PR

Mexer no conteúdo das telas além do listado; Painel dos agentes; Registro geral; renomear rotas.

# Inteligência A1 — Faxina rápida — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tirar da área Inteligência do hub o inglês, os exemplos falsos da Chatwoot, o "Saiba mais"/plano/créditos, a "Coisas Divertidas" e o PDF quebrado, e dar nome em português + cor por nível às ferramentas (Skills e Execuções) — só aparência e texto.

**Architecture:** Mudança de texto/visual nas telas existentes (`routes/dashboard/captain/**`, `components-next/captain/**`) e no i18n (en + pt_BR). Única peça de dado nova: campo `nivel` em `config/agents/tools.yml`, levado à tela pelo endpoint de ferramentas (Skills) e por um `catalogo` na resposta de Execuções; um helper JS (`ramon/helpers/ferramentas.js`) traduz nível → cor do kit `ui.js`. Aprovação do Eduardo por prints antes/depois (story + harness Vite + Chrome headless).

**Tech Stack:** Rails 7 (fork Chatwoot v4.15.1, overlay `enterprise/`), RSpec (só no CI), Vue 3 `<script setup>`, Vuex, vitest, Tailwind, vue-i18n.

**Spec:** `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-05-inteligencia-tela-a-tela.md` — seção "Resumo das ⭐ → 1. Faxina rápida": I-T1, I-T2, I-T3, I-T6, I-SK1, I-SK2, I-FE3, I-FQ3, I-CF1, I-CF2, I-DO2, I-DO3, I-CX2, I-EX1, I-WD1.

## Global Constraints

- Worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-intel-a`, branch `feat/inteligencia-a1-faxina`, base `origin/ramon` = `ffbd8c3793`. **Todo `arquivo:linha` deste plano é do commit base.** Quando uma task mexe num arquivo que outra task já mexeu, use o trecho citado como âncora (o número da linha pode ter andado).
- Pacote VISUAL/texto: nada de I-SK4, I-FE1, I-DO1, I-AS1 etc. Não inventar funcionalidade.
- Nomes da área: "Ferramentas" (nunca "Tools" em pt_BR), "Testar" (menu do Playground), "Vigia" (Watchdog), "Skills" — **nunca "Cenário(s)" em lugar nenhum da área**.
- Cores por nível de ferramenta: azul = consulta · âmbar = prepara Sugestão (`RamonEscritaTool` e `AdvboxMcpEscritaTool`) · verde = rascunho pro cliente (`solicitar_documento`, `enviar_link_portal`) · neutro = escrita interna. No kit `ui.js`: `TOM.blue`, `TOM.amber`, `TOM.teal` (é o verde do kit), `TOM.slate`. A classificação mora no `tools.yml` (campo `nivel`), nunca numa lista solta no front.
- Visual: kit `app/javascript/dashboard/routes/dashboard/ramon/helpers/ui.js` (`CHIP`, `TOM`, `AVISO`); fundos coloridos SEMPRE translúcidos; destaque azul = `n-blue` (#2563EB). Tailwind only — sem CSS, sem `style`.
- i18n: o fork mantém **en E pt_BR** (`app/javascript/dashboard/i18n/locale/{en,pt_BR}/{integrations,settings,ramon}.json`). Toda chave criada/apagada nos dois. Em en, texto em inglês; termos que já estão certos em inglês ficam (ex.: "Tools", "Watchdog").
- Vue: Composition API `<script setup>`, eventos camelCase, nada de texto cru no template.
- Sem Ruby local: specs Ruby e rubocop são validados no CI. JS local: `npx eslint <arquivos>` e `npx vitest run --config tmp/vitest.local.config.ts <spec>` (node_modules é junção pro wt-funil-padrao; sem esse config o vitest não acha o fake-indexeddb).
- Commits: Conventional Commits, mensagem em pt-BR, sem citar Claude no assunto.
- Conteúdo que fala com cliente é gate do Eduardo: os exemplos de Proteções/Diretrizes (I-CF2) só entram no assistente se alguém clicar "Adicionar"; o texto vai nos prints para ele aprovar.
- **Não fazer push nem abrir PR** antes do "aprovado" do Eduardo nos prints (Task 11).

## Review Focus

- Skill sem ferramentas (`tools: null` vindo da API, que grava `nil` quando a instrução não cita ferramenta) → o card abre sem a linha "Ferramentas usadas" e sem erro. Teste: Task 6, `ScenariosCard.spec.js` ("skill sem ferramentas").
- Usuário agente (não admin) abre Skills: `GET /captain/assistants/tools` é só admin (`assistant_policy.rb:14-16`) → chips caem no id cru, neutros, sem quebrar. Teste: Task 5, `ferramentas.spec.js` ("fora do catálogo") + Task 6 (`minha_http`).
- Execução de ferramenta fora do catálogo (HTTP personalizada, id antigo) → Execuções mostra o id cru e nenhum chip de nível. Teste: Task 5, `ferramentas.spec.js`; template usa `v-if` no chip (Task 7).
- Ferramenta nova entra no `tools.yml` sem `nivel`, ou com nível errado pra classe → CI vermelho. Teste: Task 5 (`ferramentas.spec.js` lê o yml; `captain_tools_helpers_spec.rb` amarra `sugestao` às classes de escrita).
- Hub com modo padrão "Piloto com limites" (`RAMON_COPILOTO_MODO_DEFAULT=piloto_limitado`) → o aviso ao conectar caixa diz esse modo, não "Rascunho". Teste: Task 10, `ConnectInboxForm.spec.js`.

## Divergências conscientes do backlog (registradas)

1. **I-T6 sem Visão geral/Automações:** essas telas não existem ainda. A ordem relativa pedida é respeitada; **Vigia** fica no topo (lugar da futura Visão geral, que o absorve no I-VG1) e **Caixas de Entrada** logo depois de Assistentes (vira seção do cartão do assistente no I-AS3/I-CX1). Os dois só saem do menu quando o destino existir.
2. **I-WD1 parcial:** só renomeia "Watchdog" → "Vigia" (menu + título da tela).
3. **Tela "Assistentes"** continua sendo o estado vazio fixo (a lista real é I-AS1, pacote 2). No A1 os 5 assistentes falsos e o "Saiba mais" saem, e o texto passa a dizer a verdade (os assistentes abrem pelo seletor no topo das outras telas).
4. **I-SK2 / I-EX1:** "verde" = `TOM.teal` (o kit não tem green). Em Execuções o nome/nível vem num `catalogo` dentro da própria resposta de Execuções, porque o endpoint de ferramentas é só admin e Execuções é admin + agente.
5. **I-DO2:** o PDF sai do formulário (não só um aviso) — sem "Colar texto" (I-DO1, pacote 3) o formulário fica só com URL + nome. O filtro "PDF's" da lista fica (é filtro, não criação).
6. **I-T1 / Playground:** só o rótulo do menu vira "Testar"; o cabeçalho da tela segue "Área de testes" (já está em português); a descrição perde a palavra "playground".
7. **I-T3:** o Paywall ("Atualize seu plano") não sai — só aparece com a feature desligada, o que não acontece na banca.
8. **Exemplo de Skill em inglês** — resolvido: entra no A1 (ver decisão 1 abaixo, Task 6).

## Decisões do controller sobre as dúvidas (05/10, com base em decisões já tomadas pelo Eduardo)

1. **I-SK3 entra no A1** (mesmo problema dos exemplos falsos do I-T2): na Task 6, o exemplo em inglês de `scenarios/Index.vue:43-53` vira um exemplo da banca — título "Lead que sumiu depois da reunião", descrição "Quando o lead não responde há dias depois da reunião de fechamento", instrução "Retome com gentileza, lembre o próximo passo combinado e ofereça novo horário; use @playbook_da_tese se precisar." (adapte aos campos reais do array).
2. **Proteção de rascunho reescrita** para não contradizer o piloto limitado (D7, ligado em 17/08): "Conteúdo jurídico, valores e prazos só saem como rascunho…; no modo piloto limitado, só logística sai sozinha."
3. **Vigia no topo** até a Visão geral existir: ok.
4. **Texto provisório da tela Assistentes**: ok até o I-AS1.

## Mapa de arquivos

| Arquivo | Task | O que muda |
|---|---|---|
| `app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue` (novo) | 1 | story com as 15 telas e API fictícia (prints) |
| `tmp/intel-harness/{index.html,main.js,vite.config.mts,ConversationBoxStub.vue,shots.sh,comparar.mjs}` (não versionado) | 1, 11 | harness Vite + Chrome headless |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:449-531` | 2 | ordem do menu |
| `i18n/locale/{en,pt_BR}/settings.json`, `ramon.json` | 2, 5, 7 | rótulos do menu, Vigia, níveis, Execuções |
| `components-next/captain/PageLayout.vue` + 11 páginas de `routes/dashboard/captain/**` | 3 | sem "Saiba mais"/banner de limite |
| `components-next/captain/pageComponents/{response,document}/LimitBanner.vue` (apagar) | 3 | banner de plano |
| `components-next/captain/assistant/AssistantPlayground.vue:133-135` | 3 | frase dos créditos |
| `components-next/captain/pageComponents/emptyStates/*.vue` (5) | 4 | telas vazias sem exemplo falso |
| `config/agents/tools.yml` | 5 | nomes em português + `nivel` |
| `enterprise/app/models/concerns/captain_tools_helpers.rb:51-56`, `enterprise/app/views/api/v1/accounts/captain/assistants/tools.json.jbuilder` | 5 | `nivel` no catálogo |
| `app/controllers/api/v1/accounts/captain_tool_runs_controller.rb:9-12`, `app/views/api/v1/accounts/captain_tool_runs/index.json.jbuilder` | 5 | `catalogo` em Execuções |
| `routes/dashboard/ramon/helpers/ferramentas.js` (novo) + `helpers/specs/ferramentas.spec.js` (novo) | 5 | nível → cor |
| `spec/enterprise/models/concerns/captain_tools_helpers_spec.rb`, `spec/controllers/api/v1/accounts/captain_tool_runs_controller_spec.rb` | 5 | specs Ruby (CI) |
| `components-next/captain/assistant/ScenariosCard.vue` + `assistant/specs/ScenariosCard.spec.js` (novo), `routes/dashboard/captain/assistants/scenarios/Index.vue` | 6 | chips + legenda |
| `i18n/locale/{en,pt_BR}/integrations.json` | 3,4,6,8,9,10 | textos |
| `routes/dashboard/captain/pages/Execucoes.vue` | 7 | nome legível + chip |
| `routes/dashboard/captain/assistants/{guardrails,guidelines}/Index.vue` | 8 | exemplos da banca |
| `components-next/captain/pageComponents/document/DocumentForm.vue`, `routes/dashboard/captain/documents/Index.vue` | 9 | sem PDF + aviso D4 |
| `components-next/captain/pageComponents/inbox/ConnectInboxForm.vue` + `inbox/specs/ConnectInboxForm.spec.js` (novo) | 10 | aviso ao conectar |

### Verificação de i18n usada em várias tasks ("paridade")

Rodar na raiz do worktree (Bash). Esperado: as 3 linhas com `[]` e `[]`.

```bash
node -e "
const f=p=>JSON.parse(require('fs').readFileSync(p,'utf8'));
const keys=(o,p='')=>Object.entries(o).flatMap(([k,v])=>v&&typeof v==='object'?keys(v,p+k+'.'):[p+k]);
for (const arq of ['integrations','settings','ramon']) {
  const en=new Set(keys(f('app/javascript/dashboard/i18n/locale/en/'+arq+'.json')));
  const pt=new Set(keys(f('app/javascript/dashboard/i18n/locale/pt_BR/'+arq+'.json')));
  const so=(a,b)=>[...a].filter(k=>!b.has(k)&&/CAPTAIN/.test(k));
  console.log(arq,'so en:',JSON.stringify(so(en,pt)),'so pt_BR:',JSON.stringify(so(pt,en)));
}"
```

(Se o JSON quebrar — vírgula sobrando/faltando — o `JSON.parse` acusa a linha.)

---

### Task 1: Story da área + harness + prints "antes"

Tem que rodar **antes de qualquer mudança de código**: o "antes" é o código original.

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue`
- Create (não versionado, `tmp/` está no `.gitignore:16`): `tmp/intel-harness/index.html`, `tmp/intel-harness/main.js`, `tmp/intel-harness/vite.config.mts`, `tmp/intel-harness/ConversationBoxStub.vue`, `tmp/intel-harness/shots.sh`, `tmp/vitest.local.config.ts` (se ainda não existir)

**Interfaces:**
- Produces: variantes da story (títulos ASCII, usados na URL `?variant=`): `Assistentes`, `FAQs`, `FAQs pendentes`, `Documentos`, `Documentos novo`, `Skills`, `Ferramentas`, `Testar`, `Caixas`, `Caixas conectar`, `Configuracoes`, `Protecoes`, `Diretrizes`, `Execucoes`, `Vigia`. A API fictícia já devolve `nivel` em `captain/assistants/tools` e `catalogo` em `captain_tool_runs` (formato que as Tasks 5–7 criam; o código antigo ignora).

- [ ] **Step 1: Criar `tmp/vitest.local.config.ts` (se não existir)**

```ts
import { mergeConfig } from 'vitest/config';
import base from '../vitest.config';

// local: node_modules é junção pro worktree do funil; libera o fs de fora.
export default mergeConfig(base, {
  server: { fs: { strict: false } },
});
```

- [ ] **Step 2: Criar a story** `app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue`

```vue
<script setup>
// Story da área Inteligência (pacote A1) — aprovação visual por print,
// claro/escuro. Sem rede: window.axios responde com dados FICTÍCIOS por URL.
// Variantes com diálogo clicam no botão depois de montar (pelo texto).
import { provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import AssistantsIndex from '../assistants/Index.vue';
import ResponsesIndex from '../responses/Index.vue';
import ResponsesPending from '../responses/Pending.vue';
import DocumentsIndex from '../documents/Index.vue';
import ScenariosIndex from '../assistants/scenarios/Index.vue';
import CustomToolsIndex from '../tools/Index.vue';
import PlaygroundIndex from '../assistants/playground/Index.vue';
import InboxesIndex from '../assistants/inboxes/Index.vue';
import SettingsIndex from '../assistants/settings/Settings.vue';
import GuardrailsIndex from '../assistants/guardrails/Index.vue';
import GuidelinesIndex from '../assistants/guidelines/Index.vue';
import Execucoes from './Execucoes.vue';
import Watchdog from './Watchdog.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const DIA = 86400000;
const diasAtras = n => new Date(Date.now() - n * DIA).toISOString();
const unix = n => Math.floor((Date.now() - n * DIA) / 1000);

const ATENDIMENTO = {
  id: 1,
  account_id: 1,
  name: 'Atendimento (rascunho)',
  description:
    'Responde leads no WhatsApp com rascunhos para a equipe revisar.',
  config: {
    product_name: 'Ramon Antônio Advogados',
    feature_faq: false,
    feature_memory: false,
    feature_citation: false,
    feature_contact_attributes: true,
    handoff_message: 'Vou chamar alguém da equipe para seguir com você.',
    resolution_message: 'Qualquer dúvida, é só chamar por aqui.',
    instructions: 'Você atende leads da banca no WhatsApp.',
    temperature: 0.3,
  },
  guardrails: [],
  response_guidelines: [],
  created_at: unix(60),
  updated_at: unix(1),
};
const COPILOTO = {
  ...ATENDIMENTO,
  id: 2,
  name: 'Copiloto do Escritório',
  description: 'Ajuda a equipe com AdvBox, cálculos e funil.',
};

const CATALOGO = [
  { id: 'faq_lookup', title: 'Buscar nas FAQs', nivel: 'consulta' },
  { id: 'playbook_da_tese', title: 'Playbook da tese', nivel: 'consulta' },
  {
    id: 'registrar_qualificacao',
    title: 'Registrar qualificação',
    nivel: 'interna',
  },
  {
    id: 'documentacao_faltante',
    title: 'O que falta no caso',
    nivel: 'consulta',
  },
  { id: 'solicitar_documento', title: 'Pedir documentos', nivel: 'rascunho' },
  {
    id: 'enviar_link_portal',
    title: 'Link do portal do cliente',
    nivel: 'rascunho',
  },
  { id: 'link_agendamento', title: 'Link de agendamento', nivel: 'consulta' },
  { id: 'agendar_reuniao', title: 'Agendar reunião', nivel: 'sugestao' },
  { id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao' },
  {
    id: 'consultar_dossie_advbox',
    title: 'Consultar dossiê no AdvBox',
    nivel: 'consulta',
  },
  {
    id: 'add_private_note',
    title: 'Nota interna na conversa',
    nivel: 'interna',
  },
];
const link = id =>
  `[${CATALOGO.find(tool => tool.id === id).title}](tool://${id})`;

const SKILLS = [
  {
    id: 1,
    title: 'Lead quer saber se tem direito',
    description: 'Quando o lead pergunta se o caso dele dá direito a benefício.',
    instruction: `Busque a resposta com ${link('faq_lookup')} e o ${link('playbook_da_tese')}. Confirmado um critério, use ${link('registrar_qualificacao')}.`,
    tools: ['faq_lookup', 'playbook_da_tese', 'registrar_qualificacao'],
  },
  {
    id: 2,
    title: 'Pedir documentos que faltam',
    description: 'Quando o caso está parado por falta de documento.',
    instruction: `Veja o que falta com ${link('documentacao_faltante')}, monte o pedido com ${link('solicitar_documento')} e mande o ${link('enviar_link_portal')}.`,
    tools: ['documentacao_faltante', 'solicitar_documento', 'enviar_link_portal'],
  },
  {
    id: 3,
    title: 'Lead aceitou a reunião',
    description: 'Quando o lead topa conversar com o advogado.',
    instruction: `Mande o ${link('link_agendamento')}; com a data combinada, use ${link('agendar_reuniao')} e ${link('mover_etapa')}.`,
    tools: ['link_agendamento', 'agendar_reuniao', 'mover_etapa'],
  },
  {
    id: 4,
    title: 'Lead só quer conversar',
    description: 'Quando o lead manda só um oi ou agradece.',
    instruction: 'Responda com cordialidade e pergunte como pode ajudar.',
    tools: null,
  },
];

const ASSISTENTE_FAQ = { id: 1, name: ATENDIMENTO.name };
const FAQS = [
  {
    id: 1,
    question: 'Quanto custa o trabalho de vocês?',
    answer:
      'O honorário é 30% dos atrasados + 3 benefícios, sem valor inicial e sem outra cobrança.',
    status: 'approved',
    assistant: ASSISTENTE_FAQ,
    documentable: null,
    created_at: unix(10),
    updated_at: unix(2),
  },
  {
    id: 2,
    question: 'Preciso levar algum documento na reunião?',
    answer: 'Traga RG, CPF e os laudos médicos que você tiver.',
    status: 'approved',
    assistant: ASSISTENTE_FAQ,
    documentable: { type: 'Conversation', display_id: 482 },
    created_at: unix(8),
    updated_at: unix(3),
  },
];
const PENDENTES = [
  {
    id: 3,
    question: 'Quem recebe auxílio-acidente pode continuar trabalhando?',
    answer: 'Pode. O auxílio-acidente é uma indenização e não impede o trabalho.',
    status: 'pending',
    assistant: ASSISTENTE_FAQ,
    documentable: { type: 'Captain::Document', name: 'Página do auxílio-acidente' },
    created_at: unix(1),
    updated_at: unix(1),
  },
];
const DOCS = [
  {
    id: 1,
    name: 'Página do auxílio-acidente',
    external_link: 'https://ramonantonio.adv.br/auxilio-acidente',
    status: 'available',
    assistant: ASSISTENTE_FAQ,
    created_at: unix(5),
    updated_at: unix(5),
  },
];

const RUNS = [
  ['consultar_dossie_advbox', 'ok', 0.1],
  ['mover_etapa', 'ok', 0.3],
  ['solicitar_documento', 'ok', 0.5],
  ['add_private_note', 'erro', 0.7],
].map(([tool, status, dias], i) => ({
  id: i + 1,
  tool_name: tool,
  status,
  duration_ms: 420 + i * 130,
  params: { lead_id: '123' },
  resultado: 'resultado da ferramenta',
  lead_id: 123,
  conversation_id: 482,
  assistant_id: 1,
  created_at: diasAtras(dias),
}));

const API = {
  'captain/assistants': {
    payload: [ATENDIMENTO, COPILOTO],
    meta: { total_count: 2, page: 1 },
  },
  'captain/assistants/1': ATENDIMENTO,
  'captain/assistants/tools': CATALOGO,
  'captain/assistants/1/scenarios': {
    payload: SKILLS,
    meta: { total_count: 4, page: 1 },
  },
  'captain/assistants/1/inboxes': { payload: [], meta: {} },
  'captain/assistant_responses': {
    payload: FAQS,
    meta: { total_count: 2, page: 1 },
  },
  'captain/documents': { payload: DOCS, meta: { total_count: 1, page: 1 } },
  'captain/custom_tools': { payload: [], meta: { total_count: 0, page: 1 } },
  captain_tool_runs: {
    resumo: {
      total_24h: 4,
      erros_24h: 1,
      por_tool: { consultar_dossie_advbox: 1, mover_etapa: 1 },
      tools: RUNS.map(run => run.tool_name).sort(),
    },
    items: RUNS,
    catalogo: CATALOGO,
  },
  ramon_watchdog: {
    thresholds: {
      teto_diario: 3,
      intervalo_minimo_dias: 2,
      teto_copiloto_noturno: 15,
      horario_retomada: '11:00 (BRT)',
      horario_copiloto: '05:00 (BRT)',
    },
    counters: {
      retomadas_24h: 2,
      sugestoes_pendentes: 3,
      execucoes_24h: 4,
      parados_agora: 1,
    },
    items: [
      {
        lead_id: 12,
        name: 'Maria Souza',
        stage_name: 'Qualificação',
        dias_parado: 6,
        limite_da_etapa: 3,
        tentativas: 1,
        ultima_retomada_em: diasAtras(2),
        tarefa_aberta: false,
        conversation_id: 482,
      },
    ],
  },
};
const PENDENTES_RESP = { payload: PENDENTES, meta: { total_count: 1, page: 1 } };

const responder = async (url, config) => {
  const path = url.replace(/^\/api\/v1\/(accounts\/\d+\/)?/, '');
  if (
    path === 'captain/assistant_responses' &&
    config?.params?.status === 'pending'
  )
    return { data: PENDENTES_RESP };
  return { data: API[path] ?? { payload: [], meta: {} } };
};
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

// As páginas leem :assistantId com useRoute(): rota fake.
const rota = reactive({
  name: 'captain_assistants_responses_index',
  params: { accountId: 1, assistantId: 1 },
  query: {},
});
provide(routeLocationKey, rota);
provide(routerKey, {
  push: () => {},
  replace: () => {},
  resolve: () => ({ href: '#' }),
  currentRoute: { value: rota },
});

const store = useStore();
// sem router: getCurrentAccountId lê a conta de rootState.route
store.registerModule('route', { state: { params: { accountId: 1 } } });
store.commit(types.SET_CURRENT_USER, {
  id: 1,
  name: 'Eduardo Schlata',
  accounts: [{ id: 1, role: 'administrator' }],
  ui_settings: {},
});
store.commit(`accounts/${types.ADD_ACCOUNT}`, {
  id: 1,
  features: {
    captain_integration: true,
    captain_integration_v2: true,
    custom_tools: true,
  },
});
store.commit(`inboxes/${types.SET_INBOXES}`, [
  { id: 7, name: 'WhatsApp Escritório', channel_type: 'Channel::Whatsapp' },
]);
store.dispatch('captainAssistants/get');

// Clica no botão cujo texto contém `texto`, depois de a tela montar.
const clicarEm = texto => () =>
  setTimeout(
    () =>
      [...document.querySelectorAll('button')]
        .find(botao => botao.textContent.includes(texto))
        ?.click(),
    2000
  );
</script>

<template>
  <Story
    title="Captain/Inteligência"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant title="Assistentes">
      <div class="h-screen"><AssistantsIndex /></div>
    </Variant>
    <Variant title="FAQs">
      <div class="h-screen"><ResponsesIndex /></div>
    </Variant>
    <Variant title="FAQs pendentes">
      <div class="h-screen"><ResponsesPending /></div>
    </Variant>
    <Variant title="Documentos">
      <div class="h-screen"><DocumentsIndex /></div>
    </Variant>
    <Variant
      title="Documentos novo"
      :init-state="clicarEm('Criar um novo documento')"
    >
      <div class="h-screen"><DocumentsIndex /></div>
    </Variant>
    <Variant title="Skills">
      <div class="h-screen"><ScenariosIndex /></div>
    </Variant>
    <Variant title="Ferramentas">
      <div class="h-screen"><CustomToolsIndex /></div>
    </Variant>
    <Variant title="Testar">
      <div class="h-screen"><PlaygroundIndex /></div>
    </Variant>
    <Variant title="Caixas">
      <div class="h-screen"><InboxesIndex /></div>
    </Variant>
    <Variant
      title="Caixas conectar"
      :init-state="clicarEm('Conectar uma nova caixa de entrada')"
    >
      <div class="h-screen"><InboxesIndex /></div>
    </Variant>
    <Variant title="Configuracoes">
      <div class="h-screen"><SettingsIndex /></div>
    </Variant>
    <Variant title="Protecoes">
      <div class="h-screen"><GuardrailsIndex /></div>
    </Variant>
    <Variant title="Diretrizes">
      <div class="h-screen"><GuidelinesIndex /></div>
    </Variant>
    <Variant title="Execucoes">
      <div class="h-screen"><Execucoes /></div>
    </Variant>
    <Variant title="Vigia">
      <div class="h-screen"><Watchdog /></div>
    </Variant>
  </Story>
</template>
```

- [ ] **Step 3: Lint da story**

Run: `npx eslint --fix app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue && npx eslint app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue`
Expected: sem erros (o `--fix` só ajusta quebra de linha do prettier).

- [ ] **Step 4: Montar o harness** — copiar de `..\ramon-hub-wt-centro-comando\tmp\cc-harness\` os arquivos `index.html`, `ConversationBoxStub.vue` e `vite.config.mts` para `tmp/intel-harness/`; no `vite.config.mts` copiado, trocar `port: 6193` por `port: 6194`. Criar `tmp/intel-harness/main.js`:

```js
import { createApp, h } from 'vue';
import { setupVue3 } from '../../app/javascript/histoire.setup.ts';
import StoryFile from 'dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue';

const params = new URLSearchParams(window.location.search);
if (params.get('tema') === 'escuro') document.documentElement.classList.add('dark');
const alvo = params.get('variant') || 'FAQs';

const Story = { setup: (_, { slots }) => () => slots.default?.() };
const Variant = {
  props: { title: String, initState: Function },
  setup(props, { slots }) {
    const ativo = props.title === alvo;
    if (ativo && props.initState) props.initState();
    return () => (ativo ? slots.default?.() : null);
  },
};

// sem router no harness: router-link vira <a> (ou slot custom com navigate)
const RouterLink = {
  props: { to: [Object, String], custom: Boolean },
  setup(props, { slots }) {
    return () =>
      props.custom
        ? slots.default?.({ navigate: () => {}, href: '#' })
        : h('a', { href: '#' }, slots.default?.());
  },
};

const app = createApp({ render: () => h(StoryFile) });
app.component('RouterLink', RouterLink);
app.component('Story', Story);
app.component('Variant', Variant);
setupVue3({ app });
// fontes antes de montar: o print sai com Geist, não com o fallback
Promise.all(
  ['400 14px Geist', '600 14px Geist', '400 14px "Geist Mono"'].map(f =>
    document.fonts.load(f)
  )
).finally(() => app.mount('#app'));
```

Criar `tmp/intel-harness/shots.sh` (com a ferramenta Write — heredoc no Bash deste Windows come barra invertida):

```sh
#!/bin/sh
# uso: sh tmp/intel-harness/shots.sh antes|depois
# PNGs em comercial/docs/mockups/2026-10-05-inteligencia-a1
fase=$1
out="C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-05-inteligencia-a1"
mkdir -p "$out"
chrome="/c/Program Files/Google/Chrome/Application/chrome.exe"
for v in "Assistentes:assistentes:1440,900" "FAQs:faqs:1440,1000" \
  "FAQs pendentes:faqs-pendentes:1440,900" "Documentos:documentos:1440,900" \
  "Documentos novo:documentos-novo:1440,900" "Skills:skills:1440,1500" \
  "Ferramentas:ferramentas:1440,900" "Testar:testar:1440,900" \
  "Caixas:caixas:1440,900" "Caixas conectar:caixas-conectar:1440,900" \
  "Configuracoes:configuracoes:1440,1400" "Protecoes:protecoes:1440,1000" \
  "Diretrizes:diretrizes:1440,1000" "Execucoes:execucoes:1440,1000" \
  "Vigia:vigia:1440,900"; do
  nome=$(echo "$v" | cut -d: -f1); arq=$(echo "$v" | cut -d: -f2); tam=$(echo "$v" | cut -d: -f3)
  q=$(echo "$nome" | sed 's/ /%20/g')
  for tema in claro escuro; do
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --window-size=$tam \
      --virtual-time-budget=15000 --screenshot="$out/$fase-$tema-$arq.png" \
      "http://localhost:6194/?variant=$q&tema=$tema" >/dev/null 2>&1 &
  done
  wait
done
ls "$out" | grep "^$fase"
```

- [ ] **Step 5: Subir o harness** (Bash, `run_in_background: true`): `npx vite --config tmp/intel-harness/vite.config.mts`. Conferir: `curl -s -o /dev/null -w "%{http_code}" http://localhost:6194/` → `200`.

- [ ] **Step 6: Prints "antes"** — `sh tmp/intel-harness/shots.sh antes`. Expected: 30 arquivos `antes-{claro,escuro}-*.png`. Abrir com Read `antes-claro-faqs.png`, `antes-escuro-skills.png` e `antes-claro-caixas-conectar.png`: tela desenhada (nada de página branca ou spinner eterno; o diálogo de conectar aparece). Se uma tela vier vazia, ajustar a fixture da story (formato da resposta) e repetir — sem mexer em código de produção.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/pages/Inteligencia.story.vue
git commit -m "test(inteligencia): story das telas da área para prints de aprovação"
```

---

### Task 2: Menu — nomes em português, ordem nova, Vigia (I-T1, I-T6, I-WD1)

**Files:**
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:449-531`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/settings.json:318,320,322`
- Modify: `app/javascript/dashboard/i18n/locale/en/settings.json:331`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json:1625`

**Interfaces:** nenhuma.

- [ ] **Step 1: Reordenar o menu** — em `Sidebar.vue`, substituir o array `children: [ ... ],` do item `name: 'Captain'` (linhas 449-531) por:

```js
      // ponytail: Vigia no topo e Caixas logo após Assistentes = lugar da
      // Visão geral (I-VG1) e do cartão do assistente (I-AS3); saem do menu
      // quando esses destinos existirem.
      children: [
        {
          name: 'Watchdog',
          label: t('SIDEBAR.CAPTAIN_WATCHDOG'),
          activeOn: ['captain_watchdog_index'],
          to: accountScopedRoute('captain_watchdog_index'),
        },
        {
          name: 'Assistants',
          label: t('SIDEBAR.CAPTAIN_ASSISTANTS'),
          activeOn: ['captain_assistants_create_index'],
          to: accountScopedRoute('captain_assistants_create_index'),
        },
        {
          name: 'Inboxes',
          label: t('SIDEBAR.CAPTAIN_INBOXES'),
          activeOn: ['captain_assistants_inboxes_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_inboxes_index',
          }),
        },
        {
          name: 'Scenarios',
          label: t('SIDEBAR.CAPTAIN_SCENARIOS'),
          activeOn: ['captain_assistants_scenarios_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_scenarios_index',
          }),
        },
        {
          name: 'Tools',
          label: t('SIDEBAR.CAPTAIN_TOOLS'),
          activeOn: ['captain_tools_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_tools_index',
          }),
        },
        {
          name: 'FAQs',
          label: t('SIDEBAR.CAPTAIN_RESPONSES'),
          activeOn: [
            'captain_assistants_responses_index',
            'captain_assistants_responses_pending',
          ],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_responses_index',
          }),
        },
        {
          name: 'Documents',
          label: t('SIDEBAR.CAPTAIN_DOCUMENTS'),
          activeOn: ['captain_assistants_documents_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_documents_index',
          }),
        },
        {
          name: 'Playground',
          label: t('SIDEBAR.CAPTAIN_PLAYGROUND'),
          activeOn: ['captain_assistants_playground_index'],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_playground_index',
          }),
        },
        {
          name: 'Execucoes',
          label: t('SIDEBAR.CAPTAIN_EXECUCOES'),
          activeOn: ['captain_execucoes_index'],
          to: accountScopedRoute('captain_execucoes_index'),
        },
        {
          name: 'Settings',
          label: t('SIDEBAR.CAPTAIN_SETTINGS'),
          activeOn: [
            'captain_assistants_settings_index',
            'captain_assistants_guidelines_index',
            'captain_assistants_guardrails_index',
          ],
          to: accountScopedRoute('captain_assistants_index', {
            navigationPath: 'captain_assistants_settings_index',
          }),
        },
      ],
```

- [ ] **Step 2: Rótulos**

| Arquivo:linha | Chave | Novo valor |
|---|---|---|
| `pt_BR/settings.json:318` | `SIDEBAR.CAPTAIN_TOOLS` | `"Ferramentas"` |
| `pt_BR/settings.json:320` | `SIDEBAR.CAPTAIN_PLAYGROUND` | `"Testar"` |
| `pt_BR/settings.json:322` | `SIDEBAR.CAPTAIN_WATCHDOG` | `"Vigia"` |
| `en/settings.json:331` | `SIDEBAR.CAPTAIN_PLAYGROUND` | `"Test"` |
| `pt_BR/ramon.json:1625` | `CAPTAIN_RAMON.WATCHDOG.TITLE` | `"Vigia"` |

(en `CAPTAIN_TOOLS` "Tools" e `WATCHDOG` "Watchdog" já estão certos em inglês.)

- [ ] **Step 3: Verificar**

Run: `npx eslint app/javascript/dashboard/components-next/sidebar/Sidebar.vue` → sem erros. Rodar a "paridade" → tudo `[]`. Run: `grep -n '"CAPTAIN_TOOLS"\|"CAPTAIN_PLAYGROUND"\|"CAPTAIN_WATCHDOG"' app/javascript/dashboard/i18n/locale/pt_BR/settings.json` → `Ferramentas`, `Testar`, `Vigia`.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/dashboard/components-next/sidebar/Sidebar.vue app/javascript/dashboard/i18n/locale/pt_BR/settings.json app/javascript/dashboard/i18n/locale/en/settings.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(inteligencia): menu em português na ordem nova (Ferramentas, Testar, Vigia)"
```

---

### Task 3: Sem "Saiba mais", sem banner de limite/plano, sem "créditos" (I-T3)

**Files:**
- Modify: `app/javascript/dashboard/components-next/captain/PageLayout.vue:53-56,175-181`
- Modify (tirar `:show-know-more="false"`): `routes/dashboard/captain/assistants/guardrails/Index.vue:180`, `assistants/guidelines/Index.vue:187`, `assistants/inboxes/Index.vue:71`, `assistants/playground/Index.vue:15`, `assistants/scenarios/Index.vue:196`, `assistants/settings/Settings.vue:109`, `responses/Pending.vue:253`, `tools/Index.vue:101`
- Modify: `routes/dashboard/captain/assistants/Index.vue:6,12,14,57-67`
- Modify: `routes/dashboard/captain/documents/Index.vue:7,23,24,36,368-378,389`
- Modify: `routes/dashboard/captain/responses/Index.vue:8,20,21,26,219-229,272`
- Modify: `routes/dashboard/captain/responses/Pending.vue:9,21,22,27,258-268,326`
- Delete: `components-next/captain/pageComponents/response/LimitBanner.vue`, `components-next/captain/pageComponents/document/LimitBanner.vue`
- Modify: `components-next/captain/assistant/AssistantPlayground.vue:132-135`
- Modify: `i18n/locale/{en,pt_BR}/integrations.json:395,438-445,458-461`

(Caminhos `routes/...` = `app/javascript/dashboard/routes/...`; `components-next/...` = `app/javascript/dashboard/components-next/...`.)

**Interfaces:**
- Produces: `PageLayout` sem a prop `showKnowMore` e sem o slot `knowMore`.

- [ ] **Step 1: `PageLayout.vue`** — apagar a prop (linhas 53-56):

```js
  showKnowMore: {
    type: Boolean,
    default: true,
  },
```

e o bloco do slot (linhas 175-181):

```vue
              <div
                v-if="!isEmpty && showKnowMore"
                class="flex items-center gap-2"
              >
                <div class="w-0.5 h-4 rounded-2xl bg-n-weak" />
                <slot name="knowMore" />
              </div>
```

- [ ] **Step 2: Tirar `:show-know-more="false"`** — apagar essa linha (só ela) nos 8 arquivos listados acima.

- [ ] **Step 3: `assistants/Index.vue`** — apagar as linhas `import { useAccount } from 'dashboard/composables/useAccount';` (6), `import FeatureSpotlightPopover from 'dashboard/components-next/feature-spotlight/FeatureSpotlightPopover.vue';` (12), `const { isOnChatwootCloud } = useAccount();` (14) e o bloco inteiro `<template #knowMore> … </template>` (57-67).

- [ ] **Step 4: `documents/Index.vue`** — apagar `import { useAccount } …` (7), `import FeatureSpotlightPopover …` (23), `import LimitBanner from 'dashboard/components-next/captain/pageComponents/document/LimitBanner.vue';` (24), `const { isOnChatwootCloud } = useAccount();` (36), o bloco `<template #knowMore> … </template>` (368-378, mais a linha em branco que o segue) e a linha `      <LimitBanner class="mb-5" />` (389, mais a linha em branco que a segue).

- [ ] **Step 5: `responses/Index.vue`** — apagar `import { useAccount } …` (8), `import FeatureSpotlightPopover …` (20), `import LimitBanner from 'dashboard/components-next/captain/pageComponents/response/LimitBanner.vue';` (21), `const { isOnChatwootCloud } = useAccount();` (26), o bloco `<template #knowMore> … </template>` (219-229 + linha em branco 230) e `      <LimitBanner class="mb-5" />` (272).

- [ ] **Step 6: `responses/Pending.vue`** — apagar `import { useAccount } …` (9), `import FeatureSpotlightPopover …` (21), `import LimitBanner …` (22), `const { isOnChatwootCloud } = useAccount();` (27), o bloco `<template #knowMore> … </template>` (258-268 + linha em branco 269) e `      <LimitBanner class="mb-5" />` (326 + linha em branco 327).

- [ ] **Step 7: Apagar os banners**

```bash
git rm app/javascript/dashboard/components-next/captain/pageComponents/response/LimitBanner.vue app/javascript/dashboard/components-next/captain/pageComponents/document/LimitBanner.vue
```

- [ ] **Step 8: `AssistantPlayground.vue`** — trocar

```vue
    </div>

    <p class="text-xs text-n-slate-11 pt-2 text-center">
      {{ t('CAPTAIN.PLAYGROUND.CREDIT_NOTE') }}
    </p>
  </div>
</template>
```

por

```vue
    </div>
  </div>
</template>
```

- [ ] **Step 9: i18n (pt_BR e en, mesmas linhas nos dois arquivos)** — apagar a linha 395 (`"HEADER_KNOW_MORE": …`); apagar o bloco `"BANNER": { … },` (458-461); trocar o bloco `"PLAYGROUND"` (438-445) por:

pt_BR:
```json
    "PLAYGROUND": {
      "USER": "Você",
      "ASSISTANT": "Assistente",
      "MESSAGE_PLACEHOLDER": "Digite sua mensagem...",
      "HEADER": "Área de testes",
      "DESCRIPTION": "Converse com o assistente aqui para conferir se ele responde certo, rápido e no tom esperado."
    },
```

en:
```json
    "PLAYGROUND": {
      "USER": "You",
      "ASSISTANT": "Assistant",
      "MESSAGE_PLACEHOLDER": "Type your message...",
      "HEADER": "Playground",
      "DESCRIPTION": "Chat with your assistant here to check it answers accurately, quickly and in the expected tone."
    },
```

- [ ] **Step 10: Verificar**

Run: `npx eslint app/javascript/dashboard/components-next/captain/PageLayout.vue app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue app/javascript/dashboard/routes/dashboard/captain` → sem erros (pega import sem uso).
Run: `grep -rn "knowMore\|show-know-more\|LimitBanner\|HEADER_KNOW_MORE\|CREDIT_NOTE\|CAPTAIN.BANNER" app/javascript/dashboard --include=*.vue --include=*.js` → nada.
Rodar a "paridade" → tudo `[]`.

- [ ] **Step 11: Commit**

```bash
git add -A app/javascript/dashboard/components-next/captain app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/i18n/locale/en/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/integrations.json
git commit -m "feat(inteligencia): tira Saiba mais, banner de plano e créditos da área"
```

---

### Task 4: Telas vazias sem exemplo falso em inglês (I-T2)

**Files:**
- Modify (reescrever inteiro): `app/javascript/dashboard/components-next/captain/pageComponents/emptyStates/{AssistantPageEmptyState,CustomToolsPageEmptyState,DocumentPageEmptyState,InboxPageEmptyState,ResponsePageEmptyState}.vue`
- Modify: `i18n/locale/pt_BR/integrations.json:577-584,847-856,862-869,1062-1071,1099-1102`; `i18n/locale/en/integrations.json:577-584,848-857,863-870,1063-1072,1100-1103`

**Interfaces:** mesmos props/eventos de antes (`click`; `ResponsePageEmptyState` mantém `variant`, `hasActiveFilters`, `clearFilters`). `captainEmptyStateContent.js` fica (ainda alimenta os `*.story.vue` antigos do Captain).

- [ ] **Step 1: `AssistantPageEmptyState.vue`**

```vue
<script setup>
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['click']);
</script>

<template>
  <EmptyStateLayout
    :title="$t('CAPTAIN.ASSISTANTS.EMPTY_STATE.TITLE')"
    :subtitle="$t('CAPTAIN.ASSISTANTS.EMPTY_STATE.SUBTITLE')"
    :action-perms="['administrator']"
    :show-backdrop="false"
  >
    <template #actions>
      <Button
        :label="$t('CAPTAIN.ASSISTANTS.ADD_NEW')"
        icon="i-lucide-plus"
        @click="emit('click')"
      />
    </template>
  </EmptyStateLayout>
</template>
```

- [ ] **Step 2: `CustomToolsPageEmptyState.vue`, `DocumentPageEmptyState.vue`, `InboxPageEmptyState.vue`** — mesmo molde do Step 1, cada um com o seu prefixo de chave.

`CustomToolsPageEmptyState.vue`:

```vue
<script setup>
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['click']);
</script>

<template>
  <EmptyStateLayout
    :title="$t('CAPTAIN.CUSTOM_TOOLS.EMPTY_STATE.TITLE')"
    :subtitle="$t('CAPTAIN.CUSTOM_TOOLS.EMPTY_STATE.SUBTITLE')"
    :action-perms="['administrator']"
    :show-backdrop="false"
  >
    <template #actions>
      <Button
        :label="$t('CAPTAIN.CUSTOM_TOOLS.ADD_NEW')"
        icon="i-lucide-plus"
        @click="emit('click')"
      />
    </template>
  </EmptyStateLayout>
</template>
```

`DocumentPageEmptyState.vue`:

```vue
<script setup>
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['click']);
</script>

<template>
  <EmptyStateLayout
    :title="$t('CAPTAIN.DOCUMENTS.EMPTY_STATE.TITLE')"
    :subtitle="$t('CAPTAIN.DOCUMENTS.EMPTY_STATE.SUBTITLE')"
    :action-perms="['administrator']"
    :show-backdrop="false"
  >
    <template #actions>
      <Button
        :label="$t('CAPTAIN.DOCUMENTS.ADD_NEW')"
        icon="i-lucide-plus"
        @click="emit('click')"
      />
    </template>
  </EmptyStateLayout>
</template>
```

`InboxPageEmptyState.vue`:

```vue
<script setup>
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['click']);
</script>

<template>
  <EmptyStateLayout
    :title="$t('CAPTAIN.INBOXES.EMPTY_STATE.TITLE')"
    :subtitle="$t('CAPTAIN.INBOXES.EMPTY_STATE.SUBTITLE')"
    :action-perms="['administrator']"
    :show-backdrop="false"
  >
    <template #actions>
      <Button
        :label="$t('CAPTAIN.INBOXES.ADD_NEW')"
        icon="i-lucide-plus"
        @click="emit('click')"
      />
    </template>
  </EmptyStateLayout>
</template>
```

- [ ] **Step 3: `ResponsePageEmptyState.vue`**

```vue
<script setup>
import { computed } from 'vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  variant: {
    type: String,
    default: 'approved',
    validator: value => ['approved', 'pending'].includes(value),
  },
  hasActiveFilters: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['click', 'clearFilters']);

const isApproved = computed(() => props.variant === 'approved');
const isPending = computed(() => props.variant === 'pending');
</script>

<template>
  <EmptyStateLayout
    :title="
      isPending
        ? $t('CAPTAIN.RESPONSES.EMPTY_STATE.NO_PENDING_TITLE')
        : $t('CAPTAIN.RESPONSES.EMPTY_STATE.TITLE')
    "
    :subtitle="isApproved ? $t('CAPTAIN.RESPONSES.EMPTY_STATE.SUBTITLE') : ''"
    :action-perms="['administrator']"
    :show-backdrop="false"
  >
    <template #actions>
      <div class="flex flex-col items-center gap-3">
        <Button
          v-if="isApproved"
          :label="$t('CAPTAIN.RESPONSES.ADD_NEW')"
          icon="i-lucide-plus"
          @click="emit('click')"
        />
        <Button
          v-else-if="isPending && hasActiveFilters"
          :label="$t('CAPTAIN.RESPONSES.EMPTY_STATE.CLEAR_SEARCH')"
          variant="link"
          size="sm"
          @click="emit('clearFilters')"
        />
      </div>
    </template>
  </EmptyStateLayout>
</template>
```

- [ ] **Step 4: i18n** — em cada `EMPTY_STATE` abaixo: trocar `TITLE`/`SUBTITLE` e **apagar o sub-bloco `"FEATURE_SPOTLIGHT": { … }`** (cuidando da vírgula da linha anterior). Demais chaves (`FILTERED_*`, `NO_PENDING_TITLE`, `CLEAR_SEARCH`) ficam.

| Bloco (pt_BR / en linhas) | TITLE pt_BR | SUBTITLE pt_BR | TITLE en | SUBTITLE en |
|---|---|---|---|---|
| `ASSISTANTS.EMPTY_STATE` (577-584 / 577-584) | `Os assistentes abrem pelo seletor` | `Escolha o Atendimento ou o Copiloto do Escritório no seletor que fica no topo das telas de FAQs, Skills, Testar e Configurações.` | `Open assistants from the switcher` | `Pick an assistant in the switcher at the top of the FAQs, Skills, Test and Settings screens.` |
| `DOCUMENTS.EMPTY_STATE` (847-856 / 848-857) | `Ainda não há documentos` | `Cole o link de uma página e a Inteligência gera FAQs pendentes para você aprovar.` | `No documents yet` | `Paste a page link and Captain turns it into pending FAQs for you to approve.` |
| `CUSTOM_TOOLS.EMPTY_STATE` (862-869 / 863-870) | `Não há ferramentas personalizadas` | `Ferramentas personalizadas ligam o assistente a outros sistemas por HTTP. As ferramentas do hub (AdvBox, motor de cálculos, funil, agenda) já vêm prontas e não aparecem aqui.` | `No custom tools` | `Custom tools connect the assistant to other systems over HTTP. The hub's built-in tools (AdvBox, calculation engine, funnel, calendar) are ready and are not listed here.` |
| `RESPONSES.EMPTY_STATE` (1062-1071 / 1063-1072) | `Ainda não há FAQs` | `Clique em “Criar nova FAQ” para escrever uma, ou gere FAQs pendentes a partir de um documento.` | `No FAQs yet` | `Click “Create new FAQ” to write one, or generate pending FAQs from a document.` |
| `INBOXES.EMPTY_STATE` (1099-1102 / 1100-1103) | `Nenhuma caixa conectada` | `Conecte uma caixa para o assistente começar a escrever rascunhos de resposta nas conversas dela.` | `No connected inboxes` | `Connect an inbox so the assistant starts drafting replies in its conversations.` |

Exemplo do resultado (pt_BR, Documentos):

```json
      "EMPTY_STATE": {
        "TITLE": "Ainda não há documentos",
        "SUBTITLE": "Cole o link de uma página e a Inteligência gera FAQs pendentes para você aprovar.",
        "FILTERED_TITLE": "Nenhum documento correspondente",
        "FILTERED_SUBTITLE": "Tente alterar a origem, o status ou o termo de pesquisa."
      }
```

- [ ] **Step 5: Verificar**

Run: `npx eslint app/javascript/dashboard/components-next/captain/pageComponents/emptyStates` → sem erros.
Run: `grep -rn "chwt.app\|FeatureSpotlight\|captainEmptyStateContent\|FEATURE_SPOTLIGHT" app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/components-next/captain/pageComponents` → nada.
Run: `grep -rn "EMPTY_STATE.FEATURE_SPOTLIGHT" app/javascript/dashboard --include=*.vue --include=*.js` → nada.
Rodar a "paridade" → tudo `[]`.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/components-next/captain/pageComponents/emptyStates app/javascript/dashboard/i18n/locale/en/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/integrations.json
git commit -m "feat(inteligencia): telas vazias sem exemplos falsos da Chatwoot"
```

---

### Task 5: Nível de cada ferramenta + nomes em português (I-FE3; base do I-SK2 e I-EX1)

**Files:**
- Modify (reescrever): `config/agents/tools.yml`
- Modify: `enterprise/app/models/concerns/captain_tools_helpers.rb:14,51-56`
- Modify: `enterprise/app/views/api/v1/accounts/captain/assistants/tools.json.jbuilder`
- Modify: `app/controllers/api/v1/accounts/captain_tool_runs_controller.rb:9-12`
- Modify: `app/views/api/v1/accounts/captain_tool_runs/index.json.jbuilder`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/ferramentas.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js` (novo)
- Test: `spec/enterprise/models/concerns/captain_tools_helpers_spec.rb`, `spec/controllers/api/v1/accounts/captain_tool_runs_controller_spec.rb`
- Modify: `i18n/locale/pt_BR/ramon.json:1608`, `i18n/locale/en/ramon.json:1603` (inserir bloco `NIVEL` logo depois de `RETRY`)

**Interfaces:**
- Produces (JS): `NIVEL_TOM: { consulta, sugestao, rascunho, interna }` (classes do `TOM`); `ferramentaInfo(id: string, catalogo: Array<{id, title, nivel}>) → { id, title, nivel: string|null, tom: string }`.
- Produces (API): `GET captain/assistants/tools` → cada item ganha `nivel`; `GET captain_tool_runs` → ganha `catalogo: [{ id, title, nivel }]`.
- Produces (i18n): `CAPTAIN_RAMON.NIVEL.{consulta,sugestao,rascunho,interna}`.

- [ ] **Step 1: Teste JS que falha** — criar `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js`:

```js
import tools from '../../../../../../../../config/agents/tools.yml';
import { NIVEL_TOM, ferramentaInfo } from '../ferramentas';
import { TOM } from '../ui';

describe('ferramentas', () => {
  it('toda ferramenta do tools.yml tem um nível com cor', () => {
    tools.forEach(tool => {
      expect(Object.keys(NIVEL_TOM)).toContain(tool.nivel);
    });
  });

  it('rascunho pro cliente = pedir documentos e link do portal', () => {
    const ids = tools.filter(tool => tool.nivel === 'rascunho').map(t => t.id);
    expect(ids.sort()).toEqual(['enviar_link_portal', 'solicitar_documento']);
  });

  it('acha nome e cor no catálogo', () => {
    const catalogo = [
      { id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao' },
    ];
    expect(ferramentaInfo('mover_etapa', catalogo)).toEqual({
      id: 'mover_etapa',
      title: 'Mover de etapa',
      nivel: 'sugestao',
      tom: TOM.amber,
    });
  });

  it('fora do catálogo (HTTP personalizada ou catálogo não carregado) fica neutra com o id cru', () => {
    expect(ferramentaInfo('minha_http', [])).toEqual({
      id: 'minha_http',
      title: 'minha_http',
      nivel: null,
      tom: TOM.slate,
    });
    expect(ferramentaInfo('minha_http', null).title).toBe('minha_http');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js`
Expected: FAIL — não resolve `../ferramentas`.

- [ ] **Step 3: Helper** — criar `app/javascript/dashboard/routes/dashboard/ramon/helpers/ferramentas.js`:

```js
import { TOM } from './ui';

// Cor de cada nível de ferramenta (campo `nivel` do config/agents/tools.yml):
// azul = só consulta · âmbar = prepara Sugestão (o humano aprova) ·
// verde (teal do kit) = rascunho pro cliente · neutro = escrita interna.
// A ordem das chaves é a ordem da legenda na tela de Skills.
export const NIVEL_TOM = {
  consulta: TOM.blue,
  sugestao: TOM.amber,
  rascunho: TOM.teal,
  interna: TOM.slate,
};

// Nome legível + nível pelo id. Fora do catálogo (HTTP personalizada, id
// antigo, ou catálogo que não carregou pra quem não é admin): id cru, neutra.
export const ferramentaInfo = (id, catalogo = []) => {
  const tool = (catalogo || []).find(item => item.id === id);
  return {
    id,
    title: tool?.title || id,
    nivel: tool?.nivel || null,
    tom: NIVEL_TOM[tool?.nivel] || TOM.slate,
  };
};
```

- [ ] **Step 4: `config/agents/tools.yml`** — substituir o arquivo inteiro por:

```yaml
######  Captain Agent Tools Configuration #######
# id: Tool identifier used to resolve the class (Captain::Tools::{PascalCase(id)}Tool)
# title: nome em português mostrado na tela (Skills, Execuções)
# description: texto curto mostrado na tela
# icon: Icon name for frontend display (frontend icon system)
# nivel: o que a ferramenta faz no mundo — define a cor na tela:
#   consulta (azul)  = só lê
#   interna  (cinza) = escreve no hub, só a equipe vê (nota, etiqueta, tarefa, qualificação)
#   sugestao (âmbar) = cria Sugestão pendente que o humano aprova
#                      (classes RamonEscritaTool e AdvboxMcpEscritaTool — o spec confere)
#   rascunho (verde) = devolve texto pronto pro cliente; quem envia é o humano
#######################################################

- id: add_contact_note
  title: 'Nota no contato'
  description: 'Adiciona uma nota no perfil do contato'
  icon: 'note-add'
  nivel: interna

- id: add_private_note
  title: 'Nota interna na conversa'
  description: 'Adiciona uma nota privada na conversa (só a equipe vê)'
  icon: 'eye-off'
  nivel: interna

- id: update_priority
  title: 'Mudar prioridade'
  description: 'Muda a prioridade da conversa'
  icon: 'exclamation-triangle'
  nivel: interna

- id: add_label_to_conversation
  title: 'Etiquetar conversa'
  description: 'Adiciona uma etiqueta na conversa'
  icon: 'tag'
  nivel: interna

- id: faq_lookup
  title: 'Buscar nas FAQs'
  description: 'Busca textual nas FAQs aprovadas'
  icon: 'search'
  nivel: consulta

- id: handoff
  title: 'Passar para um humano'
  description: 'Transfere a conversa para uma pessoa da equipe'
  icon: 'user-switch'
  nivel: interna

- id: buscar_processo_advbox
  title: 'Buscar processo no AdvBox'
  description: 'Busca processos no AdvBox por nome do cliente ou CPF'
  icon: 'search'
  nivel: consulta

- id: consultar_dossie_advbox
  title: 'Consultar dossiê no AdvBox'
  description: 'Dossiê completo de um processo do AdvBox numa chamada só'
  icon: 'document'
  nivel: consulta

- id: calcular_beneficio
  title: 'Calcular benefício no motor'
  description: 'Calcula renda mensal e atrasados estimados do caso no motor de cálculos'
  icon: 'calculator'
  nivel: consulta

- id: checar_prescricao
  title: 'Checar prescrição'
  description: 'Prescrição quinquenal do caso: parcelas já perdidas e meses até o corte'
  icon: 'clock'
  nivel: consulta

- id: linha_da_vida
  title: 'Linha da vida da pessoa'
  description: 'Todos os casos da pessoa no hub e os marcos etários que ainda vencem'
  icon: 'timeline'
  nivel: consulta

- id: documentacao_faltante
  title: 'O que falta no caso'
  description: 'Documentos pendentes, lacunas da colheita e tarefas em aberto do caso'
  icon: 'clipboard'
  nivel: consulta

- id: preparar_contrato_zapsign
  title: 'Preparar contrato no ZapSign'
  description: 'Sugere gerar contrato + procuração no ZapSign (o humano aprova antes)'
  icon: 'signature'
  nivel: sugestao

- id: preparar_caso_advbox
  title: 'Abrir caso no AdvBox'
  description: 'Sugere abrir cliente, caso e primeira tarefa no AdvBox (o humano aprova antes)'
  icon: 'briefcase'
  nivel: sugestao

- id: agendar_reuniao
  title: 'Agendar reunião'
  description: 'Sugere data da reunião de fechamento; aprovada, vira tarefa na Esteira'
  icon: 'calendar'
  nivel: sugestao

- id: mover_etapa
  title: 'Mover de etapa'
  description: 'Sugere mover o caso para outra etapa do funil (o humano aprova antes)'
  icon: 'columns'
  nivel: sugestao

- id: playbook_da_tese
  title: 'Playbook da tese'
  description: 'Critérios, objeções, apresentação, documentos e honorário de uma tese'
  icon: 'clipboard'
  nivel: consulta

- id: simular_honorario
  title: 'Simular honorário'
  description: 'Honorário estimado pela regra da tese sobre atrasados e mensal'
  icon: 'calculator'
  nivel: consulta

- id: historico_do_contato
  title: 'Histórico do contato'
  description: 'Casos, conversas e notas anteriores da pessoa no hub'
  icon: 'timeline'
  nivel: consulta

- id: triagem_da_lp
  title: 'Triagem da LP'
  description: 'Quiz que o lead respondeu na landing page antes de chamar: veredito, respostas e dúvidas'
  icon: 'clipboard'
  nivel: consulta

- id: link_agendamento
  title: 'Link de agendamento'
  description: 'Link para o lead escolher dia e horário da conversa'
  icon: 'calendar'
  nivel: consulta

- id: agenda_do_escritorio
  title: 'Agenda do escritório'
  description: 'Reuniões, tarefas do hub (do dia e atrasadas) e prazos do AdvBox no dia'
  icon: 'calendar'
  nivel: consulta

- id: funil_hoje
  title: 'Funil de hoje'
  description: 'Meta do dia, conversão por etapa com gargalo, SLA e perdas por tese'
  icon: 'columns'
  nivel: consulta

- id: publicacoes_advbox
  title: 'Publicações do processo no AdvBox'
  description: 'Últimas publicações de um processo do AdvBox (data e trecho)'
  icon: 'document'
  nivel: consulta

- id: registrar_qualificacao
  title: 'Registrar qualificação'
  description: 'Marca no caso se um critério de qualificação da tese foi confirmado ou não atendido'
  icon: 'checkmark-circle'
  nivel: interna

- id: criar_tarefa_esteira
  title: 'Criar tarefa de cadência'
  description: 'Cria um lembrete interno na Esteira do caso (cobrar, retomar, ligar) com data e hora'
  icon: 'calendar-clock'
  nivel: interna

- id: solicitar_documento
  title: 'Pedir documentos'
  description: 'Texto pronto pedindo ao cliente os documentos pendentes do caso'
  icon: 'document-add'
  nivel: rascunho

- id: enviar_link_portal
  title: 'Link do portal do cliente'
  description: 'Link seguro para o cliente enviar documentos pelo celular, com frase pronta'
  icon: 'link'
  nivel: rascunho

- id: marcar_perdido
  title: 'Marcar como perdido'
  description: 'Sugere marcar o caso como perdido com o motivo — o humano aprova no Cockpit'
  icon: 'dismiss-circle'
  nivel: sugestao

- id: processo_advbox
  title: 'Dados do processo no AdvBox'
  description: 'Etapa, responsável, clientes e honorários de um processo, sem o dossiê inteiro'
  icon: 'document'
  nivel: consulta

- id: movimentacoes_advbox
  title: 'Movimentações do processo no AdvBox'
  description: 'Andamentos de um processo, mais recentes primeiro'
  icon: 'timeline'
  nivel: consulta

- id: historico_tarefas_advbox
  title: 'Histórico de tarefas no AdvBox'
  description: 'Tarefas já realizadas num processo'
  icon: 'clipboard'
  nivel: consulta

- id: ultimas_movimentacoes_advbox
  title: 'Radar de movimentações no AdvBox'
  description: 'Última movimentação de cada processo do escritório'
  icon: 'timeline'
  nivel: consulta

- id: tarefas_advbox
  title: 'Tarefas e prazos no AdvBox'
  description: 'Tarefas do escritório por período, responsável ou processo'
  icon: 'calendar'
  nivel: consulta

- id: buscar_cliente_advbox
  title: 'Buscar cliente no AdvBox'
  description: 'Contatos/clientes por nome, CPF, telefone ou cidade'
  icon: 'search'
  nivel: consulta

- id: cliente_advbox
  title: 'Ficha do cliente no AdvBox'
  description: 'Ficha completa de um cliente pelo id do AdvBox'
  icon: 'document'
  nivel: consulta

- id: documentos_advbox
  title: 'Documentos no AdvBox'
  description: 'Arquivos anexados, por nome, cliente, tarefa ou transação'
  icon: 'document'
  nivel: consulta

- id: link_documento_advbox
  title: 'Link de documento do AdvBox'
  description: 'Link temporário de download de um documento'
  icon: 'link'
  nivel: consulta

- id: configuracoes_advbox
  title: 'Configurações do AdvBox'
  description: 'IDs de usuários, tipos de tarefa, origens e etapas — base para escrever no AdvBox'
  icon: 'settings'
  nivel: consulta

- id: criar_tarefa_advbox
  title: 'Criar tarefa no AdvBox'
  description: 'Cria tarefa num processo do AdvBox — prévia + código, grava só depois do ok do humano'
  icon: 'calendar-clock'
  nivel: sugestao

- id: criar_movimentacao_advbox
  title: 'Registrar movimentação no AdvBox'
  description: 'Andamento manual num processo — prévia + código, grava só depois do ok do humano'
  icon: 'timeline'
  nivel: sugestao

- id: criar_cliente_advbox
  title: 'Criar cliente no AdvBox'
  description: 'Contato/cliente novo no AdvBox — prévia + código, grava só depois do ok do humano'
  icon: 'person-add'
  nivel: sugestao
```

(Os `title`/`description` do yml só aparecem na tela — o LLM lê o `description` declarado em cada classe `enterprise/lib/captain/tools/*_tool.rb`, que não muda. Ids, ordem e ícones iguais aos de antes.)

- [ ] **Step 5: Rodar e ver passar**

Run: `npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js`
Expected: PASS (4 testes).

- [ ] **Step 6: Specs Ruby (validados no CI)** — em `spec/enterprise/models/concerns/captain_tools_helpers_spec.rb`, antes do `end` final (linha 106), acrescentar:

```ruby
  describe 'nivel das ferramentas (config/agents/tools.yml)' do
    let(:ferramentas) { Captain::Assistant.built_in_agent_tools }

    def ids_do_nivel(nivel)
      ferramentas.select { |tool| tool[:nivel] == nivel }.pluck(:id)
    end

    it 'toda ferramenta tem um dos quatro niveis' do
      expect(ferramentas.pluck(:nivel).uniq).to match_array(%w[consulta interna sugestao rascunho])
    end

    it 'sugestao = exatamente as ferramentas que herdam das bases de escrita com aprovacao' do
      herdeiras = ferramentas.pluck(:id).select do |id|
        klass = Captain::Assistant.resolve_tool_class(id)
        klass < Captain::Tools::RamonEscritaTool || klass < Captain::Tools::AdvboxMcpEscritaTool
      end

      expect(ids_do_nivel('sugestao')).to match_array(herdeiras)
    end

    it 'rascunho pro cliente = pedir documentos e link do portal' do
      expect(ids_do_nivel('rascunho')).to match_array(%w[solicitar_documento enviar_link_portal])
    end
  end
```

Em `spec/controllers/api/v1/accounts/captain_tool_runs_controller_spec.rb`, depois do teste "nao vaza execucao de outra conta" (linha 42), acrescentar:

```ruby
  it 'devolve o catalogo com nome e nivel de cada ferramenta' do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['catalogo']).to include({ 'id' => 'mover_etapa', 'title' => 'Mover de etapa', 'nivel' => 'sugestao' })
  end
```

- [ ] **Step 7: Backend** — em `enterprise/app/models/concerns/captain_tools_helpers.rb`:
  - linha 14: `# @return [Array<Hash>] Array of tool hashes with :id, :title, :description, :icon` → `# @return [Array<Hash>] Array of tool hashes with :id, :title, :description, :icon, :nivel`
  - linhas 51-56, o hash passa a ser:

```ruby
          {
            id: tool_config['id'],
            title: tool_config['title'],
            description: tool_config['description'],
            icon: tool_config['icon'],
            nivel: tool_config['nivel']
          }
```

`enterprise/app/views/api/v1/accounts/captain/assistants/tools.json.jbuilder` inteiro:

```ruby
json.array! @tools do |tool|
  json.id tool[:id]
  json.title tool[:title]
  json.description tool[:description]
  json.icon tool[:icon]
  json.nivel tool[:nivel]
end
```

`app/controllers/api/v1/accounts/captain_tool_runs_controller.rb`, `index` (linhas 9-12):

```ruby
  def index
    @tool_runs = escopo.recentes.limit(LIST_LIMIT)
    @resumo = resumo
    # nome e nivel de cada ferramenta pra tela: o endpoint de ferramentas e so admin
    @catalogo = Captain::Assistant.built_in_agent_tools
  end
```

`app/views/api/v1/accounts/captain_tool_runs/index.json.jbuilder` — acrescentar no fim:

```ruby

json.catalogo @catalogo do |tool|
  json.id tool[:id]
  json.title tool[:title]
  json.nivel tool[:nivel]
end
```

- [ ] **Step 8: i18n `CAPTAIN_RAMON.NIVEL`** — inserir logo depois da linha `"RETRY": …` (pt_BR `ramon.json:1608`, en `ramon.json:1603`):

pt_BR:
```json
    "NIVEL": {
      "consulta": "Consulta",
      "sugestao": "Prepara sugestão",
      "rascunho": "Rascunho pro cliente",
      "interna": "Escrita interna"
    },
```

en:
```json
    "NIVEL": {
      "consulta": "Lookup",
      "sugestao": "Prepares a suggestion",
      "rascunho": "Client draft",
      "interna": "Internal write"
    },
```

- [ ] **Step 9: Verificar**

Run: `npx eslint app/javascript/dashboard/routes/dashboard/ramon/helpers/ferramentas.js app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js` → sem erros.
Rodar a "paridade" → tudo `[]`.
Ruby: sem Ruby local — o CI roda `captain_tools_helpers_spec.rb`, `captain_tool_runs_controller_spec.rb` e rubocop.

- [ ] **Step 10: Commit**

```bash
git add config/agents/tools.yml enterprise/app/models/concerns/captain_tools_helpers.rb enterprise/app/views/api/v1/accounts/captain/assistants/tools.json.jbuilder app/controllers/api/v1/accounts/captain_tool_runs_controller.rb app/views/api/v1/accounts/captain_tool_runs/index.json.jbuilder app/javascript/dashboard/routes/dashboard/ramon/helpers/ferramentas.js app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js spec/enterprise/models/concerns/captain_tools_helpers_spec.rb spec/controllers/api/v1/accounts/captain_tool_runs_controller_spec.rb app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(inteligencia): ferramentas com nome em português e nível (consulta, sugestão, rascunho, interna)"
```

---

### Task 6: Skills — "Skill" em tudo, campos de advogado, ferramentas com nome e cor (I-SK1, I-SK2)

**Files:**
- Modify: `app/javascript/dashboard/components-next/captain/assistant/ScenariosCard.vue:1-15,49-50,195-201`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/Index.vue:13-18,200-203`
- Test: `app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js` (novo)
- Modify: `i18n/locale/{pt_BR,en}/integrations.json:675-738` (bloco `SCENARIOS`)

**Interfaces:**
- Consumes: `ferramentaInfo`, `NIVEL_TOM` (`ramon/helpers/ferramentas.js`), `CHIP` (`ui.js`), getter `captainTools/getRecords` (itens `{ id, title, nivel }`, preenchido pelo `store.dispatch('captainTools/getTools')` que a página já faz em `scenarios/Index.vue:188`), i18n `CAPTAIN_RAMON.NIVEL.*`.

- [ ] **Step 1: Teste que falha** — criar `app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js`:

```js
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ScenariosCard from '../ScenariosCard.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const montar = tools => {
  const store = createStore({
    modules: {
      captainTools: {
        namespaced: true,
        getters: {
          getRecords: () => [
            { id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao' },
          ],
        },
      },
    },
  });
  return mount(ScenariosCard, {
    props: {
      id: 1,
      title: 'Lead aceitou a reunião',
      description: 'Quando o lead topa conversar',
      instruction: 'Conduza a conversa',
      tools,
    },
    global: {
      plugins: [store],
      stubs: {
        CardLayout: { template: '<div><slot /></div>' },
        Checkbox: true,
        Button: true,
        Icon: true,
        Editor: true,
        Input: true,
        TextArea: true,
      },
    },
  });
};

describe('ScenariosCard — ferramentas da skill', () => {
  it('mostra o nome legível com a cor do nível, e o id cru quando não está no catálogo', () => {
    const chips = montar(['mover_etapa', 'minha_http']).findAll(
      '[data-testid="skill-ferramenta"]'
    );
    expect(chips.map(chip => chip.text())).toEqual([
      'Mover de etapa',
      'minha_http',
    ]);
    expect(chips[0].classes()).toContain('text-n-amber-11');
    expect(chips[1].classes()).toContain('text-n-slate-11');
  });

  it('skill sem ferramentas (tools null da API) não mostra a linha', () => {
    expect(montar(null).text()).not.toContain(
      'CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.TOOLS_USED'
    );
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js`
Expected: FAIL — nenhum `[data-testid="skill-ferramenta"]` (o card ainda imprime `@mover_etapa, @minha_http`).

- [ ] **Step 3: `ScenariosCard.vue`** — imports (depois da linha 14, `import Icon …`):

```js
import { useMapGetter } from 'dashboard/composables/store';
import { CHIP } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { ferramentaInfo } from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';
```

Depois de `const { formatMessage } = useMessageFormatter();` (linha 50):

```js
// Catálogo vem de captainTools/getTools (a página de Skills busca no onMounted).
// tools chega null quando a instrução não cita ferramenta.
const catalogo = useMapGetter('captainTools/getRecords');
const ferramentas = computed(() =>
  (props.tools || []).map(id => ferramentaInfo(id, catalogo.value))
);
```

Trocar o bloco das linhas 195-201

```vue
      <span
        v-if="tools?.length"
        class="text-sm text-n-slate-11 font-medium mb-1"
      >
        {{ t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.TOOLS_USED') }}
        {{ tools?.map(tool => `@${tool}`).join(', ') }}
      </span>
```

por

```vue
      <div
        v-if="ferramentas.length"
        class="flex flex-wrap items-center gap-1.5 mb-1"
      >
        <span class="text-sm text-n-slate-11 font-medium">
          {{ t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.TOOLS_USED') }}
        </span>
        <span
          v-for="ferramenta in ferramentas"
          :key="ferramenta.id"
          data-testid="skill-ferramenta"
          :class="[CHIP, ferramenta.tom]"
          :title="
            ferramenta.nivel ? t(`CAPTAIN_RAMON.NIVEL.${ferramenta.nivel}`) : ''
          "
        >
          {{ ferramenta.title }}
        </span>
      </div>
```

- [ ] **Step 4: Legenda das cores em `scenarios/Index.vue`** — imports (depois da linha 18, `import AddNewScenariosDialog …`):

```js
import { CHIP } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { NIVEL_TOM } from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';
```

Logo depois do `<SettingsHeader … />` (linhas 200-203), acrescentar:

```vue
      <div class="flex flex-wrap items-center gap-1.5 mt-3">
        <span
          v-for="(tom, nivel) in NIVEL_TOM"
          :key="nivel"
          :class="[CHIP, tom]"
        >
          {{ t(`CAPTAIN_RAMON.NIVEL.${nivel}`) }}
        </span>
      </div>
```

- [ ] **Step 5: i18n — bloco `SCENARIOS`** (linhas 675-738 nos dois arquivos) inteiro por:

pt_BR:
```json
      "SCENARIOS": {
        "TITLE": "Skills",
        "DESCRIPTION": "Situações que o assistente sabe conduzir: quando usar cada skill, como conduzir e quais ferramentas ela usa.",
        "BULK_ACTION": {
          "SELECTED": "{count} item selecionado | {count} itens selecionados",
          "SELECT_ALL": "Selecionar todos ({count})",
          "UNSELECT_ALL": "Desmarcar todos ({count})",
          "BULK_DELETE_BUTTON": "Excluir"
        },
        "ADD": {
          "SUGGESTED": {
            "TITLE": "Exemplos de skills",
            "ADD": "Adicionar todos",
            "ADD_SINGLE": "Adicionar este",
            "TOOLS_USED": "Ferramentas usadas:"
          },
          "NEW": {
            "CREATE": "Adicionar uma skill",
            "TITLE": "Criar uma skill",
            "FORM": {
              "TITLE": {
                "LABEL": "Nome da skill",
                "PLACEHOLDER": "Ex.: Lead que sumiu depois da reunião",
                "ERROR": "O nome da skill é obrigatório"
              },
              "DESCRIPTION": {
                "LABEL": "Quando usar",
                "PLACEHOLDER": "Em que situação o assistente deve seguir esta skill",
                "ERROR": "Diga quando usar esta skill"
              },
              "INSTRUCTION": {
                "LABEL": "Como conduzir",
                "PLACEHOLDER": "Passo a passo do que o assistente faz — digite @ para chamar uma ferramenta",
                "ERROR": "Escreva como conduzir esta skill"
              },
              "CREATE": "Criar",
              "CANCEL": "Cancelar"
            }
          }
        },
        "UPDATE": {
          "CANCEL": "Cancelar",
          "UPDATE": "Salvar alterações"
        },
        "LIST": {
          "SEARCH_PLACEHOLDER": "Pesquisar..."
        },
        "EMPTY_MESSAGE": "Nenhuma skill ainda. Crie uma para começar.",
        "SEARCH_EMPTY_MESSAGE": "Nenhuma skill encontrada para esta pesquisa.",
        "API": {
          "ADD": {
            "SUCCESS": "Skills adicionadas com sucesso",
            "ERROR": "Ocorreu um erro ao adicionar skills, por favor tente novamente."
          },
          "UPDATE": {
            "SUCCESS": "Skill atualizada com sucesso",
            "ERROR": "Ocorreu um erro ao atualizar a skill, por favor tente novamente."
          },
          "DELETE": {
            "SUCCESS": "Skills excluídas com sucesso",
            "ERROR": "Ocorreu um erro ao excluir as skills, por favor tente novamente."
          }
        }
      }
```

en:
```json
      "SCENARIOS": {
        "TITLE": "Skills",
        "DESCRIPTION": "Situations the assistant knows how to handle: when to use each skill, how to handle it and which tools it uses.",
        "BULK_ACTION": {
          "SELECTED": "{count} item selected | {count} items selected",
          "SELECT_ALL": "Select all ({count})",
          "UNSELECT_ALL": "Unselect all ({count})",
          "BULK_DELETE_BUTTON": "Delete"
        },
        "ADD": {
          "SUGGESTED": {
            "TITLE": "Example skills",
            "ADD": "Add all",
            "ADD_SINGLE": "Add this",
            "TOOLS_USED": "Tools used:"
          },
          "NEW": {
            "CREATE": "Add a skill",
            "TITLE": "Create a skill",
            "FORM": {
              "TITLE": {
                "LABEL": "Skill name",
                "PLACEHOLDER": "E.g. Lead went silent after the meeting",
                "ERROR": "Skill name is required"
              },
              "DESCRIPTION": {
                "LABEL": "When to use",
                "PLACEHOLDER": "In which situation the assistant should follow this skill",
                "ERROR": "Say when to use this skill"
              },
              "INSTRUCTION": {
                "LABEL": "How to handle",
                "PLACEHOLDER": "Step by step of what the assistant does — type @ to call a tool",
                "ERROR": "Write how to handle this skill"
              },
              "CREATE": "Create",
              "CANCEL": "Cancel"
            }
          }
        },
        "UPDATE": {
          "CANCEL": "Cancel",
          "UPDATE": "Save changes"
        },
        "LIST": {
          "SEARCH_PLACEHOLDER": "Search..."
        },
        "EMPTY_MESSAGE": "No skills yet. Create one to begin.",
        "SEARCH_EMPTY_MESSAGE": "No skills found for this search.",
        "API": {
          "ADD": {
            "SUCCESS": "Skills added successfully",
            "ERROR": "There was an error adding skills, please try again."
          },
          "UPDATE": {
            "SUCCESS": "Skill updated successfully",
            "ERROR": "There was an error updating the skill, please try again."
          },
          "DELETE": {
            "SUCCESS": "Skills deleted successfully",
            "ERROR": "There was an error deleting skills, please try again."
          }
        }
      }
```

- [ ] **Step 6: Rodar e ver passar**

Run: `npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js` → PASS (2 testes).
Run: `npx eslint app/javascript/dashboard/components-next/captain/assistant/ScenariosCard.vue app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/Index.vue` → sem erros.
Run: `grep -n -i "cenário\|cenario" app/javascript/dashboard/i18n/locale/pt_BR/*.json` → só a linha 554 ("Coisas Divertidas", sai na Task 8). Rodar a "paridade" → tudo `[]`.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/dashboard/components-next/captain/assistant/ScenariosCard.vue app/javascript/dashboard/components-next/captain/assistant/specs/ScenariosCard.spec.js app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/Index.vue app/javascript/dashboard/i18n/locale/en/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/integrations.json
git commit -m "feat(inteligencia): Skills sem 'Cenário', com ferramentas por nome e cor do nível"
```

---

### Task 7: Execuções — nome legível + chip do nível (I-EX1)

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue:4-6,36-38,130-132,180-182`
- Modify: `i18n/locale/pt_BR/ramon.json:1611,1614,1615`

**Interfaces:**
- Consumes: `catalogo` da resposta de `captain_tool_runs` (Task 5), `ferramentaInfo`, `CHIP`, `CAPTAIN_RAMON.NIVEL.*`.

- [ ] **Step 1: Script** — depois de `import CaptainToolRunsAPI from 'dashboard/api/captainToolRuns';` (linha 6):

```js
import { CHIP } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { ferramentaInfo } from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';
```

Depois de `const tools = computed(() => resumo.value.tools ?? []);` (linha 38):

```js
const catalogo = computed(() => data.value?.catalogo ?? []);
const ferramenta = id => ferramentaInfo(id, catalogo.value);
```

- [ ] **Step 2: Filtro** — linhas 130-132 viram:

```vue
            <option v-for="tool in tools" :key="tool" :value="tool">
              {{ ferramenta(tool).title }}
            </option>
```

- [ ] **Step 3: Linha da execução** — linhas 180-182

```vue
              <span class="text-sm font-medium text-n-slate-12">
                {{ run.tool_name }}
              </span>
```

viram

```vue
              <span class="text-sm font-medium text-n-slate-12">
                {{ ferramenta(run.tool_name).title }}
              </span>
              <span
                v-if="ferramenta(run.tool_name).nivel"
                data-testid="execucoes-nivel"
                :class="[CHIP, ferramenta(run.tool_name).tom]"
              >
                {{ t(`CAPTAIN_RAMON.NIVEL.${ferramenta(run.tool_name).nivel}`) }}
              </span>
```

- [ ] **Step 4: Textos pt_BR (`ramon.json`)**

| Linha | Chave | Novo valor |
|---|---|---|
| 1611 | `CAPTAIN_RAMON.EXECUCOES.SUBTITLE` | `"Tudo que o agente executou: qual ferramenta, com quais dados e o que voltou."` |
| 1614 | `CAPTAIN_RAMON.EXECUCOES.TOOLS_USADAS` | `"Ferramentas usadas"` |
| 1615 | `CAPTAIN_RAMON.EXECUCOES.ALL_TOOLS` | `"Todas as ferramentas"` |

(en já diz "tool(s)" em inglês — fica.)

- [ ] **Step 5: Verificar**

Run: `npx eslint --fix app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue && npx eslint app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue` → sem erros.
Run: `npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/ferramentas.spec.js` → PASS (o fallback do id cru é o que a tela usa).
Rodar a "paridade" → tudo `[]`.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/pages/Execucoes.vue app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(inteligencia): Execuções com nome da ferramenta e chip do nível"
```

---

### Task 8: FAQs e Configurações — textos certos e exemplos da banca (I-FQ3, I-CF1, I-CF2)

**Files:**
- Modify: `i18n/locale/pt_BR/integrations.json:538-539,546,550,553-554,558,562,587,632,992,1008,1026,1046`
- Modify: `i18n/locale/en/integrations.json:546,550,553-554,558,562,587,632`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/guardrails/Index.vue:51-67`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/guidelines/Index.vue:53-69`

**Interfaces:** nenhuma.

- [ ] **Step 1: FAQs (I-FQ3) — só pt_BR** (en já está certo)

| Linha | Chave | Novo valor |
|---|---|---|
| 992 | `CAPTAIN.RESPONSES.DOCUMENTABLE.CONVERSATION` | `"Conversa #{id}"` |
| 1008 | `CAPTAIN.RESPONSES.BULK_DELETE.SUCCESS_MESSAGE` | `"Perguntas Frequentes excluídas com sucesso"` |
| 1026 | `CAPTAIN.RESPONSES.STATUS.APPROVED` | `"Aprovadas"` |
| 1046 | `CAPTAIN.RESPONSES.FORM.ANSWER.LABEL` | `"Resposta"` |

- [ ] **Step 2: Configurações (I-CF1)**

| Linha (pt_BR = en) | Chave | pt_BR | en |
|---|---|---|---|
| 538 | `CAPTAIN.ASSISTANTS.EDIT.SUCCESS_MESSAGE` | `O assistente foi atualizado com sucesso` | (fica) |
| 539 | `CAPTAIN.ASSISTANTS.EDIT.ERROR_MESSAGE` | `Ocorreu um erro ao atualizar o assistente, por favor tente novamente.` | (fica) |
| 546 | `…SETTINGS.BASIC_SETTINGS.DESCRIPTION` | `Nome, descrição e o que o assistente pode usar nas respostas.` | `Name, description and what the assistant can use in its replies.` |
| 550 | `…SETTINGS.SYSTEM_SETTINGS.DESCRIPTION` | `Instruções gerais, mensagens de transferência e de encerramento e a temperatura das respostas.` | `General instructions, handoff and resolution messages and reply temperature.` |
| 553 | `…SETTINGS.CONTROL_ITEMS.TITLE` | `Regras do assistente` | `Assistant rules` |
| 554 | `…SETTINGS.CONTROL_ITEMS.DESCRIPTION` | `O que o assistente nunca pode fazer (Proteções) e como ele deve escrever (Diretrizes de resposta). Vale para todas as respostas.` | `What the assistant must never do (Guardrails) and how it should write (Response guidelines). Applies to every reply.` |
| 558 e 587 | `…CONTROL_ITEMS.OPTIONS.GUARDRAILS.DESCRIPTION` e `…ASSISTANTS.GUARDRAILS.DESCRIPTION` | `O que o assistente nunca pode fazer ou dizer — por exemplo, prometer resultado ou prazo do INSS.` | `What the assistant must never do or say — for example, promise an outcome or an INSS deadline.` |
| 562 e 632 | `…CONTROL_ITEMS.OPTIONS.RESPONSE_GUIDELINES.DESCRIPTION` e `…ASSISTANTS.RESPONSE_GUIDELINES.DESCRIPTION` | `Como o assistente escreve: tom, tamanho das mensagens e o que dizer em cada assunto.` | `How the assistant writes: tone, message length and what to say on each topic.` |

- [ ] **Step 3: Exemplos de Proteções (I-CF2)** — `guardrails/Index.vue`, o array `guardrailsExample` (linhas 51-67) vira:

```js
// Exemplos da banca (só entram no assistente se alguém clicar "Adicionar").
const guardrailsExample = [
  {
    id: 1,
    content:
      'Nunca prometer resultado nem prazo do INSS ou da Justiça — nem "o caso está ganho", nem "sai em tantos dias".',
  },
  {
    id: 2,
    content:
      'Seguir o Provimento 205/2021 da OAB: sem captação de cliente, sem comparar com outros escritórios e sem promoção de preço.',
  },
  {
    id: 3,
    content:
      'Conteúdo jurídico, valores e prazos só saem como rascunho para a equipe revisar; no modo piloto limitado, só logística (horário, endereço, lista de documentos) sai sozinha.',
  },
];
```

- [ ] **Step 4: Exemplos de Diretrizes (I-CF2)** — `guidelines/Index.vue`, o array `guidelinesExample` (linhas 53-69) vira:

```js
// Exemplos da banca (só entram no assistente se alguém clicar "Adicionar").
const guidelinesExample = [
  {
    id: 1,
    content:
      'Honorário é sempre o padrão da banca, em todas as teses: 30% dos atrasados + 3 benefícios, sem valor inicial e sem outra cobrança. Exceção, só com o advogado.',
  },
  {
    id: 2,
    content:
      'Escrever como um médico de confiança: acolhedor, simples, sem juridiquês, tratando a pessoa por "você".',
  },
  {
    id: 3,
    content:
      'Mensagens curtas, no ritmo do WhatsApp: uma ideia por mensagem e uma pergunta por vez.',
  },
];
```

(Nenhum exemplo fala em "recusar diagnóstico jurídico".)

- [ ] **Step 5: Verificar**

Run: `npx eslint app/javascript/dashboard/routes/dashboard/captain/assistants/guardrails/Index.vue app/javascript/dashboard/routes/dashboard/captain/assistants/guidelines/Index.vue` → sem erros.
Run: `grep -rn -i "coisas divertidas\|fun stuff\|diagnos\|cenário\|Conversação\|com sucesso/" app/javascript/dashboard/i18n/locale/pt_BR/integrations.json app/javascript/dashboard/i18n/locale/en/integrations.json app/javascript/dashboard/routes/dashboard/captain` → nada.
Rodar a "paridade" → tudo `[]`.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/i18n/locale/en/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/integrations.json app/javascript/dashboard/routes/dashboard/captain/assistants/guardrails/Index.vue app/javascript/dashboard/routes/dashboard/captain/assistants/guidelines/Index.vue
git commit -m "feat(inteligencia): Configurações sem 'Coisas Divertidas', exemplos da banca e textos das FAQs"
```

---

### Task 9: Documentos — sem PDF e dizendo o que o documento faz (I-DO2, I-DO3)

**Files:**
- Modify (reescrever): `app/javascript/dashboard/components-next/captain/pageComponents/document/DocumentForm.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/documents/Index.vue:5,12-26,42` e template (âncora `<template #search>`)
- Modify: `i18n/locale/{pt_BR,en}/integrations.json:742,804,810-833`

**Interfaces:**
- Produces (i18n): `CAPTAIN.DOCUMENTS.AVISO_FAQS`, `CAPTAIN.DOCUMENTS.VER_FAQS_GERADAS`. Apaga `CAPTAIN.DOCUMENTS.FORM.TYPE.*` e `CAPTAIN.DOCUMENTS.FORM.PDF_FILE.*`.

- [ ] **Step 1: `DocumentForm.vue`** — arquivo inteiro:

```vue
<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, url } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  assistantId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();
const uiFlags = useMapGetter('captainDocuments/getUIFlags');

// ponytail: só URL. O PDF ia para a OpenAI (pdf_processing_service) e aqui só
// há DeepSeek; "Colar texto" entra no I-DO1.
const state = reactive({ name: '', url: '' });
const v$ = useVuelidate({ url: { required, url } }, state);

const isLoading = computed(() => uiFlags.value.creatingItem);
const urlError = computed(() =>
  v$.value.url.$error ? t('CAPTAIN.DOCUMENTS.FORM.URL.ERROR') : ''
);

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  const formData = new FormData();
  formData.append('document[assistant_id]', props.assistantId);
  formData.append('document[external_link]', state.url);
  formData.append('document[name]', state.name || state.url);
  emit('submit', formData);
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <Input
      v-model="state.url"
      :label="t('CAPTAIN.DOCUMENTS.FORM.URL.LABEL')"
      :placeholder="t('CAPTAIN.DOCUMENTS.FORM.URL.PLACEHOLDER')"
      :message="urlError"
      :message-type="urlError ? 'error' : 'info'"
    />

    <Input
      v-model="state.name"
      :label="t('CAPTAIN.DOCUMENTS.FORM.NAME.LABEL')"
      :placeholder="t('CAPTAIN.DOCUMENTS.FORM.NAME.PLACEHOLDER')"
    />

    <div class="flex gap-3 justify-between items-center w-full">
      <Button
        type="button"
        variant="faded"
        color="slate"
        :label="t('CAPTAIN.FORM.CANCEL')"
        class="w-full bg-n-alpha-2 text-n-blue-11 hover:bg-n-alpha-3"
        @click="emit('cancel')"
      />
      <Button
        type="submit"
        :label="t('CAPTAIN.FORM.CREATE')"
        class="w-full"
        :is-loading="isLoading"
        :disabled="isLoading"
      />
    </div>
  </form>
</template>
```

- [ ] **Step 2: Aviso D4 + atalho na página** — em `documents/Index.vue`:
  - linha 5: `import { useRoute } from 'vue-router';` → `import { useRoute, useRouter } from 'vue-router';`
  - junto dos imports de componentes (bloco 12-26), acrescentar:

```js
import Button from 'dashboard/components-next/button/Button.vue';
import { AVISO, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
```

  - depois de `const selectedAssistantId = computed(() => Number(route.params.assistantId));` (linha 42):

```js
const router = useRouter();
const verFaqsGeradas = () =>
  router.push({
    name: 'captain_assistants_responses_pending',
    params: {
      accountId: route.params.accountId,
      assistantId: selectedAssistantId.value,
    },
  });
```

  - no template, logo antes de `    <template #search>` (o slot `controls` aparece com lista e com tela vazia):

```vue
    <template #controls>
      <div
        class="mb-4 flex flex-wrap items-center justify-between gap-2"
        :class="[AVISO, TOM.blue]"
      >
        <span>{{ $t('CAPTAIN.DOCUMENTS.AVISO_FAQS') }}</span>
        <Button
          :label="$t('CAPTAIN.DOCUMENTS.VER_FAQS_GERADAS')"
          link
          sm
          @click="verFaqsGeradas"
        />
      </div>
    </template>

```

- [ ] **Step 3: i18n**
  - Depois de `"ADD_NEW": …` do bloco `DOCUMENTS` (linha 742 nos dois), inserir:
    - pt_BR: `"AVISO_FAQS": "O documento não é lido pelo assistente: ele vira FAQs pendentes, e só vale o que você aprovar.",` e `"VER_FAQS_GERADAS": "Ver FAQs geradas",`
    - en: `"AVISO_FAQS": "The assistant does not read documents: each one becomes pending FAQs, and only what you approve is used.",` e `"VER_FAQS_GERADAS": "See generated FAQs",`
  - `DOCUMENTS.FORM_DESCRIPTION` (linha 804 nos dois):
    - pt_BR: `"Cole o link de uma página. A Inteligência lê a página e gera FAQs pendentes; o assistente só usa o que você aprovar."`
    - en: `"Paste a page link. Captain reads the page and generates pending FAQs; the assistant only uses what you approve."`
  - Bloco `DOCUMENTS.FORM` (linhas 810-833 nos dois) inteiro por:

pt_BR:
```json
      "FORM": {
        "URL": {
          "LABEL": "Link da página",
          "PLACEHOLDER": "Cole o link da página (https://...)",
          "ERROR": "Por favor forneça uma URL válida para o documento"
        },
        "NAME": {
          "LABEL": "Nome do documento (opcional)",
          "PLACEHOLDER": "Insira um nome para o documento"
        }
      },
```

en:
```json
      "FORM": {
        "URL": {
          "LABEL": "Page link",
          "PLACEHOLDER": "Paste the page link (https://...)",
          "ERROR": "Please provide a valid URL for the document"
        },
        "NAME": {
          "LABEL": "Document Name (Optional)",
          "PLACEHOLDER": "Enter a name for the document"
        }
      },
```

- [ ] **Step 4: Verificar**

Run: `npx eslint app/javascript/dashboard/components-next/captain/pageComponents/document/DocumentForm.vue app/javascript/dashboard/routes/dashboard/captain/documents/Index.vue` → sem erros.
Run: `grep -rn "PDF_FILE\|FORM.TYPE" app/javascript/dashboard --include=*.vue --include=*.js | grep DOCUMENTS` → nada.
Rodar a "paridade" → tudo `[]`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/components-next/captain/pageComponents/document/DocumentForm.vue app/javascript/dashboard/routes/dashboard/captain/documents/Index.vue app/javascript/dashboard/i18n/locale/en/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/integrations.json
git commit -m "feat(inteligencia): Documentos sem PDF e com aviso de que viram FAQs pendentes"
```

---

### Task 10: Caixas — aviso ao conectar (I-CX2)

**Files:**
- Modify: `app/javascript/dashboard/components-next/captain/pageComponents/inbox/ConnectInboxForm.vue:6-9,51,95-97`
- Test: `app/javascript/dashboard/components-next/captain/pageComponents/inbox/specs/ConnectInboxForm.spec.js` (novo)
- Modify: `i18n/locale/pt_BR/integrations.json:1092-1098`, `i18n/locale/en/integrations.json:1093-1099` (bloco `INBOXES.FORM`)

**Interfaces:**
- Consumes: `modoDefault()` de `dashboard/routes/dashboard/ramon/helpers/copilotoModo.js` (lê `window.chatwootConfig.ramonCopilotoModoDefault`, vindo de `RAMON_COPILOTO_MODO_DEFAULT` em `app/views/layouts/vueapp.html.erb:60`); i18n `RAMON.COPILOTO.MODOS.<modo>.NOME`.
- Produces (i18n): `CAPTAIN.INBOXES.FORM.AVISO_RASCUNHO` com `{modo}`.

- [ ] **Step 1: Teste que falha** — criar `app/javascript/dashboard/components-next/captain/pageComponents/inbox/specs/ConnectInboxForm.spec.js`:

```js
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConnectInboxForm from '../ConnectInboxForm.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
  }),
}));

const montar = () => {
  const store = createStore({
    modules: {
      captainInboxes: {
        namespaced: true,
        getters: {
          getUIFlags: () => ({ creatingItem: false }),
          getRecords: () => [],
        },
      },
      inboxes: { namespaced: true, getters: { getInboxes: () => [] } },
    },
  });
  return mount(ConnectInboxForm, {
    props: { assistantId: 1 },
    global: { plugins: [store], stubs: { ComboBox: true, Button: true } },
  });
};

describe('ConnectInboxForm — aviso ao conectar', () => {
  afterEach(() => {
    delete window.chatwootConfig;
  });

  it('avisa com o modo padrão do hub (piloto com limites)', () => {
    window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
    expect(montar().find('[data-testid="aviso-conectar-caixa"]').text()).toBe(
      'CAPTAIN.INBOXES.FORM.AVISO_RASCUNHO {"modo":"RAMON.COPILOTO.MODOS.piloto_limitado.NOME"}'
    );
  });

  it('sem config, o modo do aviso é Rascunho', () => {
    expect(
      montar().find('[data-testid="aviso-conectar-caixa"]').text()
    ).toContain('RAMON.COPILOTO.MODOS.rascunho.NOME');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/components-next/captain/pageComponents/inbox/specs/ConnectInboxForm.spec.js`
Expected: FAIL — `[data-testid="aviso-conectar-caixa"]` não existe.

- [ ] **Step 3: `ConnectInboxForm.vue`** — imports (depois da linha 9, `import ComboBox …`):

```js
import { AVISO, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { modoDefault } from 'dashboard/routes/dashboard/ramon/helpers/copilotoModo';
```

Depois de `const isLoading = computed(() => formState.uiFlags.value.creatingItem);` (linha 51):

```js
// Conectar liga a IA na caixa na hora — o aviso diz em que modo as conversas novas nascem.
const avisoConexao = computed(() =>
  t('CAPTAIN.INBOXES.FORM.AVISO_RASCUNHO', {
    modo: t(`RAMON.COPILOTO.MODOS.${modoDefault()}.NOME`),
  })
);
```

No template, entre o `</div>` do ComboBox (linha 95) e `<div class="flex items-center justify-between w-full gap-3">` (linha 97):

```vue
    <p
      data-testid="aviso-conectar-caixa"
      class="mb-0"
      :class="[AVISO, TOM.amber]"
    >
      {{ avisoConexao }}
    </p>
```

- [ ] **Step 4: i18n** — no bloco `INBOXES.FORM`, depois do sub-bloco `"INBOX": { … }` (vírgula no `}` dele):
  - pt_BR: `"AVISO_RASCUNHO": "Ao conectar, o assistente começa na hora a escrever rascunhos de resposta nas conversas desta caixa. Modo padrão das conversas novas: {modo} — dá para trocar em cada conversa."`
  - en: `"AVISO_RASCUNHO": "Once connected, the assistant immediately starts drafting replies in this inbox's conversations. Default mode for new conversations: {modo} — you can change it per conversation."`

- [ ] **Step 5: Rodar e ver passar**

Run: `npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/components-next/captain/pageComponents/inbox/specs/ConnectInboxForm.spec.js` → PASS (2 testes).
Run: `npx eslint app/javascript/dashboard/components-next/captain/pageComponents/inbox` → sem erros. Rodar a "paridade" → tudo `[]`.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/components-next/captain/pageComponents/inbox app/javascript/dashboard/i18n/locale/en/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/integrations.json
git commit -m "feat(inteligencia): aviso ao conectar caixa (rascunhos na hora, com o modo padrão)"
```

---

### Task 11: Verificação final + prints "depois" + `comparar.html`

**Files:**
- Create (não versionado): `tmp/intel-harness/comparar.mjs`
- Output: `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-05-inteligencia-a1\{depois-*.png,comparar.html}`

- [ ] **Step 1: Suíte JS da área**

Run: `npx vitest run --config tmp/vitest.local.config.ts app/javascript/dashboard/routes/dashboard/ramon/helpers app/javascript/dashboard/components-next/captain app/javascript/dashboard/composables/spec/useCaptain.spec.js` → PASS.
Run: `npx eslint app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/components-next/captain app/javascript/dashboard/components-next/sidebar/Sidebar.vue app/javascript/dashboard/routes/dashboard/ramon/helpers` → sem erros.
Rodar a "paridade" → tudo `[]`.

- [ ] **Step 2: Varredura de texto**

Run: `grep -rn -i "cenário\|coisas divertidas\|créditos\|chwt.app" app/javascript/dashboard/i18n/locale/pt_BR/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/routes/dashboard/captain app/javascript/dashboard/components-next/captain/pageComponents` → nada. (`settings.json` fica de fora: tem "créditos" na tela de cobrança da Chatwoot, que não está no menu — `Sidebar.vue:732` comentado.)
Run (sensível a maiúsculas, só valores): `grep -n ': "Tools"\|: "Playground"\|: "Watchdog"' app/javascript/dashboard/i18n/locale/pt_BR/settings.json app/javascript/dashboard/i18n/locale/pt_BR/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` → nada.

- [ ] **Step 3: Prints "depois"** — com o harness no ar (Task 1, Step 5; se caiu, subir de novo): `sh tmp/intel-harness/shots.sh depois` → 30 arquivos `depois-*`. Abrir com Read pelo menos `depois-claro-skills.png` (chips coloridos + legenda), `depois-escuro-execucoes.png` (nome legível + chip), `depois-claro-caixas-conectar.png` (aviso âmbar), `depois-claro-documentos.png` (aviso azul + "Ver FAQs geradas"), `depois-escuro-configuracoes.png` ("Regras do assistente") e `depois-claro-protecoes.png` (exemplos da banca). Fundo dos chips/avisos translúcido nos dois temas; nada de texto cobrindo texto.

- [ ] **Step 4: `comparar.html`** — criar `tmp/intel-harness/comparar.mjs` (com Write):

```js
// Gera comparar.html (antes × depois, claro/escuro) na pasta dos prints.
import { writeFileSync } from 'node:fs';

const OUT =
  'C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-05-inteligencia-a1';
const TELAS = [
  ['Assistentes', 'assistentes', 'I-T2, I-T3'],
  ['FAQs', 'faqs', 'I-T3, I-FQ3'],
  ['FAQs pendentes', 'faqs-pendentes', 'I-T3, I-FQ3'],
  ['Documentos', 'documentos', 'I-T3, I-DO3'],
  ['Documentos — novo documento', 'documentos-novo', 'I-DO2, I-DO3'],
  ['Skills', 'skills', 'I-SK1, I-SK2, I-FE3'],
  ['Ferramentas', 'ferramentas', 'I-T1, I-T2'],
  ['Testar', 'testar', 'I-T1, I-T3'],
  ['Caixas de Entrada', 'caixas', 'I-T2'],
  ['Caixas — conectar', 'caixas-conectar', 'I-CX2'],
  ['Configurações', 'configuracoes', 'I-CF1'],
  ['Proteções', 'protecoes', 'I-CF1, I-CF2'],
  ['Diretrizes de resposta', 'diretrizes', 'I-CF1, I-CF2'],
  ['Execuções', 'execucoes', 'I-EX1, I-FE3'],
  ['Vigia', 'vigia', 'I-WD1'],
];
const MENU_ANTES =
  'Assistentes · FAQs · Documentos · Skills · Playground · Caixas de Entrada · Tools · Execuções · Watchdog · Configurações';
const MENU_DEPOIS =
  'Vigia · Assistentes · Caixas de Entrada · Skills · Ferramentas · FAQs · Documentos · Testar · Execuções · Configurações';

const rotulo = fase => (fase === 'antes' ? 'Antes' : 'Depois');
const fig = (fase, tema, arq, nome) =>
  `<figure><figcaption>${rotulo(fase)}</figcaption><img src="${fase}-${tema}-${arq}.png" alt="${rotulo(fase)}, ${nome}, tema ${tema}"></figure>`;
const secoes = TELAS.flatMap(([nome, arq, itens]) =>
  ['claro', 'escuro'].map(
    tema =>
      `<section><h2>${nome} · ${itens} · tema ${tema}</h2><div class="par">${fig('antes', tema, arq, nome)}${fig('depois', tema, arq, nome)}</div></section>`
  )
).join('');
const css =
  'body{font:14px system-ui,sans-serif;margin:24px;background:#f4f4f4;color:#111}h1{font-size:20px}h2{font-size:15px;margin:28px 0 8px}.par{display:flex;gap:24px;align-items:flex-start;flex-wrap:wrap}figure{margin:0;background:#fff;padding:8px;border:1px solid #ddd;border-radius:8px}figcaption{font-weight:600;margin-bottom:6px}img{width:700px;max-width:100%;display:block}';

writeFileSync(
  `${OUT}/comparar.html`,
  `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Inteligência A1 — antes e depois</title><style>${css}</style></head><body><h1>Inteligência — pacote A1 (faxina rápida): antes e depois</h1><section><h2>Menu da Inteligência (ordem e nomes)</h2><p><b>Antes:</b> ${MENU_ANTES}</p><p><b>Depois:</b> ${MENU_DEPOIS}</p><p>Vigia no topo e Caixas logo após Assistentes até a Visão geral e o cartão do assistente existirem.</p></section>${secoes}</body></html>`
);
console.log(`ok ${OUT}/comparar.html`);
```

Run: `node tmp/intel-harness/comparar.mjs` → `ok …/comparar.html`.

- [ ] **Step 5: Derrubar o harness** (parar o `npx vite` em segundo plano) e conferir `git status`: só `tmp/` fora do índice; nada de arquivo solto.

- [ ] **Step 6: Entregar pro Eduardo** — mandar o caminho clicável `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-05-inteligencia-a1\comparar.html` + a pasta, com a lista das divergências conscientes e as 4 dúvidas deste plano. **Push/PR só depois do "aprovado".** Lembrete pro PR: o CI valida os specs Ruby da Task 5 (`captain_tools_helpers_spec.rb`, `captain_tool_runs_controller_spec.rb`) e o rubocop — sem Ruby local.

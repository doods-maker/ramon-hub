# Onda 2 — Menu único por papel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar trilho (`WorldRail`) + sidebar do Chatwoot + sidebar da Intranet por UM menu lateral, igual ao mockup v2, filtrado pelo papel de quem está logado.

**Architecture:** Funções puras (`papelDe`, `itensDoMenu`, `itensDoMais`) decidem papel e itens; dois composables (`useRamonPapel`, `useNavContadores`) ligam isso à store; o componente `RamonNav.vue` só desenha. O `Dashboard.vue` passa a montar `RamonNav` e assume o "bootstrap" de dados que hoje vive no `onMounted` do Sidebar do Chatwoot (labels, inboxes, teams…), que deixa de ser montado.

**Tech Stack:** Vue 3 (`<script setup>`), Vuex + Pinia, vue-router, vue-i18n, Tailwind (tokens `n-*`), Vitest + @vue/test-utils.

**Spec:** `docs/superpowers/specs/2026-10-03-redesign-v2-fiel-ao-mockup.md` · alvo visual `docs/superpowers/specs/mockups/2026-10-03-hub-v2.html` (seção `.nav` do CSS).

## Global Constraints

- Branch `feat/menu-unico`, empilhada em `feat/visual-branco-preto` (Onda 1). Depois do squash da Onda 1: `git rebase --onto origin/ramon <sha-da-onda-1> feat/menu-unico` e PR novo.
- Tailwind só (sem CSS próprio, sem `style=`), Composition API `<script setup>`, eventos camelCase, i18n sem texto cru (pt_BR em `i18n/locale/pt_BR/ramon.json` e en em `i18n/locale/en/ramon.json`).
- Fundo colorido sempre translúcido: ativo = `bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16] text-n-blue-11`.
- Medidas do mockup: menu `w-[228px]`, padding `px-2.5 py-3`; item `px-2 py-1.5 rounded-[7px] text-[13.5px] gap-2.5`; ícone `size-4`; contador `font-mono text-[11px] rounded-full px-[7px]`.
- Papel é cosmético: rotas continuam protegidas por `meta.permissions`; item admin-only nunca aparece pra não-gestor.
- Rodar testes: `TZ=UTC ./node_modules/.bin/vitest --no-watch <arquivos>`; lint: `./node_modules/.bin/eslint <arquivos>`. Sempre `git -C <worktree>`; conferir CRLF com `git diff --ignore-cr-at-eol`.
- Commits convencionais, sem citar Claude no assunto, com o trailer de co-autoria da sessão.

## Review Focus

1. Usuário sem time nenhum (agente recém-convidado) → papel `equipe`, menu de SDR/Closer, nada quebra.
2. Time com acento/maiúscula ("Recepção", "RECEPCAO ") → reconhecido como `recepcao`.
3. Entrar direto numa URL de conversa (sem passar por outra tela) → inboxes/labels/teams carregados (bootstrap no Dashboard, não no menu).
4. Celular: menu abre/fecha pelo `MobileSidebarLauncher`, fecha ao tocar fora e ao navegar.
5. API de contadores fora do ar → menu aparece sem os números, sem erro na tela.

---

### Task 1: Papel de quem está logado

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/papel.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/composables/useRamonPapel.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/papel.spec.js`

**Interfaces:**
- Produces: `papelDe({ isAdmin: boolean, nomesDosTimes: string[] }) → 'gestor'|'sdr'|'closer'|'recepcao'|'advogada'|'equipe'`; `useRamonPapel() → { papel: ComputedRef<string> }`.

- [ ] **Step 1: Teste que falha**

```js
import { papelDe } from '../papel';

describe('papelDe', () => {
  it('admin é gestor mesmo com time', () => {
    expect(papelDe({ isAdmin: true, nomesDosTimes: ['sdr'] })).toBe('gestor');
  });
  it('recepção com acento, maiúscula e espaço', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: [' Recepção '] })).toBe('recepcao');
  });
  it('controladoria entra como recepção', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: ['controladoria'] })).toBe('recepcao');
  });
  it('closer vence sdr quando a pessoa está nos dois', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: ['sdr', 'closer'] })).toBe('closer');
  });
  it('sdr', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: ['sdr'] })).toBe('sdr');
  });
  it('advogados vira advogada', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: ['advogados'] })).toBe('advogada');
  });
  it('sem time é equipe', () => {
    expect(papelDe({ isAdmin: false, nomesDosTimes: [] })).toBe('equipe');
    expect(papelDe({ isAdmin: false })).toBe('equipe');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar** — `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/papel.spec.js` → FAIL (módulo não existe).

- [ ] **Step 3: Implementar**

`helpers/papel.js`:

```js
// Papel de quem está logado — monta o menu e (Onda 3) a tela Hoje.
// Cosmético: o guard de verdade segue nas rotas e no backend.
const normaliza = nome =>
  (nome || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .toLowerCase();

export const papelDe = ({ isAdmin, nomesDosTimes = [] }) => {
  if (isAdmin) return 'gestor';
  const times = nomesDosTimes.map(normaliza);
  if (times.includes('recepcao') || times.includes('controladoria'))
    return 'recepcao';
  if (times.includes('closer')) return 'closer';
  if (times.includes('sdr')) return 'sdr';
  if (times.includes('advogados')) return 'advogada';
  return 'equipe';
};
```

`composables/useRamonPapel.js`:

```js
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { papelDe } from '../helpers/papel';

export const useRamonPapel = () => {
  const { isAdmin } = useAdmin();
  const meusTimes = useMapGetter('teams/getMyTeams');
  const papel = computed(() =>
    papelDe({
      isAdmin: isAdmin.value,
      nomesDosTimes: (meusTimes.value || []).map(time => time.name),
    })
  );
  return { papel };
};
```

- [ ] **Step 4: Rodar e ver passar** (mesmo comando) → PASS 7/7.
- [ ] **Step 5: Commit** — `git -C <wt> add <3 arquivos> && git -C <wt> commit -m "feat(menu): papel de quem está logado a partir dos times"`

---

### Task 2: Itens do menu por papel

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/navItems.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/navItems.spec.js`

**Interfaces:**
- Consumes: papéis da Task 1 (strings).
- Produces: `itensDoMenu(papel) → Array<{ key, label, icon, rota, params?, names, contador? }>`; `itensDoMais(papel) → Array<{ key, label, icon, rota, params? }>` (vazio para não-gestor); `CONVERSA_ROUTES: string[]`. `label` é chave i18n.

- [ ] **Step 1: Teste que falha**

```js
import { itensDoMenu, itensDoMais, CONVERSA_ROUTES } from '../navItems';

const chaves = papel => itensDoMenu(papel).map(i => i.key);

describe('itensDoMenu', () => {
  it('gestor vê os 9', () => {
    expect(chaves('gestor')).toEqual([
      'hoje', 'conversas', 'funil', 'clientes', 'agenda',
      'calculos', 'conteudo', 'resultados', 'mais',
    ]);
  });
  it('sdr, closer e equipe veem 7 (sem conteúdo e sem mais)', () => {
    ['sdr', 'closer', 'equipe'].forEach(papel =>
      expect(chaves(papel)).toEqual([
        'hoje', 'conversas', 'funil', 'clientes', 'agenda', 'calculos', 'resultados',
      ])
    );
  });
  it('recepção vê 4', () => {
    expect(chaves('recepcao')).toEqual(['hoje', 'conversas', 'clientes', 'agenda']);
  });
  it('advogada vê 5', () => {
    expect(chaves('advogada')).toEqual(['hoje', 'conversas', 'clientes', 'agenda', 'calculos']);
  });
  it('Resultados: gestor vai a relatórios, os demais ao extrato', () => {
    const rota = papel => itensDoMenu(papel).find(i => i.key === 'resultados').rota;
    expect(rota('gestor')).toBe('ramon_relatorios');
    expect(rota('sdr')).toBe('ramon_extrato');
  });
  it('Conversas acende em qualquer rota de conversa, menos o kanban', () => {
    expect(CONVERSA_ROUTES).toContain('home');
    expect(CONVERSA_ROUTES).toContain('inbox_conversation');
    expect(CONVERSA_ROUTES).not.toContain('kanban_board');
  });
  it('Mais só existe pro gestor', () => {
    expect(itensDoMais('sdr')).toEqual([]);
    expect(itensDoMais('gestor').map(i => i.key)).toContain('tv');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar.**

- [ ] **Step 3: Implementar** `helpers/navItems.js`:

```js
// Menu único (redesign v2 — mockup 03/10). `papeis` = quem vê o item;
// `names` = rotas que acendem o item. Rotas admin-only só aparecem pro gestor.
const TODOS = ['gestor', 'sdr', 'closer', 'recepcao', 'advogada', 'equipe'];
const COMERCIAL = ['gestor', 'sdr', 'closer', 'equipe'];

// Todas as rotas de conversations/conversation.routes.js, exceto kanban_board.
export const CONVERSA_ROUTES = [
  'home', 'inbox_conversation', 'inbox_dashboard', 'conversation_through_inbox',
  'label_conversations', 'conversations_through_label', 'team_conversations',
  'conversations_through_team', 'folder_conversations', 'conversations_through_folders',
  'conversation_mentions', 'conversation_through_mentions', 'conversation_unattended',
  'conversation_through_unattended', 'conversation_participating',
  'conversation_through_participating', 'inbox_view', 'inbox_view_conversation',
];

const MENU = [
  { key: 'hoje', icon: 'i-lucide-sun', rota: 'ramon_index', names: ['ramon_index', 'ramon_esteira'], papeis: TODOS },
  { key: 'conversas', icon: 'i-lucide-message-circle', rota: 'home', names: CONVERSA_ROUTES, papeis: TODOS, contador: 'conversas' },
  { key: 'funil', icon: 'i-lucide-columns-3', rota: 'ramon_funil', names: ['ramon_funil', 'kanban_board', 'ramon_pos_venda', 'ramon_radar'], papeis: COMERCIAL },
  { key: 'clientes', icon: 'i-lucide-users', rota: 'ramon_pessoas', names: ['ramon_pessoas', 'ramon_linha_da_vida', 'ramon_lead_dossie', 'ramon_portal_clientes'], papeis: TODOS },
  { key: 'agenda', icon: 'i-lucide-calendar', rota: 'ramon_agenda', names: ['ramon_agenda', 'ramon_reunioes', 'ramon_reuniao'], papeis: TODOS, contador: 'agenda' },
  { key: 'calculos', icon: 'i-lucide-calculator', rota: 'ramon_calculos', names: ['ramon_calculos', 'ramon_calculos_lead'], papeis: [...COMERCIAL, 'advogada'] },
  { key: 'conteudo', icon: 'i-lucide-image', rota: 'ramon_conteudo', names: ['ramon_conteudo'], papeis: ['gestor'], contador: 'conteudo' },
  { key: 'resultados', icon: 'i-lucide-chart-no-axes-column', rota: null, names: ['ramon_relatorios', 'ramon_extrato'], papeis: COMERCIAL },
  { key: 'mais', icon: 'i-lucide-ellipsis', rota: null, names: [], papeis: ['gestor'] },
];

const MAIS = [
  { key: 'esteira', icon: 'i-lucide-zap', rota: 'ramon_esteira' },
  { key: 'pos_venda', icon: 'i-lucide-package-check', rota: 'ramon_pos_venda' },
  { key: 'radar', icon: 'i-lucide-radar', rota: 'ramon_radar' },
  { key: 'reunioes', icon: 'i-lucide-mic', rota: 'ramon_reunioes' },
  { key: 'portal', icon: 'i-lucide-smartphone', rota: 'ramon_portal_clientes' },
  { key: 'extrato', icon: 'i-lucide-receipt', rota: 'ramon_extrato' },
  { key: 'tv', icon: 'i-lucide-tv', rota: 'ramon_tv' },
  { key: 'playbooks', icon: 'i-lucide-book-open', rota: 'ramon_playbooks' },
  { key: 'funil_config', icon: 'i-lucide-sliders-horizontal', rota: 'ramon_funil_config' },
  { key: 'captain', icon: 'i-lucide-bot', rota: 'captain_assistants_index', params: { navigationPath: 'captain_assistants_responses_index' } },
  { key: 'contatos', icon: 'i-lucide-contact', rota: 'contacts_dashboard_index' },
  { key: 'relatorios_atendimento', icon: 'i-lucide-chart-line', rota: 'account_overview_reports' },
  { key: 'configuracoes', icon: 'i-lucide-settings', rota: 'settings_home' },
  { key: 'atalhos', icon: 'i-lucide-external-link', rota: 'ramon_external_shortcuts' },
];

const comLabel = item => ({ ...item, label: `RAMON.MENU.${item.key.toUpperCase()}` });

export const itensDoMenu = papel =>
  MENU.filter(item => item.papeis.includes(papel)).map(item =>
    comLabel({
      ...item,
      rota: item.key === 'resultados' ? (papel === 'gestor' ? 'ramon_relatorios' : 'ramon_extrato') : item.rota,
    })
  );

export const itensDoMais = papel => (papel === 'gestor' ? MAIS.map(comLabel) : []);
```

Confira os nomes em `conversation.routes.js` e em `routes/dashboard/inbox/*.routes.js` (`inbox_view*`) com `grep -n "name: '"` — o array precisa bater 1:1 com o que existe (remova da lista o que não existir).

- [ ] **Step 4: Prettier** — `./node_modules/.bin/eslint --fix` no arquivo (ele reformata as linhas longas); rodar o teste → PASS.
- [ ] **Step 5: Commit** — `feat(menu): itens do menu único por papel`

---

### Task 3: Contadores do menu

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/composables/useNavContadores.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/composables/specs/useNavContadores.spec.js`

**Interfaces:**
- Consumes: `LeadTasksAPI.getAccountScope('today')` → `{ data: { payload: [] } }`; `RamonConteudoAPI.get()` → `{ data: { payload: [{ status }] } }`; getter `conversationUnreadCounts/getAllUnreadCount`.
- Produces: `useNavContadores(papel: Ref<string>) → { conversas: Ref<number>, agenda: Ref<number>, conteudo: Ref<number>, carregar: () => Promise<void> }`.

- [ ] **Step 1: Teste que falha**

```js
import { ref } from 'vue';
import LeadTasksAPI from 'dashboard/api/leadTasks';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';
import { useNavContadores } from '../useNavContadores';

vi.mock('dashboard/api/leadTasks', () => ({ default: { getAccountScope: vi.fn() } }));
vi.mock('dashboard/api/ramonConteudo', () => ({ default: { get: vi.fn() } }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(4),
}));

describe('useNavContadores', () => {
  beforeEach(() => vi.clearAllMocks());

  it('conta tarefas de hoje e peças em rascunho (gestor)', async () => {
    LeadTasksAPI.getAccountScope.mockResolvedValue({ data: { payload: [{}, {}, {}] } });
    RamonConteudoAPI.get.mockResolvedValue({
      data: { payload: [{ status: 'rascunho' }, { status: 'publicado' }, { status: 'rascunho' }] },
    });
    const c = useNavContadores(ref('gestor'));
    await c.carregar();
    expect(c.agenda.value).toBe(3);
    expect(c.conteudo.value).toBe(2);
    expect(c.conversas.value).toBe(4);
  });

  it('não-gestor não busca conteúdo', async () => {
    LeadTasksAPI.getAccountScope.mockResolvedValue({ data: { payload: [] } });
    const c = useNavContadores(ref('sdr'));
    await c.carregar();
    expect(RamonConteudoAPI.get).not.toHaveBeenCalled();
  });

  it('API fora do ar: contadores ficam zerados, sem lançar', async () => {
    LeadTasksAPI.getAccountScope.mockRejectedValue(new Error('500'));
    RamonConteudoAPI.get.mockRejectedValue(new Error('500'));
    const c = useNavContadores(ref('gestor'));
    await expect(c.carregar()).resolves.toBeUndefined();
    expect(c.agenda.value).toBe(0);
    expect(c.conteudo.value).toBe(0);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar**

```js
import { ref } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import LeadTasksAPI from 'dashboard/api/leadTasks';
import RamonConteudoAPI from 'dashboard/api/ramonConteudo';

// Números do menu: não lidas (store do Chatwoot), tarefas de hoje e peças
// aguardando aprovação. Falha de rede = número some, menu segue.
const CINCO_MINUTOS = 5 * 60 * 1000;

export const useNavContadores = papel => {
  const conversas = useMapGetter('conversationUnreadCounts/getAllUnreadCount');
  const agenda = ref(0);
  const conteudo = ref(0);

  const carregar = async () => {
    try {
      const { data } = await LeadTasksAPI.getAccountScope('today');
      agenda.value = data.payload.length;
    } catch {
      agenda.value = 0;
    }
    if (papel.value !== 'gestor') return;
    try {
      const { data } = await RamonConteudoAPI.get();
      conteudo.value = data.payload.filter(p => p.status === 'rascunho').length;
    } catch {
      conteudo.value = 0;
    }
  };

  useIntervalFn(carregar, CINCO_MINUTOS);
  return { conversas, agenda, conteudo, carregar };
};
```

(O componente chama `carregar()` no `onMounted`; o intervalo cuida do resto.)

- [ ] **Step 4: Rodar e ver passar.**
- [ ] **Step 5: Commit** — `feat(menu): contadores de não lidas, agenda do dia e conteúdo a aprovar`

---

### Task 4: Ganchos pro menu abrir a busca e o painel de chegada

**Files:**
- Modify: `app/javascript/shared/constants/busEvents.js` (nova chave)
- Modify: `app/javascript/dashboard/routes/dashboard/commands/commandbar.vue` (abrir por evento)
- Modify: `app/javascript/dashboard/stores/chegadas.js` (`painelPedido` + `pedirPainel`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/equipe/ChegouCliente.vue` (abre por pedido; sai o botão flutuante)
- Test: `app/javascript/dashboard/stores/chegadas.spec.js`, `app/javascript/dashboard/routes/dashboard/ramon/components/equipe/specs/ChegouCliente.spec.js`

**Interfaces:**
- Produces: `BUS_EVENTS.OPEN_COMMAND_BAR = 'OPEN_COMMAND_BAR'`; `useChegadasStore().pedirPainel()` (incrementa `painelPedido: number`).

- [ ] **Step 1: Testes que falham**

Em `stores/chegadas.spec.js` (acrescentar):

```js
it('pedirPainel incrementa o pedido', () => {
  const store = useChegadasStore();
  expect(store.painelPedido).toBe(0);
  store.pedirPainel();
  expect(store.painelPedido).toBe(1);
});
```

Em `ChegouCliente.spec.js`: troque o teste que clicava no botão flutuante (procure por `bottom-4`/o `find('button')` do topo) por:

```js
it('abre o painel quando o menu pede', async () => {
  const wrapper = montar(); // use o helper de montagem que o spec já tem
  const chegadas = useChegadasStore();
  chegadas.pedirPainel();
  await flushPromises();
  expect(dialogOpen).toHaveBeenCalled(); // o spy de open() do Dialog que o spec já usa
});
it('não tem mais botão flutuante', () => {
  const wrapper = montar();
  expect(wrapper.find('.fixed.bottom-4').exists()).toBe(false);
});
```

(Adapte nomes ao que o spec existente usa — leia-o inteiro antes; não apague cobertura de `usarAgenda`/`buscar`/envio.)

- [ ] **Step 2: Rodar e ver falhar.**
- [ ] **Step 3: Implementar**

`busEvents.js`: acrescentar `OPEN_COMMAND_BAR: 'OPEN_COMMAND_BAR',` no objeto.

`commandbar.vue` (dentro do `<script setup>`, junto dos outros hooks):

```js
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
// ...
useEmitter(BUS_EVENTS.OPEN_COMMAND_BAR, () => ninjakeys.value?.open());
```

(Se `dashboard/composables/emitter` não exportar `useEmitter`, use `emitter.on` no `onMounted` e `emitter.off` no `onUnmounted` — `emitter` já está importado no arquivo.)

`stores/chegadas.js`: no `state` acrescentar `painelPedido: 0,`; nas `actions`:

```js
    // O botão "Chegou cliente" mora no menu; o painel escuta este contador.
    pedirPainel() {
      this.painelPedido += 1;
    },
```

`ChegouCliente.vue`: importar `watch` de 'vue'; depois de `abrir`:

```js
watch(
  () => chegadas.painelPedido,
  () => abrir()
);
```

No template, apagar o `<button class="fixed bottom-4 …" @click="abrir">…</button>` (o `<div v-if="chegadas.podeAvisar" class="contents">` continua envolvendo o `Dialog`).

- [ ] **Step 4: Rodar os dois specs** → PASS.
- [ ] **Step 5: Commit** — `feat(menu): busca e painel de chegada abrem pelo menu`

---

### Task 5: Componente `RamonNav.vue`

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/nav/RamonNav.vue`
- Modify: `app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue` (props `subtitle` e `avatarSize`)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`, `app/javascript/dashboard/i18n/locale/en/ramon.json` (bloco `RAMON.MENU`)
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/nav/specs/RamonNav.spec.js`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: `<RamonNav :is-mobile-sidebar-open @close-mobile-sidebar @open-key-shortcut-modal />` — mesmas props/eventos que o `IntranetSidebar` tinha, + `openKeyShortcutModal`.

- [ ] **Step 1: i18n** — em `pt_BR/ramon.json`, dentro de `RAMON`, novo bloco:

```json
"MENU": {
  "HOJE": "Hoje", "CONVERSAS": "Conversas", "FUNIL": "Funil", "CLIENTES": "Clientes",
  "AGENDA": "Agenda", "CALCULOS": "Cálculos", "CONTEUDO": "Conteúdo",
  "RESULTADOS": "Resultados", "MAIS": "Mais", "BUSCAR": "Buscar",
  "NOVA_CONVERSA": "Nova conversa", "CHEGOU_CLIENTE": "Chegou cliente",
  "ESTEIRA": "Esteira", "POS_VENDA": "Pós-venda", "RADAR": "Radar de prescrição",
  "REUNIOES": "Reuniões", "PORTAL": "Painel do cliente", "EXTRATO": "Extrato da variável",
  "TV": "Placar de TV", "PLAYBOOKS": "Playbooks", "FUNIL_CONFIG": "Configurações do funil",
  "CAPTAIN": "Assistente de IA", "CONTATOS": "Contatos",
  "RELATORIOS_ATENDIMENTO": "Relatórios de atendimento", "CONFIGURACOES": "Configurações",
  "ATALHOS": "Gerenciar atalhos",
  "PAPEL": { "gestor": "Gestor", "sdr": "SDR", "closer": "Closer", "recepcao": "Recepção", "advogada": "Advogada", "equipe": "Equipe" }
}
```

Em `en/ramon.json` o mesmo bloco em inglês (Today, Conversations, Pipeline, Clients, Agenda, Calculations, Content, Results, More, Search, New conversation, Client arrived, Queue, After-sale, Statute-of-limitations radar, Meetings, Client portal, Commission statement, TV scoreboard, Playbooks, Pipeline settings, AI assistant, Contacts, Support reports, Settings, Manage shortcuts; PAPEL: Manager, SDR, Closer, Front desk, Lawyer, Team).

- [ ] **Step 2: Teste que falha** (`nav/specs/RamonNav.spec.js`)

```js
import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createTestingPinia } from '@pinia/testing';
import RamonNav from '../RamonNav.vue';
import { useChegadasStore } from 'dashboard/stores/chegadas';

const papel = ref('gestor');
const rotaAtual = ref('ramon_funil');

vi.mock('../../../composables/useRamonPapel', () => ({ useRamonPapel: () => ({ papel }) }));
vi.mock('../../../composables/useNavContadores', () => ({
  useNavContadores: () => ({ conversas: ref(3), agenda: ref(0), conteudo: ref(2), carregar: vi.fn() }),
}));
vi.mock('vue-router', () => ({ useRoute: () => ({ get name() { return rotaAtual.value; } }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: (name, params) => ({ name, params }) }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({ useUISettings: () => ({ uiSettings: ref({}) }) }));

const montar = () =>
  mount(RamonNav, {
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn })],
      mocks: { $t: k => k },
      stubs: { RouterLink: { props: ['to'], template: '<a :data-rota="to.name"><slot /></a>' }, SidebarProfileMenu: true, ComposeConversation: true },
    },
  });

describe('RamonNav', () => {
  beforeEach(() => { papel.value = 'gestor'; rotaAtual.value = 'ramon_funil'; });

  it('gestor: 8 links + Mais, Funil aceso', () => {
    const w = montar();
    const rotas = w.findAll('a[data-rota]').map(a => a.attributes('data-rota'));
    expect(rotas.slice(0, 8)).toEqual(['ramon_index', 'home', 'ramon_funil', 'ramon_pessoas', 'ramon_agenda', 'ramon_calculos', 'ramon_conteudo', 'ramon_relatorios']);
    expect(w.find('a[data-rota="ramon_funil"]').classes()).toContain('text-n-blue-11');
    expect(w.text()).toContain('RAMON.MENU.MAIS');
  });

  it('contadores: conversas em azul, conteúdo em âmbar, agenda zerada some', () => {
    const w = montar();
    expect(w.find('a[data-rota="home"]').text()).toContain('3');
    expect(w.find('a[data-rota="ramon_conteudo"]').text()).toContain('2');
    expect(w.find('a[data-rota="ramon_agenda"]').text()).not.toMatch(/\d/);
  });

  it('recepção: 4 itens e botão Chegou cliente que pede o painel', async () => {
    papel.value = 'recepcao';
    const w = montar();
    expect(w.findAll('a[data-rota]').length).toBe(4);
    await w.find('[data-test="chegou-cliente"]').trigger('click');
    expect(useChegadasStore().pedirPainel).toHaveBeenCalled();
  });

  it('não-recepção não vê Chegou cliente', () => {
    expect(montar().find('[data-test="chegou-cliente"]').exists()).toBe(false);
  });

  it('Mais abre a lista do gestor e abre sozinho numa rota dele', async () => {
    rotaAtual.value = 'ramon_tv';
    const w = montar();
    expect(w.find('a[data-rota="ramon_tv"]').exists()).toBe(true);
  });
});
```

- [ ] **Step 3: Rodar e ver falhar.**

- [ ] **Step 4: Props no `SidebarProfileMenu.vue`** (fork point mínimo):

```js
defineProps({
  isCollapsed: { type: Boolean, default: false },
  // FORK(ramon): menu único mostra o papel no lugar do e-mail, avatar menor
  subtitle: { type: String, default: '' },
  avatarSize: { type: Number, default: 32 },
});
```

No template: `:size="avatarSize"` no `<Avatar>` e `{{ subtitle || currentUser.email }}` no lugar de `{{ currentUser.email }}`.

- [ ] **Step 5: Implementar `RamonNav.vue`**

```vue
<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import SidebarProfileMenu from 'dashboard/components-next/sidebar/SidebarProfileMenu.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import { useRamonPapel } from '../../composables/useRamonPapel';
import { useNavContadores } from '../../composables/useNavContadores';
import { itensDoMenu, itensDoMais } from '../../helpers/navItems';
import { DEFAULT_EXTERNAL_SHORTCUTS } from '../../externalShortcutsDefaults';

defineProps({ isMobileSidebarOpen: { type: Boolean, default: false } });
const emit = defineEmits(['closeMobileSidebar', 'openKeyShortcutModal']);

const { t } = useI18n();
const route = useRoute();
const { accountScopedRoute } = useAccount();
const { uiSettings } = useUISettings();
const chegadas = useChegadasStore();
const { papel } = useRamonPapel();
const contadores = useNavContadores(papel);

const itens = computed(() => itensDoMenu(papel.value));
const mais = computed(() => itensDoMais(papel.value));
const atalhos = computed(
  () => uiSettings.value.external_shortcuts ?? DEFAULT_EXTERNAL_SHORTCUTS
);
const maisAtivo = computed(() => mais.value.some(i => i.rota === route.name));
const maisAberto = ref(false);
watch(maisAtivo, ativo => { if (ativo) maisAberto.value = true; }, { immediate: true });

const ativo = item => item.names.includes(route.name);
const para = item => accountScopedRoute(item.rota, item.params);

const CONTADOR_COR = {
  conversas: 'bg-n-blue-9 text-white',
  conteudo: 'bg-n-amber-9/15 text-n-amber-11',
  agenda: 'text-n-slate-9',
};
const numero = item => (item.contador ? contadores[item.contador].value : 0);

const abrirBusca = () => emitter.emit(BUS_EVENTS.OPEN_COMMAND_BAR);
const fechar = () => emit('closeMobileSidebar');

onMounted(contadores.carregar);
</script>

<template>
  <div
    v-if="isMobileSidebarOpen"
    class="fixed inset-0 z-30 bg-black/40 md:hidden"
    @click="fechar"
  />
  <aside
    class="fixed top-0 z-40 flex h-full w-[228px] flex-col gap-0.5 overflow-y-auto border-n-weak bg-n-background px-2.5 py-3 transition-transform duration-200 ease-out ltr:left-0 ltr:border-r rtl:right-0 rtl:border-l md:relative md:flex-shrink-0 md:translate-x-0"
    :class="
      isMobileSidebarOpen
        ? 'translate-x-0 shadow-lg md:shadow-none'
        : 'ltr:-translate-x-full rtl:translate-x-full md:translate-x-0'
    "
  >
    <div class="flex items-center gap-2.5 px-2 pb-3 pt-1">
      <span
        class="grid size-[26px] place-items-center rounded-[7px] bg-[#754D2A] text-[11px] font-semibold text-white dark:bg-[#C4A882] dark:text-black"
        >RA</span
      >
      <span class="text-[13.5px] font-semibold text-n-slate-12">Ramon Antonio</span>
    </div>

    <button
      v-if="papel === 'recepcao'"
      data-test="chegou-cliente"
      class="mb-2.5 flex items-center justify-center gap-1.5 rounded-[9px] bg-n-blue-9 px-4 py-2 text-sm font-medium text-white hover:brightness-110"
      @click="chegadas.pedirPainel()"
    >
      <span class="i-lucide-bell-ring size-4" />
      {{ t('RAMON.MENU.CHEGOU_CLIENTE') }}
    </button>

    <div class="mb-2.5 flex gap-1.5">
      <button
        class="flex flex-1 items-center gap-2 rounded-lg border border-n-weak px-2.5 py-1.5 text-[13px] text-n-slate-9 hover:border-n-strong"
        @click="abrirBusca"
      >
        <span class="i-lucide-search size-4" />
        {{ t('RAMON.MENU.BUSCAR') }}
        <kbd class="ml-auto font-mono text-[11px] text-n-slate-9">Ctrl K</kbd>
      </button>
      <ComposeConversation align="start">
        <template #trigger>
          <button
            class="grid size-[34px] place-items-center rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-slate-3"
            :title="t('RAMON.MENU.NOVA_CONVERSA')"
          >
            <span class="i-lucide-pen-line size-4" />
          </button>
        </template>
      </ComposeConversation>
    </div>

    <template v-for="item in itens" :key="item.key">
      <button
        v-if="item.key === 'mais'"
        class="flex items-center gap-2.5 rounded-[7px] px-2 py-1.5 text-[13.5px] text-n-slate-11 hover:bg-n-slate-3 hover:text-n-slate-12"
        @click="maisAberto = !maisAberto"
      >
        <span :class="item.icon" class="size-4 flex-shrink-0" />
        {{ t(item.label) }}
        <span
          class="ml-auto size-4"
          :class="maisAberto ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>
      <router-link
        v-else
        :to="para(item)"
        class="flex items-center gap-2.5 rounded-[7px] px-2 py-1.5 text-[13.5px]"
        :class="
          ativo(item)
            ? 'bg-n-blue-9/[0.08] font-medium text-n-blue-11 dark:bg-n-blue-9/[0.16]'
            : 'text-n-slate-11 hover:bg-n-slate-3 hover:text-n-slate-12'
        "
        @click="fechar"
      >
        <span :class="item.icon" class="size-4 flex-shrink-0" />
        {{ t(item.label) }}
        <span
          v-if="numero(item)"
          class="ml-auto rounded-full px-[7px] py-px font-mono text-[11px] font-medium"
          :class="CONTADOR_COR[item.contador]"
          >{{ numero(item) }}</span
        >
      </router-link>
    </template>

    <div v-if="maisAberto && mais.length" class="ml-4 flex flex-col gap-0.5 border-n-weak ltr:border-l ltr:pl-2 rtl:border-r rtl:pr-2">
      <router-link
        v-for="item in mais"
        :key="item.key"
        :to="para(item)"
        class="flex items-center gap-2 rounded-[7px] px-2 py-1 text-[13px]"
        :class="
          route.name === item.rota
            ? 'bg-n-blue-9/[0.08] font-medium text-n-blue-11 dark:bg-n-blue-9/[0.16]'
            : 'text-n-slate-11 hover:bg-n-slate-3 hover:text-n-slate-12'
        "
        @click="fechar"
      >
        <span :class="item.icon" class="size-3.5 flex-shrink-0" />
        {{ t(item.label) }}
      </router-link>
      <a
        v-for="atalho in atalhos"
        :key="atalho.url"
        :href="atalho.url"
        target="_blank"
        rel="noopener noreferrer"
        class="flex items-center gap-2 rounded-[7px] px-2 py-1 text-[13px] text-n-slate-11 hover:bg-n-slate-3 hover:text-n-slate-12"
      >
        <span :class="atalho.icon || 'i-lucide-external-link'" class="size-3.5 flex-shrink-0" />
        {{ atalho.label }}
      </a>
    </div>

    <div class="mt-auto border-t border-n-weak pt-3">
      <SidebarProfileMenu
        :subtitle="t(`RAMON.MENU.PAPEL.${papel}`)"
        :avatar-size="24"
        @open-key-shortcut-modal="emit('openKeyShortcutModal')"
      />
    </div>
  </aside>
</template>
```

(Atalho externo traz `label` digitado pelo usuário — não é texto cru do código, ok pro i18n. "Ramon Antonio" e "RA" são marca: se o eslint `vue/no-bare-strings-in-template` reclamar, mover pra `RAMON.MENU.MARCA` / `RAMON.MENU.MARCA_SIGLA`.)

- [ ] **Step 6: Rodar o spec** → PASS. Ajuste o spec, não o componente, se for só detalhe de stub (ex.: `data-rota` nos links do Mais).
- [ ] **Step 7: Commit** — `feat(menu): componente do menu único (RamonNav)`

---

### Task 6: Ligar no Dashboard e aposentar trilho e sidebars

**Files:**
- Create: `app/javascript/dashboard/composables/useDashboardBootstrap.js`
- Modify: `app/javascript/dashboard/routes/dashboard/Dashboard.vue`
- Delete: `app/javascript/dashboard/routes/dashboard/ramon/components/WorldRail.vue`, `.../ramon/components/IntranetSidebar.vue`, `.../ramon/helpers/worldChrome.js`, `.../ramon/helpers/specs/worldChrome.spec.js`
- Modify: `app/javascript/dashboard/assets/scss/_ramon-brand.scss` (apagar `.ramon-rail` e `--ramon-rail` se nada mais usar — `git grep -n "ramon-rail"`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/externalShortcutsDefaults.js` (comentário: "Usado pelo menu único (Mais) e pela tela ExternalShortcuts")
- Modify: `ramon.json` pt_BR/en — apagar `RAMON.RAIL.*` e `RAMON.NAV.*` só se `git grep -n "RAMON.RAIL\|RAMON.NAV" app/javascript` não achar mais uso.

**Interfaces:**
- Consumes: `RamonNav` (Task 5).
- Produces: `useDashboardBootstrap()` — sem retorno; dispara `labels/get`, `inboxes/get`, `notifications/unReadCount`, `teams/get`, `attributes/get`, `customViews/get` ('conversation' e 'contact') no mount e mantém `conversationUnreadCounts` em dia.

- [ ] **Step 1: `useDashboardBootstrap.js`** (copiado do `onMounted`/watch do `components-next/sidebar/Sidebar.vue`, que deixa de ser montado; o sort do sidebar não vem junto — só o sidebar usava):

```js
import { computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// FORK(ramon): dados que o Sidebar do Chatwoot carregava no mount. O menu
// único não monta o Sidebar, então o Dashboard carrega — inclusive quem
// entra direto por uma URL da Intranet passa a receber inboxes/teams.
export function useDashboardBootstrap() {
  const store = useStore();
  const accountId = useMapGetter('getCurrentAccountId');
  const isFeatureEnabledonAccount = useMapGetter('accounts/isFeatureEnabledonAccount');
  const temNaoLidas = computed(() =>
    isFeatureEnabledonAccount.value(accountId.value, FEATURE_FLAGS.CONVERSATION_UNREAD_COUNTS)
  );

  onMounted(() => {
    store.dispatch('labels/get');
    store.dispatch('inboxes/get');
    store.dispatch('notifications/unReadCount');
    store.dispatch('teams/get');
    store.dispatch('attributes/get');
    store.dispatch('customViews/get', 'conversation');
    store.dispatch('customViews/get', 'contact');
  });

  watch(
    [accountId, temNaoLidas],
    ([id, ligado]) => {
      if (!id) return;
      store.dispatch(ligado ? 'conversationUnreadCounts/get' : 'conversationUnreadCounts/clear');
    },
    { immediate: true }
  );
}
```

- [ ] **Step 2: `Dashboard.vue`**
  - imports: sai `NextSidebar`, `WorldRail`, `IntranetSidebar`; entra `RamonNav from './ramon/components/nav/RamonNav.vue'`, `{ useDashboardBootstrap } from 'dashboard/composables/useDashboardBootstrap'`, `{ useSidebarKeyboardShortcuts } from 'dashboard/components-next/sidebar/useSidebarKeyboardShortcuts'`.
  - `components`: troca os três por `RamonNav`.
  - `setup()`: chamar `useDashboardBootstrap();` e mover o atalho de teclado pra cá:
    ```js
    const showShortcutModal = ref(false);
    useSidebarKeyboardShortcuts(show => { showShortcutModal.value = show; });
    ```
    e devolver `showShortcutModal` no `return` (sair de `data()`); `toggleKeyShortcutModal`/`closeKeyShortcutModal` continuam mexendo em `this.showShortcutModal`.
  - `computed.isIntranetWorld` some.
  - template: as três tags viram

    ```html
    <RamonNav
      :is-mobile-sidebar-open="isMobileSidebarOpen"
      @close-mobile-sidebar="closeMobileSidebar"
      @open-key-shortcut-modal="toggleKeyShortcutModal"
    />
    ```
  - `toggleAccountModal`, `openCreateAccountModal`, `showAccountModal` ficam sem quem dispare: apague o que ficar morto (o `AddAccountModal` e o seu `showCreateAccountModal` também — conta única; `git grep` antes).
- [ ] **Step 3: Apagar** WorldRail.vue, IntranetSidebar.vue, worldChrome.js + spec; `git grep -n "WorldRail\|IntranetSidebar\|worldChrome\|applyWorldChrome" app/javascript` → vazio. `meta.world` nas rotas pode ficar (inofensivo) — não mexer em 40 rotas por nada.
- [ ] **Step 4: Verificar**
  - `./node_modules/.bin/eslint` em todos os arquivos tocados → 0 erros.
  - `TZ=UTC ./node_modules/.bin/vitest --no-watch app/javascript/dashboard/routes/dashboard/ramon app/javascript/dashboard/stores app/javascript/dashboard/components-next/sidebar app/javascript/dashboard/composables` → tudo verde.
  - `./node_modules/.bin/vite build` → sem erro.
- [ ] **Step 5: Commit** — `feat(menu): menu único no lugar do trilho e das duas sidebars`

---

### Task 7: Smoke no doc consolidado + PR

- [ ] Acrescentar seção "H — Redesign v2: cores (Onda 1) + menu único (Onda 2)" em `C:\Users\dudsl\RAdvogados\comercial\docs\2026-09-14-smoke-consolidado.md` (roteiro em bloco, por papel: logar como admin → 9 itens + Mais com TV/Playbooks/atalhos; agente sem time → 7; agente no time recepção → 4 + "Chegou cliente" abre o painel; Ctrl K e clique em Buscar abrem a busca; lápis abre nova conversa; menu do perfil mostra o papel; celular: abrir/fechar menu; tema escuro preto + azul; contadores).
- [ ] Push pelo Eduardo (`!`), PR `feat(menu): menu único por papel (redesign v2, onda 2)` com descrição pt-BR + "Como testar", CI verde, squash, deploy (sem migração), conferir label da imagem na VPS, `/app/login` 200.

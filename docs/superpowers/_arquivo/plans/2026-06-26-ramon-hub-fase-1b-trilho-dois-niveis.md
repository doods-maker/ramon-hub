# Ramon Hub — Fase 1B: Trilho de dois níveis + Externos gerenciáveis — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) ou superpowers:executing-plans para implementar tarefa-a-tarefa. Steps usam checkbox (`- [ ]`).

**Goal:** Entregar o trilho do design-ref: um **rail externo (~78px)** que troca o mundo **Conversas ⇄ Intranet** (cada mundo com sua sidebar secundária), com **INTERNOS** (Conversas, Intranet) e **EXTERNOS** (atalhos que o usuário adiciona/remove) + avatar/configurações no rodapé.

**Architecture:** Novo `WorldRail.vue` (78px) injetado no `div.flex` raiz do `Dashboard.vue`, **antes** da sidebar. O mundo é detectado por `route.meta.world`: em Conversas mostra a `NextSidebar` atual; em Intranet mostra uma `IntranetSidebar.vue` nova. Os atalhos externos vivem em `user.ui_settings.external_shortcuts` (via `useUISettings`, **sem backend novo**) e são geridos por uma tela `ExternalShortcuts.vue`. Edição de core mínima: `Dashboard.vue` + `meta` em `ramon.routes.js` + remover o item provisório da 1A no `Sidebar.vue`. Componentes novos em `routes/dashboard/ramon/`.

**Tech Stack:** Vue 3.5 (script setup + Options API no Dashboard.vue) / Vue Router (`route.meta`) / Vuex (`ui_settings` via `useUISettings`) / Tailwind (classes `n-*` do design system).

## Global Constraints

- **Pré-requisito:** Fase 1A no ar (marca bronze + dark default + seção `ramon`/`ramon_index`). Incorporar aqui qualquer achado do smoke da 1A (loader de i18n, calibração de cor).
- **Marca:** escuro+bronze, sem segunda cor; títulos em `font-cormorant`; sem emoji.
- **Persistência dos externos:** `user.ui_settings.external_shortcuts` = `[{ label, url, icon }]`. Gravar com `updateUISettings({ external_shortcuts })`. **Nenhuma alteração de backend** (o `ui_settings: {}` em `profiles_controller.rb:68` já aceita arrays — comprovado por `conversation_sidebar_items_order`).
- **Disciplina de fork:** novos arquivos em `ramon/`; editar core só em pontos de registro → `docs/FORK-PONTOS-DE-REGISTRO.md`. Nunca tocar `enterprise/`.
- **Aprovação (banca):** Claude redige; **commit/push/deploy do Eduardo** ([Eduardo]).
- **Verificação:** build via Actions/GHCR (pega erro de JS/Vue) + deploy VPS + smoke visual.
- **Defaults de externos:** AdvBox, Google Agenda, Google Drive (URLs a confirmar).

---

### Task 1B.1: IntranetSidebar.vue (sidebar secundária do mundo Intranet)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue`
- Modify: `en/ramon.json` + `pt_BR/ramon.json` (bloco `NAV`)

**Interfaces:**
- Consumes: `accountScopedRoute` (`useAccount`), rota `ramon_index` (1A).
- Produces: `<IntranetSidebar>` para o `v-else` do Dashboard.vue (Task 1B.3).

- [ ] **Step 1: Criar `IntranetSidebar.vue`**
```vue
<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const sections = computed(() => [
  {
    label: t('RAMON.NAV.COMERCIAL'),
    items: [
      { key: 'overview', label: t('RAMON.NAV.OVERVIEW'), icon: 'i-lucide-layout-dashboard', to: accountScopedRoute('ramon_index') },
      { key: 'funil', label: t('RAMON.NAV.FUNIL'), icon: 'i-lucide-filter', soon: true },
      { key: 'sdr', label: t('RAMON.NAV.SDR'), icon: 'i-lucide-phone', soon: true },
    ],
  },
  {
    label: t('RAMON.NAV.JURIDICO'),
    items: [{ key: 'triagem', label: t('RAMON.NAV.TRIAGEM'), icon: 'i-lucide-gavel', soon: true }],
  },
  {
    label: t('RAMON.NAV.INTELIGENCIA'),
    items: [{ key: 'agentes', label: t('RAMON.NAV.AGENTES'), icon: 'i-lucide-bot', soon: true }],
  },
]);
</script>

<template>
  <aside class="flex flex-col flex-shrink-0 w-[220px] h-full py-3 overflow-y-auto bg-n-solid-1 border-r border-n-weak">
    <h2 class="px-4 mb-4 text-xl font-cormorant text-n-slate-12">{{ t('RAMON.NAV.TITLE') }}</h2>
    <template v-for="section in sections" :key="section.label">
      <p class="px-4 pt-3 pb-1 text-[10px] tracking-widest uppercase text-n-slate-9">{{ section.label }}</p>
      <nav class="flex flex-col gap-0.5 px-2">
        <component
          :is="item.soon ? 'div' : 'router-link'"
          v-for="item in section.items"
          :key="item.key"
          :to="item.soon ? undefined : item.to"
          :title="item.label"
          class="flex items-center h-8 gap-2 px-2 text-sm rounded-lg"
          :class="item.soon ? 'text-n-slate-9 cursor-default' : 'text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'"
        >
          <span :class="item.icon" class="flex-shrink-0 size-4" />
          <span class="truncate">{{ item.label }}</span>
          <span v-if="item.soon" class="ml-auto text-[9px] uppercase text-n-slate-9">{{ t('RAMON.NAV.SOON') }}</span>
        </component>
      </nav>
    </template>
  </aside>
</template>
```

- [ ] **Step 2: i18n — bloco `NAV` em `en/ramon.json` e `pt_BR/ramon.json`**

Adicionar dentro de `"RAMON": { ... }` (ao lado de `OVERVIEW`):
`en`:
```json
    "NAV": {
      "TITLE": "Intranet", "SOON": "soon",
      "COMERCIAL": "Commercial", "JURIDICO": "Legal", "INTELIGENCIA": "Intelligence",
      "OVERVIEW": "Command Center", "FUNIL": "Pipeline", "SDR": "SDR Panel",
      "TRIAGEM": "Case Intake", "AGENTES": "AI Agents"
    }
```
`pt_BR`:
```json
    "NAV": {
      "TITLE": "Intranet", "SOON": "em breve",
      "COMERCIAL": "Comercial", "JURIDICO": "Jurídico", "INTELIGENCIA": "Inteligência",
      "OVERVIEW": "Centro de Comando", "FUNIL": "Funil de Leads", "SDR": "Painel do SDR",
      "TRIAGEM": "Triagem de Iniciais", "AGENTES": "Agentes de IA"
    }
```

- [ ] **Step 3: Registrar novo no FORK-PONTOS** e **commit [Eduardo]**
```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue app/javascript/dashboard/i18n/locale/ docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat(ramon): sidebar secundaria do mundo Intranet"
```

---

### Task 1B.2: WorldRail.vue (rail externo de 78px)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/WorldRail.vue`
- Modify: `en/ramon.json` + `pt_BR/ramon.json` (bloco `RAIL`)

**Interfaces:**
- Consumes: `useRoute`, `useAccount` (`accountScopedRoute`), `useUISettings` (`uiSettings.external_shortcuts`), `SidebarProfileMenu` (`next/sidebar/SidebarProfileMenu.vue`), rotas `home` e `ramon_index`.
- Produces: `<WorldRail>` para o Dashboard.vue (Task 1B.3).

- [ ] **Step 1: Criar `WorldRail.vue`**
```vue
<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import SidebarProfileMenu from 'next/sidebar/SidebarProfileMenu.vue';

const { t } = useI18n();
const route = useRoute();
const { accountScopedRoute } = useAccount();
const { uiSettings } = useUISettings();

const isIntranet = computed(() => route.meta?.world === 'intranet');
const shortcuts = computed(() => uiSettings.value.external_shortcuts || []);

const worlds = computed(() => [
  { key: 'conversas', label: t('RAMON.RAIL.CONVERSAS'), icon: 'i-lucide-messages-square', to: accountScopedRoute('home'), active: !isIntranet.value },
  { key: 'intranet', label: t('RAMON.RAIL.INTRANET'), icon: 'i-lucide-layout-dashboard', to: accountScopedRoute('ramon_index'), active: isIntranet.value },
]);
</script>

<template>
  <aside class="flex flex-col items-center flex-shrink-0 h-full py-3 w-[78px] bg-n-background border-r border-n-weak">
    <span class="mb-4 i-lucide-scale size-6 text-n-iris-11" />

    <p class="mb-1 text-[9px] tracking-widest uppercase text-n-slate-9">{{ t('RAMON.RAIL.INTERNOS') }}</p>
    <nav class="flex flex-col items-center w-full gap-1">
      <router-link
        v-for="w in worlds"
        :key="w.key"
        :to="w.to"
        :title="w.label"
        class="flex flex-col items-center justify-center gap-1 rounded-xl w-14 h-14 text-n-slate-11 hover:bg-n-alpha-2"
        :class="{ 'bg-n-alpha-2 text-n-slate-12': w.active }"
      >
        <span :class="w.icon" class="size-5" />
        <span class="text-[9px] leading-none">{{ w.label }}</span>
      </router-link>
    </nav>

    <template v-if="shortcuts.length">
      <p class="mt-4 mb-1 text-[9px] tracking-widest uppercase text-n-slate-9">{{ t('RAMON.RAIL.EXTERNOS') }}</p>
      <nav class="flex flex-col items-center w-full gap-1">
        <a
          v-for="s in shortcuts"
          :key="s.url"
          :href="s.url"
          target="_blank"
          rel="noopener noreferrer"
          :title="s.label"
          class="flex items-center justify-center rounded-xl w-14 h-11 text-n-slate-11 hover:bg-n-alpha-2"
        >
          <span :class="s.icon || 'i-lucide-external-link'" class="size-5" />
        </a>
      </nav>
    </template>

    <router-link
      :to="accountScopedRoute('ramon_external_shortcuts')"
      :title="t('RAMON.RAIL.MANAGE')"
      class="flex items-center justify-center mt-2 rounded-xl w-14 h-9 text-n-slate-9 hover:bg-n-alpha-2 hover:text-n-slate-11"
    >
      <span class="i-lucide-plus size-4" />
    </router-link>

    <div class="mt-auto">
      <SidebarProfileMenu :is-collapsed="true" />
    </div>
  </aside>
</template>
```

- [ ] **Step 2: i18n — bloco `RAIL`** (em ambos os `ramon.json`, dentro de `"RAMON"`)
`en`: `"RAIL": { "INTERNOS": "Internal", "EXTERNOS": "External", "CONVERSAS": "Chats", "INTRANET": "Intranet", "MANAGE": "Manage shortcuts" }`
`pt_BR`: `"RAIL": { "INTERNOS": "Internos", "EXTERNOS": "Externos", "CONVERSAS": "Conversas", "INTRANET": "Intranet", "MANAGE": "Gerenciar atalhos" }`

- [ ] **Step 3: Registrar novo no FORK-PONTOS** e **commit [Eduardo]**
```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/WorldRail.vue app/javascript/dashboard/i18n/locale/ docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat(ramon): rail externo de 78px (mundos + externos + perfil)"
```

> ⚠️ Smoke: confirmar que `SidebarProfileMenu` monta fora da `<aside>` original sem erro de contexto. Se reclamar de provider, substituir por um avatar simples + link de logout.

---

### Task 1B.3: Integrar o trilho no Dashboard.vue + marcar o mundo na rota

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/Dashboard.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` (meta `world`)
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (remover item provisório da 1A)
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:** consome `WorldRail` (1B.2) e `IntranetSidebar` (1B.1).

- [ ] **Step 1: Marcar o mundo na rota** — em `ramon.routes.js`, no `meta`:
```js
        meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
```
(aplicar também ao `ramon_external_shortcuts` na Task 1B.4)

- [ ] **Step 2: Dashboard.vue — imports** (junto aos outros):
```js
import WorldRail from './ramon/components/WorldRail.vue';
import IntranetSidebar from './ramon/components/IntranetSidebar.vue';
```

- [ ] **Step 3: Dashboard.vue — computed `isIntranetWorld`** (na seção `computed`):
```js
    isIntranetWorld() {
      return this.$route.meta?.world === 'intranet';
    },
```

- [ ] **Step 4: Dashboard.vue — template** (no `div.flex` raiz, linha ~133): adicionar o rail e alternar a sidebar:
```html
      <div class="flex flex-grow overflow-hidden text-n-slate-12">
        <WorldRail />
        <NextSidebar
          v-if="!isIntranetWorld"
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle-account-modal="toggleAccountModal"
          @open-key-shortcut-modal="toggleKeyShortcutModal"
          @close-key-shortcut-modal="closeKeyShortcutModal"
          @show-create-account-modal="openCreateAccountModal"
          @close-mobile-sidebar="closeMobileSidebar"
        />
        <IntranetSidebar v-else />
        <main ...> <!-- inalterado --> </main>
      </div>
```
*(Manter exatamente as props/eventos atuais do `<NextSidebar>`; só envolvê-lo com `v-if` e adicionar `WorldRail` antes + `IntranetSidebar` no `v-else`.)*

- [ ] **Step 5: Remover o item provisório da 1A** em `Sidebar.vue` — apagar o objeto `{ name: 'Ramon', ... activeOn: ['ramon_index'] }` adicionado no topo do `menuItems` (agora o mundo é trocado pelo rail). Manter a chave `SIDEBAR.RAMON` no settings.json (inofensiva) ou removê-la.

- [ ] **Step 6: Atualizar FORK-PONTOS** (Dashboard.vue editado; nota de que o item da 1A no Sidebar.vue foi revertido) e **commit [Eduardo]**
```bash
git add app/javascript/dashboard/routes/dashboard/Dashboard.vue app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js app/javascript/dashboard/components-next/sidebar/Sidebar.vue docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat(ramon): trilho de dois niveis no Dashboard (WorldRail + IntranetSidebar)"
```

---

### Task 1B.4: Externos gerenciáveis (ui_settings) + tela de gestão

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/ExternalShortcuts.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` (rota `ramon_external_shortcuts`)
- Modify: `en/ramon.json` + `pt_BR/ramon.json` (bloco `SHORTCUTS`)
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:** consome `useUISettings` (`uiSettings`/`updateUISettings`), `Input`/`Button` de `components-next/`.

- [ ] **Step 1: Criar `ExternalShortcuts.vue`**
```vue
<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const DEFAULTS = [
  { label: 'AdvBox', url: 'https://app.advbox.com.br', icon: 'i-lucide-scale' },
  { label: 'Google Agenda', url: 'https://calendar.google.com', icon: 'i-lucide-calendar' },
  { label: 'Google Drive', url: 'https://drive.google.com', icon: 'i-lucide-folder' },
];

const shortcuts = ref([]);
watch(
  uiSettings,
  v => { shortcuts.value = v.external_shortcuts ?? DEFAULTS.slice(); },
  { immediate: true }
);

const draft = ref({ label: '', url: '', icon: 'i-lucide-external-link' });

const persist = () => updateUISettings({ external_shortcuts: shortcuts.value });

const add = () => {
  if (!draft.value.label || !draft.value.url) return;
  shortcuts.value.push({ ...draft.value });
  draft.value = { label: '', url: '', icon: 'i-lucide-external-link' };
  persist();
};
const remove = i => { shortcuts.value.splice(i, 1); persist(); };
</script>

<template>
  <div class="flex flex-col w-full h-full p-8 overflow-auto bg-n-background">
    <h1 class="mb-6 text-2xl font-cormorant text-n-slate-12">{{ t('RAMON.SHORTCUTS.TITLE') }}</h1>

    <ul class="flex flex-col gap-2 mb-6 max-w-xl">
      <li v-for="(s, i) in shortcuts" :key="i" class="flex items-center gap-3 p-3 border rounded-lg border-n-weak bg-n-solid-1">
        <span :class="s.icon || 'i-lucide-external-link'" class="size-4 text-n-slate-11" />
        <span class="font-medium text-n-slate-12">{{ s.label }}</span>
        <span class="text-sm truncate text-n-slate-9">{{ s.url }}</span>
        <Button class="ml-auto" icon="Trash2" color="ruby" variant="ghost" size="sm" @click="remove(i)" />
      </li>
    </ul>

    <div class="flex flex-col gap-3 max-w-xl p-4 border rounded-lg border-n-weak">
      <Input v-model="draft.label" :label="t('RAMON.SHORTCUTS.LABEL')" :placeholder="t('RAMON.SHORTCUTS.LABEL_PH')" />
      <Input v-model="draft.url" :label="t('RAMON.SHORTCUTS.URL')" placeholder="https://..." />
      <Input v-model="draft.icon" :label="t('RAMON.SHORTCUTS.ICON')" placeholder="i-lucide-..." />
      <Button :label="t('RAMON.SHORTCUTS.ADD')" icon="Plus" class="self-start" @click="add" />
    </div>
  </div>
</template>
```

- [ ] **Step 2: Rota `ramon_external_shortcuts`** — em `ramon.routes.js`, adicionar como segundo child:
```js
      {
        path: 'atalhos',
        name: 'ramon_external_shortcuts',
        component: () => import('./pages/ExternalShortcuts.vue'),
        meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
      },
```

- [ ] **Step 3: i18n — bloco `SHORTCUTS`** (em ambos `ramon.json`, dentro de `"RAMON"`)
`en`: `"SHORTCUTS": { "TITLE": "External shortcuts", "LABEL": "Name", "LABEL_PH": "AdvBox", "URL": "URL", "ICON": "Icon (Lucide)", "ADD": "Add" }`
`pt_BR`: `"SHORTCUTS": { "TITLE": "Atalhos externos", "LABEL": "Nome", "LABEL_PH": "AdvBox", "URL": "URL", "ICON": "Ícone (Lucide)", "ADD": "Adicionar" }`

- [ ] **Step 4: Verificar JSONs** (`node -e ...JSON.parse...` nos dois `ramon.json`) → `JSON_OK`. Registrar no FORK-PONTOS e **commit [Eduardo]**
```bash
git add app/javascript/dashboard/routes/dashboard/ramon/ app/javascript/dashboard/i18n/locale/ docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat(ramon): atalhos externos geridos pelo usuario (ui_settings)"
```

> Nota: os DEFAULTS só aparecem até o usuário salvar a 1ª vez; a partir daí vale o que está em `ui_settings.external_shortcuts`. URLs reais a confirmar com o Eduardo.

---

### Task 1B.5: Build, deploy e smoke visual [Eduardo]

- [ ] **Step 1:** `git push origin ramon` → `gh run watch -R doods-maker/ramon-hub` (build **success**).
- [ ] **Step 2:** deploy VPS (`docker compose pull/up -d chatwoot-web chatwoot-worker`).
- [ ] **Step 3: Smoke:**
  - Rail de 78px à esquerda com **INTERNOS** (Conversas, Intranet) e **EXTERNOS** (AdvBox/Agenda/Drive) + avatar no rodapé.
  - Clicar **Conversas** → sidebar do Chatwoot + atendimento; clicar **Intranet** → **IntranetSidebar** (COMERCIAL/JURÍDICO/INTELIGÊNCIA, "em breve" nos não-prontos) + Centro de Comando.
  - Atalhos externos abrem em nova aba.
  - Tela **Gerenciar atalhos** (botão `+` no rail): adicionar/remover persiste (recarregar a página mantém).
- [ ] **Step 4:** rollback via `.bak` se preciso.

---

## Self-Review

**Spec coverage (1B):**
- rail 78px com mundos Conversas/Intranet → Tasks 1B.2 + 1B.3 ✓
- sidebar secundária por modo → 1B.1 (Intranet) + NextSidebar existente (Conversas) ✓
- INTERNOS/EXTERNOS no rail → 1B.2 ✓
- externos gerenciáveis pelo usuário + persistência → 1B.4 (ui_settings, sem backend) ✓
- avatar/configurações no rail → 1B.2 (SidebarProfileMenu) ✓

**Consistência:** `route.meta.world==='intranet'` setado em `ramon.routes.js` (1B.3/1B.4) ↔ lido em `WorldRail` (1B.2) e `Dashboard.isIntranetWorld` (1B.3) ✓; `ramon_external_shortcuts` (1B.4) ↔ link no `WorldRail` (1B.2) ✓; `external_shortcuts` gravado (1B.4) ↔ lido no rail (1B.2) ✓.

**Abertos (calibrar no smoke):** `SidebarProfileMenu` fora do contexto da sidebar (fallback = avatar simples); largura/aparência do rail vs design-ref; ícones Lucide dos defaults; reaproveitar achados do smoke da 1A (loader i18n, cor).

---

*Próximo após 1B: Fase 2 — Funil/Kanban com o `Lead` nativo no Postgres da VPS.*

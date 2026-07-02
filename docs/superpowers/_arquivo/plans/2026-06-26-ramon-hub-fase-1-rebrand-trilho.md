# Ramon Hub — Fase 1: Rebrand + Trilho (Conversas / Intranet / Externos) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao fork a **cara da banca** — escuro+bronze por padrão (com tema claro creme/bronze opcional), fonte Cormorant nos títulos, logo/nome do escritório — e um **trilho com dois mundos**: INTERNOS (Conversas + Intranet) e EXTERNOS (atalhos configuráveis em nova aba), com a Intranet abrindo o Centro de Comando.

**Architecture:** Rebrand por **sobreposição fork-safe** (`_ramon-brand.scss` remapeia os tokens do `.dark` e do `:root` depois do core → vence por ordem de import). Default dark = 1 linha no `themeHelper.js`. A Intranet entra como **seção de rotas nova** (`routes/dashboard/ramon/`). O trilho ganha rótulos INTERNOS/EXTERNOS e links externos **só editando o `Sidebar.vue`** (sem tocar `SidebarGroup*`), com a lista de externos num arquivo de config novo. Todo edit de core é registrado em `docs/FORK-PONTOS-DE-REGISTRO.md`.

**Tech Stack:** Vue 3.5 / Vite 6 / Tailwind 3.4 (`darkMode: 'class'`) / SCSS custom properties / Vue Router / vue-i18n 9.

## Global Constraints

- **Marca (spec §5):** escuro + **bronze**, **sem segunda cor**. Acento `#c4a882`, primária `#754d2a`, hover `#5c3c22`, fundo `#120d09`, sidebar `#15100b`, card `#1f1812`, texto sobre escuro `#ede0c8`. Tema claro = paleta creme/bronze (fundo `#faf3e8`, card `#f5e6cc`, texto `#2a1d12`, acento `#754d2a`). Prioridade "Alta" = bronze, nunca vermelho. Sem emoji institucional.
- **Tipografia:** **Cormorant Garamond** para títulos/números; **Inter** no corpo (padrão).
- **Default = dark**, com toggle para claro preservado.
- **Disciplina de fork:** novos arquivos preferidos; todo edit de upstream entra na tabela "core editados" de `docs/FORK-PONTOS-DE-REGISTRO.md`. Nunca tocar `enterprise/`.
- **Aprovação (banca):** Claude redige; **commit/push/deploy do Eduardo** (passos [Eduardo]).
- **Verificação:** sem suíte visual nem staging → cada tarefa valida por **build (Actions/GHCR) + deploy na VPS + conferência visual** (rollback via `.bak`).
- **Base:** Chatwoot v4.15.1, branch `ramon`.

## Nota de fidelidade (adaptação consciente)

O design-ref desenha um **rail fixo de ~78px + sidebar secundária por modo**. O Chatwoot usa **uma sidebar redimensionável (56–200px) com grupos colapsáveis**. Nesta fase reproduzimos a **função** do design-ref (separação clara Conversas/Intranet + atalhos externos + marca) sobre a sidebar existente rebrandizada — **não** reconstruímos o modelo de dois níveis. A fidelidade pixel-a-pixel do rail de 78px fica como refinamento futuro, se valer a pena. Externos: as URLs entram num config (`ramonExternalLinks`) — **confirmar as URLs reais com o Eduardo**.

---

### Task 1.1: Cores — bronze no escuro + paleta clara da marca

**Files:**
- Create: `app/javascript/dashboard/assets/scss/_ramon-brand.scss`
- Modify: `app/javascript/dashboard/assets/scss/_woot.scss:10` (1 `@import` após `next-colors`)
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Consumes: tokens do core em `_next-colors.scss` (`:root` light linhas 4–154; `.dark` linhas 156–306).
- Produces: os mesmos tokens em bronze (escuro) e creme/bronze (claro), vencendo por ordem de import.

- [ ] **Step 1: Criar `_ramon-brand.scss`**

```scss
// Marca Ramon Antonio — override dos tokens do design system (vence _next-colors por ordem de @import).
// RGB sem vírgula (Tailwind: rgb(var(--token) / <alpha-value>)). Valores iniciais do design-ref/_ds; calibrar no smoke.
@import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@500;600;700&display=swap');

/* ===== Tema CLARO (default :root) — paleta creme/bronze ===== */
:root {
  --iris-9: 117 77 42;       // #754d2a acento/primária
  --iris-10: 100 64 32;      // hover
  --iris-11: 117 77 42;      // texto/ícone de acento
  --iris-12: 42 29 18;       // #2a1d12 texto alto contraste
  --background-color: 250 243 232;  // #faf3e8
  --surface-1: 255 255 255;
  --surface-2: 255 255 255;
  --card-color: 245 230 204;        // #f5e6cc
}

/* ===== Tema ESCURO (.dark — default do app) — bronze sobre quase-preto ===== */
.dark {
  --iris-1: 20 14 10;
  --iris-2: 26 19 13;
  --iris-3: 38 27 17;
  --iris-4: 48 33 20;
  --iris-5: 59 40 24;
  --iris-6: 74 50 30;
  --iris-7: 92 62 37;
  --iris-8: 117 79 47;
  --iris-9: 117 77 42;      // #754d2a primária (botões)
  --iris-10: 92 60 34;      // #5c3c22 hover
  --iris-11: 196 168 130;   // #c4a882 acento (ícones/links/ativo)
  --iris-12: 237 224 200;   // #ede0c8 texto alto contraste
  --solid-iris: 59 32 16;   // #3b2010
  --background-color: 18 13 9;  // #120d09 app
  --surface-1: 21 16 11;        // #15100b sidebar
  --surface-2: 24 18 13;
  --card-color: 31 24 18;       // #1f1812 cards
  --button-color: 48 32 18;
}
```

- [ ] **Step 2: Importar depois do core em `_woot.scss`**

Em `app/javascript/dashboard/assets/scss/_woot.scss`, após a linha 10 (`@import 'next-colors';`):
```scss
@import 'next-colors';
@import 'ramon-brand';   // marca Ramon Antonio (DEVE vir depois)
```

- [ ] **Step 3: Registrar no FORK-PONTOS**
```markdown
| `app/javascript/dashboard/assets/scss/_woot.scss` | +1 `@import 'ramon-brand'` após `next-colors` | rebrand fork-safe | 1 |
```
(e o `_ramon-brand.scss` na tabela de novos)

- [ ] **Step 4: Verificar que o SCSS compila isolado**
Run (raiz do fork): `pnpm exec sass app/javascript/dashboard/assets/scss/_ramon-brand.scss /dev/null`
Expected: sem erro. (Visual = Task 1.7.)

- [ ] **Step 5: Commit [Eduardo]**
```bash
git add app/javascript/dashboard/assets/scss/_ramon-brand.scss app/javascript/dashboard/assets/scss/_woot.scss docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat(ramon): rebrand bronze (dark default) + tema claro da marca"
```

---

### Task 1.2: Default dark (mantendo o toggle)

**Files:**
- Modify: `app/javascript/dashboard/helper/themeHelper.js:6`
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Consumes: `LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME)`.
- Produces: tema **dark** quando o usuário ainda não escolheu (toggle continua gravando 'light'/'auto').

- [ ] **Step 1: Trocar o default**

Em `app/javascript/dashboard/helper/themeHelper.js` linha 6:
```js
// de:
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';
// para:
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'dark';
```

- [ ] **Step 2: Registrar no FORK-PONTOS**
```markdown
| `app/javascript/dashboard/helper/themeHelper.js` | default `'auto'` → `'dark'` (linha 6) | marca é dark por padrão | 1 |
```

- [ ] **Step 3: Commit [Eduardo]**
```bash
git add app/javascript/dashboard/helper/themeHelper.js docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat(ramon): tema dark como padrao"
```

---

### Task 1.3: Fonte Cormorant Garamond nos títulos

**Files:**
- Modify: `tailwind.config.js` (`theme.fontFamily`, ~linha 44)
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

*(O `@font-face`/`@import` da fonte já entra no `_ramon-brand.scss` na Task 1.1 Step 1.)*

**Interfaces:**
- Consumes: `theme.fontFamily` (linhas 41–45: `sans`, `inter`, `interDisplay`).
- Produces: utilitário `font-cormorant`.

- [ ] **Step 1: Registrar `cormorant` no Tailwind**

Em `tailwind.config.js`, dentro de `theme.fontFamily` (após `interDisplay`):
```js
  cormorant: ['"Cormorant Garamond"', 'Georgia', 'serif'],
```

- [ ] **Step 2: Registrar no FORK-PONTOS**
```markdown
| `tailwind.config.js` | +chave `cormorant` em `theme.fontFamily` | fonte de títulos | 1 |
```

- [ ] **Step 3: Verificar**
Run: `node -e "console.log(require('./tailwind.config.js').theme.fontFamily.cormorant)"`
Expected: `[ '"Cormorant Garamond"', 'Georgia', 'serif' ]`

- [ ] **Step 4: Commit [Eduardo]**
```bash
git add tailwind.config.js docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat(ramon): fonte Cormorant Garamond nos titulos"
```

---

### Task 1.4: Logo e nome do escritório

**Files:**
- Replace: `public/brand-assets/logo.svg`, `logo_dark.svg`, `logo_thumbnail.svg`
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:** consome `globalConfig.logo/logoDark/logoThumbnail/installationName`.

- [ ] **Step 1: Trocar os SVGs (mesmos nomes)** — fonte: `intranet-ramon/design-ref/assets/logo-full.jpeg` e `monogram.png` (exportar SVG):
  - `public/brand-assets/logo.svg`, `logo_dark.svg`, `logo_thumbnail.svg` (monograma).
- [ ] **Step 2 [Eduardo]: Super Admin (runtime, sem deploy)** em `/super_admin/installation_configs`:
  `INSTALLATION_NAME`→`Ramon Antonio` · `BRAND_NAME`→`Ramon Antonio Advogados` · `BRAND_URL`→`https://ramonantonio.adv.br`
- [ ] **Step 3: Registrar no FORK-PONTOS** (`public/brand-assets/logo*.svg`) e **commit [Eduardo]**
```bash
git add public/brand-assets/logo.svg public/brand-assets/logo_dark.svg public/brand-assets/logo_thumbnail.svg docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat(ramon): logos do escritorio"
```

---

### Task 1.5: Seção Intranet — rotas + Centro de Comando (shell)

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/RamonOverview.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Consumes: `frontendURL`, `AppContainer` (`Dashboard.vue`) + seu `<router-view>`.
- Produces: rota nomeada **`ramon_index`** (`accounts/:accountId/ramon`) — usada na Task 1.6.

- [ ] **Step 1: Criar `RamonOverview.vue`**
```vue
<script setup>
import { useI18n } from 'vue-i18n';
const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background p-8">
    <header class="mb-8">
      <p class="text-xs tracking-[0.2em] uppercase text-n-slate-11">
        {{ t('RAMON.OVERVIEW.EYEBROW') }}
      </p>
      <h1 class="font-cormorant text-4xl font-semibold text-n-slate-12">
        {{ t('RAMON.OVERVIEW.TITLE') }}
      </h1>
    </header>
    <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
      <div
        v-for="kpi in ['LEADS', 'REUNIOES', 'FECHAMENTOS']"
        :key="kpi"
        class="p-6 border rounded-xl border-n-weak bg-n-solid-2"
      >
        <p class="text-xs tracking-wide uppercase text-n-slate-11">
          {{ t(`RAMON.OVERVIEW.KPI.${kpi}`) }}
        </p>
        <p class="mt-2 font-cormorant text-3xl text-n-slate-12">—</p>
      </div>
    </div>
    <p class="mt-8 text-sm text-n-slate-11">{{ t('RAMON.OVERVIEW.PLACEHOLDER') }}</p>
  </div>
</template>
```

- [ ] **Step 2: Criar `ramon.routes.js`**
```js
import { frontendURL } from '../../../helper/URLHelper';
import RamonOverview from './pages/RamonOverview.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ramon'),
    component: RamonOverview,
    children: [
      {
        path: '',
        name: 'ramon_index',
        component: RamonOverview,
        meta: { permissions: ['administrator', 'agent'] },
      },
    ],
  },
];
```

- [ ] **Step 3: Registrar no índice de rotas** — em `dashboard.routes.js`:
```js
import { routes as ramonRoutes } from './ramon/ramon.routes';
```
e no array `children` do `AppContainer`:
```js
        ...campaignsRoutes.routes,
        ...ramonRoutes,
```

- [ ] **Step 4: Registrar no FORK-PONTOS** (`dashboard.routes.js` editado + 2 novos `ramon/`) e **commit [Eduardo]**
```bash
git add app/javascript/dashboard/routes/dashboard/ramon/ app/javascript/dashboard/routes/dashboard/dashboard.routes.js docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat(ramon): secao Intranet com Centro de Comando shell"
```

---

### Task 1.6: Trilho — Intranet + grupos INTERNOS/EXTERNOS + links externos + i18n

**Files:**
- Create: `app/javascript/dashboard/components-next/sidebar/ramon/externalLinks.js`
- Create: `app/javascript/dashboard/i18n/locale/en/ramon.json` + `pt_BR/ramon.json`
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (import + item no `menuItems` + bloco no template)
- Modify: `app/javascript/dashboard/i18n/locale/en/settings.json` + `pt_BR/settings.json` (chaves `SIDEBAR`)
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md`

**Interfaces:**
- Consumes: `accountScopedRoute` (já em `Sidebar.vue:45`), rota `ramon_index` (Task 1.5), `isEffectivelyCollapsed` (estado já usado no template).
- Produces: o trilho com os dois mundos.

- [ ] **Step 1: Criar o config de links externos**
`app/javascript/dashboard/components-next/sidebar/ramon/externalLinks.js`:
```js
// Atalhos EXTERNOS do trilho (abrem em nova aba). Editar aqui p/ adicionar/remover.
// ⚠️ Confirmar URLs reais com o Eduardo.
export const ramonExternalLinks = [
  { name: 'advbox', label: 'AdvBox', icon: 'i-lucide-scale', href: 'https://app.advbox.com.br' },
  { name: 'meu-inss', label: 'Meu INSS', icon: 'i-lucide-landmark', href: 'https://meu.inss.gov.br' },
  { name: 'agenda', label: 'Google Agenda', icon: 'i-lucide-calendar', href: 'https://calendar.google.com' },
];
```

- [ ] **Step 2: `Sidebar.vue` — import + item Intranet no `menuItems`**

Junto aos imports do `<script setup>`:
```js
import { ramonExternalLinks } from './ramon/externalLinks';
```
Logo após o `return [` do `computed menuItems` (topo do array), inserir o rótulo e o item Intranet:
```js
    { type: 'section-label', label: t('SIDEBAR.RAMON_INTERNOS') },
    {
      name: 'Ramon',
      label: t('SIDEBAR.RAMON'),
      icon: 'i-lucide-layout-dashboard',
      to: accountScopedRoute('ramon_index'),
      activeOn: ['ramon_index'],
    },
```

- [ ] **Step 3: `Sidebar.vue` — template: rótulo de seção + bloco EXTERNOS**

Trocar o loop atual (linhas ~954–958)
```html
<SidebarGroup v-for="item in menuItems" :key="item.name" v-bind="item" />
```
por:
```html
<template v-for="item in menuItems" :key="item.name ?? item.label">
  <li
    v-if="item.type === 'section-label'"
    class="px-2 pt-3 pb-0.5 text-xxs font-semibold uppercase tracking-widest text-n-slate-9 select-none"
    :class="{ 'sr-only': isEffectivelyCollapsed }"
  >
    {{ item.label }}
  </li>
  <SidebarGroup v-else v-bind="item" />
</template>

<li
  class="px-2 pt-3 pb-0.5 text-xxs font-semibold uppercase tracking-widest text-n-slate-9 select-none"
  :class="{ 'sr-only': isEffectivelyCollapsed }"
>
  {{ t('SIDEBAR.RAMON_EXTERNOS') }}
</li>
<li v-for="link in ramonExternalLinks" :key="link.name" class="list-none">
  <a
    :href="link.href"
    target="_blank"
    rel="noopener noreferrer"
    :title="link.label"
    class="flex items-center h-8 gap-2 px-2 py-1 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
  >
    <span :class="link.icon" class="flex-shrink-0 size-4" />
    <span v-if="!isEffectivelyCollapsed" class="truncate">{{ link.label }}</span>
  </a>
</li>
```
*(O `<ul>` que envolve o loop permanece; os `<li>` de externos entram dentro dele, logo após o `</template>`.)*

- [ ] **Step 4: i18n — chaves do trilho (en + pt_BR)**

Em `en/settings.json` dentro de `"SIDEBAR"`:
```json
    "RAMON": "Intranet",
    "RAMON_INTERNOS": "Internos",
    "RAMON_EXTERNOS": "Externos",
```
Em `pt_BR/settings.json` dentro de `"SIDEBAR"`:
```json
    "RAMON": "Intranet",
    "RAMON_INTERNOS": "Internos",
    "RAMON_EXTERNOS": "Externos",
```

- [ ] **Step 5: i18n — textos das telas `ramon` (en + pt_BR)**

`en/ramon.json`:
```json
{
  "RAMON": {
    "OVERVIEW": {
      "EYEBROW": "Command Center",
      "TITLE": "Overview",
      "PLACEHOLDER": "Modules will appear here as they are migrated.",
      "KPI": { "LEADS": "Leads", "REUNIOES": "Meetings", "FECHAMENTOS": "Closings" }
    }
  }
}
```
`pt_BR/ramon.json`:
```json
{
  "RAMON": {
    "OVERVIEW": {
      "EYEBROW": "Centro de Comando",
      "TITLE": "Visão Geral",
      "PLACEHOLDER": "Os módulos aparecerão aqui conforme forem migrados.",
      "KPI": { "LEADS": "Leads", "REUNIOES": "Reuniões", "FECHAMENTOS": "Fechamentos" }
    }
  }
}
```

- [ ] **Step 6: Verificar JSONs**
Run: `node -e "['en','pt_BR'].forEach(l=>JSON.parse(require('fs').readFileSync('app/javascript/dashboard/i18n/locale/'+l+'/ramon.json','utf8')));console.log('JSON ok')"`
Expected: `JSON ok`

- [ ] **Step 7: Registrar core editados no FORK-PONTOS** (`Sidebar.vue`, `en/settings.json`, `pt_BR/settings.json`) + novos (`ramon/externalLinks.js`, `*/ramon.json`) e **commit [Eduardo]**
```bash
git add app/javascript/dashboard/components-next/sidebar/ app/javascript/dashboard/i18n/locale/ docs/FORK-PONTOS-DE-REGISTRO.md
git commit -m "feat(ramon): trilho com Intranet, grupos Internos/Externos e atalhos"
```

> ⚠️ Verificar no smoke (1.7): (a) que o loader de locale carrega `ramon.json` novo — se não, mover o bloco `RAMON` para `settings.json`; (b) que os `<li>` de externos ficam dentro do `<ul>` correto e alinhados; calibrar espaçamento.

---

### Task 1.7: Build, deploy e smoke visual [Eduardo]

**Files:** nenhum (pipeline da Fase 0).

- [ ] **Step 1: Push (dispara o build)**
```bash
git push origin ramon
gh run watch -R doods-maker/ramon-hub
```
Expected: run **success**; nova imagem publicada.

- [ ] **Step 2: Deploy na VPS**
```bash
ssh -i ~/.ssh/id_ed25519 root@185.194.216.67
cd /opt/intranet-ramon
docker compose pull chatwoot-web chatwoot-worker
docker compose up -d chatwoot-web chatwoot-worker
```

- [ ] **Step 3: Smoke visual** (logar em `chat.ramonantonio.adv.br`):
- App abre **dark por padrão**; fundos escuros + acentos/ícones **bronze** (zero azul); botões bronze; títulos em **Cormorant**.
- Trocar para **claro** (command bar → Appearance) → paleta **creme/bronze** (não branco puro).
- Trilho: rótulo **INTERNOS** → Intranet + Conversas; rótulo **EXTERNOS** → AdvBox/Meu INSS/Agenda abrem em **nova aba**.
- Clicar **Intranet** → **Centro de Comando** (eyebrow + título "Visão Geral" + 3 KPIs placeholder).
- Conversas/atendimento intactos.

- [ ] **Step 4: Sobrou azul?** (telas legacy `woot-*`): anotar e tratar depois em `theme/colors.js` — não bloqueia.
- [ ] **Step 5: Rollback se preciso:** `cp docker-compose.yml.bak docker-compose.yml && docker compose up -d`.

---

## Self-Review

**Spec coverage (Fase 1, escopo ampliado):**
- rebrand bronze (dark) + tema claro da marca → Task 1.1 ✓
- default dark + toggle → Task 1.2 ✓
- fonte Cormorant → Tasks 1.1 (font load) + 1.3 (tailwind) ✓
- logo/nome → Task 1.4 ✓
- seção Intranet + Centro de Comando → Task 1.5 ✓
- trilho INTERNOS (Conversas+Intranet) / EXTERNOS (links configuráveis nova aba) → Task 1.6 ✓
- i18n en+pt_BR → Task 1.6 ✓

**Consistência:** rota `ramon_index` (1.5) ↔ `accountScopedRoute('ramon_index')`/`activeOn` (1.6) ✓; `font-cormorant` (1.3) ↔ uso em `RamonOverview.vue` (1.5) ✓; tokens `:root`/`.dark` (1.1) ↔ `darkMode:'class'` + `.dark` no body (1.2) ✓.

**Abertos (não bloqueiam, calibrar no smoke):** URLs reais dos externos; loader de `ramon.json`; escala bronze `--iris-1..8`; eventual azul em telas legacy; fidelidade do rail 78px (adiada por escolha consciente).

---

*Próximo passo após a Fase 1: Fase 2 (Funil/Kanban com o `Lead` nativo no Postgres da VPS).*

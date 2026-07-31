# BI "Relatórios" (Metabase no hub) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consertar e destrinchar a BI: faxina + correção do Metabase, dashboard novo "Análise Comercial" (13 cartões), e página "Relatórios" admin-only dentro do hub via static embedding.

**Architecture:** Tarefas 1–3 são ações de runtime contra a API do Metabase (`bi.ramonantonio.adv.br`, scripts Python no scratchpad — nada disso entra no repo). Tarefas 4–5 são código no fork (endpoint Rails que assina JWT + página Vue com iframe). Tarefas 6–7 são PR/deploy e configuração da VPS.

**Tech Stack:** Metabase v0.62.4 OSS (static embedding), Rails (gem `jwt` 2.10 já no Gemfile:92), Vue 3 `<script setup>`, Pundit policy.

**Spec:** `docs/superpowers/specs/2026-07-31-bi-relatorios-metabase-design.md`

## Global Constraints

- Conta única do hub: `account_id = 2`. TODA query de funil leva `source IS DISTINCT FROM 'calculo-advbox'` (semântica do scope `Lead.funil`, app/models/lead.rb:26-29).
- API key do Metabase (admin) em `C:\Users\dudsl\RAdvogados\conhecimento\metabase-credenciais.txt`; enviar no header `x-api-key`.
- Código do fork: SEMPRE em worktree (`ramon-hub-wt-bi`, branch `feat/ramon-bi-relatorios` a partir da `ramon` local — ela já contém a spec commitada). Worktree no Windows: `npx pnpm@10.2.0 install`; commits/push com `--no-verify`; erros eslint `Delete ␍` = CRLF local, ignorar.
- Sem teste Ruby local — RSpec valida no CI. Vitest e eslint RODAM local: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon` e `./node_modules/.bin/eslint <arquivos>` (NUNCA `pnpm eslint` — roda o repo inteiro).
- Commits Conventional (`feat:`/`fix:`/`docs:`), sem mencionar Claude no texto do commit do fork.
- i18n nos DOIS locales do fork: `pt_BR/ramon.json` e `en/ramon.json`.
- Scripts de runtime vão no scratchpad da sessão, não no repo.

---

### Task 1: Metabase — faxina + correção das 8 queries do Placar do Dono

**Files:** nenhum no repo. Script: `<scratchpad>\mb_faxina.py`.

**Interfaces — Produces:** Metabase sem coleção Examples; cards 40–47 com filtro de casos de cálculo.

- [ ] **Step 1: Escrever e rodar o script de faxina + correção**

```python
import json, urllib.request

BASE = 'https://bi.ramonantonio.adv.br/api'
KEY = 'mb_yCvMOczeqjlBi3E9du9z+uGL29DonAW/aK+WK1vI7Ik='

def api(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'x-api-key': KEY, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or 'null')

# 1. Arquivar dashboard sample e coleção Examples
api('PUT', '/dashboard/1', {'archived': True})
for col in api('GET', '/collection'):
    if col.get('name') == 'Examples' and not col.get('archived'):
        api('PUT', f"/collection/{col['id']}", {'archived': True})
        print('Examples arquivada, id', col['id'])

# 2. Corrigir cards 40-47: injetar filtro de casos de calculo
FILTRO = "source IS DISTINCT FROM 'calculo-advbox'"
for card_id in range(40, 48):
    card = api('GET', f'/card/{card_id}')
    dq = card['dataset_query']
    # formato novo (lib) ou legado — pegar a query nativa de onde estiver
    if 'stages' in dq:
        sql = dq['stages'][0]['native']
    else:
        sql = dq['native']['query']
    if 'calculo-advbox' in sql:
        print(card_id, 'ja corrigido'); continue
    alias = 'l.' if ' leads l ' in sql or ' leads l\n' in sql else ''
    # insere logo apos o WHERE (todas as 8 queries tem exatamente um WHERE)
    assert sql.count('WHERE') == 1, f'card {card_id}: WHERE ambiguo, corrigir na mao'
    novo = sql.replace('WHERE ', f'WHERE {alias}{FILTRO} AND ', 1)
    api('PUT', f'/card/{card_id}', {'dataset_query': {
        'type': 'native', 'database': 2, 'native': {'query': novo}}})
    print(card_id, 'corrigido')
```

Rodar: `python mb_faxina.py`. Esperado: `Examples arquivada` + 8 linhas `corrigido`/`ja corrigido`.

- [ ] **Step 2: Verificar** — para os cards 40 e 47, `GET /card/:id` e conferir que o SQL contém `calculo-advbox` (card 47 sem alias `l.`, os demais com). Abrir `https://bi.ramonantonio.adv.br/dashboard/2` via `GET /api/dashboard/2` e conferir que os 8 dashcards seguem lá (nada quebrou).

---

### Task 2: Metabase — dashboard "Análise Comercial" (13 cartões)

**Files:** nenhum no repo. Script: `<scratchpad>\mb_analise.py`.

**Interfaces — Produces:** dashboard novo; **anotar o `dashboard_id` impresso** — a Task 7 usa em `RAMON_METABASE_DASHBOARD_ID`.

- [ ] **Step 0: Conferir o nome da coluna de título de `theses`** — `Grep 'create_table "theses"' -A 12 db/schema.rb` no repo. Se a coluna de nome não for `name`, ajustar o SQL do cartão 9 antes de rodar.

- [ ] **Step 1: Escrever e rodar o script** (mesmo helper `api()` da Task 1):

```python
BASE_FILTRO = "l.account_id = 2 AND l.source IS DISTINCT FROM 'calculo-advbox'"
M12C = "l.created_at >= date_trunc('month', now()) - interval '11 months'"

CARDS = [
 # (nome, display, sql, descricao)
 ("Leads novos por mês (12m)", "line", f"""
SELECT date_trunc('month', l.created_at)::date AS mes, COUNT(*) AS leads
FROM leads l WHERE {BASE_FILTRO} AND {M12C}
GROUP BY 1 ORDER BY 1""", ""),

 ("Contratos e valor fechado por mês (12m)", "combo", f"""
SELECT date_trunc('month', l.won_at)::date AS mes, COUNT(*) AS contratos, COALESCE(SUM(l.value),0) AS valor
FROM leads l WHERE {BASE_FILTRO} AND l.won_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1""", ""),

 ("Conversão por mês de criação (12m)", "line", f"""
SELECT date_trunc('month', l.created_at)::date AS mes_de_criacao,
       ROUND(100.0 * COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) / COUNT(*), 1) AS conversao_pct
FROM leads l WHERE {BASE_FILTRO} AND {M12C}
GROUP BY 1 ORDER BY 1""",
 "Coorte: % dos leads criados no mês que já fecharam. Meses recentes ainda amadurecem."),

 ("Tempo médio lead → contrato (12m)", "line", f"""
SELECT date_trunc('month', l.won_at)::date AS mes,
       ROUND(AVG(EXTRACT(EPOCH FROM (l.won_at - l.created_at)) / 86400)::numeric, 1) AS dias_medios
FROM leads l WHERE {BASE_FILTRO} AND l.won_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1""", ""),

 ("Tempo médio em cada etapa (histórico)", "row", f"""
WITH passagens AS (
  SELECT la.to_value AS etapa, la.created_at,
         LEAD(la.created_at) OVER (PARTITION BY la.lead_id ORDER BY la.created_at) AS saiu_em
  FROM lead_activities la JOIN leads l ON l.id = la.lead_id
  WHERE la.account_id = 2 AND la.kind = 'stage_changed' AND l.source IS DISTINCT FROM 'calculo-advbox'
), entrada AS (
  SELECT 'Entrada (1ª etapa)' AS etapa, l.created_at, MIN(la.created_at) AS saiu_em
  FROM leads l LEFT JOIN lead_activities la ON la.lead_id = l.id AND la.kind = 'stage_changed'
  WHERE {BASE_FILTRO}
  GROUP BY l.id, l.created_at
)
SELECT etapa,
       ROUND(AVG(EXTRACT(EPOCH FROM (COALESCE(saiu_em, now()) - created_at)) / 86400)::numeric, 1) AS dias_medios,
       COUNT(*) AS passagens
FROM (SELECT * FROM passagens UNION ALL SELECT * FROM entrada) t
GROUP BY etapa ORDER BY dias_medios DESC""",
 "Aproximação pelo histórico de mudança de etapa (mesmo critério do Cockpit). Etapa renomeada mantém o nome antigo no histórico."),

 ("Transições de etapa (12m)", "table", f"""
SELECT la.from_value || ' → ' || la.to_value AS transicao, COUNT(*) AS vezes
FROM lead_activities la JOIN leads l ON l.id = la.lead_id
WHERE la.account_id = 2 AND la.kind = 'stage_changed' AND l.source IS DISTINCT FROM 'calculo-advbox'
  AND la.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY 2 DESC""", ""),

 ("Motivos de perda (12m)", "row", f"""
SELECT COALESCE(l.lost_reason, '(sem motivo)') AS motivo, COUNT(*) AS leads, COALESCE(SUM(l.value),0) AS valor_perdido
FROM leads l WHERE {BASE_FILTRO} AND l.lost_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY 2 DESC""", ""),

 ("Canal: leads, conversão e valor (12m)", "table", f"""
SELECT COALESCE(l.channel, 'outro') AS canal, COUNT(*) AS leads,
       COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) AS fechados,
       ROUND(100.0 * COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) / COUNT(*), 1) AS conversao_pct,
       COALESCE(SUM(l.value) FILTER (WHERE l.won_at IS NOT NULL), 0) AS valor_fechado
FROM leads l WHERE {BASE_FILTRO} AND l.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY leads DESC""", ""),

 ("Tese: leads, conversão e valor (12m)", "table", f"""
SELECT COALESCE(t.name, '(sem tese)') AS tese, COUNT(*) AS leads,
       COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) AS fechados,
       ROUND(100.0 * COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) / COUNT(*), 1) AS conversao_pct,
       COALESCE(SUM(l.value) FILTER (WHERE l.won_at IS NOT NULL), 0) AS valor_fechado
FROM leads l LEFT JOIN theses t ON t.id = l.thesis_id
WHERE {BASE_FILTRO} AND l.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY leads DESC""", ""),

 ("Campanha (UTM): leads e fechados (12m)", "table", f"""
SELECT l.custom_attributes #>> '{{utm,utm_campaign}}' AS campanha, COUNT(*) AS leads,
       COUNT(*) FILTER (WHERE l.won_at IS NOT NULL) AS fechados
FROM leads l
WHERE {BASE_FILTRO} AND l.custom_attributes #>> '{{utm,utm_campaign}}' IS NOT NULL
  AND l.created_at >= now() - interval '12 months'
GROUP BY 1 ORDER BY 2 DESC""",
 "Reentrada de lead já aberto não cria lead novo (vira atividade lp_recaptured) — retorno de campanha fica subestimado."),

 ("SLA de 1ª resposta por mês (12m)", "combo", f"""
SELECT date_trunc('month', c.created_at)::date AS mes,
       ROUND(AVG(EXTRACT(EPOCH FROM (c.first_reply_created_at - c.created_at)) / 60)::numeric, 1) AS minutos_medios,
       ROUND(100.0 * COUNT(*) FILTER (
         WHERE c.first_reply_created_at - c.created_at <= (COALESCE(i.first_response_sla_minutes, 15) || ' minutes')::interval
       ) / COUNT(*), 1) AS dentro_do_sla_pct
FROM leads l
JOIN conversations c ON c.id = l.conversation_id
JOIN inboxes i ON i.id = c.inbox_id
WHERE {BASE_FILTRO} AND c.first_reply_created_at IS NOT NULL
  AND c.created_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1""",
 "Tempo entre a criação da conversa e a 1ª resposta humana, só conversas de lead."),

 ("Reuniões: marcadas × realizadas (12m)", "bar", f"""
SELECT date_trunc('month', lt.due_at)::date AS mes, COUNT(*) AS marcadas, COUNT(lt.completed_at) AS realizadas
FROM lead_tasks lt JOIN leads l ON l.id = lt.lead_id
WHERE lt.account_id = 2 AND lt.kind = 'meeting' AND l.source IS DISTINCT FROM 'calculo-advbox'
  AND lt.due_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1 ORDER BY 1""",
 "Realizada = tarefa de reunião concluída."),

 ("Follow-ups feitos × contratos (12m)", "combo", f"""
SELECT mes, SUM(follow_ups) AS follow_ups, SUM(contratos) AS contratos FROM (
  SELECT date_trunc('month', lt.completed_at)::date AS mes, COUNT(*) AS follow_ups, 0 AS contratos
  FROM lead_tasks lt JOIN leads l ON l.id = lt.lead_id
  WHERE lt.account_id = 2 AND lt.kind = 'follow_up' AND lt.completed_at IS NOT NULL
    AND l.source IS DISTINCT FROM 'calculo-advbox'
    AND lt.completed_at >= date_trunc('month', now()) - interval '11 months'
  GROUP BY 1
  UNION ALL
  SELECT date_trunc('month', l.won_at)::date, 0, COUNT(*)
  FROM leads l WHERE {BASE_FILTRO} AND l.won_at >= date_trunc('month', now()) - interval '11 months'
  GROUP BY 1
) t GROUP BY mes ORDER BY mes""", ""),
]

col = api('POST', '/collection', {'name': 'Análise Comercial'})
card_ids = []
for nome, display, sql, desc in CARDS:
    c = api('POST', '/card', {
        'name': nome, 'display': display, 'collection_id': col['id'],
        'description': desc or None, 'visualization_settings': {},
        'dataset_query': {'type': 'native', 'database': 2, 'native': {'query': sql.strip()}}})
    card_ids.append(c['id']); print('card', c['id'], nome)

dash = api('POST', '/dashboard', {'name': 'Análise Comercial', 'collection_id': col['id'],
    'description': 'Tendência, funil profundo, origem/tese e atendimento. Janelas fixas por cartão.'})
# grade: 2 colunas de 12, cartões de 8 de altura, na ordem dos blocos
dashcards = []
for i, cid in enumerate(card_ids):
    dashcards.append({'id': -(i + 1), 'card_id': cid,
        'row': (i // 2) * 8, 'col': (i % 2) * 12, 'size_x': 12, 'size_y': 8})
api('PUT', f"/dashboard/{dash['id']}", {'dashcards': dashcards})
print('DASHBOARD_ID =', dash['id'])
```

Rodar: `python mb_analise.py`. Esperado: 13 linhas `card ...` + `DASHBOARD_ID = N`.

- [ ] **Step 2: Verificar cada cartão executa** — para cada id em `card_ids`: `POST /api/card/:id/query` e conferir `status == 'completed'` (dados podem ser vazios — meses sem evento — mas não pode haver erro de SQL). Qualquer erro: corrigir o SQL do cartão via `PUT /card/:id` e re-testar.

- [ ] **Step 3: Sanidade dos números** — comparar `Leads novos por mês` (mês atual) com o card 40 corrigido do Placar + total do Kanban informado na Task 7 (smoke). Registrar o `DASHBOARD_ID` no arquivo de credenciais (Task 3, Step 2).

---

### Task 3: Metabase — ligar static embedding

**Files:** Modify: `C:\Users\dudsl\RAdvogados\conhecimento\metabase-credenciais.txt` (fora do repo).

**Interfaces — Produces:** `EMBED_SECRET` (hex de 64) e `DASHBOARD_ID` — consumidos pela Task 7 (envs da VPS) e pela Task 4 (specs usam valores fake, não estes).

- [ ] **Step 1: Gerar secret e ligar embedding** (mesmo helper `api()`):

```python
import secrets
secret = secrets.token_hex(32)
api('PUT', '/setting/enable-embedding-static', {'value': True})
api('PUT', '/setting/embedding-secret-key', {'value': secret})
api('PUT', f'/dashboard/{DASHBOARD_ID}', {'enable_embedding': True, 'embedding_params': {}})
print('EMBED_SECRET =', secret)
```

- [ ] **Step 2: Anotar no arquivo de credenciais** — acrescentar ao `metabase-credenciais.txt`:

```
static embedding (31/07/2026):
  EMBED_SECRET: <valor impresso>
  dashboard "Análise Comercial": id <N> — https://bi.ramonantonio.adv.br/dashboard/<N>
```

- [ ] **Step 3: Provar o embed fora do hub** — gerar um token de teste e abrir a URL:

```python
# pip nao necessario: JWT HS256 na mao
import hmac, hashlib, base64, json, time
def b64(d): return base64.urlsafe_b64encode(d).rstrip(b'=')
h = b64(json.dumps({'alg': 'HS256', 'typ': 'JWT'}).encode())
p = b64(json.dumps({'resource': {'dashboard': DASHBOARD_ID}, 'params': {}, 'exp': int(time.time()) + 600}).encode())
sig = b64(hmac.new(secret.encode(), h + b'.' + p, hashlib.sha256).digest())
print(f"https://bi.ramonantonio.adv.br/embed/dashboard/{(h + b'.' + p + b'.' + sig).decode()}#theme=night&bordered=false&titled=false")
```

`curl -s -o NUL -w "%{http_code}"` na URL → esperado `200`.

---

### Task 4: Fork — endpoint `GET /api/v1/accounts/:id/ramon_relatorios` (admin-only, assina o JWT)

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_relatorios_controller.rb`
- Create: `app/policies/ramon_relatorio_policy.rb`
- Modify: `config/routes.rb` (seção ramon, junto de `resource :ramon_watchdog`, ~linha 307)
- Test: `spec/requests/api/v1/accounts/ramon_relatorios_spec.rb`

**Interfaces — Produces:** `GET .../ramon_relatorios` → `{ configured: false }` sem envs; `{ configured: true, url: "<site>/embed/dashboard/<jwt>#theme=night&bordered=false&titled=false" }` com envs. Consumido pela Task 5.

- [ ] **Step 1: Escrever a spec (falha primeiro no CI, valida na Task 6)**

```ruby
require 'rails_helper'

RSpec.describe 'Ramon Relatorios API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_relatorios" }
  let(:envs) do
    { 'RAMON_METABASE_SITE_URL' => 'https://bi.test', 'RAMON_METABASE_SECRET_KEY' => 'a' * 64,
      'RAMON_METABASE_DASHBOARD_ID' => '7' }
  end

  it 'exige autenticacao' do
    get url, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'barra agente (admin-only)' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve configured false sem envs' do
    with_modified_env('RAMON_METABASE_SITE_URL' => nil) do
      get url, headers: admin.create_new_auth_token, as: :json
    end
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['configured']).to be(false)
  end

  it 'devolve a url do embed com JWT valido' do
    with_modified_env(envs) do
      get url, headers: admin.create_new_auth_token, as: :json
    end
    body = response.parsed_body
    expect(body['configured']).to be(true)
    token = body['url'][%r{embed/dashboard/([^#]+)}, 1]
    payload, = JWT.decode(token, 'a' * 64, true, algorithm: 'HS256')
    expect(payload['resource']).to eq('dashboard' => 7)
    expect(body['url']).to start_with('https://bi.test/embed/dashboard/')
    expect(body['url']).to end_with('#theme=night&bordered=false&titled=false')
  end
end
```

- [ ] **Step 2: Policy**

```ruby
class RamonRelatorioPolicy < ApplicationPolicy
  def show? = @account_user.administrator?
end
```

(Padrão de `app/policies/triage_agent_policy.rb:11`.)

- [ ] **Step 3: Controller**

```ruby
class Api::V1::Accounts::RamonRelatoriosController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  EMBED_HASH = '#theme=night&bordered=false&titled=false'.freeze

  def show
    site_url = ENV.fetch('RAMON_METABASE_SITE_URL', nil)
    secret = ENV.fetch('RAMON_METABASE_SECRET_KEY', nil)
    dashboard_id = ENV.fetch('RAMON_METABASE_DASHBOARD_ID', nil)
    return render json: { configured: false } if [site_url, secret, dashboard_id].any?(&:blank?)

    payload = { resource: { dashboard: dashboard_id.to_i }, params: {}, exp: 10.minutes.from_now.to_i }
    token = JWT.encode(payload, secret, 'HS256')
    render json: { configured: true, url: "#{site_url}/embed/dashboard/#{token}#{EMBED_HASH}" }
  end

  private

  def check_authorization
    authorize(:ramon_relatorio, :show?)
  end
end
```

- [ ] **Step 4: Rota** — em `config/routes.rb`, logo abaixo de `resource :ramon_watchdog` (~:307):

```ruby
resource :ramon_relatorios, only: [:show], controller: 'ramon_relatorios'
```

- [ ] **Step 5: Rubocop local + commit**

```bash
bundle exec rubocop -a app/controllers/api/v1/accounts/ramon_relatorios_controller.rb app/policies/ramon_relatorio_policy.rb spec/requests/api/v1/accounts/ramon_relatorios_spec.rb 2>/dev/null || true
git add app/controllers/api/v1/accounts/ramon_relatorios_controller.rb app/policies/ramon_relatorio_policy.rb config/routes.rb spec/requests/api/v1/accounts/ramon_relatorios_spec.rb
git commit --no-verify -m "feat(ramon): endpoint de embed do Metabase (Relatorios, admin-only)"
```

(Se `bundle` não existir no Windows, pular — o CI roda rubocop.)

---

### Task 5: Fork — página "Relatórios" na Intranet

**Files:**
- Create: `app/javascript/dashboard/api/ramonRelatorios.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/Relatorios.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Relatorios.spec.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js` (nova entrada)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue` (item de menu, `adminOnly: true`)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` e `app/javascript/dashboard/i18n/locale/en/ramon.json`

**Interfaces — Consumes:** `RamonRelatoriosAPI.get()` → `{ data: { configured, url } }` (Task 4).

- [ ] **Step 1: Client API**

```js
/* global axios */
import ApiClient from './ApiClient';

class RamonRelatoriosAPI extends ApiClient {
  constructor() {
    super('ramon_relatorios', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }
}

export default new RamonRelatoriosAPI();
```

(Conferir no arquivo vizinho `ramonPrescriptionRadar.js` se o `get()` custom é necessário ou se o da base já cobre — copiar o padrão de lá.)

- [ ] **Step 2: i18n** — nos dois locales, em `ramon.json`:

Em `NAV`: `"RELATORIOS": "Relatórios"` (en: `"Reports"`). Bloco novo:

```json
"RELATORIOS": {
  "TITLE": "Relatórios",
  "SUBTITLE": "Análise comercial — tendências, funil, origem e atendimento",
  "NOT_CONFIGURED": "A BI ainda não está configurada neste ambiente. Defina RAMON_METABASE_SITE_URL, RAMON_METABASE_SECRET_KEY e RAMON_METABASE_DASHBOARD_ID.",
  "LOAD_ERROR": "Não foi possível carregar o relatório.",
  "RETRY": "Tentar de novo"
}
```

(en: textos equivalentes em inglês.)

- [ ] **Step 3: Página** — `Relatorios.vue`, padrão `RadarPrescricao.vue`:

```vue
<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonRelatoriosAPI from 'dashboard/api/ramonRelatorios';
import RamonPageHeader from '../components/RamonPageHeader.vue';

defineOptions({ name: 'RamonRelatorios' });

const { t } = useI18n();
const loading = ref(true);
const error = ref(false);
const configured = ref(false);
const embedUrl = ref('');

const fetchEmbed = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await RamonRelatoriosAPI.get();
    configured.value = data.configured;
    embedUrl.value = data.url || '';
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(fetchEmbed);
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background p-4 sm:p-8">
    <RamonPageHeader
      :title="t('RAMON.RELATORIOS.TITLE')"
      :subtitle="t('RAMON.RELATORIOS.SUBTITLE')"
      compact
    />
    <div v-if="loading" class="flex-1" />
    <div v-else-if="error" class="flex flex-col items-start gap-2">
      <p class="text-n-slate-11">{{ t('RAMON.RELATORIOS.LOAD_ERROR') }}</p>
      <button class="text-n-brand underline" @click="fetchEmbed">
        {{ t('RAMON.RELATORIOS.RETRY') }}
      </button>
    </div>
    <p v-else-if="!configured" class="text-n-slate-11">
      {{ t('RAMON.RELATORIOS.NOT_CONFIGURED') }}
    </p>
    <iframe
      v-else
      :src="embedUrl"
      class="flex-1 w-full border-0 rounded-lg"
      :title="t('RAMON.RELATORIOS.TITLE')"
    />
  </div>
</template>
```

- [ ] **Step 4: Rota** — em `ramon.routes.js`, padrão da entrada `ramon_playbooks` (:41-46):

```js
{
  path: frontendURL('accounts/:accountId/ramon/relatorios'),
  name: 'ramon_relatorios',
  component: () => import('./pages/Relatorios.vue'),
  meta: { permissions: ['administrator'], world: 'intranet' },
},
```

- [ ] **Step 5: Menu** — em `IntranetSidebar.vue`, na mesma seção do item Playbooks (:100-107), acrescentar:

```js
{
  key: 'relatorios',
  label: t('RAMON.NAV.RELATORIOS'),
  icon: 'i-lucide-chart-column',
  to: accountScopedRoute('ramon_relatorios'),
  names: ['ramon_relatorios'],
  adminOnly: true,
},
```

(Conferir que `i-lucide-chart-column` existe no set usado pelo sidebar — senão usar o mesmo padrão de ícone de um item vizinho, ex. `i-lucide-bar-chart-3`.)

- [ ] **Step 6: Vitest** — `Relatorios.spec.js`, padrão `RadarPrescricao.spec.js` (mesmos mocks de vue-i18n/router/store/useAccount):

```js
import { mount, flushPromises } from '@vue/test-utils';
import Relatorios from '../Relatorios.vue';
import RamonRelatoriosAPI from 'dashboard/api/ramonRelatorios';

vi.mock('dashboard/api/ramonRelatorios', () => ({ default: { get: vi.fn() } }));
// + mocks de vue-i18n (t devolve a chave), vue-router, dashboard/composables/store,
//   dashboard/composables/useAccount — copiar do RadarPrescricao.spec.js

describe('Relatorios', () => {
  it('mostra aviso quando nao configurado', async () => {
    RamonRelatoriosAPI.get.mockResolvedValue({ data: { configured: false } });
    const wrapper = mount(Relatorios);
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.RELATORIOS.NOT_CONFIGURED');
    expect(wrapper.find('iframe').exists()).toBe(false);
  });

  it('renderiza o iframe quando configurado', async () => {
    RamonRelatoriosAPI.get.mockResolvedValue({
      data: { configured: true, url: 'https://bi.test/embed/dashboard/tok#theme=night' },
    });
    const wrapper = mount(Relatorios);
    await flushPromises();
    expect(wrapper.find('iframe').attributes('src')).toBe('https://bi.test/embed/dashboard/tok#theme=night');
  });

  it('mostra erro com retry quando a API falha', async () => {
    RamonRelatoriosAPI.get.mockRejectedValue(new Error('boom'));
    const wrapper = mount(Relatorios);
    await flushPromises();
    expect(wrapper.text()).toContain('RAMON.RELATORIOS.LOAD_ERROR');
  });
});
```

- [ ] **Step 7: Rodar local**

```bash
npx vitest run app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Relatorios.spec.js
./node_modules/.bin/eslint app/javascript/dashboard/api/ramonRelatorios.js "app/javascript/dashboard/routes/dashboard/ramon/pages/Relatorios.vue" app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js
```

Esperado: vitest 3/3 PASS; eslint sem erro (ignorar `Delete ␍`).

- [ ] **Step 8: Commit**

```bash
git add app/javascript/dashboard/api/ramonRelatorios.js "app/javascript/dashboard/routes/dashboard/ramon/pages/Relatorios.vue" app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Relatorios.spec.js app/javascript/dashboard/routes/dashboard/ramon/ramon.routes.js app/javascript/dashboard/routes/dashboard/ramon/components/IntranetSidebar.vue app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/i18n/locale/en/ramon.json
git commit --no-verify -m "feat(ramon): pagina Relatorios com dashboard Metabase embutido"
```

---

### Task 6: FORK-PONTOS + PR + CI + merge + deploy

**Files:** Modify: `docs/FORK-PONTOS-DE-REGISTRO.md` (1 linha — só `config/routes.rb` é arquivo do upstream tocado).

- [ ] **Step 1:** Acrescentar à tabela do FORK-PONTOS:

```
| `config/routes.rb` | `resource :ramon_relatorios` na seção ramon | página Relatórios (embed Metabase) | BI |
```

Commit: `git add docs/FORK-PONTOS-DE-REGISTRO.md && git commit --no-verify -m "docs: registra fork-ponto da rota ramon_relatorios"`.

- [ ] **Step 2: PR** — push `--no-verify`, `gh pr create` com `--body-file` (nunca corpo inline no PS 5.1), título Conventional: `feat(ramon): BI Relatorios — dashboard Metabase embutido (admin-only)`.

- [ ] **Step 3: CI** — poll com `gh pr view N --json statusCheckRollup`; exigir TODOS os checks completed e zero não-success (check "test" SKIPPED é normal). Lint quebrando: corrigir e re-push.

- [ ] **Step 4: Merge + deploy** — regime autônomo (CI verde): merge; aguardar workflow "Publica imagem do fork"; na VPS `docker compose pull chatwoot-web chatwoot-worker && docker compose up -d`; puxar por `sha-<mergesha7>` e retagear se houver builds concorrentes; conferir `docker inspect` label `org.opencontainers.image.revision` == merge SHA. Sem migração de schema neste PR. Smoke técnico: `https://chat.ramonantonio.adv.br/api` 200 + `docker exec` grep `ramon_relatorios` em `config/routes.rb` do container.

---

### Task 7: VPS envs + smoke + doc

**Files:** Create: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-07-31-smoke-bi-relatorios.md` (fora do repo do hub).

- [ ] **Step 1: Envs na VPS** — **AskUserQuestion pro Eduardo antes** (mudança de env de produção, padrão da casa). Com OK: backup `cp chatwoot.env chatwoot.env.bak-pre-metabase`, acrescentar:

```
RAMON_METABASE_SITE_URL=https://bi.ramonantonio.adv.br
RAMON_METABASE_SECRET_KEY=<EMBED_SECRET da Task 3>
RAMON_METABASE_DASHBOARD_ID=<DASHBOARD_ID da Task 2>
```

`docker compose up -d chatwoot-web chatwoot-worker` (recarrega env). Verificar presença com `test -n` (NUNCA ecoar o valor do secret).

- [ ] **Step 2: Smoke técnico final** — logado como admin (ou via `ActionDispatch::Integration::Session` com `s.https!` no console): `GET /api/v1/accounts/2/ramon_relatorios` → `configured: true` + URL; `curl` na URL do embed → 200. Conferir que "Leads abertos" do Placar do Dono == total de leads abertos do Kanban (`Lead.open.count` no console = fonte da verdade).

- [ ] **Step 3: Doc de smoke do Eduardo** — criar `comercial\docs\2026-07-31-smoke-bi-relatorios.md`: (1) menu Intranet → "Relatórios" aparece SÓ pra admin e abre o dashboard dentro do hub; (2) conferir 2-3 números contra o Kanban; (3) abrir `bi.ramonantonio.adv.br/dashboard/2` (Placar corrigido) e ver que Examples sumiu; (4) lembrete da regra de manutenção (mudou regra de lead → revisar queries do Metabase).

---

## Self-review (feito 31/07)

- Spec coverage: faxina+correção (T1), dashboard 13 cartões (T2 — NPS fora, spec atualizada), embedding+página admin-only+envs com aviso (T3-T5, T7), validação (specs T4/T5 + smokes T6/T7), regra de manutenção (T7 Step 3). Sem lacuna.
- Placeholders: nenhum "TBD"; os dois "conferir X" (coluna de `theses`, ícone lucide) são verificações com fallback definido, não lacunas.
- Consistência de tipos: resposta `{configured, url}` idêntica em T4 (produz), T5 (consome) e specs; envs com os mesmos 3 nomes em T4 e T7; formato do hash `#theme=night&bordered=false&titled=false` idêntico em T3/T4/T5.

# Onda 5 — Funil, Clientes/Ficha em abas e busca Ctrl K — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Funil, Clientes/Ficha e a busca ficam iguais ao mockup v2: colunas com cabeçalho em bloco translúcido da cor da etapa, cards enxutos com selo de prazo e de documentos, Pós-venda e Radar viram filtros do funil, "Clientes" ganha lista própria, a ficha vira abas, e Ctrl K abre uma paleta própria que acha lead, cliente e processo sem gastar cota do ADVBOX.

**Architecture:** Backend: filtro `thesis_id` no index de leads; `GET ramon_busca?q=` busca local (leads + espelho `PortalCliente`, inclusive nº de processo dentro do jsonb); dossiê ganha profissão, responsáveis e total de cálculos. Front: reestilo de `KanbanColumn`/`LeadCard`/filtros, filtros derivados no front (`helpers/filtrosFunil.js`), página `Clientes.vue` (rota `ramon_clientes`), `Dossie.vue` em abas, `CommandPalette.vue` no Ctrl K (a command bar antiga passa pra Ctrl+Shift+K e continua acessível pela paleta).

**Tech Stack:** Rails 7.1 + RSpec; Vue 3, Vuex, Tailwind, Vitest.

**Spec:** `docs/superpowers/specs/2026-10-03-redesign-v2-fiel-ao-mockup.md` · alvo `docs/superpowers/specs/mockups/2026-10-03-hub-v2.html` (telas `.t-funil`, `.t-ficha`, `#busca`).

## Global Constraints

- Branch `feat/funil-clientes-busca` a partir de `feat/tela-hoje` (Onda 3 — usa `SeloPrazo`/`Selo`). Pode andar em paralelo com a Onda 4 (arquivos quase disjuntos); quem chegar depois rebaseia.
- Sem Ruby local; Rubocop do projeto; `FORK(ramon)` em arquivo upstream.
- Tailwind only, i18n pt_BR + en, `font-mono` em números/valores/telefone/processo, fundos coloridos translúcidos.
- Nada some: o que sair do card do funil (triagem, retomadas, próxima ação) continua na gaveta do lead; Pós-venda e Radar viram filtros com a mesma informação; a command bar antiga continua em Ctrl+Shift+K e no item "Mais comandos…" da paleta.
- Regra de ganho mantida: mover pra etapa de ganho SEMPRE pede confirmação de valor (`WonValueModal`) — inclusive o botão "Marcar como ganho" da ficha.

## Review Focus

1. Busca com 1 letra, com acento, com CPF formatado (`123.456.789-00`) e com nº CNJ com pontos/traços → normaliza e acha; < 2 caracteres não chama o servidor.
2. Filtro "Ganhos com docs pendentes" com lead ganho cuja tese não tem itens de documento → não aparece (mesma regra do `LeadRadar.pos_venda`).
3. Coluna sem cor configurada → bloco neutro legível nos dois temas.
4. URL antiga `ramon/pos-venda` ou `ramon/radar` (favoritos) → cai no funil com o filtro ligado.
5. Ficha de lead sem conversa, sem cálculos, sem reunião → abas mostram vazio, sem erro; "Conversa" desabilitado.

---

### Task 1: Backend — filtro por tese, busca local, dossiê completo

**Files:**
- Modify: `app/controllers/api/v1/accounts/leads_controller.rb` (`apply_equality_filters` + `thesis_id`)
- Create: `app/services/ramon/busca.rb`, `app/controllers/api/v1/accounts/ramon_busca_controller.rb`; Modify: `config/routes.rb` (`resource :ramon_busca, only: [:show], controller: 'ramon_busca'`)
- Modify: `app/services/ramon/dossie_service.rb` (pessoa: `profissao`, `sdr`, `closer`; calculos: `total`)
- Test: `spec/controllers/api/v1/accounts/leads_controller_spec.rb` (filtro), `spec/services/ramon/busca_spec.rb`, `spec/requests/api/v1/accounts/ramon_busca_spec.rb`, `spec/services/ramon/dossie_service_spec.rb`

**Interfaces:**
- Produces: `GET leads?thesis_id=`; `GET ramon_busca?q=` → `{ leads: [{ id, nome, tese, telefone, stage_name, stage_color }], clientes: [{ id, nome, advogada, desde }], processos: [{ numero, cliente, tipo, cliente_id }] }` (máx. 6 por grupo; `q` < 2 chars → tudo vazio); dossiê `pessoa.profissao`, `pessoa.sdr`, `pessoa.closer`, `calculos.total`.

- [ ] **Step 1: Specs que falham** — `busca_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Busca do
  let(:account) { create(:account) }

  it 'menos de 2 caracteres não busca' do
    expect(described_class.new(account, 'j').perform).to eq(leads: [], clientes: [], processos: [])
  end

  it 'acha lead por nome sem acento e por telefone' do
    lead = create(:lead, account: account, name: 'João Pedro Martins')
    expect(described_class.new(account, 'joao p').perform[:leads].pluck(:id)).to eq([lead.id])
  end

  it 'acha processo pelo número com ou sem pontuação' do
    create(:portal_cliente, account: account, nome: 'João Paulo Ramos',
                            processos: [{ 'numero' => '5001876-22.2023.4.04.7216', 'tipo' => 'Auxílio-doença' }])
    numeros = described_class.new(account, '50018762220234047216').perform[:processos].pluck(:numero)
    expect(numeros).to eq(['5001876-22.2023.4.04.7216'])
  end
end
```

(Confira a factory `:portal_cliente`, colunas `nome`/`cpf`/`telefone`/`account_id` e se `unaccent` existe no banco — `git grep -n "unaccent" db/`; se não existir, compare com `I18n.transliterate` em Ruby sobre um `ILIKE` mais largo, ou use `LOWER` + `translate()` do Postgres.)

Filtro: no `leads_controller_spec.rb`, caso novo — `get index, params: { thesis_id: tese.id }` devolve só o lead da tese.

Dossiê: lead com `custom_attributes: { 'colheita' => { 'dados' => { 'cliente' => { 'profissao' => 'metalúrgico' } } } }`, `sdr` e `closer` → `pessoa` inclui `profissao: 'metalúrgico'` e os nomes; `calculos[:total]` conta todos (o bloco continua listando no máximo 5).

- [ ] **Step 2: Implementar**

`leads_controller.rb`: `%i[benefit_type_id lead_priority_id lead_stage_id source channel contact_id thesis_id]`.

`app/services/ramon/busca.rb`:

```ruby
# Busca da paleta Ctrl K (redesign v2): leads + espelho do painel do cliente
# (PortalCliente, inclusive nº de processo no jsonb). Tudo local — zero cota do ADVBOX.
class Ramon::Busca
  LIMITE = 6

  def initialize(account, termo)
    @account = account
    @termo = termo.to_s.strip
  end

  def perform
    return { leads: [], clientes: [], processos: [] } if @termo.length < 2

    { leads: leads, clientes: clientes, processos: processos }
  end

  private

  def digitos = @termo.gsub(/\D/, '')
  def like = "%#{ActiveRecord::Base.sanitize_sql_like(I18n.transliterate(@termo).downcase)}%"

  def leads
    escopo = @account.leads.funil.includes(:lead_stage, :thesis, :contact).left_joins(:contact)
    condicao = escopo.where('unaccent(LOWER(leads.name)) LIKE ?', like)
    condicao = condicao.or(escopo.where('contacts.phone_number LIKE ?', "%#{digitos}%")) if digitos.length >= 4
    condicao.limit(LIMITE).map do |lead|
      { id: lead.id, nome: lead.name, tese: lead.thesis&.name, telefone: lead.contact&.phone_number,
        stage_name: lead.lead_stage&.name, stage_color: lead.lead_stage&.color }
    end
  end

  def clientes
    escopo = PortalCliente.where(account_id: @account.id)
    condicao = escopo.where('unaccent(LOWER(nome)) LIKE ?', like)
    condicao = condicao.or(escopo.where(cpf: digitos)).or(escopo.where(telefone: digitos)) if digitos.length >= 8
    condicao.limit(LIMITE).map do |cliente|
      principal = Array(cliente.processos).first || {}
      { id: cliente.id, nome: cliente.nome, advogada: principal['responsavel'], desde: principal['inicio'].to_s[0, 7].presence }
    end
  end

  def processos
    return [] if digitos.length < 7

    PortalCliente.where(account_id: @account.id)
                 .where("regexp_replace(processos::text, '[^0-9]', '', 'g') LIKE ?", "%#{digitos}%").limit(LIMITE)
                 .flat_map { |cliente| processos_do(cliente) }.first(LIMITE)
  end

  def processos_do(cliente)
    Array(cliente.processos).select { |p| p['numero'].to_s.gsub(/\D/, '').include?(digitos) }
                            .map { |p| { numero: p['numero'], tipo: p['tipo'], cliente: cliente.nome, cliente_id: cliente.id } }
  end
end
```

(Sem `unaccent`: troque por `translate(LOWER(x), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')`. Métodos endless `def x = ...` só se o Rubocop/Ruby do projeto aceitarem — senão, método normal.)

Controller: `authorize(:ramon_dashboard, :show?)`; `render json: Ramon::Busca.new(Current.account, params[:q]).perform`.

`dossie_service.rb` — no bloco `pessoa`: `profissao: lead.custom_attributes.dig('colheita', 'dados', 'cliente', 'profissao')`, `sdr: lead.sdr&.name`, `closer: lead.closer&.name`; no bloco `calculos`: acrescente `total:` com o `count` sem limite (mantenha a lista limitada a 5).

- [ ] **Step 3: Commit** — `feat(funil): filtro por tese, busca local da paleta e ficha com profissão e responsáveis`

---

### Task 2: Funil — cabeçalho de coluna em bloco, card enxuto, filtros em chips

**Files:**
- Modify: `routes/dashboard/ramon/components/kanban/KanbanColumn.vue`, `LeadCard.vue`, `KanbanFilters.vue`, `pages/Funil.vue` (cabeçalho da página)
- Create: `routes/dashboard/ramon/helpers/filtrosFunil.js`
- Modify: `store/modules/leads.js` (`thesisId` no `toParams`)
- Test: `kanban/specs/KanbanColumn.spec.js`, `LeadCard.spec.js`, `KanbanFilters.spec.js`, `helpers/specs/filtrosFunil.spec.js`

**Interfaces:**
- Produces: `filtrarPosVenda(leads) → leads` (ganho com `docs_total > 0` e `docs_received < docs_total`); `filtrarPrescricao(leads) → leads` (usa `prescriptionInfo` de `helpers/prescription.js`, nível de risco ≥ o que o Radar chama de "risco 90d"); `contarFiltros(leads) → { posVenda, prescricao }`.

Visual (mockup `.t-funil`):
- **Cabeçalho da página** (`h-14 px-7 border-b border-n-weak flex items-center gap-2.5`): "Funil" `text-[15px] font-semibold`; chips de filtro tracejados `inline-flex items-center gap-1.5 rounded-[7px] border border-dashed border-n-strong px-2.5 py-1.5 text-[12.5px] text-n-slate-11` com `i-lucide-plus` ("Tese", "Responsável", "Origem", "Mais filtros" abre o painel atual de `KanbanFilters`); chip **ativo** = sólido translúcido `border-transparent bg-n-amber-9/15 text-n-amber-11 font-medium` (para "Ganhos com docs pendentes · N", ícone `i-lucide-file-warning`) e `bg-n-ruby-9/10 text-n-ruby-11` para "Prescrição em risco · N" (`i-lucide-radar`); à direita "Novo lead" (botão cheio azul com `i-lucide-plus`) e o seletor de modo (colunas/raias/lista) como ícones.
- **Cabeçalho da coluna**: bloco `rounded-[10px] px-3 py-2.5` com fundo `color-mix(in srgb, var(--stage) 12%, transparent)` e texto `color-mix(in srgb, var(--stage) 75%, rgb(var(--slate-12)))` — implemente como classe do `ramon-stage-pill` da Onda 1 (`.ramon-stage-block` no `_ramon-brand.scss`, mesma técnica, sem pílula); linha 1: nome `font-semibold text-[13.5px]` + contagem `font-mono` com opacidade 75%; linha 2 (`font-mono text-xs opacity-75`): `R$ total` · `~R$ ponderado` · `↳ N%` (o que hoje já é calculado — mantém), e no ganho `R$ total · {mês}`; alertas da coluna e o menu da etapa ficam à direita do bloco; colapsar continua. Sai o filete de 0,5 no topo.
- **Coluna**: sem fundo/borda de cartão (o bloco é o cabeçalho), `w-auto flex-1 min-w-[220px]` com `gap-2` entre cards.
- **Card** (`rounded-[10px] border border-n-weak bg-n-background p-3 hover:border-n-strong`; prazo estourado → `shadow-[inset_3px_0_0_rgb(var(--ruby-9))]`):
  - linha 1: nome `text-[13.5px] font-medium` + à direita `SeloPrazo` (quando `lead.sla` sem `replied_at`) senão tempo parado em `font-mono text-[11.5px] text-n-slate-9` (`qui 10h` se reunião marcada, `5h`, `8 dias`…);
  - linha 2: tese (`thesis_name`, cai pra `benefit_type_name`) `text-[12.5px] text-n-slate-11`;
  - linha 3 (`mt-2.5 flex items-center gap-2.5 text-xs text-n-slate-9`): `Selo` docs (`warn` "docs X/Y" incompleto, `ok` completo; nada se `docs_total` = 0), valor `font-mono`, prescrição crítica como `Selo bad` "prescreve em Nd" quando houver, e as iniciais do responsável num círculo `size-5 text-[9.5px]` à direita;
  - linha 4 (`mt-2.5 border-t border-n-weak pt-2 flex gap-3.5 text-xs text-n-slate-11 hover:[&_a]:text-n-blue-11`): "Conversa · Follow-up · Dossiê" (o `TaskBellMenu` com rótulo "Follow-up"); no ganho: "Conversa · Cobrar documentos" (reusa a ação "Cobrar pendentes" do `DocChecklist` — abre a conversa com o rascunho); "Responder agora" quando estourado continua.
  - saem do card (ficam na gaveta): próxima ação, triagem, retomadas, idade da etapa como selo separado.
- `stage_color` sem cor → `DEFAULT_STAGE_COLOR` (já existe).

- [ ] **Step 1: Specs** — `filtrosFunil.spec.js` (pós-venda: ganho 3/5 entra, ganho 5/5 não, ganho 0/0 não, aberto não; prescrição: usa `prescriptionInfo`); `KanbanColumn.spec.js`: o bloco mostra nome, contagem, total (os `data-testid` existentes continuam); `LeadCard.spec.js`: docs 2/5 → selo âmbar, 5/5 → verde; SLA correndo → `SeloPrazo`; ganho → "Cobrar documentos".
- [ ] **Step 2: Implementar** (filtro de tese: `thesisId` no estado de filtros da store e em `toParams` → `thesis_id`; opções de tese vêm do `leadConfig`/endpoint que o `FunilConfig` já usa).
- [ ] **Step 3: Commit** — `feat(funil): colunas em bloco da cor da etapa, cards enxutos e filtros em chips`

---

### Task 3: Pós-venda e Radar viram filtros do funil

**Files:**
- Modify: `pages/Funil.vue`/`KanbanBoard.vue` (aplicar `filtrarPosVenda`/`filtrarPrescricao` sobre `getLeadsByStage` quando o chip estiver ativo; estado na query `?filtro=pos_venda|prescricao`)
- Modify: `ramon.routes.js` — `ramon_pos_venda` e `ramon_radar` viram `redirect` para `ramon_funil` com `query: { filtro: ... }`
- Delete: `pages/PosVenda.vue`, `pages/RadarPrescricao.vue` + spec do Radar, `api/ramonPosVenda.js` se nada mais usar (`git grep`); NÃO apagar o endpoint Ruby (a tela Hoje usa `LeadRadar.pos_venda`; o controller pode ficar)
- Modify: `helpers/navItems.js` — tirar `pos_venda` e `radar` do MAIS (e do spec)
- Test: spec do board/página com `?filtro=pos_venda` mostrando só os ganhos pendentes

- [ ] Steps: spec → implementar → `git grep -n "ramon_pos_venda\|ramon_radar"` (links da tela Hoje e da Esteira continuam funcionando via redirect) → commit `feat(funil): pós-venda e radar de prescrição viram filtros do funil`

---

### Task 4: Lista "Clientes"

**Files:**
- Create: `pages/Clientes.vue`; Modify: `ramon.routes.js` (`ramon_clientes`, path `ramon/clientes`), `helpers/navItems.js` (Clientes → `ramon_clientes`, `names` com `ramon_clientes`, `ramon_lead_dossie`, `ramon_pessoas`, `ramon_linha_da_vida`, `ramon_portal_clientes`)
- Test: `pages/specs/Clientes.spec.js`, navItems spec

Visual: cabeçalho de página "Clientes" + campo de busca (filtra `q` na store de leads, debounce 300 ms) + chips de filtro "Tese"/"Etapa"/"Responsável"; tabela (`text-[13px]`, cabeçalho `text-xs text-n-slate-9 font-normal border-b border-n-weak`, linhas `border-b border-n-weak py-2.5 hover:bg-n-slate-3 cursor-pointer`): Nome (`font-medium`), Etapa (`ramon-stage-pill`), Tese, Responsável, Telefone (`font-mono`), Última mudança (`font-mono text-n-slate-9`, de `stage_entered_at`). Clique na linha → `ramon_lead_dossie`. Reaproveite a busca/paginação que o `LeadListView` já faz (extraia o que precisar, não duplique).

- [ ] Steps: spec (lista, busca chama a action com `q`, clique navega) → implementar → commit `feat(clientes): lista de clientes`

---

### Task 5: Ficha em abas

**Files:**
- Modify: `pages/Dossie.vue` (reorganizar em abas), `components/ficha/EsteiraEtapas.vue` (barra fina por etapa, cor da etapa no feito/atual)
- Test: `pages/specs/Dossie.spec.js`, `ficha/specs/EsteiraEtapas.spec.js`

Visual (mockup `.t-ficha`, largura máx. 1080 px, `px-8 pt-7`):
- "← Clientes" (`text-[12.5px] text-n-slate-9`, volta pra `ramon_clientes`);
- cabeçalho: nome `text-[26px] font-semibold tracking-tight`; linha abaixo: `ramon-stage-pill` da etapa + "tese · cidade · profissão"; à direita botões "Conversa" (borda, `i-lucide-message-circle`; desabilitado sem conversa), "Gravar reunião" (borda, `i-lucide-mic`, rota existente com `leadId`), "Marcar como ganho" (cheio verde `bg-n-teal-9 text-white` com `i-lucide-trophy` → abre o `WonValueModal` e faz o mesmo `leads/update` do Kanban; some se já ganho/perdido), "Copiar dossiê" como ícone;
- `EsteiraEtapas`: faixa com uma barrinha de 3 px por etapa (feita/atual na cor da etapa, futura `bg-n-slate-4`), nome da etapa abaixo (`text-[12.5px]`, atual `font-semibold` na cor da etapa) e data/“há N dias” em `font-mono text-[11.5px] text-n-slate-9` — mantenha a regra de lead perdido (selo ruby, ganho não marca feito);
- abas (`flex gap-[22px] border-b border-n-weak`, aba `py-2.5 text-[13.5px] text-n-slate-11 border-b-2 border-transparent -mb-px`, ativa `text-n-slate-12 font-medium border-n-blue-9`): **Resumo** (resumo do caso/triagem + pendências + histórico/timeline) · **Documentos** `X/Y` (tabela Documento | Situação [`Selo ok` Recebido / `Selo warn` Pendente] | Recebido [mono]) + "Cobrar pendentes" · **Cálculos** `N` (tabela Data | Benefício estimado | Atrasados | Honorário, tudo mono à direita) + "Novo cálculo" · **Reuniões** · **Linha da vida** (embute o conteúdo da `LinhaDaVida` pelo `contact_id`) · **Painel do cliente** (link/convite do portal — `portal_link`). Aba na query `?aba=` (volta pro lugar ao recarregar);
- lateral 280 px: caixa "Próximo passo" (`bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16] rounded-[10px] p-3.5`, título `text-n-blue-11 font-semibold text-xs`); depois `dado`s: Responsável (closer ou sdr), Valor estimado (`font-mono`, com selo "estimado" se a origem for auto), Telefone (`font-mono`), Origem, Tese/honorário.

- [ ] Steps: specs (abas trocam e respeitam `?aba=`; "Marcar como ganho" abre o modal de valor e salva na etapa `is_won`; lead sem conversa → botão desabilitado; contagens nas abas) → implementar → commit `feat(ficha): ficha do cliente em abas`

---

### Task 6: Paleta Ctrl K própria

**Files:**
- Create: `api/ramonBusca.js`, `routes/dashboard/ramon/components/busca/CommandPalette.vue`
- Modify: `routes/dashboard/Dashboard.vue` (montar a paleta), `routes/dashboard/commands/commandbar.vue` (atalho da ninja-keys → Ctrl+Shift+K; `OPEN_COMMAND_BAR` passa a abrir a PALETA; novo evento `OPEN_NINJA` abre a antiga), `shared/constants/busEvents.js`
- Test: `components/busca/specs/CommandPalette.spec.js`

Visual (mockup `#busca`): véu `fixed inset-0 bg-white/60 dark:bg-black/60 backdrop-blur-sm grid place-items-start justify-center pt-[12vh] z-50`; caixa `w-[620px] max-w-[calc(100vw-32px)] rounded-[14px] border border-n-strong bg-n-background shadow-[0_24px_64px_rgb(0_0_0/0.18)]`; campo `px-4 py-3.5 border-b border-n-weak` com `i-lucide-search`, input `text-[15px]` sem borda e `kbd` "esc"; grupos com título `text-[11.5px] text-n-slate-9 px-2 pt-1.5`: **Clientes e leads** (lead: ícone em quadrado `size-7 rounded-[7px] bg-n-slate-4`, nome, "tese · telefone(mono)", etiqueta da etapa à direita → ficha; cliente do painel: "Cliente desde aaaa · advogada", `Selo neutro` "cliente" → Linha da vida/painel), **Processos** (nº em mono, "cliente · tipo" → cliente), **Ações** (Novo lead → abre `NewLeadModal` no Funil; Novo cálculo → `ramon_calculos`; Buscar nas conversas e mensagens → `search` com o termo; Mais comandos… → evento `OPEN_NINJA`); item ativo `bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16]` com o ícone em `bg-n-blue-9 text-white`; rodapé `text-[11.5px] text-n-slate-9`: "↑↓ navegar · ↵ abrir · Busca por nome, CPF, telefone ou nº do processo".
Comportamento: Ctrl/⌘+K e o botão Buscar do menu abrem; digitação com debounce 250 ms chama `RamonBuscaAPI.get(q)` (≥ 2 caracteres); ↑/↓ movem; Enter abre; Esc e clique no véu fecham; foco volta pra onde estava.

- [ ] Steps: spec (abre com Ctrl+K; não chama a API com 1 letra; chama com "joao p" depois do debounce (fake timers); ↓ + Enter navega pro 2º item; "Mais comandos…" emite `OPEN_NINJA`) → implementar → commit `feat(busca): paleta Ctrl K com leads, clientes e processos`

---

### Task 7: Verificação, smoke e PR (sessão principal)

- [ ] eslint 0 erros; vitest em `routes/dashboard/ramon` e `routes/dashboard/commands`; `vite build`.
- [ ] Seção "K — Funil, Clientes, Ficha e busca" no smoke consolidado.
- [ ] Push (Eduardo), PR, CI verde, squash, deploy sem migração.

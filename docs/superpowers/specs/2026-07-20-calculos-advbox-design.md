# Cálculos a partir do AdvBox — design

**Data:** 2026-07-20 · **Aprovado por:** Eduardo (AskUserQuestion, 2 rodadas + aprovação final com extra)

## Problema

A tela **Cálculos** (`Calculos.vue`, PR #83) só alcança pessoas que já são contato do hub
com lead no funil. Eduardo quer calcular também para **cadastros do AdvBox** (clientes
antigos da banca que nunca passaram pelo funil) — e hoje pessoa do hub **sem** lead é
beco sem saída ("não tem caso").

## Decisões de design (Eduardo)

1. **Modelo: caso de cálculo oculto.** Ao escolher um cadastro do AdvBox, o hub reusa ou
   cria o contato e cria um lead com `source: 'calculo-advbox'` que NÃO aparece nas
   superfícies comerciais. Reusa 100% do pipeline de cálculo existente
   (`/leads/:id/cnis`, `/painel`, simulação, liquidação — CNIS persiste, cold-open ok).
2. **Busca: uma busca só, AdvBox sob demanda.** O campo atual continua buscando contato
   do hub a cada tecla; um botão **"Buscar no AdvBox"** dispara UMA chamada
   (`GET /customers` por nome via `Ramon::AdvboxClient`). Motivo: teto de 500
   chamadas/dia por rota na API AdvBox — nada de busca por tecla lá.
3. **Extra aprovado:** contato do hub sem nenhum lead ganha botão
   **"Criar caso de cálculo"** (mesma mecânica).

## Comportamento

### Busca AdvBox (tela Cálculos)
- Com termo ≥2 chars, abaixo dos resultados do hub aparece o botão "Buscar no AdvBox".
- Clique → `GET ramon/advbox_customers?q=<termo>` (proxy novo) → lista nome + CPF.
  Termo só-dígitos com 11 dígitos busca por `identification` (CPF); senão por `name`.
- Erro do AdvBox (fora do ar/limite) → mensagem visível + retry (padrão da varredura #85).

### Escolher um cadastro do AdvBox
`POST ramon/calculo_casos` com os dados do cliente AdvBox (nome, cpf, nascimento,
telefone, e-mail — o que houver). O serviço:
1. **Resolve o contato** (dedup): por CPF → por telefone → cria contato novo copiando
   os dados. CPF passa pela validação de dígito existente; inválido = contato sem CPF
   (não derruba o fluxo). Campos já preenchidos no contato NUNCA são sobrescritos
   (mesma filosofia do `fill_contact_blanks`).
2. **Resolve o caso:** se o contato já tem lead(s), devolve a lista (front reusa a UI
   atual de escolha — o cálculo vive no lead que já existe, comercial ou não).
   Se não tem nenhum, cria o **caso de cálculo**: lead na primeira etapa do funil,
   `source: 'calculo-advbox'`, sem tese, nome = nome da pessoa.
3. Resposta: `{ contact, leads }` (leads inclui o recém-criado quando for o caso).
   Front: 1 lead → abre o Simulador direto (rota `ramon_calculos_lead`); >1 → lista.

### Contato do hub sem lead
Mesmo `POST ramon/calculo_casos` com `contact_id` → passo 2 acima. Botão aparece no
lugar do texto "não tem caso".

## Ocultação do caso de cálculo

Escopo NULL-safe no modelo (`where.not(source:)` excluiria os leads com source NULL):

```ruby
scope :funil, -> { where("leads.source IS DISTINCT FROM 'calculo-advbox'") }
```

**Crítico — adoção de lead:** 7 pontos usam `leads.open.find_by(contact_id:)` como
"essa pessoa já tem caso vivo?" (conversa nova, LP pública, Cal.com, eventos AdvBox,
import CSV, dedup do Novo Lead). Um caso de cálculo NÃO pode responder sim — senão um
lead real de entrada é adotado pelo caso invisível e some do Kanban. Correção na raiz:
o próprio `scope :open` passa a encadear `:funil` (semântica de "vivo NO FUNIL" — todos
os 7 chamadores corrigidos de uma vez; nenhum chamador quer caso de cálculo).

O `:funil` é aplicado também em (superfícies que listam/contam leads):
- `LeadsController#filtered_leads` — **exceto** quando `params[:contact_id]` presente
  (visões por pessoa: Cálculos, gaveta, Linha da Vida — lá o caso DEVE aparecer);
- `RamonDashboardController` (funil, semana won/lost/created, canais, perdidos 30d);
- `Ramon::FunnelSnapshotService` (snapshot diário);
- `Ramon::LeadRadar.active_leads` e `.new_from_lp_leads` (Esteira, radar de parado,
  bloco no_next_action herda);
- `SearchService#filter_leads` (Cmd+K).

**Onde aparece:** tela Cálculos, lista de leads por contato, Linha da Vida.
**Ressalva conhecida:** Metabase (Placar do Dono) lê o banco direto — queries que
contam leads incluem casos de cálculo até ajuste manual lá (anotar no doc de smokes).

## Fora de escopo (de propósito)

- Baixar CNIS/documentos do AdvBox (a API não expõe documentos — PDF anexado à mão
  como hoje).
- Sexo do segurado quando o AdvBox não tiver (preenche no Simulador).
- Promover caso de cálculo a lead comercial (se um dia precisar: mudar o source).
- Paginação da busca AdvBox (limit fixo ~15).

## Componentes tocados

- **Novo** `Api::V1::Accounts::RamonCalculosController` (2 actions:
  `advbox_customers` proxy + `criar_caso`) + rotas + policy (padrão Esteira).
- **Novo** `Ramon::CalculoCasoService` (dedup contato + criação do caso).
- `Lead` — scope `:funil`.
- 5 superfícies acima — 1 linha cada.
- `Calculos.vue` — seção AdvBox + botão criar caso + estados de erro; API module novo.
- i18n `pt_BR`/`en` (`RAMON.CALCULOS.*`).
- Specs: request (proxy + criar_caso c/ WebMock), service (dedup 3 caminhos),
  exclusão do scope nas superfícies, componente (vitest).

## Riscos

- **NULL do source** — coberto pelo `IS DISTINCT FROM` + spec dedicado.
- **409 do `duplicate_open_lead`** — não passa por `leads#create`; endpoint próprio.
- **Lead ganho dispara AdvBox closing** — caso de cálculo nunca muda de etapa via UI
  comercial (não aparece lá); sem mudança de comportamento.
- **Conflito com PR #84** (abas do Simulador, aguardando merge): este PR não toca
  `LeadSimulador.vue`; em `Calculos.vue` o toque é aditivo — conflito improvável e
  pequeno.

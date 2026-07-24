# UI Pensão + Maternidade + Planejamento (hub) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 3 abas novas no LeadSimulador (Pensão, Maternidade, Planejamento) consumindo os endpoints do motor já NO AR (master=f14cf8a), incluindo download do PDF de consultivo do planejamento.

**Architecture:** Espelho EXATO do padrão do PR #95 (aba Elegibilidade): `Ramon::MotorClient` métodos novos → controllers proxy (mirror `lead_elegibilidades_controller`; PDF mirror `lead_liquidacoes_controller#pdf`) → `leads.js` → componentes filhos montados na tab-bar interna do LeadSimulador (o redesign #96-98 NÃO tocou o interior do Simulador — mapa confirmado 24/07). Pendências de 1 clique no padrão do LeadElegibilidade.

**Tech Stack:** Rails + Vue 3 script setup + vitest (local). RSpec/rubocop SÓ NO CI.

## Global Constraints

- Worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-eleg`, branch `feat/ui-pensao-planejamento` (base ramon=20a1b6aff). Vitest local: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon` — TUDO verde (baseline atual do diretório precisa passar antes e depois).
- Contratos do motor (fonte da verdade — já no ar):
  - `POST /pensao` req `{segurado:{nascimento,sexo}, data_obito, competencias, vinculos, dependentes:[{tipo:"conjuge"|"filho"|"outro", nascimento?, invalido:bool, inicio_uniao?}] (min 1), valor_beneficio_obito?, decisoes?:{desemprego?,facultativo?,uniao_2_anos?}}` → `{qualidade_falecido ("dispensada"|{cenarios,...}), direito_adquirido, base:{valor,origem}, percentual, rmi, quotas:[{tipo,quota_pct,cessa_em (date|{uniao_menor_2_anos,uniao_2_anos_ou_mais}|null),fundamento,avisos}], decisoes_pendentes:[{tipo,pergunta,efeito_por_resposta,...}], avisos}`. 422 detail PT-BR.
  - `POST /maternidade` req `{segurado, data_evento, competencias, vinculos?, categoria:"empregada"|"ci_facultativa"|"especial"}` → `{rmi, memoria, carencia:{exigida:0,fundamento}, duracao_dias:120, avisos}`.
  - `POST /planejamento` req `{segurado, competencias, vinculos, data_calculo?, cenarios?:[{nome,salario,aliquota}] (máx 10), horizonte_anos?}` → `{data_calculo, cenarios:[{nome,salario,aliquota,observacao,resultados:[{regra,titulo,fecha_em,rmi_projetada,meses_contribuindo,desembolso_total,payback_meses}],regras_excluidas:[{regra,motivo}],avisos}], decisoes_pendentes, avisos}`.
  - `POST /planejamento/pdf` = mesmo req + `segurado_nome` → bytes PDF.
- Gating (lição do #95 — endpoints não aceitam vínculo manual digitado na UI): **CNIS obrigatório nas 3 abas** (`cnis.value`), + campos próprios preenchidos. **Pensão: o CNIS anexado é o do FALECIDO** (decisão de fluxo da fatia 2) — aviso visível na aba.
- Regras de UI da casa: erro nunca vira vazio (hasError+retry), data-testid em tudo que teste toca, i18n pt_BR + en (namespace RAMON.SIMULADOR, paridade ELEG_* confirmada), dinheiro/data pelos formatadores do arquivo, busy-guard compartilhado entre botões da mesma aba (lição do #95), duplo-clique guardado.
- FORK-PONTOS: linha do routes.rb atualizada. Commits com `--no-verify`; PR título conventional (`feat: ...`).
- ⚠️ Specs Ruby: NO local runner — espelhar `lead_elegibilidades_controller_spec.rb` / `lead_liquidacoes_controller_spec.rb` com leitura rigorosa; CI valida. Spec files novos re-embaralham o knapsack round-robin (lição #95) — se um shard core sem relação falhar, investigar co-locação antes de culpar a lógica.

---

### Task 1: Backend — MotorClient + 3 controllers + rotas + specs

**Files:**
- Modify `lib/ramon/motor_client.rb`: `pensao(payload)`, `maternidade(payload)`, `planejamento(payload)` via `post_json` (read_timeout 60 p/ planejamento — roda painel várias vezes); `planejamento_pdf(payload)` espelhando `liquidacao_pdf` (bytes).
- Create `app/controllers/api/v1/accounts/lead_pensoes_controller.rb` (create), `lead_maternidades_controller.rb` (create), `lead_planejamentos_controller.rb` (create + pdf com send_data, mirror liquidacoes).
- Modify `config/routes.rb` (~322, junto de elegibilidade): `resource :pensao, only: [:create], controller: 'lead_pensoes'` · `resource :maternidade, only: [:create], controller: 'lead_maternidades'` · `resource :planejamento, only: [:create], controller: 'lead_planejamentos' do post :pdf end`.
- Create specs espelhando os irmãos (contexts: 401, sucesso com MotorClient stubado + payload montado do cnis conferido, campos obrigatórios ausentes → 422, ValidationError → 422, UnavailableError → 503; planejamento#pdf → send_data com content-type).

**Params → payload (todos leem `cnis_entrada` como o elegibilidades):**
- pensões: `data_obito` (obrigatório), `dependentes` (array JSON obrigatório, repassado cru — motor valida), `valor_beneficio_obito?`, `decisoes?` (permit desemprego/facultativo/uniao_2_anos).
- maternidades: `data_evento` + `categoria` obrigatórios.
- planejamentos: `data_calculo?`, `cenarios?` (repassado cru), `horizonte_anos?`; `#pdf` adiciona `segurado_nome` (default: nome do contato do lead — `@lead.contact&.name.to_s`).

- [ ] Steps: implementar (ler os 2 controllers-espelho ANTES) → FORK-PONTOS → commit `feat(ui-motor): backend proxy pensao/maternidade/planejamento (+pdf)`.

---

### Task 2: Abas Pensão e Maternidade

**Files:** Modify `leads.js` (+`pensao`, `maternidade`); Create `LeadPensao.vue`, `LeadMaternidade.vue` (mesmo dir do LeadElegibilidade); Modify `LeadSimulador.vue` (2 botões na tab-bar linhas ~564-613, seções v-show, `canPensao = cnis && form.pensao.dataObito`... gating na própria aba: CNIS via prop; campos dentro do componente); i18n pt_BR+en; Create specs vitest dos 2 componentes (espelhar LeadElegibilidade.spec.js).

**LeadPensao.vue** (props lead, cnis presente via prop ou lido do lead como o Elegibilidade faz): aviso topo "O CNIS anexado deve ser o do FALECIDO"; campos: data do óbito, valor do benefício no óbito (opcional, dinheiro como texto/decimal — lição #95: nunca input number pra dinheiro), lista dinâmica de dependentes (tipo select, nascimento date, inválido checkbox, início da união date — só p/ cônjuge); botão Calcular (busy-guard); resultado: qualidade do falecido (dispensada | cenários como no Elegibilidade), base+origem (aviso quando hipotética), percentual/RMI destacados, tabela de quotas (tipo, %, cessa em — quando dict, mostrar os DOIS cenários; fundamento em texto menor; avisos da quota), pendências 1-clique (uniao_2_anos e desemprego → re-POST com decisoes; `false` explícito), avisos gerais. Testes: calcular renderiza quotas; clique "Não" na união re-chama com `decisoes.uniao_2_anos=false`; erro → retry; 422 detail PT-BR surfaced.

**LeadMaternidade.vue**: campos data do evento + categoria (select 3 opções com labels claros); resultado: RMI, "carência exigida: 0" com fundamento, duração 120 dias, avisos (inclui o aviso pré-04/2024 quando vier). Testes: calcular renderiza RMI+carência 0; erro → retry.

- [ ] Steps: ler LeadElegibilidade.vue+spec primeiro → implementar → `npx vitest run ...ramon` verde → commit `feat(ui-motor): abas Pensao e Maternidade no Simulador`.

---

### Task 3: Aba Planejamento + PDF + fechamento

**Files:** `leads.js` (+`planejamento`, `planejamentoPdf` blob — mirror `liquidacaoPdf`); Create `LeadPlanejamento.vue`; Modify `LeadSimulador.vue` (3º botão); i18n; spec vitest.

**LeadPlanejamento.vue**: botão "Planejar" (cenários padrão; sem inputs obrigatórios além do CNIS — data_calculo default do servidor); resultado por cenário: cabeçalho (nome, salário, alíquota, observação), tabela de resultados (regra/título, fecha em, RMI projetada, meses contribuindo, desembolso, payback), regras excluídas com motivo (collapsible/texto menor), avisos; pendências (cenario_manter) exibidas; botão **"Baixar PDF do planejamento"** (blob download `planejamento-<lead>.pdf`, busy-guard próprio, erro blob-aware — lição #95: 422 de blob precisa FileReader, copiar o handleError do LeadLiquidacao). Testes: planejar renderiza cenários+resultados+excluídas; PDF chama com responseType blob; erro → retry.

- [ ] Fechamento: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon` TUDO verde; conferir abas antigas intactas (specs existentes); FORK-PONTOS se faltou; commit `feat(ui-motor): aba Planejamento com PDF de consultivo`; push `--no-verify`; PR `feat: abas Pensao, Maternidade e Planejamento no Simulador (motor fatias 2-3)` contra `ramon`; CI verde (controller faz merge+deploy no regime autônomo).

---

## Fora deste plano

Persistência das análises no lead (efêmero); vínculos manuais nas abas novas (fatia futura do motor); editar cenários custom de planejamento na UI (v2 — API já aceita; entra se o Eduardo pedir); PDF de pensão (não existe no motor).

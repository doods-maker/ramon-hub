# Elegibilidade UI (hub) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Seção "Elegibilidade" no LeadSimulador consumindo o novo `POST /elegibilidade` do motor (qualidade de segurado, pendências de 1 clique, lacunas + simulação) + aviso de qualidade na aba Honorário.

**Architecture:** Espelho exato do padrão painel: `Ramon::MotorClient.elegibilidade` → `LeadElegibilidadesController` (lê `lead.cnis['entrada']`, funde vínculos manuais) → `leads.js` → aba nova no `LeadSimulador.vue` com child `LeadElegibilidade.vue`. Design aprovado na spec do motor (`motor-calculos/docs/superpowers/specs/2026-07-23-elegibilidade-cnis-design.md`, seção Hub): pendências como perguntas de 1 clique (resposta reenvia com `decisoes`), tabela de lacunas com botão "Simular preenchimento", aviso destacado no Honorário quando a qualidade estiver perdida/em risco. Sem persistência (cálculo efêmero).

**Tech Stack:** Rails (controller+HTTParty client), Vue 3 script setup, vitest. RSpec/rubocop SÓ NO CI (sem Ruby local — lição 17/07).

## Global Constraints

- Worktree: `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-eleg`, branch `feat/elegibilidade-ui` (base ramon=12d907b). NUNCA tocar o checkout principal.
- Vitest RODA local: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon` — specs novos verdes localmente antes do commit. RSpec: escrever, validar só no CI.
- Contrato do motor `/elegibilidade` (já NO AR na VPS): request = `{segurado:{nascimento,sexo}, der, competencias:[], vinculos:[], data_referencia?, decisoes?:{desemprego?:bool, facultativo?:bool}, simular_lacunas?:bool}`; response = `{data_referencia, qualidade:{cenarios:{unico?|sem_desemprego?+com_desemprego?:{mantida,ate,fundamento}}}, carencia:{total, perda_qualidade_anterior, desde_nova_filiacao, art_27a}, lacunas:[{inicio,fim,meses,graca_cobriu,fundamento_graca,ganho_tempo_meses,ganho_carencia}], simulacao?:[{cenario,lacunas,cartoes:[{id,elegivel_antes,elegivel_depois,previsao_antes,previsao_depois,rmi_antes,rmi_depois}],aviso}], decisoes_pendentes:[{tipo,inicio,fim,pergunta,efeito_por_resposta:{sim,nao}}], avisos:[str]}`. 422 vem em `detail` PT-BR.
- i18n: strings novas em `pt_BR/ramon.json` namespace `RAMON.SIMULADOR` (convenção da casa: pt_BR mantido à mão) E espelho em `en/ramon.json` se existir o namespace lá (conferir; se não existir, só pt_BR como as demais chaves RAMON).
- FORK-PONTOS: TODO arquivo core do Chatwoot tocado (routes.rb já é fork-ponto registrado? conferir) vira linha em `docs/FORK-PONTOS-DE-REGISTRO.md`. LeadSimulador.vue é código ramon (não core) — não precisa.
- `data-testid` em tudo que o vitest toca (padrão do arquivo).
- Commits pequenos; push com `--no-verify` (husky ausente em worktree).

---

### Task 1: Backend — MotorClient.elegibilidade + LeadElegibilidadesController + rota

**Files:**
- Modify: `lib/ramon/motor_client.rb` (adicionar método junto de `.painel`)
- Create: `app/controllers/api/v1/accounts/lead_elegibilidades_controller.rb`
- Modify: `config/routes.rb` (~linha 317, dentro do bloco `resources :leads`, junto de `resource :painel`)
- Create: `spec/controllers/api/v1/accounts/lead_elegibilidades_controller_spec.rb`

**Interfaces:**
- Consumes: `Ramon::MotorClient.post_json(path, payload, read_timeout:)` (privado, já existe); padrão do `lead_paineis_controller.rb` (fetch_lead, authorize, cnis entrada, rescues 422/503).
- Produces: rota `POST /api/v1/accounts/:account_id/leads/:id/elegibilidade`; params aceitos: `der` (obrigatório), `data_referencia`, `decisoes` (hash `{desemprego, facultativo}` — valores "true"/"false"/nil de JSON), `simular_lacunas` (bool). Task 2 chama via `LeadsAPI.elegibilidade(leadId, payload)`.

- [ ] **Step 1: MotorClient** — em `lib/ramon/motor_client.rb`, junto dos métodos públicos:

```ruby
    def elegibilidade(payload)
      post_json('/elegibilidade', payload, read_timeout: 30)
    end
```

- [ ] **Step 2: Controller** — espelhar `lead_paineis_controller.rb` (MESMA estrutura de before_action/authorize/erros; copiar de lá a leitura do cnis e a fusão de vínculos manuais se o painel fizer — conferir no arquivo real e reproduzir):

```ruby
class Api::V1::Accounts::LeadElegibilidadesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def create
    authorize(@lead, :show?)
    return render_error('informe a DER') if params[:der].blank?

    resultado = Ramon::MotorClient.elegibilidade(motor_payload)
    render json: resultado
  rescue Ramon::MotorClient::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Ramon::MotorClient::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def render_error(msg)
    render json: { error: msg }, status: :unprocessable_entity
  end

  def motor_payload
    entrada = @lead.cnis&.dig('entrada') || {}
    payload = {
      segurado: entrada['segurado'] ||
                { nascimento: @lead.contact_data_nascimento, sexo: @lead.contact_sexo },
      der: params[:der],
      competencias: entrada['competencias'] || [],
      vinculos: entrada['vinculos'] || [],
    }
    payload[:data_referencia] = params[:data_referencia] if params[:data_referencia].present?
    if params[:decisoes].present?
      payload[:decisoes] = params[:decisoes].permit(:desemprego, :facultativo).to_h.compact
    end
    payload[:simular_lacunas] = true if ActiveModel::Type::Boolean.new.cast(params[:simular_lacunas])
    payload
  end
end
```

⚠️ Ajustar `motor_payload` ao padrão REAL do `lead_paineis_controller.rb` (nome exato do jsonb, fusão de vínculos manuais/especiais se existir lá, helpers compartilháveis) — o código acima é esqueleto; o painel é a fonte da verdade do repo. Se o painel exigir nascimento/sexo quando não há CNIS, reproduzir a mesma validação/mensagem.

- [ ] **Step 3: Rota** — em `config/routes.rb`, dentro do `resources :leads`, junto de `resource :painel`:

```ruby
          resource :elegibilidade, only: [:create], controller: 'lead_elegibilidades'
```

- [ ] **Step 4: Spec** — espelhar `lead_paineis_controller_spec.rb` (mesmos contexts: sem login 401, agente de outra conta, sucesso com MotorClient stubado — `allow(Ramon::MotorClient).to receive(:elegibilidade).and_return({...})` — verificando o payload montado do cnis, der ausente → 422, ValidationError → 422, UnavailableError → 503, decisoes/simular_lacunas repassados). Não dá pra rodar local: garantir sintaxe por leitura cuidadosa; CI valida.

- [ ] **Step 5: FORK-PONTOS** — adicionar linha para `config/routes.rb` em `docs/FORK-PONTOS-DE-REGISTRO.md` (se routes.rb já tem linha de rotas ramon, atualizar a existente).

- [ ] **Step 6: Commit** — `feat(elegibilidade): backend proxy /leads/:id/elegibilidade (MotorClient + controller + rota)`

---

### Task 2: Frontend — leads.js + LeadElegibilidade.vue + aba nova

**Files:**
- Modify: `app/javascript/dashboard/api/leads.js` (junto de `painel`)
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadElegibilidade.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadSimulador.vue` (aba nova; linhas de referência: tab bar 518-553, `aba` ref 329, seções v-show 570/786, child LeadLiquidacao 984, canPainel 279-286)
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` (namespace `RAMON.SIMULADOR`, bloco linha 627+)
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadElegibilidade.spec.js` (espelhar `LeadLiquidacao.spec.js`)

**Interfaces:**
- Consumes: rota da Task 1; padrões do LeadSimulador (props `lead`, `form.der`, `cnis`, `canPainel`).
- Produces: aba `elegibilidade` (3ª), componente com: botão "Analisar elegibilidade" (POST com `der: form.der`), cenários renderizados (mantida/perdida + data + fundamento), pendências como pergunta com botões **Sim/Não** (clique → re-POST com `decisoes` acumuladas em ref local), tabela de lacunas, botão "Simular preenchimento" (re-POST com `simular_lacunas: true`, render tabela antes→depois por cartão SÓ das linhas que mudaram + aviso), bloco carência/27-A, avisos.

- [ ] **Step 1: leads.js**

```javascript
  elegibilidade(leadId, payload) {
    return axios.post(`${this.url}/${leadId}/elegibilidade`, payload);
  },
```

- [ ] **Step 2: LeadElegibilidade.vue** — script setup; estrutura mínima (seguir a estética/classes do LeadSimulador e o padrão de erro do repo — `hasError` + retry + useAlert, lição 20/07 "erro nunca se mascara de vazio"):

```
props: { lead: Object, der: String }
state: carregando, erro, resultado, decisoes (ref {desemprego: null, facultativo: null}), simulando
analisar() → LeadsAPI.elegibilidade(lead.id, { der, decisoes: decisoesPreenchidas() })
responder(tipo, valor) → decisoes[tipo] = valor; analisar()
simular() → mesmo POST com simular_lacunas: true (estado separado simulando; resultado.simulacao)
render:
  - cenários: se cenarios.unico → 1 cartão; senão 2 lado a lado (sem_desemprego/com_desemprego),
    verde mantida / vermelho perdida, data `ate` formatada dd/mm/aaaa, fundamento em texto menor
  - decisoes_pendentes: caixa amber por pendência: pergunta + efeito_por_resposta.sim/nao +
    botões "Sim"/"Não" (data-testid="eleg-pendencia-sim"/"-nao")
  - carência: total + bloco art_27a quando presente (exigência/cumprida)
  - lacunas: tabela (período, meses, graça cobriu?, ganho) + botão simular
    (data-testid="eleg-simular"); simulacao: por cenário, só cartoes com mudança
    (elegivel_antes !== elegivel_depois || rmi_antes !== rmi_depois || previsao muda),
    colunas antes→depois; aviso do cenário em destaque
  - avisos: lista padrão
datas: formatar com o helper de data já usado no LeadSimulador (conferir e reusar); dinheiro: BRL
  como no restante (lição: sempre o formatador existente)
```

- [ ] **Step 3: aba no LeadSimulador.vue** — 3º botão na tab bar (`data-testid="sim-aba-elegibilidade"`, i18n `ABA_ELEGIBILIDADE`), seção `v-show="aba === 'elegibilidade'"` montando `<LeadElegibilidade :lead="lead" :der="form.der" />`; gating: mesmo `canPainel` (precisa de CNIS/vínculos + DER) — sem canPainel, mostrar o mesmo hint que o painel usa.

- [ ] **Step 4: i18n** — chaves novas no `RAMON.SIMULADOR` (PT-BR): `ABA_ELEGIBILIDADE: "Elegibilidade"`, `ELEG_ANALISAR`, `ELEG_MANTIDA`, `ELEG_PERDIDA`, `ELEG_SEM_DESEMPREGO`, `ELEG_COM_DESEMPREGO`, `ELEG_PENDENCIAS`, `ELEG_SIM`, `ELEG_NAO`, `ELEG_CARENCIA`, `ELEG_LACUNAS`, `ELEG_SIMULAR`, `ELEG_GRACA_COBRIU`, `ELEG_GANHO`, `ELEG_ANTES`, `ELEG_DEPOIS`, `ELEG_ERRO` (+ retry). Textos em PT-BR claros de advogado.

- [ ] **Step 5: vitest** — `LeadElegibilidade.spec.js` espelhando `LeadLiquidacao.spec.js` (mock de `LeadsAPI.elegibilidade`): (a) analisar renderiza 2 cenários + pendência; (b) clique em "Sim" re-chama com `decisoes.desemprego=true` e colapsa pra cenário único; (c) erro de rede mostra erro+retry (não vazio); (d) simular chama com `simular_lacunas: true` e renderiza só cartões alterados. Rodar: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon` — TUDO verde (baseline do diretório precisa continuar passando).

- [ ] **Step 6: Commit** — `feat(elegibilidade): aba Elegibilidade no Simulador (cenarios, pendencias 1-clique, lacunas+simulacao)`

---

### Task 3: Aviso de qualidade na aba Honorário + fechamento

**Files:**
- Modify: `LeadSimulador.vue` (seção honorário, linhas 570-784)
- Modify: `pt_BR/ramon.json`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadSimulador.spec.js` (1 teste novo)

**Interfaces:**
- Consumes: o `/incapacidade` (botão Simular do honorário) JÁ devolve `avisos` com os textos novos de qualidade (contêm "art. 27-A" ou "Tema 1360" ou "qualidade de segurado" — vêm do motor).

- [ ] **Step 1:** onde o resultado do honorário é renderizado, computed `avisosQualidade` = avisos do resultado que casem `/qualidade de segurado|27-A|Tema 1360/i`; se presente, banner vermelho destacado (`data-testid="sim-aviso-qualidade"`) ANTES do valor do honorário, com o texto do(s) aviso(s) + dica i18n `ELEG_VER_ABA` ("Confira a aba Elegibilidade para o parecer completo"). Conferir se os avisos do /incapacidade já são exibidos hoje; se sim, só destacar os de qualidade no banner (sem duplicar).
- [ ] **Step 2:** teste no `LeadSimulador.spec.js`: resposta mockada do simulate com aviso contendo "art. 27-A" → banner aparece; sem aviso → não aparece.
- [ ] **Step 3:** rodar vitest do diretório inteiro; commit `feat(elegibilidade): aviso de qualidade em risco na aba Honorario`.
- [ ] **Step 4 (fechamento do PR, controller faz):** push `--no-verify`, abrir PR contra `ramon` via `gh pr create`, CI verde (rubocop+specs rodam lá; lição #94: build publica imagem GHCR — puxar sha-tag no deploy).

---

## Fora deste plano

Persistir análise no lead (efêmero por design); decisões por período (fatia 2 do motor); adjust-panel cold. Deploy = gate do Eduardo (compose pull da sha-tag + up).

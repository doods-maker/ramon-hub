# F3 — Tese automática + modos "sozinha até…" · Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** o lead novo ganha a tese sozinho (campanha da LP, palavra-chave da 1ª mensagem, tese padrão da caixa ou o passo comum "assunto"), e cada caixa pode ter um modo padrão da IA, incluindo três modos novos que enviam direto até um limite (qualificação, reunião marcada, contrato enviado) e aí voltam para rascunho com aviso ao responsável.

**Architecture:** `Ramon::CopilotoModo` sai de `enterprise/lib` para `app/services/ramon/` (o CI passa a testar; o motor do roteiro passa a usar a fonte única) e ganha os 3 modos, o padrão por caixa (lido ao vivo + carimbado na conversa nova) e `direto?`. Três peças novas em `app/services/ramon/`: `TeseAutomatica` (casa texto com palavras-chave/nome das teses; define a tese na 1ª mensagem), `CopilotoLimite` (nível atingido pelo lead → rascunho + carimbo + sino, sem handoff) e `ContratoAutomatico` (no modo contrato, gera o ZapSign na hora). O roteiro (F1) ganha o passo comum `assunto`. A tool `preparar_contrato_zapsign` fica fina e chama `ContratoAutomatico`. Tela: dois campos nas configurações da caixa.

**Tech Stack:** Rails 7.1 (fork Chatwoot 4.15.1), RSpec, Vue 3 (Options API em `Settings.vue`), Vitest, Captain tools (`enterprise/lib/captain/tools/`).

**Spec:** `docs/superpowers/specs/2026-10-13-roteiro-da-tese-design.md` §3.6, §3.7, §5 e §6 (F3). Plano anterior (vale onde a F3 toca o código dele): `docs/superpowers/plans/2026-10-13-roteiro-f1-motor.md`.

## Decisões que tomei sem perguntar (revisar)

1. **`Ramon::CopilotoModo` muda de `enterprise/lib/ramon/` para `app/services/ramon/`.** Porquê: é lógica pura, sem nada de enterprise. Lá o CI não testa (ele apaga `enterprise/`), e o motor da F1 teve de ler o atributo cru por isso.
2. **Padrão da caixa lido ao vivo E carimbado na conversa nova.** Porquê: o ouvinte é assíncrono e a 1ª resposta da IA é agendada antes dele. Sem a leitura ao vivo, a 1ª mensagem do lead viraria rascunho numa caixa em piloto. O carimbo deixa certos o seletor e o botão "Pausar" do front, que leem o atributo, sem mexer no front.
3. **Conversas antigas sem atributo seguem o padrão da caixa ao vivo.** Antes de ligar um padrão numa caixa, carimbar `rascunho` nas abertas antigas dela (snippet no doc de gate). Porquê: é o mesmo cuidado que já vale para a env `RAMON_COPILOTO_MODO_DEFAULT`, e evita código só para isso.
4. **Ordem da tese automática:** campanha da LP (`lead.source`) → palavra-chave na 1ª mensagem ou no título do anúncio da Meta → tese padrão da caixa. Porquê: a spec supõe que "o lead da LP já nasce com a tese do quiz", mas o código **não** grava tese no lead da LP. O slug da campanha (`t-auxilio-acidente`, `bpc-loas`) já casa com a palavra-chave, sem mexer no endpoint da LP.
5. **Como casa:** palavra ou frase inteira, sem acento nem maiúscula/minúscula, contra as palavras-chave **e o nome** da tese; só teses ativas. **Duas teses casando = não escolhe nenhuma** (cai na caixa ou no "assunto"). Porquê: a tese errada é pior que nenhuma (o roteiro desqualificaria com a régua errada).
6. **Só na 1ª mensagem do cliente na conversa, e só para lead sem tese.** A tese nunca é trocada automaticamente. Porquê: a spec diz "1ª mensagem"; trocar tese no meio reinicia o roteiro.
7. **Passo comum "assunto" = chave fixa `assunto`.** Só aparece para lead sem tese. Lead sem tese e sem esse passo cadastrado continua sem roteiro, ou seja, nada muda até a F4 semear os comuns. Resposta sem tese ou casando com duas → equipe, motivo "assunto sem tese cadastrada". Porquê: chave fixa é o jeito mais simples de o motor reconhecer o passo, sem coluna nova.
8. **Limite "qualificação" = desfecho `qualificado` apenas.** Desqualificado e "equipe" já encerram o envio direto pelos efeitos da F1 (IA calada / rascunho). Porquê: se contassem como limite, o rascunho entraria antes do Perdido direto e o transformaria em sugestão.
9. **Os limites seguem uma ordem** (qualificação < reunião < contrato): chegar a um mais adiante encerra também os de antes. Consequência: numa tese **sem roteiro**, "sozinha até qualificar" só para na reunião. Porquê: senão a IA seguiria em piloto até o fim nessas teses.
10. **"Reunião" = etapa "Reunião agendada" ou qualquer etapa depois dela** (ganho incluso). Perdido não conta. Porquê: Perdido fica depois da Reunião na ordem do funil.
11. **Ao atingir o limite: rascunho + carimbo `copiloto_limite` + sino e push, SEM handoff.** A conversa segue pendente, e a resposta do turno que atingiu o limite ainda sai: o link do contrato e, no "até qualificar", a resposta do turno que qualificou (pode levar o link da agenda, conforme a skill de agendamento). Porquê: o `ResponseBuilderJob` só publica se a conversa continua pendente. Um handoff no meio do turno engoliria o link do contrato.
12. **O limite é conferido em três eventos:** a etapa mudou, o ZapSign do lead mudou, ou terminou um registro do roteiro. Não é conferido a cada resposta da IA. Consequência: se alguém voltar à mão para um modo "até…" num lead que já passou do limite, ele só encerra no próximo evento. Porquê: avisar na hora em que o limite acontece, mesmo sem nova mensagem do lead.
13. **ZapSign automático só para tese com modelo de contrato** (coluna nova `theses.zapsign_template_id`). Hoje só existe um modelo, o de auxílio-acidente, fixo em constante. Sem essa trava, um lead de BPC receberia contrato de auxílio-acidente. O campo é preenchido pelo console (tela = F2/F4).
14. **"Cadastro confirmado" para o contrato sair sozinho:** nome com 2 ou mais palavras, CPF do contato e rua, número e cidade do "Dados do contrato" do painel. Endereço que só veio da colheita (uma string só) não basta.
15. **No modo contrato, se faltar dado ou o ZapSign falhar:** fica a sugestão pendente de sempre, o modo encerra (rascunho + sino com o que faltou) e a tool manda a IA passar para humano.
16. **Tela da caixa:** dois seletores nas configurações. A tese padrão aparece só com "Criar lead" ligado. O modo padrão aparece em qualquer caixa e oferece os 7 modos.

**Perguntas abertas (decisão do Eduardo; o plano segue com o padrão indicado):**

- **A.** A IA não tem como gravar CPF/endereço no cadastro (não existe tool para isso). Na prática, "sozinha até o contrato" vai parar em "faltam dados" até a equipe preencher o "Dados do contrato". Quer uma tool para a IA gravar esses dados (fatia nova)? *Padrão: não; a equipe preenche.*
- **B.** "Quer contratar → humano" (pergunta 5 do doc de textos da F1). A F3 propõe: a IA tenta o contrato na hora; se não sair, passa para humano. Confirmar junto com os textos.
- **C.** Qual modelo do ZapSign vale para BPC, maternidade e demais teses? *Padrão: até lá, só auxílio-acidente pode rodar "até o contrato".*

**Observação para a F1 (não resolvida aqui — conferir):** `Ramon::Roteiro::Efeitos.humano` chama `bot_handoff!` **durante** o turno da IA. O `ResponseBuilderJob#process_response` só cria a mensagem (ou o rascunho) se a conversa ainda está `pending` e se não foi o `HandoffTool` que fez o handoff. Então, quando o roteiro passa para a equipe (inclusive no "assunto sem tese" desta F3), a resposta daquele turno parece sumir. Conferir no staging/caixa Teste antes de ligar qualquer modo piloto.

## Global Constraints

- Branch `feat/roteiro-f3-tese-e-modos` no worktree `ramon-hub-wt-roteiro`, criada de `origin/ramon` **com a F1 mergeada**. Base do PR: `ramon`. Se a F2 já subiu, rebasear nela (sem arquivos em comum, fora o `db/schema.rb`).
- Os trechos "trocar X por Y" em arquivos da F1 (`app/services/ramon/roteiro.rb`, `roteiro/registro.rb`, `roteiro/efeitos.rb`) citam o código como está no plano da F1. Conferir no código mergeado e adaptar só a âncora, sem mudar a intenção.
- Sem Ruby local (Smart App Control): Ruby é validado pelo **CI**. Lint antes do push com `rubocop-vps <arquivos>` (Git Bash, ~10 s). Limites: `Metrics/MethodLength` 19, `Metrics/AbcSize` 26, linha 150. Se um `Metrics/*` acusar, extrair método privado (não desligar o cop).
- JS roda local: `node_modules/.bin/vitest run <spec>` e `node_modules/.bin/eslint <arquivos>`.
- **Specs em `spec/enterprise` não rodam no CI FOSS** (o CI apaga `enterprise/`). Toda lógica nova fica em `app/`; a tool do ZapSign é fina e a prova dela é o `rails runner` da Task 7.
- Migração nova: `db/schema.rb` editado à mão. Versão do topo = `2026_10_13_300001`, ou a maior já presente se a F2 tiver subido migração mais nova (nesse caso, renomear a migração para um timestamp posterior).
- `ResponseBuilderJob` e `HookExecutionService` **não mudam**: já tratam qualquer `piloto_*` (atraso aleatório, `envia?`), e o modo é lido no início do turno.
- **Texto que fala com cliente** (diretriz, skill "Fechar contrato") só é **ativado** (`rake 'ramon:inteligencia:seed[2]'`) depois do aprovado do Eduardo. O código sobe antes. **Modos "sozinha até…", tese padrão e modelo de contrato da tese só são ligados numa caixa a pedido dele.**
- i18n: `en` **e** `pt_BR` (`inboxMgmt.json`, `ramon.json`). Vue: eventos camelCase, Tailwind, sem string solta no template.
- Commits: Conventional Commits + rodapé de atribuição da sessão. Nunca `git add -A`: só os caminhos de cada task.

## Review Focus

1. **1ª mensagem do lead numa caixa com modo padrão piloto, antes de o ouvinte carimbar a conversa** → a IA já responde no modo da caixa (leitura ao vivo), não vira rascunho (Task 1).
2. **Mensagem que cita duas teses ("recebi auxílio-doença e quero o auxílio-acidente") ou palavra dentro de outra ("bpcista")** → não escolhe; cai na caixa ou no "assunto" (Task 3).
3. **Lead que já tem tese (LP, conversa anterior, escolhida à mão) ou 2ª mensagem com palavra-chave** → a tese nunca é trocada (Task 3).
4. **Limite atingido no meio do turno** → a conversa continua pendente (sem handoff), o link do contrato é devolvido à IA mesmo com o modo já em rascunho, e o aviso sai uma vez só (Tasks 5 e 6).
5. **Lead vai para Perdido (etapa depois da Reunião) ou é desqualificado no "até qualificar"** → não conta como limite; o Perdido da F1 continua direto e a IA fica calada (Task 5).

---

### Task 1: Modo do copiloto em `app/` — 3 modos, padrão da caixa e `direto?`

**Files:**
- Move: `enterprise/lib/ramon/copiloto_modo.rb` → `app/services/ramon/copiloto_modo.rb` (reescrito)
- Move: `spec/lib/ramon/copiloto_modo_default_spec.rb` → `spec/services/ramon/copiloto_modo_spec.rb` (reescrito)
- Modify: `app/models/inbox.rb` (validação do modo da caixa)
- Modify: `app/views/layouts/vueapp.html.erb:60`
- Modify: `app/services/ramon/roteiro/efeitos.rb` (`direto?`)

**Interfaces:**
- Consumes: colunas `inboxes.ramon_copiloto_modo` e `inboxes.ramon_thesis_id` (migração da F1)
- Produces:
  - `Ramon::CopilotoModo::LIMITES` = `{ 'piloto_ate_qualificacao' => 'qualificacao', 'piloto_ate_reuniao' => 'reuniao', 'piloto_ate_contrato' => 'contrato' }`
  - `Ramon::CopilotoModo::MODOS` (7 modos)
  - `Ramon::CopilotoModo.default(inbox = nil) -> String`
  - `Ramon::CopilotoModo.of(conversation) -> String` (atributo → caixa → env → rascunho)
  - `Ramon::CopilotoModo.direto?(modo) -> Boolean` (`piloto_total` e os 3 "até…")
  - `Ramon::CopilotoModo.carimbar_padrao(conversation) -> void`
  - `Ramon::Roteiro::Efeitos.direto?(lead)` passa a usar `CopilotoModo` (lead sem conversa = false)

- [ ] **Step 1: Mover os arquivos (preserva o histórico)**

```bash
git mv enterprise/lib/ramon/copiloto_modo.rb app/services/ramon/copiloto_modo.rb
git mv spec/lib/ramon/copiloto_modo_default_spec.rb spec/services/ramon/copiloto_modo_spec.rb
```

- [ ] **Step 2: Spec (falha até o Step 3)**

`spec/services/ramon/copiloto_modo_spec.rb` (conteúdo inteiro; sai o `if: ChatwootApp.enterprise?`):

```ruby
require 'rails_helper'

RSpec.describe Ramon::CopilotoModo do
  let(:inbox) { create(:inbox) }
  let(:conversation) { create(:conversation, account: inbox.account, inbox: inbox) }

  it 'sem atributo nem padrão da caixa: env válida, senão rascunho' do
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: nil do
      expect(described_class.of(conversation)).to eq('rascunho')
    end
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
      expect(described_class.of(conversation)).to eq('piloto_limitado')
    end
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'xablau' do
      expect(described_class.of(conversation)).to eq('rascunho')
    end
  end

  # Review Focus 1: a 1ª resposta é agendada antes do ouvinte carimbar — vale o padrão da caixa, lido ao vivo.
  it 'padrão da caixa vence a env; atributo da conversa vence a caixa' do
    inbox.update!(ramon_copiloto_modo: 'piloto_ate_reuniao')
    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
      expect(described_class.of(conversation.reload)).to eq('piloto_ate_reuniao')
      conversation.update!(custom_attributes: { 'copiloto_modo' => 'manual' })
      expect(described_class.of(conversation)).to eq('manual')
    end
  end

  it 'caixa recusa modo inválido e vazio vira nil' do
    expect(inbox.update(ramon_copiloto_modo: 'xablau')).to be(false)
    inbox.reload.update!(ramon_copiloto_modo: '')
    expect(inbox.reload.ramon_copiloto_modo).to be_nil
  end

  it 'os modos "sozinha até…" enviam e aplicam direto, como o piloto total' do
    described_class::LIMITES.each_key do |modo|
      expect(described_class.envia?(modo, handoff: false, logistica_ok: nil)).to be(true)
      expect(described_class.direto?(modo)).to be(true)
    end
    expect(described_class.direto?('piloto_total')).to be(true)
    expect(described_class.direto?('piloto_limitado')).to be(false)
    expect(described_class.direto?('rascunho')).to be(false)
  end

  it 'carimbar_padrao grava o modo da caixa na conversa nova sem passar por cima de escolha' do
    inbox.update!(ramon_copiloto_modo: 'piloto_ate_qualificacao')
    described_class.carimbar_padrao(conversation)
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_ate_qualificacao')

    escolhida = create(:conversation, account: inbox.account, inbox: inbox, custom_attributes: { 'copiloto_modo' => 'manual' })
    described_class.carimbar_padrao(escolhida)
    expect(escolhida.reload.custom_attributes['copiloto_modo']).to eq('manual')
  end

  it 'o roteiro aplica direto nos modos "sozinha até…", inclusive pelo padrão da caixa; lead sem conversa nunca' do
    lead = create(:lead, account: inbox.account, conversation: conversation)
    expect(Ramon::Roteiro::Efeitos.direto?(lead)).to be(false)

    inbox.update!(ramon_copiloto_modo: 'piloto_ate_contrato')
    expect(Ramon::Roteiro::Efeitos.direto?(lead.reload)).to be(true)
    expect(Ramon::Roteiro::Efeitos.direto?(create(:lead, account: inbox.account))).to be(false)
  end
end
```

- [ ] **Step 3: Implementar o modo**

`app/services/ramon/copiloto_modo.rb` (conteúdo inteiro):

```ruby
# Modo do copiloto POR CONVERSA (Onda C, spec D5; F3 do roteiro da tese). Fonte única da leitura:
# custom_attributes['copiloto_modo'] → padrão da caixa (inboxes.ramon_copiloto_modo) → RAMON_COPILOTO_MODO_DEFAULT →
# rascunho. Piloto é opt-in explícito (decisão Eduardo 14/08). Mora em app/ desde a F3: o motor do roteiro e o limite
# dos modos "sozinha até…" usam, e o CI testa.
module Ramon::CopilotoModo
  # "Sozinha até…" (spec roteiro §3.7): envia direto como o piloto total até o limite (Ramon::CopilotoLimite).
  LIMITES = { 'piloto_ate_qualificacao' => 'qualificacao', 'piloto_ate_reuniao' => 'reuniao',
              'piloto_ate_contrato' => 'contrato' }.freeze
  MODOS = (%w[manual rascunho piloto_limitado piloto_total] + LIMITES.keys).freeze
  DEFAULT = 'rascunho'.freeze

  module_function

  # D7: piloto_limitado vira padrao por env depois de ~20 conversas revisadas.
  # ponytail: a env e o padrão da caixa valem pra TODA conversa sem atributo (antigas inclusive) — antes de virar,
  # carimbar copiloto_modo=rascunho nas abertas antigas pelo console.
  def default(inbox = nil)
    caixa = inbox&.ramon_copiloto_modo
    return caixa if MODOS.include?(caixa)

    env = ENV.fetch('RAMON_COPILOTO_MODO_DEFAULT', DEFAULT).strip
    MODOS.include?(env) ? env : DEFAULT
  end

  def of(conversation)
    modo = conversation&.custom_attributes&.[]('copiloto_modo').to_s
    MODOS.include?(modo) ? modo : default(conversation&.inbox)
  end

  def piloto?(modo)
    modo.start_with?('piloto_')
  end

  # Etapa e Perdido do roteiro aplicados direto (decisões 13/10): piloto total e os modos "sozinha até…".
  def direto?(modo)
    modo == 'piloto_total' || LIMITES.key?(modo)
  end

  # Handoff é logística por definição (constraint global) — nunca vira rascunho
  # em piloto_limitado. logistica_ok nil (não classificado) é fail-safe: rascunho.
  def envia?(modo, handoff:, logistica_ok:)
    piloto?(modo) && (handoff || modo != 'piloto_limitado' || logistica_ok == true)
  end

  def carimbo(modo)
    { 'ramon_piloto' => { 'modo' => modo, 'em' => Time.zone.now.iso8601 } }
  end

  # Conversa nova numa caixa com modo padrão: grava o modo na conversa — o seletor e o "Pausar" do front leem o
  # atributo. Atributo já presente (escolhido antes de o ouvinte rodar) vence.
  def carimbar_padrao(conversation)
    modo = conversation.inbox&.ramon_copiloto_modo
    attrs = conversation.custom_attributes || {}
    return if modo.blank? || attrs.key?('copiloto_modo')

    conversation.update!(custom_attributes: attrs.merge('copiloto_modo' => modo))
  end
end
```

- [ ] **Step 4: Caixa valida o modo**

Em `app/models/inbox.rb`, logo depois de `validates :first_response_sla_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true`:

```ruby
  # ramon (F3 do roteiro): modo padrão da IA nas conversas desta caixa; vazio = padrão do sistema (env).
  validates :ramon_copiloto_modo, inclusion: { in: Ramon::CopilotoModo::MODOS }, allow_nil: true
  normalizes :ramon_copiloto_modo, with: ->(v) { v.presence }
```

- [ ] **Step 5: Layout e roteiro usam a fonte única**

`app/views/layouts/vueapp.html.erb:60` — trocar
`ramonCopilotoModoDefault: '<%= ChatwootApp.enterprise? ? Ramon::CopilotoModo.default : 'rascunho' %>'`
por:

```erb
        ramonCopilotoModoDefault: '<%= Ramon::CopilotoModo.default %>'
```

`app/services/ramon/roteiro/efeitos.rb` — trocar o comentário `ponytail` e o método `direto?` por:

```ruby
  # Etapa e Perdido direto no piloto total e nos modos "sozinha até…" (F3), pelo modo efetivo da conversa
  # (atributo → caixa → env). Lead sem conversa nunca é direto.
  def direto?(lead)
    lead.conversation.present? && Ramon::CopilotoModo.direto?(Ramon::CopilotoModo.of(lead.conversation))
  end
```

(`spec/enterprise/...response_builder_job_spec.rb`, `hook_execution_service_spec.rb` e `assistants_controller.rb` continuam achando `Ramon::CopilotoModo`: o Zeitwerk carrega de `app/services`. `default` sem argumento segue valendo para a contagem por modo do `assistants_controller`.)

- [ ] **Step 6: Lint + commit**

```bash
rubocop-vps app/services/ramon/copiloto_modo.rb spec/services/ramon/copiloto_modo_spec.rb app/models/inbox.rb app/services/ramon/roteiro/efeitos.rb
# (os caminhos antigos já estão no índice pelo git mv — não passar de novo, o git add falharia)
git add app/services/ramon/copiloto_modo.rb spec/services/ramon/copiloto_modo_spec.rb \
  app/models/inbox.rb app/views/layouts/vueapp.html.erb app/services/ramon/roteiro/efeitos.rb
git commit -m "feat(copiloto): modos 'sozinha até…', padrão da IA por caixa e modo do copiloto testado no CI"
```

---

### Task 2: Caixa — API, carimbo na conversa nova e tela

**Files:**
- Modify: `app/controllers/api/v1/accounts/inboxes_controller.rb:162` (permit)
- Modify: `app/views/api/v1/models/_inbox.json.jbuilder` (2 campos)
- Modify: `app/listeners/ramon_lead_listener.rb` (`conversation_created`)
- Modify: `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb`, `spec/listeners/ramon_lead_listener_spec.rb`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js` + `helpers/specs/copilotoModo.spec.js`
- Modify: `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue` (`MODO_TOM`)
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/inboxMgmt.json`, `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`

**Interfaces:**
- Consumes: `Ramon::CopilotoModo.carimbar_padrao`, `MODOS` (Task 1); store `theses/get` + getter `theses/getTheses` (já existem)
- Produces: API da caixa aceita e devolve `ramon_thesis_id` (Integer|null) e `ramon_copiloto_modo` (String|null); front `MODOS` com 7 modos; i18n `RAMON.COPILOTO.MODOS.<modo>.NOME/DESC` dos 3 novos

- [ ] **Step 1: Specs Ruby (falham)**

Em `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb`, logo depois do `it 'enables portaria_enabled on the inbox'`:

```ruby
      it 'sets the default thesis and AI mode of the inbox' do
        thesis = account.theses.first
        patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
              headers: admin.create_new_auth_token,
              params: valid_params.merge({ ramon_thesis_id: thesis.id, ramon_copiloto_modo: 'piloto_ate_reuniao' }),
              as: :json

        expect(response).to have_http_status(:success)
        expect(inbox.reload).to have_attributes(ramon_thesis_id: thesis.id, ramon_copiloto_modo: 'piloto_ate_reuniao')
      end

      it 'rejects an unknown AI mode' do
        patch "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}",
              headers: admin.create_new_auth_token,
              params: valid_params.merge({ ramon_copiloto_modo: 'xablau' }),
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(inbox.reload.ramon_copiloto_modo).to be_nil
      end
```

Em `spec/listeners/ramon_lead_listener_spec.rb`, logo depois do `it 'não cria se a inbox não tem auto_create_lead'`:

```ruby
  it 'carimba o modo padrão da caixa na conversa nova, mesmo sem Criar lead' do
    inbox.update!(auto_create_lead: false, ramon_copiloto_modo: 'piloto_ate_qualificacao')
    listener.conversation_created(event)
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_ate_qualificacao')
  end
```

- [ ] **Step 2: API e ouvinte**

`app/controllers/api/v1/accounts/inboxes_controller.rb` — em `inbox_attributes`, trocar
`:lock_to_single_conversation, :portal_id, :sender_name_type, :business_name, :auto_create_lead, :first_response_sla_minutes, :portaria_enabled,`
por:

```ruby
     :lock_to_single_conversation, :portal_id, :sender_name_type, :business_name, :auto_create_lead, :first_response_sla_minutes, :portaria_enabled,
     :ramon_thesis_id, :ramon_copiloto_modo,
```

`app/views/api/v1/models/_inbox.json.jbuilder` — depois de `json.portaria_enabled resource.portaria_enabled`:

```ruby
json.ramon_thesis_id resource.ramon_thesis_id
json.ramon_copiloto_modo resource.ramon_copiloto_modo
```

`app/listeners/ramon_lead_listener.rb` — início de `conversation_created`:

```ruby
  def conversation_created(event)
    conversation = event.data[:conversation]
    # F3: modo padrão da IA da caixa vira atributo da conversa (o front lê o atributo). Vale com ou sem "Criar lead".
    Ramon::CopilotoModo.carimbar_padrao(conversation)
    return unless Ramon::LeadDaConversa.cabe?(conversation)
```

(o resto do método fica igual).

- [ ] **Step 3: Front — modos (spec + helper)**

`app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/copilotoModo.spec.js` — novo `it` no fim do `describe`:

```js
  it('aceita os modos "sozinha até…"', () => {
    expect(
      copilotoModoDe({
        custom_attributes: { copiloto_modo: 'piloto_ate_reuniao' },
      })
    ).toBe('piloto_ate_reuniao');
  });
```

`app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js` — trocar a 1ª linha por:

```js
export const MODOS = [
  'manual',
  'rascunho',
  'piloto_limitado',
  'piloto_total',
  'piloto_ate_qualificacao',
  'piloto_ate_reuniao',
  'piloto_ate_contrato',
];
```

`app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue` — em `MODO_TOM`, depois de `piloto_total: TOM.ruby,`:

```js
  piloto_ate_qualificacao: TOM.ruby,
  piloto_ate_reuniao: TOM.ruby,
  piloto_ate_contrato: TOM.ruby,
```

- [ ] **Step 4: i18n**

`app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` — em `RAMON.COPILOTO.MODOS`, depois do bloco `piloto_total` (pôr vírgula no `}` dele):

```json
        "piloto_ate_qualificacao": {
          "NOME": "Sozinha até qualificar",
          "DESC": "A IA responde tudo sozinha até o roteiro da tese qualificar o lead; aí volta para Rascunho e avisa o responsável."
        },
        "piloto_ate_reuniao": {
          "NOME": "Sozinha até a reunião",
          "DESC": "A IA responde tudo sozinha até a reunião ser marcada; aí volta para Rascunho e avisa o responsável."
        },
        "piloto_ate_contrato": {
          "NOME": "Sozinha até o contrato",
          "DESC": "A IA responde tudo sozinha e envia o link do contrato quando o cadastro estiver completo; aí volta para Rascunho e avisa o responsável."
        }
```

`app/javascript/dashboard/i18n/locale/en/ramon.json` — mesmo lugar:

```json
        "piloto_ate_qualificacao": {
          "NOME": "On its own until qualified",
          "DESC": "The AI replies on its own until the thesis script qualifies the lead; then it goes back to Draft and alerts the owner."
        },
        "piloto_ate_reuniao": {
          "NOME": "On its own until the meeting",
          "DESC": "The AI replies on its own until the meeting is booked; then it goes back to Draft and alerts the owner."
        },
        "piloto_ate_contrato": {
          "NOME": "On its own until the contract",
          "DESC": "The AI replies on its own and sends the contract link once the client's data is complete; then it goes back to Draft and alerts the owner."
        }
```

`app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json` — em `INBOX_MGMT.SETTINGS_POPUP`, entre o bloco `"AUTO_CREATE_LEAD"` e `"PORTARIA"`:

```json
      "RAMON_TESE_PADRAO": {
        "LABEL": "Tese padrão da caixa",
        "SUB_TEXT": "Lead novo sem tese recebe esta tese quando a 1ª mensagem não traz palavra-chave de nenhuma tese.",
        "NENHUMA": "Nenhuma (só palavra-chave)"
      },
      "RAMON_MODO_PADRAO": {
        "LABEL": "Modo padrão da IA nesta caixa",
        "SUB_TEXT": "Vale para as conversas novas desta caixa. Cada conversa ainda pode trocar o modo no botão Copiloto.",
        "SISTEMA": "Padrão do sistema"
      },
```

`app/javascript/dashboard/i18n/locale/en/inboxMgmt.json` — mesmo lugar:

```json
      "RAMON_TESE_PADRAO": {
        "LABEL": "Default thesis for this inbox",
        "SUB_TEXT": "A new lead without a thesis gets this one when the first message has no thesis keyword.",
        "NENHUMA": "None (keywords only)"
      },
      "RAMON_MODO_PADRAO": {
        "LABEL": "Default AI mode for this inbox",
        "SUB_TEXT": "Applies to new conversations in this inbox. Each conversation can still change it in the Copilot button.",
        "SISTEMA": "System default"
      },
```

- [ ] **Step 5: Tela da caixa (`Settings.vue`)**

a) Imports — depois de `import SelectInput from 'dashboard/components-next/select/Select.vue';`:

```js
import { MODOS as COPILOTO_MODOS } from 'dashboard/routes/dashboard/ramon/helpers/copilotoModo';
```

b) `data()` — depois de `firstResponseSlaMinutes: null,`:

```js
      ramonThesisId: '',
      ramonCopilotoModo: '',
      copilotoModos: COPILOTO_MODOS,
```

c) `computed` → `...mapGetters({ ... })` — depois de `portals: 'portals/allPortals',`:

```js
      theses: 'theses/getTheses',
```

d) `fetchSharedData()` — depois de `this.$store.dispatch('portals/index');`:

```js
      this.$store.dispatch('theses/get');
```

e) `syncInboxData()` — depois de `this.firstResponseSlaMinutes = this.inbox.first_response_sla_minutes;`:

```js
      this.ramonThesisId = this.inbox.ramon_thesis_id
        ? String(this.inbox.ramon_thesis_id)
        : '';
      this.ramonCopilotoModo = this.inbox.ramon_copiloto_modo || '';
```

f) Payload do salvar — depois do bloco `first_response_sla_minutes: ... : null,`:

```js
          ramon_thesis_id: this.ramonThesisId
            ? Number(this.ramonThesisId)
            : null,
          ramon_copiloto_modo: this.ramonCopilotoModo || null,
```

g) Template — logo depois do `</SettingsToggleSection>` que fecha o `v-model="autoCreateLead"`:

```vue
              <SettingsFieldSection
                v-if="autoCreateLead"
                :label="$t('INBOX_MGMT.SETTINGS_POPUP.RAMON_TESE_PADRAO.LABEL')"
                :help-text="
                  $t('INBOX_MGMT.SETTINGS_POPUP.RAMON_TESE_PADRAO.SUB_TEXT')
                "
              >
                <SelectInput
                  v-model="ramonThesisId"
                  :options="[
                    {
                      value: '',
                      label: $t(
                        'INBOX_MGMT.SETTINGS_POPUP.RAMON_TESE_PADRAO.NENHUMA'
                      ),
                    },
                    ...theses.map(tese => ({
                      value: String(tese.id),
                      label: tese.name,
                    })),
                  ]"
                />
              </SettingsFieldSection>

              <SettingsFieldSection
                :label="$t('INBOX_MGMT.SETTINGS_POPUP.RAMON_MODO_PADRAO.LABEL')"
                :help-text="
                  $t('INBOX_MGMT.SETTINGS_POPUP.RAMON_MODO_PADRAO.SUB_TEXT')
                "
              >
                <SelectInput
                  v-model="ramonCopilotoModo"
                  :options="[
                    {
                      value: '',
                      label: $t(
                        'INBOX_MGMT.SETTINGS_POPUP.RAMON_MODO_PADRAO.SISTEMA'
                      ),
                    },
                    ...copilotoModos.map(modo => ({
                      value: modo,
                      label: $t(`RAMON.COPILOTO.MODOS.${modo}.NOME`),
                    })),
                  ]"
                />
              </SettingsFieldSection>
```

- [ ] **Step 6: Rodar JS e lint**

```bash
node_modules/.bin/vitest run app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/copilotoModo.spec.js \
  app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/CopilotoModoSelector.spec.js \
  app/javascript/dashboard/components-next/message/specs/PilotoCarimbo.spec.js
node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js \
  app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue
rubocop-vps app/controllers/api/v1/accounts/inboxes_controller.rb app/listeners/ramon_lead_listener.rb \
  spec/controllers/api/v1/accounts/inboxes_controller_spec.rb spec/listeners/ramon_lead_listener_spec.rb
```

Esperado: specs JS PASS (o seletor lista 7 opções; os specs existentes não contam opções); eslint/rubocop sem ofensa.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/accounts/inboxes_controller.rb app/views/api/v1/models/_inbox.json.jbuilder app/listeners/ramon_lead_listener.rb \
  spec/controllers/api/v1/accounts/inboxes_controller_spec.rb spec/listeners/ramon_lead_listener_spec.rb \
  app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/copilotoModo.spec.js \
  app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue \
  app/javascript/dashboard/i18n/locale/en/inboxMgmt.json app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json \
  app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(caixa): tese padrão e modo padrão da IA nas configurações da caixa"
```

---

### Task 3: Tese automática na 1ª mensagem

**Files:**
- Create: `app/services/ramon/tese_automatica.rb`
- Create: `spec/services/ramon/tese_automatica_spec.rb`
- Modify: `app/services/ramon/lead_da_conversa.rb` (`origem`)
- Modify: `spec/listeners/ramon_lead_listener_spec.rb` (1 teste pelo ouvinte)

**Interfaces:**
- Consumes: `theses.palavras_chave` (F1), `inboxes.ramon_thesis_id` (F1), `Ramon::LeadDaConversa.referral_da(message)`
- Produces:
  - `Ramon::TeseAutomatica.por_texto(account, *textos) -> Thesis | nil` (só tese ativa; nenhuma ou mais de uma = nil)
  - `Ramon::TeseAutomatica.definir(lead, message) -> void` (só lead sem tese, só 1ª mensagem do cliente na conversa)
  - `Ramon::TeseAutomatica.normal(texto) -> String`

- [ ] **Step 1: Spec (falha)**

`spec/services/ramon/tese_automatica_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::TeseAutomatica do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:lead) { create(:lead, account: account, conversation: conversation, contact: conversation.contact) }
  # Toda conta nasce com as teses do theses_seed.yml (Leads::SeedDefaultConfigService).
  let!(:acidente) do
    account.theses.find_by!(name: 'Auxílio-acidente (B36)').tap { |t| t.update!(palavras_chave: ['auxílio-acidente', 'acidente de trabalho']) }
  end
  let!(:bpc) { account.theses.find_by!(name: 'BPC/LOAS por deficiência').tap { |t| t.update!(palavras_chave: %w[bpc loas]) } }

  def mensagem(texto, **attrs)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: texto, **attrs)
  end

  describe '.por_texto' do
    it 'casa palavra ou frase inteira, sem acento nem caixa' do
      expect(described_class.por_texto(account, 'Sofri um ACIDENTE DE TRABALHO')).to eq(acidente)
      expect(described_class.por_texto(account, 'quero o Bpc da minha filha')).to eq(bpc)
      expect(described_class.por_texto(account, 'sou bpcista')).to be_nil
    end

    # Review Focus 2: tese errada é pior que nenhuma.
    it 'duas teses = não escolhe; tese inativa não conta; nada = nil' do
      expect(described_class.por_texto(account, 'tenho bpc e sofri acidente de trabalho')).to be_nil
      bpc.update!(active: false)
      expect(described_class.por_texto(account, 'tenho bpc e sofri acidente de trabalho')).to eq(acidente)
      expect(described_class.por_texto(account, nil, 'oi, tudo bem?')).to be_nil
    end

    it 'slug da campanha da LP casa com a palavra-chave' do
      expect(described_class.por_texto(account, 't-auxilio-acidente-desqualificado')).to eq(acidente)
    end
  end

  describe '.definir' do
    it '1ª mensagem com palavra-chave define a tese e vence a tese da caixa' do
      inbox.update!(ramon_thesis_id: bpc.id)
      described_class.definir(lead, mensagem('me acidentei, foi acidente de trabalho'))
      expect(lead.reload.thesis).to eq(acidente)
    end

    it 'sem palavra-chave: tese padrão da caixa' do
      inbox.update!(ramon_thesis_id: bpc.id)
      described_class.definir(lead, mensagem('oi, boa tarde'))
      expect(lead.reload.thesis).to eq(bpc)
    end

    it 'campanha da LP e título do anúncio da Meta contam' do
      lead.update!(source: 'bpc-loas')
      described_class.definir(lead, mensagem('oi'))
      expect(lead.reload.thesis).to eq(bpc)

      outra = create(:conversation, account: account, inbox: inbox)
      lead2 = create(:lead, account: account, conversation: outra, contact: outra.contact)
      anuncio = create(:message, account: account, conversation: outra, message_type: :incoming, content: 'oi',
                                 content_attributes: { referral: { 'headline' => 'Machucou no trabalho? Acidente de trabalho' } })
      described_class.definir(lead2, anuncio)
      expect(lead2.reload.thesis).to eq(acidente)
    end

    # Review Focus 3: a tese nunca é trocada nem decidida depois da 1ª mensagem.
    it 'só na 1ª mensagem e só para lead sem tese' do
      mensagem('oi')
      described_class.definir(lead, mensagem('acidente de trabalho'))
      expect(lead.reload.thesis).to be_nil

      outra = create(:conversation, account: account, inbox: inbox)
      com_tese = create(:lead, account: account, conversation: outra, contact: outra.contact, thesis: bpc)
      primeira = create(:message, account: account, conversation: outra, message_type: :incoming, content: 'acidente de trabalho')
      described_class.definir(com_tese, primeira)
      expect(com_tese.reload.thesis).to eq(bpc)
    end
  end
end
```

Em `spec/listeners/ramon_lead_listener_spec.rb`, novo bloco no fim do `RSpec.describe` (antes do último `end`):

```ruby
  describe '#message_created -> tese automática (F3)' do
    it 'lead sem tese recebe a tese padrão da caixa na 1ª mensagem' do
      tese = account.theses.first
      inbox.update!(ramon_thesis_id: tese.id)
      lead = create(:lead, account: account, conversation: conversation, contact: contact)
      msg = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')
      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: msg))
      expect(lead.reload.thesis).to eq(tese)
    end
  end
```

- [ ] **Step 2: Implementar**

`app/services/ramon/tese_automatica.rb`:

```ruby
# Tese automática do lead (spec roteiro §3.6, F3). Na 1ª mensagem do cliente, lead sem tese ganha a tese pela
# palavra-chave — na campanha da LP (lead.source, ex. "t-auxilio-acidente"), no texto da mensagem ou no título do
# anúncio da Meta — e, sem palavra, pela tese padrão da caixa. Sem nada, o passo comum "assunto" do roteiro pergunta.
# Também casa a resposta do "assunto" (Ramon::Roteiro::Registro). Tese nunca é trocada aqui.
module Ramon::TeseAutomatica
  module_function

  def definir(lead, message)
    return if lead.thesis_id || !primeira?(message)

    titulo_anuncio = Ramon::LeadDaConversa.referral_da(message)&.dig('headline')
    tese = por_texto(lead.account, lead.source, message.content, titulo_anuncio) ||
           lead.account.theses.find_by(id: message.inbox&.ramon_thesis_id)
    lead.update!(thesis: tese) if tese
  end

  # Palavra ou frase inteira, sem acento nem caixa, contra palavras-chave e nome das teses ativas.
  # Duas teses casando = ambíguo = nil (tese errada é pior que nenhuma).
  def por_texto(account, *textos)
    alvo = " #{textos.map { |texto| normal(texto) }.join(' ')} "
    achadas = account.theses.where(active: true).select do |tese|
      (tese.palavras_chave + [tese.name]).any? { |termo| casa?(alvo, normal(termo)) }
    end
    achadas.first if achadas.one?
  end

  def casa?(alvo, termo) = termo.present? && alvo.include?(" #{termo} ")

  def primeira?(message)
    message.conversation.messages.incoming.where(id: ...message.id).none?
  end

  def normal(texto)
    I18n.transliterate(texto.to_s).downcase.gsub(/[^a-z0-9]+/, ' ').strip
  end
end
```

`app/services/ramon/lead_da_conversa.rb` — trocar `origem` por:

```ruby
  def origem(lead, message)
    apply_meta_referral(lead, message)
    derive_channel_from_first_contact(lead, message)
    Ramon::TeseAutomatica.definir(lead, message)
  end
```

(Corrida conhecida: em rascunho, sem atraso, a IA pode rodar antes do ouvinte e perguntar o "assunto"; se a tese chegar depois, `roteiro_registrar('assunto')` volta "Passo assunto nao existe" e a IA chama o passo atual de novo. Nos modos piloto há o atraso de 30 s a 3 min, e a tese chega antes.)

- [ ] **Step 3: Lint + commit**

```bash
rubocop-vps app/services/ramon/tese_automatica.rb spec/services/ramon/tese_automatica_spec.rb app/services/ramon/lead_da_conversa.rb \
  spec/listeners/ramon_lead_listener_spec.rb
git add app/services/ramon/tese_automatica.rb spec/services/ramon/tese_automatica_spec.rb app/services/ramon/lead_da_conversa.rb \
  spec/listeners/ramon_lead_listener_spec.rb
git commit -m "feat(roteiro): tese automática do lead pela campanha, palavra-chave da 1ª mensagem ou caixa"
```

---

### Task 4: Passo comum "assunto" no roteiro

**Files:**
- Modify: `app/services/ramon/roteiro.rb` (`ASSUNTO`, `passos`, `TIPOS`, `descrever`)
- Modify: `app/services/ramon/roteiro/registro.rb` (`call` + `assunto?`/`assunto`)
- Create: `spec/services/ramon/roteiro_assunto_spec.rb`

**Interfaces:**
- Consumes: `Ramon::TeseAutomatica.por_texto` (Task 3); motor da F1 (`passos`, `estado`, `Registro`)
- Produces:
  - `Ramon::Roteiro::ASSUNTO = 'assunto'`
  - `Ramon::Roteiro.passos(lead)`: lead sem tese → comuns, **só se** existir o comum `assunto` (senão `[]`); lead com tese → comuns sem o `assunto` + os da tese
  - registrar `assunto`: casou uma tese → `lead.thesis` gravada, `proximo` = 1º passo pendente do novo roteiro; nenhuma ou duas → desfecho `humano`, motivo `assunto sem tese cadastrada`

- [ ] **Step 1: Spec (falha)**

`spec/services/ramon/roteiro_assunto_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Roteiro, 'passo comum assunto' do
  let(:account) { create(:account) }
  let(:acidente) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:lead) { create(:lead, account: account, conversation: conversation) }

  before do
    create(:user, account: account, role: :administrator)
    acidente.update!(palavras_chave: ['acidente de trabalho'])
    create(:roteiro_passo, account: account, thesis: nil, chave: 'assunto', position: 1, titulo: 'Assunto', tipo_resposta: 'texto')
    create(:roteiro_passo, account: account, thesis: nil, chave: 'tem_advogado', position: 2, titulo: 'Tem advogado')
    create(:roteiro_passo, account: account, thesis: acidente, chave: 'sequela', position: 1, titulo: 'Sequela')
  end

  it 'sem o passo assunto cadastrado, lead sem tese segue sem roteiro (como na F1)' do
    RoteiroPasso.find_by!(chave: 'assunto').destroy!
    expect(described_class.atual(lead)).to be_nil
  end

  it 'lead sem tese começa pelo assunto; com tese, o assunto some da lista' do
    expect(described_class.atual(lead)[:passo].chave).to eq('assunto')
    lead.update!(thesis: acidente)
    expect(described_class.passos(lead.reload).map(&:chave)).to eq(%w[tem_advogado sequela])
  end

  it 'resposta casa com a tese: o lead ganha a tese e o roteiro segue nos passos dela' do
    res = described_class.registrar(lead, chave: 'assunto', valor: 'sofri acidente de trabalho na obra')

    expect(lead.reload.thesis).to eq(acidente)
    expect(res[:proximo].chave).to eq('tem_advogado')
    expect(res[:estado]).to include('tese_id' => acidente.id)
    expect(res[:estado]['respostas']).to have_key('assunto')
    expect(described_class.atual(lead)[:passo].chave).to eq('tem_advogado')
  end

  it 'resposta sem tese vai para a equipe' do
    res = described_class.registrar(lead, chave: 'assunto', valor: 'pensao alimenticia')
    expect(res[:estado]).to include('desfecho' => 'humano', 'motivo' => 'assunto sem tese cadastrada')
    expect(lead.reload.thesis).to be_nil
  end

  it 'descrever do assunto não pede saida_id (passo de texto sem saídas)' do
    texto = described_class.descrever(*described_class.atual(lead).values_at(:passo, :estado))
    expect(texto).to include('Passo atual: Assunto').and include('texto livre')
    expect(texto).not_to include('saida_id')
  end
end
```

- [ ] **Step 2: `Ramon::Roteiro`**

Em `app/services/ramon/roteiro.rb`:

a) Em `TIPOS`, trocar `'texto' => 'texto livre + saida_id'` por `'texto' => 'texto livre'`.

b) Logo depois de `COMUNS_OK = …freeze`:

```ruby
  # Passo comum que descobre a tese do lead que chegou sem (spec §3.6, F3). Chave fixa.
  ASSUNTO = 'assunto'.freeze
```

c) Trocar o método `passos` (e o comentário `ponytail` acima dele) por:

```ruby
  # Comuns da conta (em toda tese) e depois os da tese. Nenhum passo = sem roteiro (triagem de sempre).
  # Lead sem tese (F3): só os comuns, e só se existir o comum "assunto" — é ele que descobre a tese. Com tese, ele sai.
  def passos(lead)
    comuns = RoteiroPasso.comuns.where(account_id: lead.account_id).to_a
    sem_tese = lead.thesis_id.nil?
    return [] if sem_tese && comuns.none? { |p| p.chave == ASSUNTO }
    return comuns if sem_tese

    comuns.reject { |p| p.chave == ASSUNTO } + RoteiroPasso.where(thesis_id: lead.thesis_id).to_a
  end
```

d) Em `descrever`, trocar a condição da linha das saídas
`… if passo.tipo_resposta == 'texto'`
por:

```ruby
… if passo.tipo_resposta == 'texto' && passo.saidas.present?
```

(o texto da linha — `"Saidas (informe saida_id): …"` — fica igual).

- [ ] **Step 3: `Registro`**

Em `app/services/ramon/roteiro/registro.rb`, no `call`, trocar
`saida = escolher(saida_id, calc ? calc[:resultado] : normal)`
por:

```ruby
    saida = assunto? ? assunto(normal) : escolher(saida_id, calc ? calc[:resultado] : normal)
```

E na seção `private`, depois de `escolher`:

```ruby
  def assunto?
    @passo.thesis_id.nil? && @passo.chave == Ramon::Roteiro::ASSUNTO
  end

  # Passo comum "assunto" (F3): a resposta casa com nome/palavras-chave das teses. Casou com uma → o lead ganha a tese
  # e o roteiro segue nos passos dela (as respostas dos comuns ficam); nenhuma ou mais de uma → equipe.
  def assunto(texto)
    tese = Ramon::TeseAutomatica.por_texto(@lead.account, texto)
    return { 'id' => 'sem_tese', 'acao' => 'humano', 'motivo' => 'assunto sem tese cadastrada' } if tese.nil?

    @lead.update!(thesis: tese)
    @lista = Ramon::Roteiro.passos(@lead)
    @est = Ramon::Roteiro.estado(@lead)
    { 'id' => 'tese', 'acao' => 'seguir' }
  end
```

(Por que funciona sem mais nada: com a tese nova, `estado` recomeça mantendo as respostas dos comuns; o `gravar` da F1 grava o `assunto` nesse estado novo; o `avancar` acha o 1º passo pendente da lista nova. Tese sem passos próprios: ao fim dos comuns, a IA recebe "siga a triagem de sempre", como na F1.)

- [ ] **Step 4: Lint + commit**

```bash
rubocop-vps app/services/ramon/roteiro.rb app/services/ramon/roteiro/registro.rb spec/services/ramon/roteiro_assunto_spec.rb
git add app/services/ramon/roteiro.rb app/services/ramon/roteiro/registro.rb spec/services/ramon/roteiro_assunto_spec.rb
git commit -m "feat(roteiro): passo comum assunto descobre a tese do lead que chegou sem"
```

---

### Task 5: Limite dos modos "sozinha até…"

**Files:**
- Create: `app/services/ramon/copiloto_limite.rb`
- Create: `spec/services/ramon/copiloto_limite_spec.rb`
- Modify: `app/models/lead.rb` (callback)
- Modify: `app/services/ramon/roteiro/efeitos.rb` (`aplicar` confere o limite no fim)

**Interfaces:**
- Consumes: `Ramon::CopilotoModo::LIMITES`, `.of` (Task 1); `Ramon::ReuniaoAgendamento::STAGE_LABEL`; `Ramon::LeadNotificationBuilder`, `Ramon::NtfyPushJob`, `Ramon::Papeis.gestor_ids`
- Produces:
  - `Ramon::CopilotoLimite::NIVEIS = %w[qualificacao reuniao contrato]`
  - `Ramon::CopilotoLimite.verificar(lead) -> String | nil` (limite encerrado agora)
  - `Ramon::CopilotoLimite.encerrar(lead, limite, motivo = nil) -> String | nil` (idempotente: fora de modo "até…" não faz nada)
  - `Ramon::CopilotoLimite.atingido?(limite, lead) -> Boolean`, `.nivel(lead) -> String | nil`
  - carimbo na conversa: `custom_attributes['copiloto_limite'] = { 'limite', 'modo', 'motivo'?, 'em' }` (o `bi_roteiro` da F4 lê daqui)

- [ ] **Step 1: Spec (falha)**

`spec/services/ramon/copiloto_limite_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::CopilotoLimite do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: etapa('Novo'), conversation: conversation) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  def etapa(nome) = account.lead_stages.find_by!(name: nome)
  def modo!(modo) = conversation.update!(custom_attributes: { 'copiloto_modo' => modo })
  def avisos = Notification.where(user: admin, primary_actor: lead, notification_type: 'ramon_fluxo_aviso')

  # Review Focus 4: sem handoff (a resposta do turno ainda sai) e aviso uma vez só.
  it 'até reunião: Reunião agendada volta a conversa para rascunho, carimba e avisa uma vez, sem handoff' do
    modo!('piloto_ate_reuniao')
    lead.update!(lead_stage: etapa('Qualificação'))
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_ate_reuniao')

    lead.update!(lead_stage: etapa('Reunião agendada'))
    expect(conversation.reload.custom_attributes).to include(
      'copiloto_modo' => 'rascunho', 'copiloto_limite' => include('limite' => 'reuniao', 'modo' => 'piloto_ate_reuniao')
    )
    expect(conversation.status).to eq('pending')

    lead.update!(lead_stage: etapa('Negociação'))
    expect(avisos.count).to eq(1)
  end

  # Review Focus 5.
  it 'Perdido não conta como reunião; ganho conta' do
    modo!('piloto_ate_reuniao')
    lead.update!(lead_stage: account.lead_stages.find_by!(is_lost: true))
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_ate_reuniao')

    ganho = account.lead_stages.find_by!(is_won: true)
    lead.update_columns(lead_stage_id: ganho.id, won_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- sem o fluxo "Lead ganho"
    expect(described_class.atingido?('reuniao', lead.reload)).to be(true)
  end

  it 'link do ZapSign no lead encerra o "até contrato" e, pela ordem dos limites, também o "até reunião"' do
    modo!('piloto_ate_reuniao')
    lead.update!(custom_attributes: { 'zapsign' => { 'sign_url' => 'https://zap/x' } })
    expect(conversation.reload.custom_attributes['copiloto_limite']).to include('limite' => 'reuniao')
  end

  it 'até qualificar: roteiro qualificado muda a etapa direto e depois encerra o modo' do
    modo!('piloto_ate_qualificacao')
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'sequela', titulo: 'Sequela',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'concluir', 'efeitos' => { 'etapa' => 'Qualificação' } }])

    Ramon::Roteiro.registrar(lead, chave: 'sequela', valor: 'sim')

    expect(lead.reload.lead_stage).to eq(etapa('Qualificação'))
    expect(account.copilot_suggestions.count).to eq(0)
    expect(conversation.reload.custom_attributes).to include('copiloto_modo' => 'rascunho',
                                                             'copiloto_limite' => include('limite' => 'qualificacao'))
    expect(avisos.count).to eq(1)
  end

  # Review Focus 5: desqualificado não é limite — segue o Perdido direto e a IA calada (F1).
  it 'até qualificar: desqualificado vai direto para Perdido com a IA calada, sem carimbo de limite' do
    modo!('piloto_ate_qualificacao')
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'tem_advogado', titulo: 'Tem advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado' }])

    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim')

    expect(lead.reload.lead_stage).to eq(account.lead_stages.find_by!(is_lost: true))
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('manual')
    expect(conversation.custom_attributes).not_to have_key('copiloto_limite')
  end

  it 'até qualificar numa tese sem roteiro: para na reunião' do
    modo!('piloto_ate_qualificacao')
    lead.update!(lead_stage: etapa('Reunião agendada'))
    expect(conversation.reload.custom_attributes['copiloto_limite']).to include('limite' => 'qualificacao')
  end

  it 'fora dos modos "sozinha até…" nada muda' do
    modo!('piloto_total')
    lead.update!(lead_stage: etapa('Reunião agendada'))
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_total')
    expect(described_class.encerrar(lead, 'contrato', 'x')).to be_nil
    expect(avisos.count).to eq(0)
  end
end
```

- [ ] **Step 2: Implementar o limite**

`app/services/ramon/copiloto_limite.rb`:

```ruby
# Modos "sozinha até…" (spec roteiro §3.7, F3): a IA envia direto até o limite do modo; ao atingir, a conversa volta
# para rascunho, fica o carimbo copiloto_limite (métricas da F4) e o responsável recebe sino + push.
# SEM handoff: a resposta do turno que atingiu o limite ainda sai (o ResponseBuilderJob guarda o modo do início e só
# publica com a conversa pendente) — é assim que o link do contrato chega ao lead.
# Níveis em ordem: chegar a um mais adiante também encerra os de antes. Quem chama: Lead (etapa ou ZapSign mudou),
# o roteiro (fim de Efeitos.aplicar) e o contrato automático que não saiu (Ramon::ContratoAutomatico).
module Ramon::CopilotoLimite
  NIVEIS = %w[qualificacao reuniao contrato].freeze
  NOMES = { 'qualificacao' => 'lead qualificado', 'reuniao' => 'reunião marcada', 'contrato' => 'contrato enviado' }.freeze

  module_function

  # @return [String, nil] o limite encerrado agora
  def verificar(lead)
    return if lead.conversation.nil?

    limite = Ramon::CopilotoModo::LIMITES[Ramon::CopilotoModo.of(lead.conversation)]
    encerrar(lead, limite) if limite && atingido?(limite, lead)
  end

  # Idempotente: fora de um modo "até…" (já encerrado, ou nunca esteve) não faz nada.
  def encerrar(lead, limite, motivo = nil)
    conversa = lead.conversation
    modo = conversa && Ramon::CopilotoModo.of(conversa)
    return unless Ramon::CopilotoModo::LIMITES.key?(modo)

    carimbo = { 'limite' => limite, 'modo' => modo, 'motivo' => motivo, 'em' => Time.zone.now.iso8601 }.compact
    conversa.update!(custom_attributes: (conversa.custom_attributes || {}).merge('copiloto_modo' => 'rascunho',
                                                                                 'copiloto_limite' => carimbo))
    avisar(lead, limite, motivo)
    limite
  end

  def atingido?(limite, lead)
    alcancado = nivel(lead)
    !alcancado.nil? && NIVEIS.index(alcancado) >= NIVEIS.index(limite)
  end

  # Qualificação = só o desfecho qualificado do roteiro (desqualificado/equipe já encerram pelos efeitos da F1).
  def nivel(lead)
    return 'contrato' if lead.custom_attributes&.dig('zapsign', 'sign_url').present?
    return 'reuniao' if reuniao?(lead)

    'qualificacao' if lead.custom_attributes&.dig('roteiro', 'desfecho') == 'qualificado'
  end

  # Reunião agendada ou qualquer etapa depois dela (ganho incluso); Perdido não conta.
  def reuniao?(lead)
    etapa = lead.lead_stage
    marco = lead.account.lead_stages.find_by(label: Ramon::ReuniaoAgendamento::STAGE_LABEL)
    etapa.present? && marco.present? && !etapa.is_lost && etapa.position >= marco.position
  end

  # Mesmo destino do "IA passou para a equipe" (Efeitos.humano): closer/SDR do lead, sem eles os gestores.
  def avisar(lead, limite, motivo)
    ids = [lead.closer_id || lead.sdr_id].compact.presence || Ramon::Papeis.gestor_ids(lead.account)
    texto = "IA chegou ao limite (#{NOMES[limite]}) com #{lead.name}#{": #{motivo}" if motivo} - conversa em rascunho"
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso', user_ids: ids,
                                       meta: { 'label' => texto.truncate(200) }).perform
    Ramon::NtfyPushJob.perform_later(lead.id, title: "IA chegou ao limite: #{lead.name}", body: (motivo || NOMES[limite]).truncate(200))
  end
end
```

- [ ] **Step 3: Quem chama**

`app/models/lead.rb` — logo depois da linha `after_update_commit :ganhou, if: :saved_change_to_won_at?` (e da `reabrir_roteiro` da F1):

```ruby
  after_update_commit :verificar_limite_copiloto, if: -> { saved_change_to_lead_stage_id? || zapsign_mudou? }
```

Na seção privada, depois de `ganhou`:

```ruby
  # Modos "sozinha até…" (F3): etapa (reunião) ou contrato do ZapSign mudou → a IA pode ter chegado ao limite.
  # Mudança só do roteiro NÃO entra aqui: o roteiro confere no fim dos efeitos (Efeitos.aplicar), senão o rascunho
  # entraria antes da etapa/Perdido direto e os viraria sugestão.
  def verificar_limite_copiloto
    Ramon::CopilotoLimite.verificar(self)
  end

  def zapsign_mudou?
    saved_change_to_custom_attributes? &&
      custom_attributes_before_last_save.to_h['zapsign'] != custom_attributes.to_h['zapsign']
  end
```

`app/services/ramon/roteiro/efeitos.rb` — última linha de `aplicar` (depois do `anotar(...)`):

```ruby
    Ramon::CopilotoLimite.verificar(lead)
```

- [ ] **Step 4: Lint + commit**

```bash
rubocop-vps app/services/ramon/copiloto_limite.rb spec/services/ramon/copiloto_limite_spec.rb app/models/lead.rb app/services/ramon/roteiro/efeitos.rb
git add app/services/ramon/copiloto_limite.rb spec/services/ramon/copiloto_limite_spec.rb app/models/lead.rb app/services/ramon/roteiro/efeitos.rb
git commit -m "feat(copiloto): limite dos modos 'sozinha até…' volta a conversa para rascunho e avisa o responsável"
```

---

### Task 6: Contrato na hora no modo "sozinha até o contrato"

**Files:**
- Create: `db/migrate/20261013300001_add_zapsign_template_id_to_theses.rb`
- Modify: `db/schema.rb`
- Create: `app/services/ramon/contrato_automatico.rb`
- Create: `spec/services/ramon/contrato_automatico_spec.rb`
- Modify: `enterprise/lib/captain/tools/preparar_contrato_zapsign_tool.rb`
- Modify: `config/agents/tools.yml` (descrição de `preparar_contrato_zapsign`)
- Modify: `db/seeds/ramon/inteligencia/assistentes.yml` (diretriz + skill "Fechar contrato" — **texto com gate**)
- Create: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-13-roteiro-f3-textos.md` (fora do repo do hub)

**Interfaces:**
- Consumes: `Ramon::CopilotoModo.of` (Task 1), `Ramon::CopilotoLimite.encerrar` (Task 5), `Ramon::ZapsignContractService.new(lead, template_id:)` (`#preview['faltando']`, `#perform['sign_url']`)
- Produces:
  - coluna `theses.zapsign_template_id` (string, nulo)
  - `Ramon::ContratoAutomatico.preparar(lead) -> nil | { link: String } | { falta: Array<String> }` (nil = fora do modo)

- [ ] **Step 1: Migração e schema**

`db/migrate/20261013300001_add_zapsign_template_id_to_theses.rb`:

```ruby
# Modelo de contrato do ZapSign por tese (F3 do roteiro): o modo "sozinha até o contrato" só gera o contrato sozinho
# para tese com modelo definido — hoje só existe o de auxílio-acidente (Ramon::ZapsignContractService::TEMPLATE_ID).
class AddZapsignTemplateIdToTheses < ActiveRecord::Migration[7.1]
  def change
    add_column :theses, :zapsign_template_id, :string
  end
end
```

`db/schema.rb`: topo `ActiveRecord::Schema[7.1].define(version: 2026_10_13_300001) do` (ver Global Constraints); no bloco `create_table "theses"`, depois de `t.string "palavras_chave", default: [], null: false, array: true`:

```ruby
    t.string "zapsign_template_id"
```

- [ ] **Step 2: Spec (falha)**

`spec/services/ramon/contrato_automatico_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::ContratoAutomatico do
  let(:account) { create(:account) }
  let(:thesis) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
  let(:endereco) { { 'rua' => 'Rua das Flores', 'numero' => '100', 'bairro' => 'Centro', 'cidade' => 'Tubarão', 'uf' => 'SC' } }
  let(:contact) do
    create(:contact, account: account, name: 'João da Silva', phone_number: '+5548999990000', cpf: '529.982.247-25',
                     custom_attributes: { 'endereco' => endereco })
  end
  let(:conversation) do
    create(:conversation, account: account, contact: contact, status: :pending,
                          custom_attributes: { 'copiloto_modo' => 'piloto_ate_contrato' })
  end
  let(:lead) { create(:lead, account: account, thesis: thesis, contact: contact, conversation: conversation) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  around { |example| with_modified_env(ZAPSIGN_API_TOKEN: 'tok') { example.run } }

  before do
    thesis.update!(zapsign_template_id: 'modelo-aa')
    allow(Ramon::ZapsignClient).to receive(:templates).and_return([])
  end

  # Review Focus 4: o link volta para a IA mesmo com o modo já encerrado pelo callback, e sem handoff.
  it 'com cadastro completo: gera com o modelo da tese, devolve o link e encerra o modo sem handoff' do
    stub = stub_request(:post, 'https://api.zapsign.com.br/api/v1/models/create-doc/')
           .with { |req| JSON.parse(req.body)['template_id'] == 'modelo-aa' }
           .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                      body: { 'token' => 'doc-1', 'signers' => [{ 'sign_url' => 'https://zap/assinar' }] }.to_json)

    expect(described_class.preparar(lead)).to eq(link: 'https://zap/assinar')
    expect(stub).to have_been_requested
    expect(conversation.reload.custom_attributes).to include('copiloto_modo' => 'rascunho',
                                                             'copiloto_limite' => include('limite' => 'contrato'))
    expect(conversation.status).to eq('pending')
  end

  it 'fora do modo não gera nada (segue a sugestão de sempre)' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_total' })
    expect(Ramon::ZapsignClient).not_to receive(:create_doc_from_template)
    expect(described_class.preparar(lead)).to be_nil
  end

  it 'cadastro incompleto: não gera, diz o que falta, encerra o modo e avisa' do
    contact.update!(cpf: nil, custom_attributes: {})
    expect(Ramon::ZapsignClient).not_to receive(:create_doc_from_template)

    expect(described_class.preparar(lead)).to eq(falta: %w[CPF rua número cidade])
    expect(conversation.reload.custom_attributes['copiloto_limite']).to include('limite' => 'contrato', 'motivo' => include('CPF'))
    expect(Notification.where(user: admin, primary_actor: lead, notification_type: 'ramon_fluxo_aviso').count).to eq(1)
  end

  it 'endereço só da colheita não basta; nome de uma palavra também não' do
    contact.update!(name: 'João', custom_attributes: {})
    lead.update!(custom_attributes: { 'colheita' => { 'dados' => { 'cliente' => { 'endereco' => 'Rua X, 10, Centro, Tubarão/SC' } } } })
    expect(described_class.preparar(lead)).to eq(falta: ['nome completo', 'número', 'cidade'])
  end

  it 'tese sem modelo de contrato não gera' do
    thesis.update!(zapsign_template_id: nil)
    expect(described_class.preparar(lead)).to eq(falta: ['modelo de contrato da tese'])
  end

  it 'ZapSign fora do ar: não quebra, encerra o modo com o motivo' do
    allow(Ramon::ZapsignClient).to receive(:create_doc_from_template).and_raise(Ramon::ZapsignClient::UnavailableError, 'fora do ar')
    expect(described_class.preparar(lead)[:falta].first).to include('fora do ar')
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('rascunho')
  end
end
```

- [ ] **Step 3: Implementar**

`app/services/ramon/contrato_automatico.rb`:

```ruby
# Modo "sozinha até o contrato" (spec roteiro §3.7, F3): o contrato sai na hora, sem a sugestão no Cockpit — só nesse
# modo, só com modelo de contrato na tese e com o cadastro confirmado (nome completo, CPF e rua/número/cidade do
# "Dados do contrato" do painel). Gerou → o link volta para a IA enviar; o callback do Lead (zapsign mudou) encerra o
# modo. Faltou algo ou o ZapSign falhou → o modo encerra com o motivo e a tool deixa a sugestão de sempre.
module Ramon::ContratoAutomatico
  MODO = 'piloto_ate_contrato'.freeze
  # Endereço da colheita vem numa string só (vai inteiro na rua): sem número e cidade não conta como confirmado.
  OBRIGATORIOS = { '{{CPF}}' => 'CPF', '{{rua}}' => 'rua', '{{número}}' => 'número', '{{cidade}}' => 'cidade' }.freeze

  module_function

  # @return nil (fora do modo) | { link: } | { falta: [..] }
  def preparar(lead)
    return unless lead.conversation && Ramon::CopilotoModo.of(lead.conversation) == MODO

    modelo = lead.thesis&.zapsign_template_id
    falta = faltando(lead, modelo)
    return parar(lead, falta) if falta.any?

    { link: Ramon::ZapsignContractService.new(lead, template_id: modelo).perform['sign_url'] }
  rescue Ramon::ZapsignContractService::ConflictError, Ramon::ZapsignClient::RequestError,
         Ramon::ZapsignClient::UnavailableError => e
    parar(lead, ["ZapSign: #{e.message.to_s.truncate(120)}"])
  end

  def faltando(lead, modelo)
    return ['modelo de contrato da tese'] if modelo.blank?

    vazios = Ramon::ZapsignContractService.new(lead, template_id: modelo).preview['faltando']
    nome = lead.contact&.name.presence || lead.name
    (nome.to_s.split.size < 2 ? ['nome completo'] : []) + OBRIGATORIOS.slice(*vazios).values
  end

  def parar(lead, falta)
    Ramon::CopilotoLimite.encerrar(lead, 'contrato', "contrato nao saiu na hora: falta #{falta.join(', ')}")
    { falta: falta }
  end
end
```

- [ ] **Step 4: Tool fina**

`enterprise/lib/captain/tools/preparar_contrato_zapsign_tool.rb` (conteúdo inteiro):

```ruby
# Escrita com aprovacao: propoe gerar contrato + procuracao no ZapSign. O documento so nasce quando o humano aplica a
# sugestao no Cockpit — exceto no modo "sozinha ate o contrato", em que Ramon::ContratoAutomatico gera na hora.
class Captain::Tools::PrepararContratoZapsignTool < Captain::Tools::RamonEscritaTool
  description 'Prepara o contrato de honorarios + procuracao do caso no ZapSign. No modo "sozinha ate o contrato", com ' \
              'o cadastro completo, gera na hora e devolve o link de assinatura para voce enviar ao lead. Nos outros ' \
              'casos cria uma sugestao pendente para o humano aprovar no Cockpit. Use quando o cliente decidir fechar.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead) no hub. Sem ele, usa o caso da conversa aberta.', required: false
  param :motivo, type: 'string', desc: 'Por que o contrato deve ser preparado agora', required: false

  def perform(tool_context, lead_id: nil, motivo: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    pronto = lead.custom_attributes&.dig('zapsign', 'sign_url')
    return "O caso #{lead.name} ja tem contrato preparado no ZapSign: #{pronto}" if pronto.present?

    log_tool_usage('preparar_contrato_zapsign', { lead_id: lead.id })
    na_hora = ::Ramon::ContratoAutomatico.preparar(lead)
    return "Contrato gerado. Envie este link ao lead para assinar pelo celular: #{na_hora[:link]}" if na_hora&.key?(:link)

    sugestao = sugerir(lead, acao: 'zapsign', texto: "Preparar contrato + procuracao no ZapSign para #{lead.name}",
                             justificativa: motivo.presence || 'pedido pelo agente durante o atendimento')
    return sugestao if na_hora.nil?

    "#{sugestao} Nao deu para gerar na hora (falta: #{na_hora[:falta].join(', ')}): " \
      'diga que a equipe envia o contrato e passe para humano.'
  end
end
```

`config/agents/tools.yml` — no bloco `- id: preparar_contrato_zapsign`, trocar a `description` por:

```yaml
  description: 'Sugere gerar contrato + procuração no ZapSign (o humano aprova antes); no modo "sozinha até o contrato", gera na hora'
```

- [ ] **Step 5: Seed — textos (gate do Eduardo)**

Em `db/seeds/ramon/inteligencia/assistentes.yml`, assistente **Atendimento**:

a) Trocar a diretriz
`- "Nunca afirme que contrato, reunião ou caso já existem: as ações que você prepara ficam pendentes para o humano aplicar."`
por:

```yaml
      - "Nunca afirme que contrato, reunião ou caso já existem: as ações que você prepara ficam pendentes para o humano aplicar. Única exceção: quando a ferramenta de preparar contrato devolver \"Contrato gerado\" com o link, o contrato existe — envie o link."
```

b) Trocar a diretriz da F1
`- "Sempre que uma dúvida exigir decisão jurídica sobre o caso concreto, ou o lead disser que quer contratar ou pedir para falar com uma pessoa/advogado, passe para humano. Nunca diga que está \"transferindo\": diga só que alguém da equipe continua a conversa por aqui."`
por (pergunta aberta B):

```yaml
      - "Sempre que uma dúvida exigir decisão jurídica sobre o caso concreto, ou o lead pedir para falar com uma pessoa/advogado, passe para humano. Se o lead disser que quer contratar, siga a skill Fechar contrato (ela tenta o contrato na hora e, se não der, passa para humano). Nunca diga que está \"transferindo\": diga só que alguém da equipe continua a conversa por aqui."
```

c) Na skill `Fechar contrato`, trocar o `instruction: |` inteiro por (mesma indentação):

```yaml
        instruction: |
          Quando o lead decidir fechar, chame [Preparar contrato no ZapSign](tool://preparar_contrato_zapsign).
          Se ela devolver "Contrato gerado" com um link, envie o link ao lead numa frase curta: é o contrato de
          honorários + procuração, para assinar pelo celular; explique o honorário mais uma vez, com clareza.
          Nos outros casos ela só deixa uma sugestão pendente: diga ao lead que a equipe vai enviar o contrato para
          assinatura pelo celular, explique o honorário mais uma vez e passe para humano. Nunca afirme que o
          contrato existe sem o link na mão. Depois que o humano confirmar que o caso foi fechado,
          [Abrir caso no AdvBox](tool://preparar_caso_advbox) — também só deixa sugestão; quem aplica é o humano.
```

- [ ] **Step 6: Doc de gate para o Eduardo**

`C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-13-roteiro-f3-textos.md` — rascunho para aprovação, com estas seções:

1. **Textos que mudam** — os três trechos do Step 5, exatos, com o "antes → depois".
2. **O que nada disso muda até você ligar**: sem modo "sozinha até…" escolhido numa caixa, tudo segue em rascunho; ativar os textos = `rake 'ramon:inteligencia:seed[2]'` depois do aprovado.
3. **As 3 perguntas abertas (A, B, C)** do topo do plano, com o padrão adotado.
4. **Checklist para ligar numa caixa** (cada item é ação sua ou pedido seu):
   - palavras-chave das teses (tela da F2, ou console: `Account.find(2).theses.find_by!(name: 'Auxílio-acidente (B36)').update!(palavras_chave: ['auxílio-acidente', 'auxilio acidente', 'acidente de trabalho'])`);
   - carimbar rascunho nas conversas abertas antigas da caixa, antes de escolher o modo padrão (`caixa = Account.find(2).inboxes.find(<id>)` e `caixa.conversations.where(status: %i[open pending]).where("custom_attributes->>'copiloto_modo' IS NULL").find_each { |c| c.update!(custom_attributes: (c.custom_attributes || {}).merge('copiloto_modo' => 'rascunho')) }`);
   - escolher tese padrão e modo padrão na tela da caixa;
   - modo contrato: definir o modelo da tese (`….find_by!(name: 'Auxílio-acidente (B36)').update!(zapsign_template_id: Ramon::ZapsignContractService::TEMPLATE_ID)`).
5. **Destaques de comportamento**: o turno que atinge o limite ainda envia (inclusive o link da agenda no "até qualificar"); "até qualificar" numa tese sem roteiro só para na reunião; a observação para a F1 (resposta do turno que passa para a equipe pode sumir).

- [ ] **Step 7: Lint + commit** (o `.md` do comercial fica fora do repo do hub)

```bash
rubocop-vps db/migrate/20261013300001_add_zapsign_template_id_to_theses.rb app/services/ramon/contrato_automatico.rb \
  spec/services/ramon/contrato_automatico_spec.rb enterprise/lib/captain/tools/preparar_contrato_zapsign_tool.rb
git add db/migrate/20261013300001_add_zapsign_template_id_to_theses.rb db/schema.rb app/services/ramon/contrato_automatico.rb \
  spec/services/ramon/contrato_automatico_spec.rb enterprise/lib/captain/tools/preparar_contrato_zapsign_tool.rb \
  config/agents/tools.yml db/seeds/ramon/inteligencia/assistentes.yml
git commit -m "feat(copiloto): contrato na hora no modo 'sozinha até o contrato' (texto aguarda aprovação)"
```

---

### Task 7: PR, CI, merge, deploy, prova e registro

**Files:**
- Modify: `C:\Users\dudsl\.claude\projects\C--Users-dudsl-RAdvogados\memory\roteiro-da-tese.md`

- [ ] **Step 1: Push e PR** (push = Eduardo via `!` se o classificador barrar)

```bash
git push -u origin feat/roteiro-f3-tese-e-modos
gh pr create --base ramon --title "feat(roteiro): tese automática e modos 'sozinha até…' (F3)" --body-file <corpo>
```

Corpo: parágrafo de produto ("o lead ganha a tese sozinho; cada caixa pode ter tese e modo padrão da IA; 3 modos novos enviam direto até qualificar / marcar reunião / enviar contrato e aí voltam para rascunho com aviso"); as **Decisões que tomei sem perguntar** e as **Perguntas abertas** do topo; a observação para a F1; "Como testar" = a prova do Step 4 + a tela da caixa; o aviso de que os textos só são ativados com o seed após o aprovado e de que nada liga sem escolha na caixa; rodapé de atribuição.

- [ ] **Step 2: CI 100% verde** — spec/lint vermelho → corrigir, `rubocop-vps`, novo commit (sem amend). 429/503 baixando actions = re-rodar o job.

- [ ] **Step 3: Merge (squash) e deploy** — regime autônomo com CI verde (CLAUDE.md do ramon-hub). Migração só de estrutura. Na VPS: `docker pull ghcr.io/doods-maker/ramon-hub:sha-<7>` + `docker tag … :v4.15.1-ramon` + `docker compose run --rm --no-deps chatwoot-web bundle exec rails db:migrate` + `docker compose up -d chatwoot-web chatwoot-worker`. Conferir a label da imagem e login 200 em https://chat.ramonantonio.adv.br. **Nada é ligado** (nenhuma caixa ganha tese/modo padrão, nenhuma tese ganha modelo).

- [ ] **Step 4: Prova em produção sem deixar rastro** — tudo numa transação desfeita. Os callbacks `after_*_commit` não rodam dentro dela, então o limite é chamado à mão. Nada chama o ZapSign: sem CPF o contrato para em "falta". Rodar via `cat prova.rb | ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails runner "eval(STDIN.read)"'`:

```ruby
ActiveRecord::Base.transaction do
  a = Account.find(2)
  aa = a.theses.find_by!(name: 'Auxílio-acidente (B36)')
  aa.update!(palavras_chave: ['auxilio-acidente', 'acidente de trabalho'])
  puts Ramon::TeseAutomatica.por_texto(a, 'oi, sofri acidente de trabalho ano passado')&.name # => Auxílio-acidente (B36)
  puts Ramon::TeseAutomatica.por_texto(a, 't-auxilio-acidente')&.name                         # => Auxílio-acidente (B36)

  caixa = a.inboxes.where('name ILIKE ?', '%teste%').first!
  caixa.update!(ramon_copiloto_modo: 'piloto_ate_reuniao', ramon_thesis_id: aa.id)
  c = a.contacts.create!(name: 'Prova F3 Silva')
  ci = ContactInbox.create!(contact: c, inbox: caixa, source_id: "prova-f3-#{Time.now.to_i}")
  conv = a.conversations.create!(inbox: caixa, contact: c, contact_inbox: ci, status: :pending)
  puts Ramon::CopilotoModo.of(conv)                                   # => piloto_ate_reuniao (padrão da caixa, ao vivo)

  lead = a.leads.create!(name: 'Prova F3', lead_stage: a.lead_stages.order(:position).first, contact: c,
                         conversation: conv, thesis: aa)
  puts Ramon::Roteiro::Efeitos.direto?(lead)                          # => true
  lead.update!(lead_stage: a.lead_stages.find_by!(label: 'fase-reuniao-agendada'))
  p Ramon::CopilotoLimite.verificar(lead)                             # => "reuniao"
  p conv.reload.custom_attributes                                     # copiloto_modo rascunho + copiloto_limite
  p conv.status                                                       # => "pending" (sem handoff)

  conv.update!(custom_attributes: { 'copiloto_modo' => 'piloto_ate_contrato' })
  p Ramon::ContratoAutomatico.preparar(lead.reload)                   # => {:falta=>[...]} (sem CPF / sem modelo) — ZapSign não é chamado
  raise ActiveRecord::Rollback
end
puts Account.find(2).inboxes.where.not(ramon_copiloto_modo: nil).count # => 0
```

- [ ] **Step 5: Registro** — atualizar `memory\roteiro-da-tese.md` com: PR, squash, sha da VPS, migração aplicada, prova OK; textos aguardando o aprovado (doc `2026-10-13-roteiro-f3-textos.md`) → depois `rake 'ramon:inteligencia:seed[2]'`; perguntas abertas A/B/C; observação para a F1; próximo = F4 (conteúdo + métricas; o `bi_roteiro` lê `conversations.custom_attributes->'copiloto_limite'`). Prints da tela da caixa (dois seletores) vão na página de prints do pacote, junto com as telas da F2 (regra de 05/10: uma página de prints e um deploy por bloco).

# Onda 1 — Aquisição Limpa (Funil Estratégico) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Todo lead nasce com canal derivado automaticamente (fim do balde `outro`) e o lead qualificado pelo quiz da LP chega estruturado, nascendo direto em "Qualificação".

**Architecture:** Três repositórios, três frentes pequenas. No **ramon-hub**, a derivação de canal ganha um segundo estágio no seam que já existe (`Ramon::SourceCatalog` + `RamonLeadListener#message_created`): assinaturas de texto da 1ª mensagem → canal; sem assinatura e sem referral → `indicacao` (regra de negócio 13/08). O endpoint público passa a aceitar as respostas estruturadas do quiz (`custom_attributes['quiz']`) e a escolher a etapa inicial (`fase-qualificacao` p/ qualificado). No **landing-pages**, o `ChatQuiz` deixa de achatar as respostas (elas já existem como `Resposta[]`) e as envia junto. No **ramonantonio-site**, 1 linha de copy nova pra assinatura do site (GATE Eduardo).

**Tech Stack:** Rails 7 (fork Chatwoot v4.15.1) + RSpec · Vue 3 `<script setup>` + Tailwind · Astro 5 + TypeScript + Vitest.

**Contexto de domínio:** ver `CONTEXT.md` (Canal vs Origem, Indicação) e `docs/superpowers/specs/2026-08-13-funil-estrategico-design.md` (decisões 1–4). ADRs relacionados: nenhum nesta onda.

## Ondas (mapa geral — este plano é só a Onda 1)

| Onda | Escopo | Plano |
|---|---|---|
| **1 (esta)** | Derivação completa de canal + quiz estruturado + lead de LP nasce em Qualificação | este arquivo |
| 2 | Pós-venda: visão "Pós-venda", redesign do checklist de documentos (aba, cobrança como rascunho na conversa, casamento anexo↔item por IA, badge docs X/Y), exportação Drive + atalhos diários, tarefa ADVBOX p/ controller | a escrever após Onda 1 no ar |
| 3 | Estratégia visível: valor estimado por tese, previsão, cabeça de coluna do kanban com números, views SQL `bi_*` no repo + Metabase lendo delas | a escrever após Onda 2 |

## Global Constraints

- **Sem ambiente de teste local no hub** → quem valida é PR + CI 100% verde (regime 09/07). Os passos "rodar teste" do hub executam no CI do PR; localmente rode apenas rubocop/eslint se disponíveis.
- **RSpec: NUNCA criar arquivo de spec novo no hub** — estender specs existentes (lição knapsack 20/07: arquivo novo reshuffla shards e expõe flakes de upstream). Todos os specs deste plano estendem arquivos que já existem.
- Rubocop: linha máx 150; `RSpec/ContextWording` exige contexto em inglês (`when/with/without`).
- Vue: Composition API `<script setup>`, eventos camelCase, Tailwind only, zero string solta em template (i18n em `en/ramon.json` E `pt_BR/ramon.json` — padrão do fork).
- Commits: Conventional Commits (`feat:`/`fix:`), sem referência a Claude.
- **Copy que fala com cliente = gate do Eduardo** (Task 7 do site institucional só faz push após "aprovado" explícito dele; textos das LPs NÃO mudam nesta onda — as assinaturas casam com os textos já em produção).
- **Sem migração de banco nesta onda** (tudo em `custom_attributes` jsonb e colunas existentes).
- Ordem de deploy: **hub primeiro** (aceita os params novos), depois landing-pages (passa a enviá-los). Params desconhecidos são ignorados pelo hub, então a ordem inversa não quebra — mas perde dados de quiz até o hub subir.
- Repos: hub = `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub` (branch nova a partir de `ramon`, worktree via superpowers:using-git-worktrees) · landing-pages e ramonantonio-site = repos irmãos em `..\`.

---

## Parte A — ramon-hub (Tasks 1–4, um PR)

### Task 1: Assinaturas de mensagem no SourceCatalog

**Files:**
- Modify: `app/services/ramon/source_catalog.rb`
- Test: `spec/services/ramon/source_catalog_spec.rb` (estender — NÃO criar arquivo)

**Interfaces:**
- Consumes: nada novo.
- Produces: `Ramon::SourceCatalog.derive_from_message(text)` → `[channel, source]` (Array de 2 Strings) ou `nil`. Task 2 chama exatamente essa assinatura.

- [ ] **Step 1: Escrever os testes que falham** — adicionar ao final do `describe` existente em `spec/services/ramon/source_catalog_spec.rb`:

```ruby
  describe '.derive_from_message' do
    it 'derives google_seo from the institutional site signature' do
      expect(described_class.derive_from_message('Olá! Vim pelo site do escritório e gostaria de falar com a equipe.'))
        .to eq(%w[google_seo site-institucional])
    end

    it 'derives landing_page from the classic LP signature' do
      expect(described_class.derive_from_message('Olá, vim pelo site e gostaria de tirar dúvidas sobre o auxílio-acidente.'))
        .to eq(%w[landing_page lp:whatsapp])
    end

    it 'derives landing_page from the triage quiz signature' do
      expect(described_class.derive_from_message("Olá! Fiz a triagem de auxílio-acidente no site.\nTriagem — Auxílio-acidente"))
        .to eq(%w[landing_page lp:triagem])
    end

    it 'derives instagram from the bio link signature' do
      expect(described_class.derive_from_message('Olá! Vim pelo Instagram e quero avaliar meu caso.'))
        .to eq(%w[instagram instagram-bio])
    end

    it 'returns nil for unsigned text' do
      expect(described_class.derive_from_message('oi, tudo bem?')).to be_nil
    end

    it 'returns nil for blank text' do
      expect(described_class.derive_from_message(nil)).to be_nil
    end
  end
```

- [ ] **Step 2: Implementar** — em `app/services/ramon/source_catalog.rb`, adicionar após a constante `RULES`:

```ruby
  # Assinaturas do texto pré-preenchido dos botões wa.me (1ª mensagem da conversa).
  # A mais específica vem primeiro: "site do escritório" (site institucional) tem
  # que vencer "vim pelo site e gostaria" (texto atual das LPs em produção —
  # mudar esses textos quebra a derivação; ver plano onda1-aquisicao-limpa).
  SIGNATURES = [
    [/vim pelo site do escrit[óo]rio/i, %w[google_seo site-institucional]],
    [/vim pelo site e gostaria/i, %w[landing_page lp:whatsapp]],
    [/fiz a triagem/i, %w[landing_page lp:triagem]],
    [/vim pelo instagram/i, %w[instagram instagram-bio]]
  ].freeze

  def self.derive_from_message(text)
    return nil if text.blank?

    SIGNATURES.find { |pattern, _result| text.match?(pattern) }&.last
  end
```

- [ ] **Step 3: Rubocop local se disponível** — `bundle exec rubocop app/services/ramon/source_catalog.rb spec/services/ramon/source_catalog_spec.rb` (senão, CI valida).

- [ ] **Step 4: Commit**

```bash
git add app/services/ramon/source_catalog.rb spec/services/ramon/source_catalog_spec.rb
git commit -m "feat(leads): assinaturas de mensagem no SourceCatalog (derive_from_message)"
```

### Task 2: Derivação de canal no primeiro contato (listener)

**Files:**
- Modify: `app/listeners/ramon_lead_listener.rb` (método `message_created` ~linha 25 e novo método privado)
- Test: `spec/listeners/ramon_lead_listener_spec.rb` (estender — NÃO criar arquivo)

**Interfaces:**
- Consumes: `Ramon::SourceCatalog.derive_from_message(text)` → `[channel, source] | nil` (Task 1).
- Produces: comportamento — lead com `channel == 'outro'` é reclassificado na 1ª mensagem incoming. Nenhuma API nova.

**Regra implementada (decisões 1–2 do design):** `'outro'` é o sentinela de "não derivado" (é o que `Lead#assign_channel` grava quando não há source). Na 1ª mensagem incoming: referral Meta → `meta_ads` (código existente, roda antes); assinatura no texto → canal da assinatura; senão, inbox Instagram → `instagram`; senão → `indicacao` (WhatsApp sem anúncio = indicação). Canal escolhido à mão ou já derivado (`landing_page`, `meta_ads`…) nunca é sobrescrito. Se a 1ª mensagem não tem assinatura ("oi"), vira `indicacao` de imediato e mensagens seguintes não re-derivam — correto pela regra de negócio.

- [ ] **Step 1: Escrever os testes que falham** — adicionar ao `describe RamonLeadListener` em `spec/listeners/ramon_lead_listener_spec.rb`, dentro do bloco de `message_created` existente (seguir os `let`/factories que o spec já usa para account/inbox/conversation/lead; criar a mensagem incoming com a factory `:message` já usada no arquivo):

```ruby
    context 'when deriving channel on first contact' do
      it 'turns an unsigned whatsapp lead into indicacao' do
        lead.update!(channel: 'outro', source: nil)
        message = create(:message, account: account, conversation: conversation,
                         message_type: :incoming, content: 'oi, tudo bem?')
        listener.message_created(build_message_event(message))
        expect(lead.reload.channel).to eq('indicacao')
      end

      it 'derives channel and source from a signature message' do
        lead.update!(channel: 'outro', source: nil)
        message = create(:message, account: account, conversation: conversation,
                         message_type: :incoming,
                         content: 'Olá! Vim pelo site do escritório e gostaria de falar com a equipe.')
        listener.message_created(build_message_event(message))
        expect(lead.reload).to have_attributes(channel: 'google_seo', source: 'site-institucional')
      end

      it 'does not override a channel that is already derived' do
        lead.update!(channel: 'landing_page', source: 'auxilio-acidente')
        message = create(:message, account: account, conversation: conversation,
                         message_type: :incoming, content: 'oi')
        listener.message_created(build_message_event(message))
        expect(lead.reload.channel).to eq('landing_page')
      end

      it 'derives instagram from an instagram inbox without signature' do
        allow_any_instance_of(Inbox).to receive(:channel_type).and_return('Channel::Instagram')
        lead.update!(channel: 'outro', source: nil)
        message = create(:message, account: account, conversation: conversation,
                         message_type: :incoming, content: 'vi o perfil de vocês')
        listener.message_created(build_message_event(message))
        expect(lead.reload.channel).to eq('instagram')
      end
    end
```

  (Se o spec existente tiver um helper próprio para montar o evento — ex.: `Events::Base.new('message.created', Time.zone.now, message: message)` — usar esse padrão no lugar de `build_message_event`; copiar do teste de referral que já existe no arquivo. Se `allow_any_instance_of` reprovar no rubocop do projeto, criar a conversa numa inbox de channel `:instagram` com as factories do Chatwoot.)

- [ ] **Step 2: Implementar** — em `app/listeners/ramon_lead_listener.rb`:

No `message_created`, após `apply_meta_referral(lead, message)`:

```ruby
    apply_meta_referral(lead, message)
    derive_channel_from_first_contact(lead, message)
```

E nos métodos privados, após `referral_source_label`:

```ruby
  # Regra de negócio (13/08, design funil-estrategico): nos números da banca,
  # quem chega sem anúncio e sem assinatura de site/LP/bio veio por indicação.
  # 'outro' é o sentinela de "não derivado" — canal manual ou já derivado
  # (landing_page, meta_ads) nunca é sobrescrito.
  def derive_channel_from_first_contact(lead, message)
    return unless lead.channel == 'outro'

    channel, source = Ramon::SourceCatalog.derive_from_message(message.content)
    channel ||= message.inbox&.channel_type == 'Channel::Instagram' ? 'instagram' : 'indicacao'
    attrs = { channel: channel }
    attrs[:source] = source if source.present? && lead.source.blank?
    lead.update!(attrs)
  end
```

- [ ] **Step 3: Rubocop local se disponível**, senão CI.

- [ ] **Step 4: Commit**

```bash
git add app/listeners/ramon_lead_listener.rb spec/listeners/ramon_lead_listener_spec.rb
git commit -m "feat(leads): deriva canal no 1o contato (assinatura, instagram, indicacao)"
```

### Task 3: Endpoint público — quiz estruturado + nascer em Qualificação

**Files:**
- Modify: `app/controllers/public/api/v1/ramon_leads_controller.rb`
- Test: `spec/requests/public/api/v1/ramon_leads_controller_spec.rb` (estender — NÃO criar arquivo)

**Interfaces:**
- Consumes: params novos do POST `/public/api/v1/ramon_leads`: `qualificado` (boolean), `duvidas` (array de strings), `respostas` (array de objetos `{id, pergunta, resposta, valor, reprova?, duvida?}`) — exatamente o shape que a Task 6 (landing-pages) envia.
- Produces: `lead.custom_attributes['quiz']` = `{'qualificado' => bool, 'duvidas' => [...], 'respostas' => [...], 'em' => iso8601}`; lead qualificado nasce na etapa de label `fase-qualificacao`. Task 4 (UI) lê esse shape.

- [ ] **Step 1: Escrever os testes que falham** — adicionar ao request spec existente (reusar o setup de token/account/params válidos que o arquivo já tem; os params abaixo entram por cima do payload válido existente):

```ruby
    context 'with structured quiz payload' do
      let(:quiz_params) do
        {
          qualificado: true,
          duvidas: ['Renda familiar'],
          respostas: [
            { id: 'sequela', pergunta: 'Sequela permanente', resposta: 'Sim, tenho sequela', valor: 'sim' },
            { id: 'renda', pergunta: 'Renda por pessoa', resposta: 'Perto de meio salário', valor: 'meio-salario', duvida: true }
          ]
        }
      end

      it 'stores the quiz under custom_attributes and starts at qualificacao' do
        post ramon_leads_path, params: valid_params.merge(quiz_params), headers: headers, as: :json
        lead = Lead.last
        expect(lead.custom_attributes['quiz']).to include(
          'qualificado' => true,
          'duvidas' => ['Renda familiar']
        )
        expect(lead.custom_attributes['quiz']['respostas'].length).to eq(2)
        expect(lead.lead_stage.label).to eq('fase-qualificacao')
      end

      it 'starts a disqualified quiz lead at the first stage' do
        post ramon_leads_path, params: valid_params.merge(quiz_params, qualificado: false),
                               headers: headers, as: :json
        expect(Lead.last.lead_stage).to eq(account.lead_stages.order(:position).first)
      end

      it 'merges the quiz into an existing open lead without moving its stage' do
        existing = create(:lead, account: account, contact: contact,
                          lead_stage: account.lead_stages.order(:position).last)
        post ramon_leads_path, params: valid_params.merge(quiz_params), headers: headers, as: :json
        expect(existing.reload.custom_attributes['quiz']['qualificado']).to be(true)
        expect(existing.reload.lead_stage).to eq(account.lead_stages.order(:position).last)
      end
    end

    context 'without quiz payload' do
      it 'keeps the lead at the first stage' do
        post ramon_leads_path, params: valid_params, headers: headers, as: :json
        expect(Lead.last.lead_stage).to eq(account.lead_stages.order(:position).first)
      end
    end
```

  (Ajustar `ramon_leads_path`, `valid_params`, `headers`, `contact` aos nomes que o spec já usa — copiar do teste de criação que já existe; a etapa `fase-qualificacao` vem do seed `Leads::SeedDefaultConfigService`, que o spec já dispara ao criar a account. `Lead.last` só é seguro porque cada exemplo cria um lead — seguir o padrão do arquivo se ele usar outra forma de capturar o lead criado.)

- [ ] **Step 2: Implementar** — em `app/controllers/public/api/v1/ramon_leads_controller.rb`:

Trocar `register_lead` para mesclar o quiz no lead reaproveitado:

```ruby
  def register_lead(contact, phone)
    lead = open_lead_for(contact)
    if lead
      # Lead ainda vivo no funil → não duplica: registra atividade na Linha da Vida.
      lead.lead_activities.create!(account: account, kind: 'lp_recaptured', to_value: recapture_source)
      # Triagem nova vale registrar; a etapa NÃO anda sozinha (um lead em
      # Negociação não pode regredir porque refez o quiz).
      lead.update!(custom_attributes: lead.custom_attributes.merge(quiz_attributes)) if quiz_attributes.present?
    else
      lead = create_lead(contact, phone)
    end
    lead.lead_notes.create!(account: account, body: params[:mensagem].to_s.truncate(1000)) if params[:mensagem].present?
    Ramon::LeadNotificationBuilder.new(lead: lead).perform
    lead
  end
```

Trocar `create_lead` e adicionar os métodos novos (abaixo de `utm_attributes`):

```ruby
  def create_lead(contact, phone)
    account.leads.create!(
      name: params[:nome].to_s.strip.presence || phone,
      lead_stage: initial_stage,
      contact_id: contact.id,
      source: params[:campanha].to_s.presence,
      channel: 'landing_page',
      custom_attributes: utm_attributes.merge(quiz_attributes)
    )
  end

  # Lead qualificado pelo quiz nasce em Qualificação (design 13/08, decisão 4):
  # o SDR confirma com documento — não recomeça do "chegou alguém".
  def initial_stage
    (quiz_qualificado? && account.lead_stages.find_by(label: 'fase-qualificacao')) ||
      account.lead_stages.order(:position).first
  end

  def quiz_qualificado?
    quiz_attributes.dig('quiz', 'qualificado') == true
  end

  QUIZ_RESPOSTA_KEYS = %i[id pergunta resposta valor reprova duvida].freeze

  def quiz_attributes
    @quiz_attributes ||= begin
      respostas = Array.wrap(params[:respostas]).first(20).filter_map do |r|
        r.permit(*QUIZ_RESPOSTA_KEYS).to_h.compact_blank if r.respond_to?(:permit)
      end
      if respostas.empty?
        {}
      else
        {
          'quiz' => {
            'qualificado' => ActiveModel::Type::Boolean.new.cast(params[:qualificado]) == true,
            'duvidas' => Array.wrap(params[:duvidas]).map { |d| d.to_s.first(120) }.first(10),
            'respostas' => respostas,
            'em' => Time.current.iso8601
          }
        }
      end
    end
  end
```

- [ ] **Step 3: Rubocop local se disponível**, senão CI.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/public/api/v1/ramon_leads_controller.rb spec/requests/public/api/v1/ramon_leads_controller_spec.rb
git commit -m "feat(leads): quiz estruturado no endpoint publico + lead qualificado nasce em Qualificacao"
```

### Task 4: UI — bloco "Triagem da LP" no painel do lead

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadQuizResumo.vue`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadQuizResumo.spec.js` (spec JS novo é ok — a lição do knapsack vale só pra RSpec)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue` (import + render antes de `<LeadNotes>` na aba Resumo, ~linha 541)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` e `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`

**Interfaces:**
- Consumes: `lead.custom_attributes.quiz` no shape produzido pela Task 3. O payload completo do lead (show/create/update) já inclui `custom_attributes` — nada a mudar no jbuilder (o índice slim do Kanban não mostra quiz, por design).
- Produces: componente `LeadQuizResumo` com prop `lead` (Object, required).

- [ ] **Step 1: Escrever o spec que falha** — `LeadQuizResumo.spec.js` (seguir o padrão de mount dos specs vizinhos em `components/lead/specs/`, com o mesmo helper de i18n que `LeadPanelBody.spec.js` usa):

```js
import { mount } from '@vue/test-utils';
import LeadQuizResumo from '../LeadQuizResumo.vue';

const mountComponent = lead =>
  mount(LeadQuizResumo, {
    props: { lead },
    global: { mocks: { $t: key => key } },
  });

describe('LeadQuizResumo', () => {
  it('renders nothing without quiz data', () => {
    const wrapper = mountComponent({ custom_attributes: {} });
    expect(wrapper.find('[data-testid="lead-quiz-resumo"]').exists()).toBe(false);
  });

  it('renders answers and the qualified badge', () => {
    const wrapper = mountComponent({
      custom_attributes: {
        quiz: {
          qualificado: true,
          duvidas: ['Renda familiar'],
          respostas: [
            { id: 'sequela', pergunta: 'Sequela permanente', resposta: 'Sim, tenho sequela' },
          ],
        },
      },
    });
    const el = wrapper.find('[data-testid="lead-quiz-resumo"]');
    expect(el.exists()).toBe(true);
    expect(el.text()).toContain('Sequela permanente');
    expect(el.text()).toContain('Sim, tenho sequela');
    expect(el.text()).toContain('Renda familiar');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar** — `pnpm test LeadQuizResumo` → falha (componente não existe).

- [ ] **Step 3: Implementar o componente** — `LeadQuizResumo.vue`:

```vue
<script setup>
import { computed } from 'vue';

const props = defineProps({
  lead: { type: Object, required: true },
});

defineOptions({ name: 'LeadQuizResumo' });

const quiz = computed(() => props.lead?.custom_attributes?.quiz || null);
const respostas = computed(() => quiz.value?.respostas || []);
const duvidas = computed(() => quiz.value?.duvidas || []);
</script>

<template>
  <div
    v-if="quiz"
    data-testid="lead-quiz-resumo"
    class="pt-3 border-t border-n-weak"
  >
    <div class="flex items-center gap-2 mb-2">
      <p
        class="text-[10.5px] font-semibold uppercase tracking-[.1em] text-n-slate-10"
      >
        {{ $t('RAMON.LEAD_PANEL.QUIZ.TITLE') }}
      </p>
      <span
        class="rounded-full px-2 py-0.5 text-[10.5px]"
        :class="
          quiz.qualificado
            ? 'bg-n-teal-9/10 text-n-teal-11'
            : 'bg-n-ruby-9/10 text-n-ruby-11'
        "
      >
        {{
          quiz.qualificado
            ? $t('RAMON.LEAD_PANEL.QUIZ.QUALIFIED')
            : $t('RAMON.LEAD_PANEL.QUIZ.DISQUALIFIED')
        }}
      </span>
    </div>
    <dl class="flex flex-col gap-1">
      <div
        v-for="r in respostas"
        :key="r.id"
        class="flex justify-between gap-2 text-[12px]"
      >
        <dt class="text-n-slate-10">{{ r.pergunta }}</dt>
        <dd
          class="text-right text-n-slate-12"
          :class="{ 'text-n-ruby-11': r.reprova, 'text-n-amber-11': r.duvida }"
        >
          {{ r.resposta }}
        </dd>
      </div>
    </dl>
    <p
      v-for="d in duvidas"
      :key="d"
      class="mt-1 text-[11px] text-n-amber-11"
    >
      {{ $t('RAMON.LEAD_PANEL.QUIZ.DOUBT', { doubt: d }) }}
    </p>
  </div>
</template>
```

- [ ] **Step 4: i18n** — em `pt_BR/ramon.json`, dentro de `RAMON.LEAD_PANEL`, adicionar:

```json
"QUIZ": {
  "TITLE": "Triagem da LP",
  "QUALIFIED": "Qualificado no quiz",
  "DISQUALIFIED": "Reprovado no quiz",
  "DOUBT": "⚠ Ponto de atenção: {doubt}"
}
```

  Em `en/ramon.json`, mesmo bloco com: `"TITLE": "LP triage"`, `"QUALIFIED": "Quiz-qualified"`, `"DISQUALIFIED": "Quiz-disqualified"`, `"DOUBT": "⚠ Attention point: {doubt}"`.

- [ ] **Step 5: Integrar no painel** — em `LeadPanelBody.vue`: adicionar `import LeadQuizResumo from './LeadQuizResumo.vue';` junto aos imports de `./Lead*` e, no template da aba Resumo, logo ANTES de `<LeadNotes :lead-id="lead.id" />`:

```html
        <LeadQuizResumo :lead="lead" />
```

- [ ] **Step 6: Rodar testes e lint** — `pnpm test LeadQuizResumo` → PASS; `./node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadQuizResumo.vue app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue --fix` (eslint direto, não `pnpm eslint` — o script roda o repo inteiro).

- [ ] **Step 7: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadQuizResumo.vue app/javascript/dashboard/routes/dashboard/ramon/components/lead/specs/LeadQuizResumo.spec.js app/javascript/dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(leads): bloco Triagem da LP no painel do lead"
```

### Checkpoint da Parte A: PR + CI + deploy

- [ ] Abrir PR da branch para `ramon` com `--body-file` (aspas no corpo quebram no PS 5.1). Corpo: parágrafo de produto + "How to test" apontando o roteiro de smoke (abaixo).
- [ ] CI 100% verde (vigiar build com loop `until status=completed` — `gh run watch` solta exit 0 com run in_progress). Merge autônomo permitido com CI verde (regime 09/07).
- [ ] Deploy: puxar na VPS a imagem `ghcr.io/doods-maker/ramon-hub:sha-<mergesha>` DIRETO e retagear (nunca confiar na tag flutuante com merges próximos); `docker inspect` confere digest. Sem migração nesta onda.
- [ ] Escrever roteiro de smoke pro Eduardo em `comercial\docs\2026-08-13-smoke-onda1-aquisicao.md`: (1) mandar "oi" de um número novo → lead nasce e vira canal Indicação; (2) mandar a mensagem do botão do site → Google/SEO; (3) fazer o quiz da LP e chamar no WhatsApp → lead em Qualificação com bloco "Triagem da LP" no painel; (4) lead antigo com canal manual não muda.

---

## Parte B — landing-pages (Tasks 5–6, commit direto na main = deploy FTP automático)

### Task 5: Payload estruturado no enviarLead

**Files:**
- Modify: `src/lib/enviarLead.ts`
- Test: `src/lib/enviarLead.test.ts` (estender)

**Interfaces:**
- Consumes: nada novo.
- Produces: `LeadPayload` ganha `qualificado?: boolean`, `duvidas?: string[]`, `respostas?: QuizRespostaPayload[]`, com `QuizRespostaPayload = { id: string; pergunta: string; resposta: string; valor: string; reprova?: boolean; duvida?: boolean }`. O body do POST inclui os três campos quando `respostas` vem preenchido. Task 6 monta esse shape; Task 3 (hub) o consome.

- [ ] **Step 1: Escrever o teste que falha** — em `src/lib/enviarLead.test.ts`, seguindo o padrão de mock de `fetch` que o arquivo já usa:

```ts
it('inclui a triagem estruturada no body quando há respostas', async () => {
  const fetchMock = vi.fn().mockResolvedValue({ ok: true });
  vi.stubGlobal('fetch', fetchMock);
  await enviarLead('https://hub.test/public/api/v1/ramon_leads', {
    nome: 'Lead triagem',
    telefone: '5548999990000',
    campanha: 't-auxilio-acidente',
    qualificado: true,
    duvidas: ['Renda familiar'],
    respostas: [
      { id: 'sequela', pergunta: 'Sequela permanente', resposta: 'Sim, tenho sequela', valor: 'sim' },
    ],
  });
  const body = JSON.parse(fetchMock.mock.calls[0][1].body as string);
  expect(body.qualificado).toBe(true);
  expect(body.duvidas).toEqual(['Renda familiar']);
  expect(body.respostas).toHaveLength(1);
  expect(body.respostas[0].id).toBe('sequela');
});

it('omite os campos de triagem sem respostas', async () => {
  const fetchMock = vi.fn().mockResolvedValue({ ok: true });
  vi.stubGlobal('fetch', fetchMock);
  await enviarLead('https://hub.test/public/api/v1/ramon_leads', {
    nome: 'Fulano',
    telefone: '5548999990000',
    campanha: 'bpc-loas',
  });
  const body = JSON.parse(fetchMock.mock.calls[0][1].body as string);
  expect(body.respostas).toBeUndefined();
  expect(body.qualificado).toBeUndefined();
});
```

- [ ] **Step 2: Rodar e ver falhar** — `npm test -- enviarLead` → falha de tipo/asserção.

- [ ] **Step 3: Implementar** — em `src/lib/enviarLead.ts`: adicionar a interface e estender `LeadPayload`:

```ts
export interface QuizRespostaPayload {
  id: string;
  pergunta: string;
  resposta: string;
  valor: string;
  reprova?: boolean;
  duvida?: boolean;
}
```

Em `LeadPayload`, após `consent?: boolean;`:

```ts
  /** Triagem estruturada do quiz-chat (opcional). */
  qualificado?: boolean;
  duvidas?: string[];
  respostas?: QuizRespostaPayload[];
```

No `body: JSON.stringify({...})`, após `...capturarUtm(),`:

```ts
        ...(payload.respostas?.length
          ? {
              respostas: payload.respostas,
              duvidas: payload.duvidas ?? [],
              qualificado: payload.qualificado === true,
            }
          : {}),
```

- [ ] **Step 4: Rodar** — `npm test -- enviarLead` → PASS; `npx astro check` limpo.

- [ ] **Step 5: Commit** (ainda sem push — push junto com a Task 6)

```bash
git add src/lib/enviarLead.ts src/lib/enviarLead.test.ts
git commit -m "feat(quiz): payload de triagem estruturada no enviarLead"
```

### Task 6: ChatQuiz envia as respostas estruturadas

**Files:**
- Modify: `src/components/ChatQuiz.astro` (função `veredito()`, ~linha 179)

**Interfaces:**
- Consumes: `respostas: Resposta[]` (já acumulado no componente), `avaliar()` de `../lib/quiz`, `LeadPayload` estendido (Task 5).
- Produces: POST com `respostas/duvidas/qualificado` no shape da Task 3.

- [ ] **Step 1: Implementar** — em `veredito()`, trocar o bloco `if (endpoint) {...}` por:

```ts
    if (endpoint) {
      const campanha = qualificado ? quiz.slug : `${quiz.slug}-desqualificado`;
      const respostasPayload = respostas.map((r) => ({
        id: r.pergunta.id,
        pergunta: r.pergunta.rotuloResumo,
        resposta: r.opcao.rotulo,
        valor: r.opcao.valor,
        ...(r.opcao.reprova ? { reprova: true } : {}),
        ...(r.opcao.duvida ? { duvida: true } : {}),
      }));
      // Sem etapa de nome no fluxo (decisão Eduardo 10/08): o hub identifica
      // pelo telefone; o nome real vem na conversa do WhatsApp.
      void enviarLead(endpoint, {
        nome: 'Lead triagem', telefone, campanha, mensagem: resumo, website: honeypot.value,
        qualificado, duvidas, respostas: respostasPayload,
      // Pixel `Lead` só no qualificado: desqualificado entra no hub, mas não
      // ensina o algoritmo da Meta com lead ruim (decisão Eduardo 10/08).
      }).then((res) => { if (res.ok && qualificado) trackLead(); });
    }
```

  (O `mensagem: resumo` CONTINUA sendo enviado — vira nota legível como hoje; o estruturado é adicional, não substituto.)

- [ ] **Step 2: Validar** — `npm test` completo (conteúdo OAB + libs) → verde; `npm run build` → verde; `npx astro check` limpo.

- [ ] **Step 3: Commit + push** (push na main = deploy automático; código, não copy — sem gate. **Só fazer o push DEPOIS do deploy da Parte A no hub.**)

```bash
git add src/components/ChatQuiz.astro
git commit -m "feat(quiz): envia respostas estruturadas da triagem pro hub"
git push origin main
```

---

## Parte C — ramonantonio-site (Task 7, GATE DE COPY)

### Task 7: Assinatura do site institucional na mensagem de WhatsApp

**Files:**
- Modify: `src/data/site.ts` (campo `whatsapp.mensagem`)

**Interfaces:**
- Produces: a 1ª mensagem de quem clica no WhatsApp do site casa com a assinatura `/vim pelo site do escrit[óo]rio/i` da Task 1 → canal `google_seo`.

- [ ] **Step 1: Editar** — em `src/data/site.ts`, trocar:

```ts
mensagem: 'Olá! Gostaria de falar com a equipe do Ramon Antonio Advogados.',
```

por:

```ts
mensagem: 'Olá! Vim pelo site do escritório e gostaria de falar com a equipe.',
```

- [ ] **Step 2: ⛔ GATE — apresentar ao Eduardo como rascunho** (copy que fala com cliente). Mostrar antes/depois e esperar o "aprovado" explícito. **NÃO commitar/pushar antes disso** (push na main do site = deploy FTP automático).

- [ ] **Step 3 (só após aprovado): Build + commit + push**

```bash
npm run build
git add src/data/site.ts
git commit -m "feat: assinatura de canal na mensagem de WhatsApp do site"
git push origin main
```

---

## Passos manuais do Eduardo (fora de código — listar no doc de smoke)

1. **Link da bio do Instagram**: trocar o wa.me da bio por um com `?text=` "Olá! Vim pelo Instagram e quero avaliar meu caso." (assinatura da Task 1). Sem isso, lead de bio vira `indicacao` — aceitável até ele trocar.
2. **Aprovar a copy da Task 7** (1 linha do site).
3. **Rodar o smoke** `comercial\docs\2026-08-13-smoke-onda1-aquisicao.md` quando a Parte A estiver no ar.

## Self-review (feito na escrita)

- **Cobertura do design (Onda 1)**: decisão 1 (canal=dimensão) — já era o estado, nada a fazer; decisão 2 (derivação completa) — Tasks 1, 2, 7 + passo manual 1; decisão 3 (quiz viaja) — Tasks 3, 5, 6, 4 (exibição); decisão 4 (nasce em Qualificação) — Task 3; decisão 5 (papéis) — sem código, já coberto por sdr_id/closer_id existentes. Decisões 6–13 = Ondas 2–3, fora deste plano de propósito.
- **Placeholders**: nenhum "TBD/similar à Task N"; os dois pontos de adaptação explícitos (helper de evento no spec do listener, nomes do setup no request spec) apontam o arquivo-fonte exato de onde copiar o padrão — inevitável sem rodar RSpec localmente.
- **Consistência de tipos**: shape `{id, pergunta, resposta, valor, reprova?, duvida?}` idêntico em Task 3 (permit), Task 4 (render), Task 5 (interface TS) e Task 6 (map); `derive_from_message` → `[channel, source]` usado igual em Task 1 e 2; label `fase-qualificacao` confere com o seed (`seed_default_config_service.rb`).

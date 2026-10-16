# Funil automático — plano de implementação

> **Para agentes que executam:** SUB-SKILL OBRIGATÓRIA: superpowers:subagent-driven-development (recomendado) ou
> superpowers:executing-plans, task a task. Os passos usam checkbox (`- [ ]`).

**Objetivo:** o hub mantém o kanban em dia sozinho, em qualquer modo de atendimento. Ele age por regras fixas
(ZapSign e tempo parado) e por um observador de IA que lê a conversa na pausa. Toda ação fica registrada, pode ser
desfeita e liga por chave, com modo ensaio.

**Arquitetura:**
- **Ponto único** `Ramon::FunilAutomatico.executar`: lê a chave da peça (off / ensaio / on), grava a ação numa tabela
  nova `ramon_funil_acoes` (rastro, ensaio, desfazer, resumo das 8h) e só então aplica.
- **Regras fixas:** ganchos no ZapSign e um job diário de tempo.
- **Observador:** job com espera de 10 min depois de cada mensagem (sai se chegou mensagem mais nova). Faz uma chamada
  barata de LLM que devolve um JSON de decisões, e cada decisão passa pelo ponto único.

**Stack:** Rails 7.1 / Ruby 3.4 (fork Chatwoot v4.15.1), Sidekiq + sidekiq-cron (`config/schedule.yml`), Postgres jsonb,
Vue 3 `<script setup>` + Tailwind, RSpec.

**Spec:** `docs/superpowers/specs/2026-10-16-funil-automatico-design.md`, aprovado em 16/10. Leia junto. A seção
"Respostas do Eduardo" e a seção "Decisões da revisão do builder" valem como requisito.

## Restrições globais

- **Nunca volta etapa**, com uma exceção: contrato assinado com o lead em Perdido vira Ganho.
- **A IA (LLM) nunca marca Ganho.** O Ganho só vem de `zapsign_ganho`, uma regra fixa.
- **Nada é enviado ao cliente por este plano.** Remarcação e reativação são notas-rascunho
  (`"RASCUNHO (revisar antes de enviar) — …"`), como o `confirmation_draft` de `Ramon::ReuniaoAgendamento`.
- **Chaves por peça,** com o valor `'off' | 'ensaio' | 'on'` em `account.settings['funil_automatico'][<peça>]`.
  O padrão é `'off'`. Peças: `etapa_ia perdido_recusa reuniao_ia colheita promessas pendencias temperatura
  zapsign_negociacao zapsign_ganho tempo_ultima_chance tempo_perdido no_show reativacao`.
- **Etapas por label, nunca por nome:**
  - `fase-novo`, `fase-qualificacao`, `fase-reuniao-agendada`, `fase-reuniao-realizada`, `fase-negociacao`,
    `fase-ultima-chance`;
  - Ganho = `find_by(is_won: true)`; Perdido = `find_by(is_lost: true)`.
- **Motivo de perda por sumiço:** `'Sumiu / não respondeu'`, exato e do catálogo `LostReason`.
- **Ganho pelo ZapSign usa o `value` estimado,** sem tarefa e sem confirmação. Ele congela sozinho
  (`LeadValorEstimado`, `return if won_at.present?`).
- **Resumo:** seção "O que a IA mexeu ontem" no resumo das 8h, só para administradores.
- **LLM:**
  - modelo de `Ramon::LlmEscolha.para(account, 'copiloto')`, com `funcao: 'funil_observador'`;
  - texto passa por `Ramon::Pseudonymizer.mask` antes de sair;
  - `retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3`.
- **Código só em `app/`.** Nada pode depender de `enterprise/`, porque o CI de código aberto apaga essa pasta.
- **Ruby:** RuboCop com linha de 150 caracteres. Classe/módulo compacto (`class Ramon::X`).
- **Vue:** Composition API, eventos em camelCase, só Tailwind. i18n em `en.json` **e** `pt_BR/ramon.json` (padrão do
  fork).
- **Verificação:** não há Ruby local (Smart App Control). Lint com `rubocop-vps <arquivos>`; specs no CI do PR da fase.
  Cada task escreve o spec antes do código.
- **Entrega:** uma fase = um PR. Merge com CI 100% verde, deploy na VPS e registro em doc de entrega com smoke em bloco
  por seção. O regime é de merge e deploy autônomos. Toda peça sobe **off**; ligar é ação do Eduardo.

## Pontos de revisão (o que nenhum teste de feliz-caminho pega)

1. **Lead sem conversa, ou conversa sem mensagens novas desde a última pausa.** O observador não chama o LLM e não
   grava nada. Teste na Task 6.
2. **LLM devolve lixo, etapa inexistente, motivo de perda fora do catálogo ou data no passado.** Nada é aplicado, só um
   log. Motivo fora do catálogo vira `nil`, e o Lead preenche "Automação: sistema". Testes nas Tasks 6, 7 e 10.
3. **Desfazer e a próxima pausa.** Depois de desfazer, o observador não repete a mesma ação até chegar mensagem nova do
   cliente. Teste na Task 8.
4. **Conta com etapa faltando ou label renomeado** (ex.: sem `fase-ultima-chance`). A regra pula sem quebrar o job da
   conta. Testes nas Tasks 2 e 3.
5. **Corrida entre regra fixa e observador** (ex.: ZapSign assina enquanto o observador decide "Última chance"). O
   observador relê o lead antes de aplicar e não mexe em lead ganho ou perdido. Teste na Task 7.

---

## Fase 1 — fundação e regras fixas (PR 1)

### Task 1: Ponto único, tabela de ações e chaves

**Arquivos:**
- Criar `db/migrate/20261017120001_create_ramon_funil_acoes.rb` e regenerar `db/schema.rb`. Não há Postgres local: use
  um banco de rascunho na VPS, lição do `CLAUDE.md` do hub.
- Criar `app/models/funil_acao.rb`, `app/services/ramon/funil_automatico.rb`, `lib/tasks/ramon_funil.rake`.
- Testes: `spec/services/ramon/funil_automatico_spec.rb`, `spec/models/funil_acao_spec.rb`.

**Interfaces:**
- Produz a tabela `ramon_funil_acoes`:
  - colunas: `account_id`, `lead_id` (FK, índice), `peca` string, `acao` string, `motivo` string(250), `alvo` string
    (ex.: nome da etapa ou id da tarefa), `desfazer` jsonb default `{}`, `ensaio` boolean default false, `desfeita_em`
    datetime, `desfeita_por_id` (users), `created_at`;
  - índice `(account_id, created_at)`.
- Produz o model `FunilAcao` (`self.table_name = 'ramon_funil_acoes'`):
  - `scope :reais, -> { where(ensaio: false) }`;
  - `scope :vivas, -> { reais.where(desfeita_em: nil) }`.
- Produz `Ramon::FunilAutomatico` com:
  - `PECAS` (lista das Restrições globais);
  - `modo(account, peca) -> 'off'|'ensaio'|'on'`;
  - `mudar!(account, peca, modo)` (valida peça e modo, `ArgumentError` senão);
  - `executar(lead, peca:, acao:, motivo:, alvo: nil, desfazer: {}) { ... } -> FunilAcao | nil`, que se comporta assim:
    - **off** → `nil`, sem gravar e sem rodar o bloco;
    - **ensaio** → grava `FunilAcao(ensaio: true)` e não roda o bloco;
    - **on** → roda o bloco e grava `FunilAcao(ensaio: false)` na mesma transação. Bloco que devolve `false` → não grava
      e devolve `nil`.
    - Em on, cria também `LeadActivity(kind: 'funil_auto', to_value: "#{acao}: #{motivo}".truncate(250))` para o
      histórico do lead, que é a "marca de que foi a IA" do spec.
  - `desfeita_recente?(lead, acao:, alvo:) -> Boolean`: existe `FunilAcao` desfeita com o mesmo `acao`/`alvo` e
    `desfeita_em` depois da última mensagem incoming da conversa do lead.
- Produz o rake `ramon:funil:modo[account_id,peca,modo]` (chama `mudar!` e imprime o novo estado).

- [ ] **Passo 1: specs que falham.**
  - `executar` em off devolve `nil` e `FunilAcao.count == 0`.
  - Em ensaio, grava 1 com `ensaio: true` e o bloco não roda (`expect { |b| ... }.not_to yield_control`).
  - Em on, roda o bloco, grava `ensaio: false` e cria 1 `LeadActivity` com `kind 'funil_auto'`.
  - Bloco que devolve `false` → nada gravado.
  - `mudar!(account, 'xyz', 'on')` levanta `ArgumentError`.
  - `desfeita_recente?` é true sem mensagem nova e false depois de uma incoming criada após `desfeita_em`.
- [ ] **Passo 2: implementar migração, model, módulo e rake.** As chaves seguem o precedente do
  `Ramon::CadernoNoturnoJob` (merge em `account.settings`).
- [ ] **Passo 3: lint** com `rubocop-vps app/models/funil_acao.rb app/services/ramon/funil_automatico.rb
  lib/tasks/ramon_funil.rake db/migrate/20261017120001_create_ramon_funil_acoes.rb`. Esperado: sem ofensas.
- [ ] **Passo 4: commit** `feat(funil): ponto único das ações automáticas do funil`.

### Task 2: ZapSign — contrato criado → Negociação; assinado → Ganho

**Arquivos:**
- Modificar `app/services/ramon/zapsign_contract_service.rb` (`gravar`, L49-53).
- Modificar `app/jobs/ramon/zapsign_lead_status_job.rb`: trocar o comentário L3-5 e mexer no `perform` depois de
  `avisar`.
- Modificar `db/seeds/ramon/fluxos/sistema/contrato_zapsign.json`: tirar "Nunca marca o lead como ganho" (L5, L8, L22)
  e descrever as duas regras com as chaves.
- Criar `app/services/ramon/funil_regras.rb`.
- Testes: `spec/services/ramon/funil_regras_spec.rb`; ajustar `spec/jobs/ramon/zapsign_lead_status_job_spec.rb` (L21
  hoje afirma `won_at` nil e passa a depender da chave).

**Interfaces:**
- Consome `Ramon::FunilAutomatico.executar` (Task 1).
- Produz `Ramon::FunilRegras.contrato_criado(lead)` e `Ramon::FunilRegras.contrato_assinado(lead)`.
- Produz o helper público `Ramon::FunilRegras.mover_para_frente(lead, label, peca:, motivo:) -> FunilAcao|nil`, que as
  Tasks 3 e 7 reutilizam:
  - acha a etapa por `label`;
  - pula se não existe, se o lead está ganho ou perdido, ou se `lead.lead_stage.position >= etapa.position`;
  - grava `desfazer: { 'etapa_id' => <anterior> }`.

- [ ] **Passo 1: specs que falham.**
  - **Peça `zapsign_negociacao` on:**
    - lead em `fase-reuniao-realizada` → `contrato_criado` leva a `fase-negociacao`, com `FunilAcao(acao:
      'mover_etapa', alvo: 'Negociação')`;
    - lead já em `fase-ultima-chance` → fica onde está.
  - **Peça `zapsign_ganho` on:**
    - `contrato_assinado` leva à etapa `is_won` e `lead.won_at` presente;
    - o `value` estimado de antes é mantido (`expect(lead.reload.value).to eq(valor_antes)`);
    - lead em Perdido → vira Ganho.
  - **Peças off:** nada muda (é o comportamento atual).
  - **Job:** com `zapsign_ganho` on, `doc['status'] == 'signed'` leva a `won_at` presente; com a peça off, `won_at` nil.
- [ ] **Passo 2: implementar.**
  - `gravar` chama `Ramon::FunilRegras.contrato_criado(@lead)` depois do `update!`, só quando o doc é novo (não na
    regravação de status).
  - O job chama `contrato_assinado(lead)` só para `'signed'`, depois de `avisar`.
  - O motivo da ação é `'contrato enviado pelo ZapSign'` / `'contrato assinado no ZapSign'`.
- [ ] **Passo 3: lint** dos arquivos tocados.
- [ ] **Passo 4: commit** `feat(funil): ZapSign move para Negociação e marca ganho (atrás de chave)`.

### Task 3: Regras de tempo (Negociação → Última chance → Perdido)

**Arquivos:**
- Criar `app/jobs/ramon/funil_tempo_job.rb`.
- Modificar `config/schedule.yml`: entrada `ramon_funil_tempo_job`, cron `'0 14 * * *'` (11h em São Paulo), fila `low`.
- Teste: `spec/jobs/ramon/funil_tempo_job_spec.rb`.

**Interfaces:**
- Consome `Ramon::Cadencia.parados(leads, agora)` e `Ramon::FunilRegras.mover_para_frente`.
- Para Perdido, chama `Ramon::FunilAutomatico.executar` direto.
- Produz `Ramon::FunilTempoJob#perform`, que percorre `Account.find_each` e pula a conta com as duas peças off.

- [ ] **Passo 1: specs que falham** (padrão `travel_to` + `update_columns(stage_entered_at:)`, como no
  `relogio_spec.rb`).
  - Negociação parada além de `stalled_after_days`, com `tempo_ultima_chance` on → `fase-ultima-chance`.
  - Última chance parada, com `tempo_perdido` on → etapa `is_lost` e `lost_reason == 'Sumiu / não respondeu'`.
    `desfazer['etapa_id']` = Última chance.
  - Lead parado em Qualificação não é tocado.
  - Conta sem `fase-ultima-chance` → o job termina sem erro.
- [ ] **Passo 2: implementar.** Ordem: primeiro Perdido, depois Última chance, para o lead não andar duas etapas no
  mesmo dia.
- [ ] **Passo 3: lint.**
- [ ] **Passo 4: commit** `feat(funil): regras de tempo do funil (Última chance e Perdido por sumiço)`.

### Task 4: Resumo das 8h e ficha nas Automações

**Arquivos:**
- Modificar `app/services/ramon/daily_digest_service.rb` (`yesterday_stats`, L21) e
  `app/views/mailers/administrator_notifications/ramon_digest_mailer/daily_digest.html.erb` (bloco novo antes da L54).
- Criar `db/seeds/ramon/fluxos/sistema/funil_automatico.json`. O modelo é `copiloto_noturno.json`, no grupo
  `leads_conversas`, com a ficha descrevendo as peças, as chaves (rake da Task 1) e as travas do spec.
- Modificar `spec/services/ramon/fluxos/sistema_spec.rb:10-11`: 29 → 30.
- Teste: `spec/services/ramon/daily_digest_service_spec.rb`.

**Interfaces:**
- Produz `yesterday_stats[:funil_auto]`: array de `{ lead_id:, lead_name:, texto:, ensaio: }`, ordenado por
  `created_at` e com no máximo 50 itens. `texto` = `"#{acao_legivel}: #{motivo}"`; o ensaio aparece como `"faria: …"`.

- [ ] **Passo 1: specs que falham.**
  - Ação de ontem aparece.
  - Ação desfeita aparece com o sufixo `" (desfeita)"`.
  - Ação de hoje não aparece.
  - Ensaio aparece com `faria:`.
- [ ] **Passo 2: implementar.** A tabela no e-mail mostra lead (link `/app/accounts/:id/leads/:lead_id`) e texto, e
  some quando a lista está vazia.
- [ ] **Passo 3: lint.** Abrir o PR 1, aguardar o CI verde e mergear. Fazer o deploy na VPS, rodar a migração e
  conferir o login 200. Atualizar o doc de entrega.
- [ ] **Passo 4: commit** `feat(funil): resumo das 8h e ficha das automações do funil`.

---

## Fase 2 — observador (PR 2)

### Task 5: Gatilho com espera de 10 min

**Arquivos:**
- Modificar `app/listeners/ramon_lead_listener.rb` (ramo `message_created`, L26-36): antes do
  `return unless message.incoming?`, enfileirar o observador para mensagem incoming ou outgoing, `private: false`, com
  lead aberto.
- Criar `app/jobs/ramon/funil_observador_job.rb`.
- Teste: `spec/jobs/ramon/funil_observador_job_spec.rb`.

**Interfaces:**
- Produz `Ramon::FunilObservadorJob.set(wait: 10.minutes).perform_later(message_id)`.
- `perform(message_id)` sai sem fazer nada em qualquer um destes casos:
  - mensagem ou lead sumiu;
  - lead ganho ou perdido;
  - existe mensagem não privada, incoming ou outgoing, com `id > message_id` na conversa (copiar a ideia de
    `mensagem_superada?`, sem depender de `enterprise/`);
  - todas as peças de IA estão off (`etapa_ia perdido_recusa reuniao_ia colheita promessas pendencias temperatura`).
- Nos outros casos chama `Ramon::FunilObservador.new(lead).perform` (Task 6).
- `queue_as :low` e o `retry_on` das Restrições globais.

- [ ] **Passo 1: specs que falham.**
  - Mensagem superada → `FunilObservador` não é chamado.
  - Peças todas off → não é chamado.
  - Caso normal → chamado uma vez.
  - Nota privada não enfileira (spec do listener).
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: lint.**
- [ ] **Passo 4: commit** `feat(funil): observador da conversa dispara na pausa de 10 min`.

### Task 6: Observador — prompt, chamada e decisão

**Arquivos:**
- Criar `app/services/ramon/funil_observador.rb`.
- Extrair a transcrição de `Ramon::NightCopilotService#transcript` (L115-127) para `app/services/ramon/transcricao.rb`.
  O `NightCopilotService` passa a usar o módulo, sem mudar o comportamento dele.
- Testes: `spec/services/ramon/funil_observador_spec.rb`, `spec/services/ramon/transcricao_spec.rb`.

**Interfaces:**
- Produz `Ramon::Transcricao.de(conversation, limite: 200) -> String`, com o mesmo formato atual (`"Cliente: …"` /
  `"Atendimento: …"`).
- Produz `Ramon::FunilObservador.new(lead).perform -> Hash|nil`:
  - monta o prompt;
  - chama `Ramon::LlmClient.complete(**Ramon::LlmEscolha.para(account, 'copiloto'), system:, user:,
    funcao: 'funil_observador', account_id:, lead_id:)`;
  - faz o parse (tira as cercas ``` e aplica `JSON.parse`);
  - entrega a decisão a `Ramon::FunilObservador::Aplicar.new(lead, decisao).perform` (Task 7);
  - devolve a decisão. JSON inválido → `nil` e log `warn`.
  - O texto do usuário inclui a ficha (etapa atual, tese, docs pendentes do checklist), a lista de `LostReason` da
    conta, as tarefas abertas "Cobrar:" com id (Task 11) e a transcrição. Tudo passa por `Ramon::Pseudonymizer.mask`.
- O formato do JSON (no `SYSTEM_PROMPT`, que é interno e não fala com o cliente):

```json
{"etapa": "qualificacao" | "ultima_chance" | null, "etapa_motivo": "1 frase",
 "perdido": {"motivo": "<nome exato da lista>", "frase": "1 frase"} | null,
 "reuniao": {"inicio": "AAAA-MM-DDTHH:MM", "frase": "1 frase"} | null,
 "promessas": [{"o_que": "texto curto", "prazo": "AAAA-MM-DD", "documento": true}],
 "promessas_cumpridas": [<id da tarefa>],
 "pendencias": ["laudo", "CNIS"],
 "temperatura": "quente" | "morno" | "frio", "temperatura_motivo": "1 frase"}
```

- Regras do `SYSTEM_PROMPT`, uma linha cada:
  - decidir só pelo que está na conversa;
  - `qualificacao` só quando o cliente respondeu a triagem e cabe na tese;
  - `ultima_chance` só depois da reunião, com objeção ("vou pensar", preço, família);
  - `perdido` só com recusa clara do cliente;
  - `reuniao` só com dia **e** hora exatos aceitos pelos dois, no fuso de São Paulo;
  - promessa com data vaga → o 1º dia útil citado;
  - nunca prometer resultado nem prazo do INSS.

- [ ] **Passo 1: specs que falham** (stub de `Ramon::LlmClient.complete` devolvendo `Result` com `content` JSON).
  - Lead sem conversa → `perform` devolve `nil` e o LLM não é chamado.
  - JSON com cercas → parse ok e `Aplicar` recebe o Hash.
  - Conteúdo "não sei" → `nil`, sem exceção.
  - O texto enviado não contém o CPF do contato (máscara aplicada).
  - `NightCopilotService`: o spec existente continua verde.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: lint.**
- [ ] **Passo 4: commit** `feat(funil): observador decide pela conversa (etapa, perda, reunião, promessas, temperatura)`.

### Task 7: Aplicar — etapa, perdido por recusa, temperatura

**Arquivos:**
- Criar `app/services/ramon/funil_observador/aplicar.rb`. As Tasks 10–13 acrescentam métodos nesta classe.
- Teste: `spec/services/ramon/funil_observador/aplicar_spec.rb`.

**Interfaces:**
- Consome `Ramon::FunilRegras.mover_para_frente`, `Ramon::FunilAutomatico.executar`/`desfeita_recente?`,
  `Ramon::Roteiro::Efeitos.perder(lead, motivo)`.
- `Ramon::FunilObservador::Aplicar.new(lead, decisao).perform`:
  1. Faz `lead.reload` e sai se o lead está ganho ou perdido.
  2. **Etapa:**
     - `qualificacao` só sai de `fase-novo`;
     - `ultima_chance` só sai de `fase-reuniao-realizada` ou `fase-negociacao`;
     - a peça é `etapa_ia`;
     - pula se `desfeita_recente?(lead, acao: 'mover_etapa', alvo: <nome>)`.
  3. **Perdido** (peça `perdido_recusa`):
     - motivo fora de `account.lost_reasons.pluck(:name)` vira `nil`;
     - o bloco chama `Efeitos.perder` (etiqueta `desqualificado-ia` + modo manual);
     - `desfazer` = `{ 'etapa_id' => anterior, 'modo' => <copiloto_modo antes> }`.
  4. **Temperatura** (peça `temperatura`):
     - grava `custom_attributes['temperatura'] = { 'nivel', 'motivo', 'em' }`;
     - **não** cria `FunilAcao`, porque seria ruído no resumo. Em ensaio, não grava.

- [ ] **Passo 1: specs que falham.**
  - `etapa: 'qualificacao'` com o lead em Novo → Qualificação.
  - O mesmo com o lead em Negociação → nada.
  - `ultima_chance` com o lead em Novo → nada.
  - `perdido` com motivo `'Honorário'` → Perdido, `lost_reason 'Honorário'`, conversa com a etiqueta
    `desqualificado-ia`.
  - Motivo inventado → Perdido com `lost_reason` começando por `'Automação:'`.
  - Lead ganho → nada.
  - Temperatura gravada só com a peça on.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: lint.**
- [ ] **Passo 4: commit** `feat(funil): aplica etapa, perda por recusa e temperatura`.

### Task 8: Desfazer (API + card)

**Arquivos:**
- Modificar `config/routes.rb`: dentro do recurso de leads da conta, `resources :funil_acoes, only: [] { post :desfazer,
  on: :member }`.
- Criar `app/controllers/api/v1/accounts/funil_acoes_controller.rb`.
- Modificar `app/models/funil_acao.rb` (`desfazer!`), `app/views/api/v1/accounts/leads/_lead.json.jbuilder`, `app/models/lead.rb`
  (`push_event_data`, L95-96), `app/javascript/dashboard/routes/dashboard/ramon/components/kanban/LeadCard.vue` (chip
  junto dos chips L348-371) e a API JS de leads (padrão `LeadsAPI`).
- i18n: `RAMON.FUNIL_AUTO.DESFAZER` e `RAMON.FUNIL_AUTO.IA_MOVEU`.
- Testes: `spec/requests/api/v1/accounts/funil_acoes_spec.rb`, `spec/models/funil_acao_spec.rb`.

**Interfaces:**
- Produz `FunilAcao#desfazer!(user) -> Boolean`:
  - `desfazer['etapa_id']` → `lead.update!(lead_stage_id:, lost_reason: nil)`;
  - `desfazer['modo']` → `Ramon::CopilotoModo.trocar(conversa, modo)` + `Ramon::Roteiro::Efeitos.tirar_etiqueta(conversa)`;
  - `desfazer['task_id']` (meeting) → `Ramon::ReuniaoAgendamento.cancelar(task:, user:)`;
  - `desfazer['task_id']` (follow_up) → `task.destroy!`;
  - grava `desfeita_em` e `desfeita_por`;
  - já desfeita → `false`.
- `POST /api/v1/accounts/:account_id/leads/:lead_id/funil_acoes/:id/desfazer` → 200, com o lead no JSON completo.
- Card (index slim):
  - escalar `funil_acao: { id, texto }` com a última `FunilAcao.vivas` do lead nas últimas 24h, ou `nil`;
  - chip `IA: <texto>` com o botão "Desfazer";
  - no clique, chamar a API e recarregar o card pelo broadcast.

- [ ] **Passo 1: specs que falham.**
  - `desfazer!` de mover etapa volta à etapa anterior e grava `desfeita_em`.
  - O segundo `desfazer!` devolve `false`.
  - `desfazer!` de perdido devolve a etapa, tira a etiqueta e restaura o modo.
  - Request de agente de outra conta → 404.
  - Depois de desfazer, `Aplicar` com a mesma decisão e sem mensagem nova não move de novo (ponto de revisão 3).
- [ ] **Passo 2: implementar o back.**
- [ ] **Passo 3: implementar o front.** Rodar `pnpm eslint` nos arquivos tocados (via node_modules, lição do hub).
- [ ] **Passo 4: lint Ruby.** Abrir o PR 2, aguardar o CI verde e mergear. Fazer o deploy, aplicar a migração se houver,
  e atualizar o doc de entrega com o smoke da Fase 2.
- [ ] **Passo 5: commit** `feat(funil): desfazer ação automática pelo card`.

---

## Fase 3 — extras do observador (PR 3)

### Task 9: Reunião pela conversa + correção do `agendar_reuniao`

**Arquivos:**
- Modificar `app/services/ramon/funil_observador/aplicar.rb` (método `reuniao`).
- Modificar `app/models/copilot_suggestion.rb` (`agendar_reuniao`, ~L102).
- Testes: o spec do `aplicar` e `spec/models/copilot_suggestion_spec.rb`.

**Interfaces:**
- Peça `reuniao_ia`.
- O `inicio` é lido com `Time.find_zone!('America/Sao_Paulo').parse`. Pula se:
  - for inválido ou estiver no passado;
  - o lead já tiver tarefa `meeting` aberta;
  - `desfeita_recente?(acao: 'marcar_reuniao', alvo: inicio.iso8601)`.
- O bloco chama `Ramon::ReuniaoAgendamento.call(lead:, starts_at:, title: 'Reunião', user: nil)`.
- `desfazer` = `{ 'task_id' => <tarefa meeting criada> }`.
- `CopilotSuggestion#agendar_reuniao` passa a chamar `Ramon::ReuniaoAgendamento.call` (lembretes, etapa e Closer),
  e não só criar a tarefa.

- [ ] **Passo 1: specs que falham.**
  - Decisão com reunião futura → tarefa `meeting` criada e lead em `fase-reuniao-agendada`.
  - Data no passado → nada.
  - Já existe reunião aberta → nada.
  - Sugestão `acao: 'reuniao'` aplicada → lead em `fase-reuniao-agendada`, que hoje fica parado.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: lint.**
- [ ] **Passo 4: commit** `feat(funil): reunião combinada na conversa vira reunião no hub`.

### Task 10: Colheita na pausa

**Arquivos:**
- Modificar `app/services/ramon/funil_observador.rb`: chamar a colheita depois do `Aplicar`, peça `colheita`.
- Atualizar o comentário de `app/jobs/ramon/colheita_extraction_job.rb:1-5`.
- Teste: o spec do observador.

**Interfaces:**
- Com a peça on, usa `Ramon::FunilAutomatico.executar(lead, peca: 'colheita', acao: 'colher', motivo: 'pausa na
  conversa') { Ramon::ColheitaExtractionService.new(lead).perform; true }`. O `desfazer` fica `{}`, porque a colheita
  só preenche campo vazio.
- A colheita continua restrita a auxílio-acidente (`THESIS_MATCH`).

- [ ] **Passo 1: specs que falham.**
  - Peça on → o serviço é chamado uma vez.
  - Peça off → não é chamado.
  - Tese ≠ auxílio-acidente → o serviço roda e não grava (comportamento atual).
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: lint.**
- [ ] **Passo 4: commit** `feat(funil): colheita automática na pausa da conversa`.

### Task 11: Promessas viram tarefa e pendências no card

**Arquivos:**
- Modificar `app/services/ramon/funil_observador/aplicar.rb` (métodos `promessas` e `pendencias`).
- Modificar `_lead.json.jbuilder`, `lead.rb` (`push_event_data`) e `LeadCard.vue`.
- i18n `RAMON.FUNIL_AUTO.AGUARDANDO`.
- Teste: o spec do `aplicar`.

**Interfaces:**
- **Promessas** (peça `promessas`):
  - cada item vira `lead.lead_tasks.create!(account:, user: lead.sdr || lead.closer, kind: 'follow_up',
    title: "Cobrar: #{o_que}".truncate(255), due_at: <prazo às 10:00 SP>)`;
  - pula se já existe tarefa aberta com o mesmo título;
  - `desfazer` = `{ 'task_id' => id }`.
- **Promessas cumpridas:** cada id que pertence ao lead, aberto e com título começando por `"Cobrar:"`, recebe
  `task.complete!(nil)` dentro de `executar(acao: 'promessa_cumprida')`.
- **Pendências** (peça `pendencias`):
  - grava `custom_attributes['pendencias_docs']` = a lista, substituída a cada pausa (no máximo 5 itens, 40
    caracteres cada);
  - lista vazia remove a chave;
  - sem `FunilAcao`.
- **Card:** escalar `pendencias_docs` no slim e chip `Aguardando: laudo, CNIS`.

- [ ] **Passo 1: specs que falham.**
  - Promessa com prazo `'2026-10-20'` → tarefa follow_up do SDR em `2026-10-20 10:00 -03:00`.
  - A mesma promessa duas vezes → 1 tarefa.
  - `promessas_cumpridas: [id]` → tarefa concluída.
  - Id de tarefa de outro lead → ignorado.
  - `pendencias: []` → a chave sai.
- [ ] **Passo 2: implementar o back.**
- [ ] **Passo 3: implementar o front.** Rodar o eslint.
- [ ] **Passo 4: commit** `feat(funil): promessas viram tarefa e pendências aparecem no card`.

### Task 12: No-show automático

**Arquivos:**
- Criar `app/jobs/ramon/funil_no_show_job.rb`.
- Modificar `config/schedule.yml`: cron `'*/30 * * * *'`, fila `low`.
- Teste: `spec/jobs/ramon/funil_no_show_job_spec.rb`.

**Interfaces:**
- Peça `no_show`.
- Considera tarefas `meeting` abertas com `due_at < 2.hours.ago` e `due_at > 2.days.ago`, que ainda não tenham
  `FunilAcao(acao: 'avisar_no_show', alvo: task.id.to_s)`.
- Para cada uma:
  - `Ramon::LeadNotificationBuilder.new(lead:, notification_type: 'ramon_meeting_reminder', user_ids:
    [lead.closer_id].compact.presence || <admins>, meta: { 'quando' => ReuniaoAgendamento.quando(task.due_at), 'label'
    => 'sem registro' }).perform`;
  - nota-rascunho em `lead.lead_notes.create!(account:, body:)`, com o texto abaixo, que foi **APROVADO pelo Eduardo em 16/10**:

```
RASCUNHO (revisar antes de enviar) — remarcação:
"Oi {primeiro_nome}! Senti sua falta na nossa conversa de {quando}. Imagino que tenha surgido algum imprevisto. Quer que a gente marque um novo horário?"
```

- **Não marca a falta** (`complete!(no_show: true)` continua sendo do Closer).
- `desfazer` = `{}`.

- [ ] **Passo 1: specs que falham.**
  - Reunião 3h atrás sem registro → 1 nota e 1 `FunilAcao`.
  - Rodar de novo → nada novo.
  - Reunião concluída → nada.
  - Reunião há 1h → nada.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: lint.**
- [ ] **Passo 4: commit** `feat(funil): aviso de no-show com rascunho de remarcação`.

### Task 13: Reativação de perdidos (30 e 60 dias)

**Arquivos:**
- Criar `app/jobs/ramon/funil_reativacao_job.rb`.
- Modificar `config/schedule.yml`: cron `'0 13 * * 1-5'` (10h em São Paulo).
- Teste: `spec/jobs/ramon/funil_reativacao_job_spec.rb`.

**Interfaces:**
- Peça `reativacao`.
- Considera leads com `lost_reason == 'Sumiu / não respondeu'` e `lost_at.to_date` ∈ `{30.days.ago.to_date,
  60.days.ago.to_date}` (hoje, fuso de São Paulo). Dias não úteis são cobertos no dia útil seguinte, comparando com
  "desde a última rodada", e a idempotência vem de `FunilAcao(acao: 'reativar', alvo: '30'|'60')`.
- Para cada lead:
  - nota-rascunho (texto abaixo, **APROVADO pelo Eduardo em 16/10**);
  - tarefa follow_up do SDR, "Retomar contato (30 dias)" ou "(60 dias)", com prazo hoje às 10h.

```
RASCUNHO (revisar antes de enviar) — retomada:
"Oi {primeiro_nome}, tudo bem? Passando pra saber se você ainda quer ajuda com o seu caso. Se fizer sentido, é só me responder por aqui que a gente retoma de onde parou."
```

- [ ] **Passo 1: specs que falham.**
  - Perdido por sumiço há 30 dias → nota + tarefa.
  - Perdido por `'Honorário'` → nada.
  - Rodar 2x no mesmo dia → nada repetido.
  - Lead perdido há 31 dias e o job não rodou ontem (feriado) → coberto.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: lint.**
- [ ] **Passo 4: commit** `feat(funil): rascunho de retomada aos 30 e 60 dias`.

### Task 14: Fila do dia

**Arquivos:**
- Modificar o controller de leads (index; achar com `rg -n "def index" app/controllers/api/v1/accounts/leads_controller.rb`).
- Modificar o kanban: `KanbanBoard.vue` ou a barra de filtros dele, com o botão "Fila do dia" que troca a vista para a
  lista ordenada.
- i18n `RAMON.FUNIL_AUTO.FILA_DO_DIA`.
- Teste: `spec/requests/api/v1/accounts/leads_spec.rb` (caso novo).

**Interfaces:**
- `GET /api/v1/accounts/:account_id/leads?ordem=fila` devolve só os leads abertos, ordenados por:
  1. `custom_attributes->'temperatura'->>'nivel'`, na ordem quente, morno, frio, sem;
  2. a última mensagem incoming sem resposta, a mais antiga primeiro.
- Escalar `temperatura` (`nivel`) no slim; chip de cor no card: quente = vermelho, morno = âmbar, frio = azul, sempre
  com fundo translúcido (regra visual do hub).

- [ ] **Passo 1: spec que falha.** Três leads quente, frio e sem temperatura → a ordem é `[quente, frio, sem]`.
- [ ] **Passo 2: implementar o back.**
- [ ] **Passo 3: implementar o front.** Rodar o eslint.
- [ ] **Passo 4: lint Ruby.** Abrir o PR 3, aguardar o CI verde e mergear. Fazer o deploy e completar o doc de entrega
  com o smoke da Fase 3. Os textos de remarcação e retomada já estão aprovados (16/10).
- [ ] **Passo 5: commit** `feat(funil): fila do dia por temperatura`.

---

## Entrega (todas as fases)

- Doc de entrega `comercial/docs/2026-10-XX-funil-automatico-entrega.md`, com:
  - PRs, SHAs, deploy e migração;
  - **smoke em bloco por seção**, na caixa "WhatsApp Cloud (teste)": qualifica, combina horário, promete documento,
    recusa, some; ZapSign criado e assinado; no-show; resumo das 8h;
  - comandos para ligar cada peça em **ensaio** e depois em **on** (`rake ramon:funil:modo[1,<peça>,ensaio]`).
- Nenhuma peça é ligada pelo Claude. Ligar é ação do Eduardo.

# Agenda no hub (Google Calendar) — plano de implementação

> **Para agentes que executam:** SUB-SKILL OBRIGATÓRIA: superpowers:subagent-driven-development (recomendado) ou
> superpowers:executing-plans, task a task. Os passos usam checkbox (`- [ ]`).

**Objetivo:** o hub vira a agenda do comercial, sincronizada nos dois sentidos com o Google Calendar de cada pessoa. A IA,
o SDR e o Closer oferecem horários livres de verdade, a reunião nasce no Google com Meet, e o Cal.com é aposentado.

**Arquitetura:**
- **Conta Google por usuário:** tabela própria com tokens cifrados, OAuth com callback próprio e escopo `calendar.events`.
- **Cliente HTTP mínimo** (HTTParty, padrão do fork) para a Calendar v3.
- **A reunião continua sendo uma `LeadTask kind 'meeting'`.** Callbacks do model empurram a reunião para o Google em
  todos os caminhos: painel, fluxos, IA, observador e Cal.com durante a virada.
- **Job periódico** traz do Google as mudanças feitas lá.
- **Disponibilidade** é uma função pura sobre intervalos ocupados (hub + Google).
- **A tela Agenda que já existe** (`pages/Agenda.vue`) ganha filtro por pessoa, cor por pessoa e os compromissos do Google.

**Stack:** Rails 7.1 / Ruby 3.4 (fork Chatwoot v4.15.1), HTTParty, `oauth2` (já no Gemfile), ActiveRecord encryption,
sidekiq-cron, Vue 3 `<script setup>` + Tailwind, RSpec + WebMock.

**Spec:** `docs/superpowers/specs/2026-10-16-agenda-no-hub-design.md`, aprovado em 16/10. As seções "Respostas do Eduardo"
e "Decisões da revisão do builder" valem como requisito.

## Restrições globais

- **Reunião = 30 min, folga de 15 min depois.** A folga também vale em volta dos compromissos do Google.
- **Horário de oferta:** `Ramon::HorarioComercial::JANELAS` (8h30–12h e 13h30–18h), seg–sex, fuso
  `America/Sao_Paulo`, próximos **5 dias úteis**, nunca com menos de **2h** de antecedência, sem feriados.
- **Quem tem agenda:** membros dos times `sdr` e `closer` (`Ramon::Papeis.membro_ids`) e os administradores.
- **Compromissos do Google aparecem com o título** para todo o comercial.
- **Formato:** `video` (Meet, padrão) ou `whatsapp` (ligação, sem Meet).
- **IA marca conforme o modo:**
  - direto (com conferência e bloqueio do horário) quando `Ramon::CopilotoModo.direto?`;
  - nos outros modos, sugestão no Cockpit, que é o comportamento atual de `agendar_reuniao`.
- **Convite ao cliente** só quando o contato tem e-mail, com o texto APROVADO 16/10 (seção "Texto do convite" do spec):
  - título: `Conversa com Ramon Antonio Advogados`;
  - descrição com `{primeiro_nome}` e `{nome_do_closer}`.
- **Confirmação no WhatsApp** com dia, hora, Meet e "salvar na minha agenda": **texto APROVADO 16/10** (Task 11). O
  envio automático pela IA nos modos piloto fica atrás da chave `RAMON_AGENDA_CONFIRMACAO=on`, que o Eduardo liga.
  Desligada, a confirmação é o rascunho nas notas.
- **Nada sai para o cliente fora disso.**
- **Tokens do Google cifrados** (`encrypts`), nunca em log. Logs de erro levam só a classe e os ids (LGPD).
- **Código só em `app/` e `lib/`,** exceto as tools do assistente, que moram em `enterprise/lib/captain/tools/` como as
  irmãs.
- **Estilo:** RuboCop 150 colunas; Vue com Composition API e eventos em camelCase; só Tailwind, com fundos
  translúcidos (`R/helpers/ui.js` → `TOM`, `CHIP`); i18n em `en.json` **e** `pt_BR/ramon.json`.
- **Verificação:** sem Ruby local, `rubocop-vps` + `npx eslint` por task; specs no CI do PR da fase; HTTP externo com
  WebMock (`stub_request`).
- **Entrega:** uma fase = um PR; merge com CI verde e deploy; doc de entrega com smoke em bloco por seção.

## Pontos de revisão

1. **Token do Google revogado ou expirado sem refresh.** A marcação no hub não falha; a reunião nasce só no hub, a
   conta fica marcada `desconectada` e o resumo das 8h avisa. Teste na Task 3.
2. **Laço de sincronização:** o hub move um evento, o job de entrada vê a mudança e remarca de novo, e assim por diante.
   O job só age quando o horário do Google difere do `due_at`. Teste na Task 6.
3. **Duas ofertas aceitas para o mesmo horário** (corrida entre IA e SDR). A segunda marcação confere de novo e
   recusa. Teste na Task 5.
4. **Closer sem Google conectado.** A oferta usa só a agenda do hub, a marcação não tenta o Google e nada quebra.
   Testes nas Tasks 4 e 5.
5. **Reunião que veio do Cal.com durante a virada.** Ela também vai para o Google do Closer, e o webhook continua
   remarcando e cancelando. Teste na Task 5.

---

## Fase A — conexão Google (PR 1)

### Task 0 (gate, ação do Eduardo + controller): app do Google e chaves

**Não é código.** O controller entrega o passo a passo no doc da fase e confere antes da Task 1 subir para produção.
1. **Google Cloud do cliente OAuth existente** (`GOOGLE_OAUTH_CLIENT_ID`):
   - ativar a **Google Calendar API**;
   - na tela de consentimento, adicionar o escopo `.../auth/calendar.events`, tipo **Externo**, status
     **Em produção** (sem verificação, porque o modo Teste expira o acesso em 7 dias);
   - incluir a URI de redirecionamento `https://chat.ramonantonio.adv.br/ramon/google_agenda/callback`.
2. **Na VPS:** conferir se existem `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `_DETERMINISTIC_KEY` e
   `_KEY_DERIVATION_SALT` no `chatwoot.env`. Se faltarem, gerar com `rails db:encryption:init`, gravar no env e reiniciar
   **antes** do primeiro token. Isso é escrita na VPS: pedir ao Eduardo se o classificador barrar.
3. **Prova com conta real (passo 0 do spec):** depois do deploy, o Eduardo conecta o próprio Google pela tela e o
   controller confere três coisas: o evento de teste nasce com Meet, a listagem traz os compromissos e o refresh funciona
   depois de 1h.

### Task 1: Conta Google por usuário (tabela, model, token)

**Arquivos:**
- Criar `db/migrate/20261018120001_create_ramon_google_agendas.rb` e editar `db/schema.rb` à mão.
- Criar `app/models/google_agenda_conta.rb` e `app/services/ramon/google_agenda/token.rb`.
- Testes: `spec/models/google_agenda_conta_spec.rb`, `spec/services/ramon/google_agenda/token_spec.rb`.

**Interfaces:**
- Produz a tabela `ramon_google_agendas`:
  - `account_id` (FK cascade);
  - `user_id` (FK cascade, **único**);
  - `email` string;
  - `access_token` text;
  - `refresh_token` text;
  - `expira_em` datetime;
  - `status` string default `'conectada'` (`conectada` | `desconectada`);
  - `ultima_sincronizacao_em` datetime;
  - timestamps.
- Produz o model `GoogleAgendaConta` (`self.table_name = 'ramon_google_agendas'`):
  - `belongs_to :user`, `belongs_to :account`;
  - `encrypts :access_token, :refresh_token if Chatwoot.encryption_configured?`;
  - `scope :conectadas`;
  - `self.de(user) -> GoogleAgendaConta|nil` (só `conectada`).
- Produz `Ramon::GoogleAgenda::Token.valido(conta) -> String|nil`:
  - devolve o access token, renovando se faltar menos de 5 min;
  - a renovação usa `OAuth2::AccessToken.new(cliente, access, refresh_token:, expires_at:).refresh!`;
  - o `cliente` é o mesmo `OAuth2::Client` do `GoogleConcern#google_client`: extrair um método de classe reutilizável,
    ex. `Ramon::GoogleAgenda::Token.oauth_client`, lendo `GlobalConfigService`;
  - `invalid_grant` → `status: 'desconectada'` e `nil`;
  - erro de rede → levanta `Ramon::GoogleAgenda::Token::Transitorio`.

- [ ] **Passo 1: specs que falham (WebMock no token endpoint).**
  - Token válido devolve sem chamar a rede.
  - Faltando 4 min, renova e grava o novo `expira_em`.
  - `invalid_grant` marca `desconectada` e devolve `nil`.
  - Um usuário só tem uma conta (unicidade).
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(agenda): conta Google por usuário com token cifrado`.

### Task 2: OAuth por usuário (iniciar, callback, desconectar, status)

**Arquivos:**
- Criar `app/controllers/api/v1/accounts/ramon_google_agenda_controller.rb` e
  `app/controllers/ramon/google_agenda_callbacks_controller.rb`.
- Modificar `config/routes.rb`.
- Testes: `spec/requests/api/v1/accounts/ramon_google_agenda_spec.rb`, `spec/requests/ramon/google_agenda_callbacks_spec.rb`.

**Interfaces:**
- `POST /api/v1/accounts/:account_id/ramon_google_agenda/autorizacao` (qualquer agente da conta, para o
  `Current.user`) → `{ url: }`:
  - `scope: 'openid email https://www.googleapis.com/auth/calendar.events'`;
  - `access_type: 'offline'`, `prompt: 'consent'`;
  - `redirect_uri: "#{ENV['FRONTEND_URL']}/ramon/google_agenda/callback"`;
  - `state: Current.user.to_sgid(expires_in: 15.minutes, for: 'ramon_google_agenda').to_s + ":" + account_id`.
- `GET /ramon/google_agenda/callback?code&state`:
  - valida o sgid (`for: 'ramon_google_agenda'`) e confirma que o user pertence à conta;
  - troca o code, grava ou atualiza a `GoogleAgendaConta` (email vem do `id_token`, decodificado como o fork já faz) com
    status `conectada`;
  - redireciona para `/app/accounts/:account_id/ramon/agenda?google=ok`;
  - em erro, redireciona para `…?google=erro`, sem stacktrace na tela.
- `GET /api/v1/accounts/:account_id/ramon_google_agenda` → `{ conectada:, email:, status: }` do `Current.user`.
- `DELETE /api/v1/accounts/:account_id/ramon_google_agenda` → apaga a conta do usuário. A revogação no Google é
  best-effort: `POST https://oauth2.googleapis.com/revoke`.

- [ ] **Passo 1: specs que falham.**
  - Agente comum recebe a URL com o escopo de agenda.
  - State de outro usuário ou expirado → redireciona com `google=erro` e não grava.
  - Callback feliz grava a conta com tokens.
  - DELETE apaga.
  - Status 200 com `conectada: false` quando não há conta.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(agenda): conectar o Google por usuário`.

### Task 3: Cliente da Calendar API

**Arquivos:**
- Criar `lib/ramon/google_agenda/cliente.rb`, no padrão HTTParty de `lib/ramon/zapsign_client.rb`.
- Teste: `spec/lib/ramon/google_agenda/cliente_spec.rb`.

**Interfaces:**
- `Ramon::GoogleAgenda::Cliente.new(conta)`. Todos os métodos pegam o token via `Token.valido`. Token `nil` → levanta
  `Ramon::GoogleAgenda::Cliente::SemConexao`.
- `#eventos(de:, ate:) -> Array<Hash>`:
  - formato de cada item: `{ id:, inicio: Time, fim: Time, titulo:, cancelado: Boolean, hub_task_id: Integer|nil, atualizado_em: Time }`;
  - chama `events.list` em `calendars/primary/events` com `singleEvents=true`, `orderBy=startTime`, `timeMin`,
    `timeMax`, `showDeleted=true`;
  - `hub_task_id` vem de `extendedProperties.private.hub_task_id`;
  - evento de dia inteiro conta como ocupado no dia todo.
- `#criar(inicio:, fim:, titulo:, descricao:, meet:, convidado_email: nil, hub_task_id:) -> { id:, meet_url: }`:
  - `conferenceDataVersion=1`; com `meet: true`, manda `conferenceData.createRequest` com `requestId` = `"hub-#{hub_task_id}"`;
  - `sendUpdates=all` se houver convidado, senão `none`.
- `#atualizar(id, inicio:, fim:) -> true`: `PATCH`, `sendUpdates=all`.
- `#cancelar(id) -> true`: `DELETE`, `sendUpdates=all`; 404/410 contam como sucesso.
- Erros: 401 → uma renovação e nova tentativa; 429/5xx/rede → `Transitorio`; outros → `Erro`.

- [ ] **Passo 1: specs que falham (WebMock).**
  - `eventos` mapeia os campos e o `hub_task_id`.
  - `criar` com Meet manda `conferenceData` e devolve `meet_url` de `hangoutLink`.
  - `criar` sem convidado usa `sendUpdates=none`.
  - `cancelar` com 410 → `true`.
  - 503 → `Transitorio`.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(agenda): cliente da Google Calendar`. Abrir o PR A, aguardar CI verde, mergear e fazer o deploy
  (migração na mão: `compose run --rm --no-deps chatwoot-web bundle exec rails db:migrate`). Doc de entrega da fase
  com a Task 0.

---

## Fase B — reunião no Google e disponibilidade (PR 2)

### Task 4: Disponibilidade (função pura) e feriados

**Arquivos:**
- Criar `app/services/ramon/agenda/disponibilidade.rb` e `app/services/ramon/agenda/feriados.rb`.
- Teste: `spec/services/ramon/agenda/disponibilidade_spec.rb`.

**Interfaces:**
- `Ramon::Agenda::Feriados.feriado?(date) -> Boolean`:
  - `NACIONAIS` fixos: 01/01, 21/04, 01/05, 07/09, 12/10, 02/11, 15/11, 20/11, 25/12;
  - `MOVEIS`: 2026-02-16, 2026-02-17, 2026-04-03, 2026-06-04, 2027-02-08, 2027-02-09, 2027-03-26, 2027-05-27;
  - `MUNICIPAIS = []` com o comentário `# ponytail: Tubarão/SC — Eduardo informa as datas; ano novo = acrescentar móveis`.
- `Ramon::Agenda::Disponibilidade.new(user:, account:, agora: Time.current)`:
  - `#ocupados(de:, ate:) -> Array<Range>` junta duas fontes, cada intervalo expandido de 15 min de folga:
    - reuniões abertas do hub do usuário (`LeadTask meeting` com `agenda_user_id = user.id`, ver Task 5), de
      `due_at` a `due_at + 30.min`;
    - eventos do Google (`Cliente#eventos`), se a conta estiver conectada. `SemConexao` ou `Transitorio` → só o hub.
  - `#livres(qtd: 3) -> Array<Time>`, sobre a grade de 30 em 30 min, alinhada em :00 e :30:
    - candidatos dentro das JANELAS dos próximos 5 dias úteis sem feriado, com `inicio >= agora + 2h` e
      `inicio + 30.min <= fim da janela`;
    - descarta quem cruza um ocupado;
    - escolhe os mais cedo com **no máximo um por meio-período** (manhã ou tarde de cada dia), até `qtd`.
  - `#livre?(inicio) -> Boolean`: mesma regra para um horário específico. É a reconferência na hora de marcar.
  - `self.texto(horarios) -> String`: `"quinta, 20/08 às 14:00; sexta, 21/08 às 9:00 ou 10:30"`, usando
    `Ramon::ReuniaoAgendamento.quando`.

- [ ] **Passo 1: specs que falham (Google stubado no `Cliente`; `travel_to` numa quinta às 9h).**
  - Agenda vazia → 3 horários, o primeiro ≥ 11h de hoje, um por meio-período.
  - Reunião do hub às 14h → 13h30–15h15 indisponível.
  - Evento do Google 15h–16h → 14h45–16h15 indisponível.
  - Sábado e feriado pulados.
  - Sem conexão → só o hub, sem erro.
  - `livre?` falso dentro de um ocupado.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(agenda): horários livres do Closer`.

### Task 5: Reunião vai para o Google (todos os caminhos) e conferência na marcação

**Arquivos:**
- Criar `db/migrate/20261018120002_add_agenda_to_lead_tasks.rb`:
  - `agenda_user_id` (FK users, nullify);
  - `google_event_id` string;
  - `meet_url` string;
  - `formato` string default `'video'`.
- Editar `db/schema.rb`.
- Modificar `app/models/lead_task.rb`.
- Criar `app/jobs/ramon/google_agenda_push_job.rb`.
- Modificar `app/controllers/api/v1/accounts/lead_reunioes_agendadas_controller.rb` (create/update: 409 `HORARIO_OCUPADO`),
  `app/services/ramon/funil_observador/aplicar.rb` (`marcar_reuniao` pula se ocupado) e
  `app/models/copilot_suggestion.rb#agendar_reuniao` (recusa se ocupado).
- Testes: `spec/models/lead_task_spec.rb`, `spec/jobs/ramon/google_agenda_push_job_spec.rb` e os specs dos três pontos.

**Interfaces:**
- **`LeadTask`:**
  - `FORMATOS = %w[video whatsapp]`, `DURACAO = 30.minutes`;
  - `before_create` (só meeting): `agenda_user_id ||= lead.closer_id || Ramon::Papeis.proximo(account, 'closer')&.id`;
  - `after_create_commit`, `after_update_commit` (se mudou `due_at` ou `formato`) e `after_destroy_commit` (só meeting)
    enfileiram `Ramon::GoogleAgendaPushJob.perform_later(acao, dados)`, com `acao` em `criar`, `atualizar` ou
    `cancelar`;
  - `dados` leva `task_id`, e no cancelar também `google_event_id` e `agenda_user_id`, porque a linha já não existe.
- **`Ramon::GoogleAgendaPushJob#perform(acao, dados)`:**
  - acha a `GoogleAgendaConta.de(agenda_user)`; sem conta → sai;
  - **criar:**
    - título = texto aprovado do convite;
    - descrição = texto aprovado com `{primeiro_nome}` (do lead) e `{nome_do_closer}` (`agenda_user.name`);
    - `convidado_email` = `lead.contact.email.presence`;
    - `meet: formato == 'video'`;
    - grava `google_event_id` e `meet_url` com `update_columns`, que não dispara de novo.
  - **atualizar:** `Cliente#atualizar` com `due_at..due_at+30min`. A troca de formato vai junto:
    - de vídeo para WhatsApp: o evento fica, a descrição ganha "Ligação pelo WhatsApp" e o hub limpa o `meet_url`;
    - de WhatsApp para vídeo: o PATCH manda `conferenceData.createRequest` e grava o `meet_url`.
    - `Cliente#atualizar` ganha os kwargs opcionais `meet: nil` e `descricao: nil`.
  - **Formato na marcação:** `lead_reunioes_agendadas_controller` aceita `formato` (`video` | `whatsapp`) no create e no
    update, e o formulário "+ Tarefa → Reunião" (`LeadPanelBody.vue:930-1000`) e o "Remarcar" (`LeadNextAction.vue`)
    ganham um seletor Vídeo/WhatsApp (padrão Vídeo). `Ramon::ReuniaoAgendamento.call`/`remarcar` aceitam o kwarg
    `formato: 'video'` e o repassam à tarefa.
  - **cancelar:** `Cliente#cancelar`.
  - `retry_on Transitorio` com 3 tentativas; outros erros → log de classe + ids e `ChatwootExceptionTracker`, sem
    re-raise.
- **Conferência:** `Ramon::Agenda::Disponibilidade.new(user: <dono>, account:).livre?(inicio)` antes de
  `ReuniaoAgendamento.call`/`remarcar`, nos três pontos:
  - painel: 409 `HORARIO_OCUPADO` com `message`, salvo `force: true`;
  - observador: pula e anota no card via a ação `marcar_reuniao` não registrada;
  - sugestão do Cockpit: `recusar('Esse horário ficou ocupado — escolha outro')`.

- [ ] **Passo 1: specs que falham.**
  - Meeting criada → job `criar` enfileirado.
  - `due_at` mudou → `atualizar`.
  - `destroy` → `cancelar` com `google_event_id` capturado.
  - Follow-up não enfileira.
  - Job sem conta → nada.
  - Job `criar` com convidado manda o título e a descrição aprovados, com nomes preenchidos (WebMock com corpo).
  - Painel com horário ocupado → 409, e com `force` → 201.
  - Reunião vinda do Cal.com também enfileira `criar` (ponto de revisão 5).
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(agenda): reunião do hub nasce no Google do Closer`.

### Task 6: Google → hub (mudanças feitas no Google)

**Arquivos:**
- Criar `app/jobs/ramon/google_agenda_pull_job.rb`.
- Modificar `config/schedule.yml` (`ramon_google_agenda_pull_job`, cron `'*/5 * * * *'`, `queue: scheduled_jobs`).
- Teste: `spec/jobs/ramon/google_agenda_pull_job_spec.rb`.

**Interfaces:**
- Para cada `GoogleAgendaConta.conectadas`, lê `Cliente#eventos(de: 1.day.ago, ate: 30.days.from_now)` e, para os itens
  com `hub_task_id`, acha a `LeadTask` aberta. Os casos:
  - **cancelado no Google e tarefa aberta** → `Ramon::ReuniaoAgendamento.cancelar(task:, user: nil)`;
  - **início diferente de `task.due_at`** (tolerância de 60 s) → `Ramon::ReuniaoAgendamento.remarcar(task:, starts_at: inicio)`;
  - **tarefa não existe** → ignora.
- Evento sem `hub_task_id` é compromisso pessoal: não faz nada aqui, ele só ocupa o horário.
- Atualiza `ultima_sincronizacao_em`. Rescue por conta (classe + ids, tracker).
- **Resumo das 8h** (`Ramon::DailyDigestService#yesterday_stats`, chave nova `agenda_sem_google`): lista os membros do
  comercial (times `sdr`/`closer`) sem `GoogleAgendaConta` conectada ou com status `desconectada`. Uma linha
  "Sem Google conectado: <nomes>" no e-mail, que some quando a lista está vazia.

- [ ] **Passo 1: specs que falham (Cliente stubado).**
  - Evento movido → `remarcar` 1x.
  - Evento igual ao hub → nada (ponto de revisão 2).
  - Cancelado → `cancelar`.
  - Hub já cancelou (tarefa sumiu) → nada.
  - Conta com erro não impede a próxima.
  - Digest lista o Closer sem conta e some quando todos conectaram.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(agenda): mudanças no Google voltam para o hub`. Abrir o PR B, CI, merge, deploy (migração).

---

## Fase C — ofertas, telas e confirmação (PR 3)

### Task 7: IA oferece horários e marca conforme o modo

**Arquivos:**
- Criar `enterprise/lib/captain/tools/horarios_livres_tool.rb`.
- Modificar `enterprise/lib/captain/tools/agendar_reuniao_tool.rb` e `config/agents/tools.yml` (registrar
  `horarios_livres`, nível consulta, sistema `agenda`).
- Modificar `app/javascript/dashboard/routes/dashboard/ramon/helpers/ferramentas.js` (sistema `agenda`).
- Testes: `spec/enterprise/lib/captain/tools/horarios_livres_tool_spec.rb`,
  `spec/enterprise/lib/captain/tools/agendar_reuniao_tool_spec.rb`.

**Interfaces:**
- **`horarios_livres`:**
  - fixa o Closer no lead se faltar (`Ramon::Papeis.atribuir_closer!`);
  - devolve `"Horários livres com <nome do closer>: <Disponibilidade.texto(livres)>. Ofereça estes ao cliente e espere ele escolher."`;
  - sem horário → `"Sem horário livre nos próximos 5 dias úteis — passe para a equipe."`.
- **`agendar_reuniao`:**
  - com `Ramon::CopilotoModo.direto?(lead.copiloto_modo)`: confere `livre?` e chama `ReuniaoAgendamento.call(lead:, starts_at:, title:)`.
    O resultado é `"Reunião marcada para <quando>."`, ou `"Esse horário acabou de ser ocupado — ofereça outro."`;
  - nos outros modos: igual a hoje (sugestão no Cockpit).
- **Texto do assistente:** a mudança em `db/seeds/ramon/inteligencia/assistentes.yml` (trocar o bloco que usa
  `link_agendamento` por `horarios_livres` + `agendar_reuniao`) fica **pronta num commit à parte**. Texto **APROVADO 16/10**: o `seed[2]` roda no deploy
  da Fase C. Trecho:
  > Quando o lead quiser avançar, ofereça a conversa com o advogado. Use [Horários livres](tool://horarios_livres) e ofereça
  > os horários exatamente como vierem. Quando ele escolher, use [Agendar reunião](tool://agendar_reuniao) com o horário
  > escolhido. Nunca invente horário.

- [ ] **Passo 1: specs que falham.**
  - Tool devolve o texto com 3 horários (Disponibilidade stubada).
  - Sem horários → texto de passar à equipe.
  - `agendar_reuniao` em `piloto_total` com horário livre → `ReuniaoAgendamento.call`.
  - Mesmo modo com horário ocupado → texto de ocupado e nada marcado.
  - Modo `rascunho` → sugestão (comportamento atual).
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: `rubocop-vps` + eslint.**
- [ ] **Passo 4: commits** `feat(agenda): IA oferece horários livres e marca no modo direto` e, separado,
  `chore(agenda): texto do assistente com horários livres`.

### Task 8: "Sugerir horários" na caixa de resposta

**Arquivos:**
- Modificar `config/routes.rb` (member em leads: `get :horarios_livres`) e `app/controllers/api/v1/accounts/leads_controller.rb`
  (ou um controller pequeno no padrão dos membros de lead).
- Modificar `app/javascript/dashboard/api/leads.js` (`horariosLivres(leadId)`) e
  `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` (botão depois do de artigo, ~389-397,
  só quando a conversa tem lead).
- Criar `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/BotaoSugerirHorarios.vue`.
- i18n `RAMON.AGENDA.SUGERIR_HORARIOS` e `RAMON.AGENDA.SEM_HORARIOS`.
- Teste: request spec do endpoint.

**Interfaces:**
- `GET /api/v1/accounts/:account_id/leads/:id/horarios_livres` → `{ horarios: [iso8601…], texto: }`. Usa a agenda do
  Closer do lead e o fixa se faltar.
- O botão (`NextButton` slate faded sm, ícone `i-lucide-calendar-clock`) chama a API e faz
  `emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, texto)` com
  `"Posso te atender em: <texto>. Qual fica melhor pra você?"`. É um rascunho no editor: a pessoa edita e envia.
- Sem horários → `useAlert(SEM_HORARIOS)`.

- [ ] **Passo 1: spec que falha.** Endpoint devolve horários e texto, e lead de outra conta → 404.
- [ ] **Passo 2: implementar o back e o front** (o modelo é `LeadSugerirResposta.vue:29`).
- [ ] **Passo 3: `rubocop-vps` + eslint.**
- [ ] **Passo 4: commit** `feat(agenda): sugerir horários na caixa de resposta`.

### Task 9: Tela Agenda — pessoas, cores e compromissos do Google

**Arquivos:**
- Criar o endpoint `GET /api/v1/accounts/:account_id/ramon_agenda/google?from&to&user_ids[]` →
  `{ payload: [{ user_id, inicio, fim, titulo }] }`:
  - só membros do comercial;
  - `Rails.cache` por user + período, 2 min;
  - eventos com `hub_task_id` ficam de fora, porque já aparecem como reunião do hub.
- Modificar o jbuilder de `lead_tasks` (`_lead_task.json.jbuilder`: `agenda_user_id`, `agenda_user_name`, `meet_url`,
  `formato`) e `app/javascript/dashboard/routes/dashboard/ramon/pages/Agenda.vue`.
- i18n em `RAMON.AGENDA`: `PESSOAS`, `TODAS_PESSOAS`, `GOOGLE`, `CONECTAR_GOOGLE`, `GOOGLE_CONECTADO`, `GOOGLE_ERRO`,
  `MEET`, `WHATSAPP`.
- Teste: request spec do endpoint (Cliente stubado).

**Interfaces / comportamento:**
- **Filtro "Pessoas":** multi-seleção dos membros do comercial (agentes da conta filtrados pelos ids que um endpoint de
  status devolve). Ele substitui "Minhas/Time", e "Minhas" vira o atalho que seleciona só o usuário atual. A escolha fica
  em localStorage `ramon_agenda_pessoas`.
- **Cor por pessoa:** `TOM` por índice estável (`ids ordenados`).
- **Itens:** reunião do hub com chip da pessoa; Meet com link e "Ligação WhatsApp" quando `formato == 'whatsapp'`;
  compromisso do Google como item cinza "Google · <título>" com o horário.
- **Ordem:** dentro do dia, por horário. Mantém as visões dia, semana e mês já existentes (sem eixo de horas — decisão do
  plano: a lista por horário basta e mexe menos).
- **Cabeçalho:** "Conectar meu Google" se o usuário não estiver conectado (Task 2). Na volta, `?google=ok|erro` vira
  `useAlert`.

- [ ] **Passo 1: spec que falha.** O endpoint filtra por pessoa, exclui eventos do hub e devolve 403 para user fora do
  comercial.
- [ ] **Passo 2: implementar o back e o front.**
- [ ] **Passo 3: `rubocop-vps` + eslint.**
- [ ] **Passo 4: commit** `feat(agenda): agenda do comercial com pessoas, cores e Google`.

### Task 10: Conectar o Google no perfil

**Arquivos:**
- Modificar `app/javascript/dashboard/routes/dashboard/settings/profile/Index.vue` (um `SectionLayout` novo).
- Criar `app/javascript/dashboard/routes/dashboard/ramon/components/agenda/ConexaoGoogle.vue` (reusado no cabeçalho da
  Agenda) e `app/javascript/dashboard/api/ramonGoogleAgenda.js` (`status`, `autorizar`, `desconectar`).
- i18n `RAMON.AGENDA.GOOGLE_CARD_TITULO`, `GOOGLE_CARD_DESCRICAO` e `DESCONECTAR`.

**Comportamento:**
- Mostra o status (e-mail conectado ou "não conectado").
- O botão "Conectar" faz POST de autorização e `window.location.href = url`.
- "Desconectar" pede confirmação.
- `desconectada` (token revogado) aparece como "reconectar".

- [ ] **Passo 1: implementar** (sem vitest local; seguir o padrão de `OAuthChannel.vue:45-58`).
- [ ] **Passo 2: eslint.**
- [ ] **Passo 3: commit** `feat(agenda): conectar o Google no perfil`.

### Task 11: Confirmação com Meet e "salvar na minha agenda"

**Arquivos:**
- Modificar `app/services/ramon/reuniao_agendamento.rb#confirmation_draft` (e o texto equivalente do fluxo
  `reuniao_marcada` só se ele copiar o código — conferir).
- Criar `app/controllers/public/api/v1/agenda_ics_controller.rb` (rota `get 'agenda/:token.ics'`) e
  `app/services/ramon/agenda/convite.rb`.
- Teste: `spec/services/ramon/agenda/convite_spec.rb` e request spec do .ics.

**Interfaces:**
- `Ramon::Agenda::Convite.new(task)`:
  - `#link_google -> String`: `https://calendar.google.com/calendar/render?action=TEMPLATE&text=…&dates=YYYYMMDDTHHMMSSZ/…&details=…`
    com o título aprovado e o Meet;
  - `#link_ics -> String`: `"#{FRONTEND_URL}/public/api/v1/agenda/#{task.signed_id(purpose: :ics, expires_in: 60.days)}.ics"`;
  - `#ics -> String`: VCALENDAR/VEVENT com UID `hub-<id>`, DTSTART/DTEND em UTC, SUMMARY aprovado e o Meet na
    DESCRIPTION/LOCATION.
- **Rascunho de confirmação (APROVADO 16/10):**

```
RASCUNHO (revisar antes de enviar) — confirmação de reunião:
"Oi {primeiro_nome}! Nossa conversa está confirmada pra {quando}. {linha_formato} Pra salvar na sua agenda: {link_google} Se não puder comparecer, me avise com antecedência que a gente remarca sem problema."
```

  - `{linha_formato}` = `"É por vídeo, neste link: {meet_url}."` ou `"Eu te ligo no WhatsApp nesse horário."`.
- **Envio automático pela IA nos modos piloto:** só com `RAMON_AGENDA_CONFIRMACAO=on`, que o Eduardo liga (texto já
  aprovado). Pelo mesmo caminho de envio que o assistente usa hoje; se não houver um caminho simples, fica fora
  deste plano e vai anotado.
- O `meet_url` chega pelo job (Task 5). O rascunho é criado **depois** que o job grava o Meet: mover a criação do
  rascunho para o fim do `GoogleAgendaPushJob#criar` quando houver conta Google; sem conta, continua como hoje.

- [ ] **Passo 1: specs que falham.**
  - `link_google` com as datas UTC certas.
  - `.ics` válido (BEGIN:VCALENDAR … END:VCALENDAR, DTSTART certo).
  - Token inválido → 404.
  - Rascunho contém o Meet e o link.
- [ ] **Passo 2: implementar.**
- [ ] **Passo 3: `rubocop-vps`.**
- [ ] **Passo 4: commit** `feat(agenda): confirmação com Meet e salvar na agenda`. Abrir o PR C, CI, merge e deploy.

---

## Fase D — aposentar o Cal.com (PR 4)

### Task 12: Tirar o Cal.com

**Pré-condição (controller):** não pode haver reunião futura marcada pelo Cal.com. Conferir na VPS (pedir ao Eduardo se
o classificador barrar):

```
LeadTask.open_tasks.where(kind: 'meeting').where('title LIKE ?', 'Reunião Cal.com%').where('due_at > ?', Time.current).count == 0
```

Se houver alguma, adiar esta fase para depois da última data.

**Arquivos:**
- **Remover:**
  - `app/controllers/public/api/v1/calcom_webhooks_controller.rb`, a rota (`routes.rb:762`) e a regra do rack_attack
    (`config/initializers/rack_attack.rb:204-206`);
  - `enterprise/lib/captain/tools/link_agendamento_tool.rb` e a entrada em `config/agents/tools.yml:163`;
  - os specs `spec/requests/public/api/v1/calcom_webhooks_spec.rb` e
    `spec/enterprise/lib/captain/tools/link_agendamento_tool_spec.rb`;
  - `RAMON_CALCOM_URL` e `CALCOM_WEBHOOK_SECRET` do `.env.example`.
- **Ajustar:**
  - os textos que citam o Cal.com: `db/seeds/ramon/fluxos/migrados/reuniao_marcada.json:3`, `reuniao_cancelada.json:3`,
    `sistema/lembretes_reuniao.json`;
  - comentários;
  - o front: `LeadNextAction.vue:112,200,419-424` (`isCalcom` sai, porque toda reunião é do hub), i18n
    `CALCOM_REMARCAR/CANCELAR`, `nextAction.js:10`, `Esteira.vue:185`, `LeadPanelBody.vue:363`, `api/leads.js:157`
    (conferir cada um);
  - `ferramentas.js` (sistema `calcom` sai).
- **Manter:** `Ramon::ReuniaoAgendamento::CALCOM_PREFIX` e `titulo_de`, só para exibir reuniões antigas. Comentário:
  `# ponytail: legado do Cal.com, apagar quando não houver mais tarefas com o prefixo`.

- [ ] **Passo 1: remover e ajustar.** Rodar `grep -ri calcom app enterprise lib config db/seeds spec`; o esperado é só o
  legado mantido.
- [ ] **Passo 2: `rubocop-vps` + eslint.** Os specs dos fluxos e sistema continuam verdes; se a contagem de desenhos
  mudar, ajustar.
- [ ] **Passo 3: commit** `chore(agenda): aposenta o Cal.com`. Abrir o PR D, CI, merge e deploy.
- [ ] **Passo 4 (Eduardo):** desativar o link público no painel do Cal.com e o webhook lá.

---

## Entrega

- Doc `comercial/docs/2026-10-XX-agenda-no-hub-entrega.md`, com:
  - Task 0 (Google Cloud + chaves);
  - PRs, SHAs e migrações;
  - smoke em bloco:
    - A: conectar Google;
    - B: marcar pelo painel e conferir no Google (com Meet e convite quando houver e-mail);
    - C: mover e apagar no Google e conferir no hub;
    - D: IA oferecendo horários na caixa de teste;
    - E: "Sugerir horários";
    - F: Agenda com filtro por pessoa;
    - G: rascunho de confirmação com Meet e link;
  - gates abertos: feriados de Tubarão (Task 4, por ora só os nacionais, decisão do Eduardo em 16/10) e
    `RAMON_AGENDA_CONFIRMACAO` (ligar = Eduardo).

# F5 — Correções da revisão integrada + IA grava os dados do contrato · Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** fechar tudo o que a revisão integrada do roteiro da tese (F0–F4) encontrou: o fail-safe da spec §5 (ferramenta falhou → a resposta vira rascunho), o handoff do roteiro por sinal e não por texto, o reabrir que respeita o limite do modo, a troca de tese que zera o roteiro na hora, o contrato que não saiu contado à parte no Metabase, o modelo de contrato na tela da tese, o Testar sem tese e com modo simulado, o aviso ao admin no roteiro sem saída, uma fonte única para desfechos e modos (front e back), e a ferramenta nova `registrar_dados_contrato`, para a IA guardar no lead os dados que o ZapSign usa.

**Architecture:** primeiro as refatorações sem mudança de comportamento (constantes num lugar só, leituras do lead em `LeadRoteiro`, avisos em `Ramon::AvisoDaIa`, troca e restauração do modo em `Ramon::CopilotoModo`, Teste × real num caminho só). Depois as correções, cada uma com o próprio spec. A regra fica em `app/` (o CI testa) e o enterprise fica fino: as tools gravam sinais no `tool_context.state` (o mesmo hash que o runner devolve no `result.context`, porque o `deep_copy_context` do ai-agents 0.10 faz cópia rasa), o `AgentRunnerService` os lê e o `ResponseBuilderJob` decide pelo `Ramon::CopilotoModo.envia?(…, falhou:)`. A ferramenta nova chama `Ramon::DadosContrato`, que grava no contato nos mesmos campos que o painel e o ZapSign leem. Os textos que falam com o cliente (skill "Fechar contrato" e a diretriz do CPF) vão num PR draft separado, com doc de aprovado.

**Tech Stack:** Rails 7.1 (fork Chatwoot 4.15.1), RSpec, scenic (views), Vue 3 `<script setup>` + Tailwind, Vitest, Captain tools (ai-agents 0.10 / RubyLLM), Python 3 (API do Metabase).

**Spec:** `docs/superpowers/specs/2026-10-13-roteiro-da-tese-design.md` (§3.2, §3.4, §3.7, §3.8.5, §3.9, §5). Planos anteriores cujo código esta fatia corrige: F1 `docs/superpowers/plans/2026-10-13-roteiro-f1-motor.md`, F2 `…-roteiro-f2-telas.md`, F3 `…-roteiro-f3-tese-e-modos.md`, F4 `…/2026-10-14-roteiro-f4-conteudo-e-metricas.md`. Diff inteiro da feature: `git diff 063d72b...HEAD`.

## Decisões que tomei sem perguntar (revisar)

1. **Achados conferidos no código: todos procedem.** O 5 só afeta quem lê o atributo cru (`CopilotoLimite.nivel` e `bi_roteiro`), porque o motor já recalculava o estado na leitura. O 8 era parcial: os admins só eram avisados quando o lead não tinha responsável. *Custo se errado:* nenhum, só o diagnóstico.
2. **O fail-safe vale para qualquer ferramenta, não só as do roteiro.** O ponto é um só (`BasePublicTool#execute`). *Custo se errado:* em modo piloto, um turno com FAQ ou agenda instável vira rascunho (mais trabalho manual). A Task 11 mede os erros dos últimos 14 dias antes do deploy.
3. **Com ferramenta que falhou, a mensagem fixa de handoff ainda sai.** Ela é logística, a mesma regra do `piloto_limitado`. Texto livre da IA nunca sai direto. *Custo:* nenhum identificado.
4. **Os sinais vão no `tool_context.state`.** São `:ramon_ferramenta_falhou` e `:ramon_roteiro_handoff`. O runner lê o hash, e nada depende do texto da tool. *Custo se errado:* se uma versão nova do gem fizer cópia funda do state, os sinais somem. A prova em produção (Task 11) pega isso.
5. **O rascunho por falha usa o prefixo de sempre, `RASCUNHO (revisar antes de enviar):`.** As views `bi_ia_*` contam por esse prefixo. O motivo fica na tela Execuções (status erro). *Custo:* quem revisa não vê o motivo no próprio rascunho.
6. **Contrato que não saiu vira o limite próprio `contrato_falhou`.** Ele encerra o modo do mesmo jeito, com sino. `contrato` fica só para o contrato que de fato saiu. A `bi_roteiro` v02 ganha `limite_motivo`. *Custo:* consulta antiga que contava `contrato` deixa de contar as falhas, e é de propósito.
7. **O reabrir faz quatro coisas:** devolve o modo de antes do desfecho, desfaz o carimbo `qualificacao` (só quando o desfecho reaberto era `qualificado`: volta o modo do carimbo e apaga o carimbo), tira a etiqueta e, no fim, confere o limite de novo. *Custo:* um lead que já passou do limite recebe um 2º sino, porque o limite fecha de novo na hora.
8. **Reabrir um `humano` devolve a conversa ao robô (pendente).** Só vale se a conversa está aberta e o modo restaurado não é `manual`. *Custo:* se alguém da equipe estava no meio da conversa, a IA volta a responder. Reabrir é ação explícita no painel ou no Kanban.
9. **Trocar a tese zera o roteiro gravado na hora** (`before_save` no Lead): os comuns ficam, o resto sai, e o `passo` é recalculado. O modo da conversa não muda. *Custo:* se a tese for trocada depois de um "equipe", a IA não volta sozinha. Para isso é preciso reabrir ou trocar o modo.
10. **O modo efetivo no front segue a mesma ordem do backend:** atributo, depois o padrão da caixa (store `inboxes`), depois a env. A lista de modos fica num só módulo JS, e um spec Ruby a confere contra `Ramon::CopilotoModo::MODOS`. A tela Assistentes conta pelo padrão de cada caixa (`CopilotoModo.contar`) e mostra o padrão de cada uma. Não pus "modo efetivo" no payload da conversa, que tem vários caminhos (jbuilder e eventos). *Custo:* são duas implementações da mesma ordem, e o spec confere a lista, não a ordem.
11. **`restaurar` sem modo de antes tira o atributo** em vez de gravar `nil`. Com isso volta a valer o padrão da caixa ou da env.
12. **O aviso do roteiro sem saída vai ao responsável e também aos administradores.** Só vale para a saída `sem_saida` (nada casou ou o destino não existe). "Assunto sem tese" continua só com o responsável. *Custo:* um sino a mais para o Eduardo.
13. **O modelo de contrato na tela é um seletor com os modelos do ZapSign** (`GET /leads/zapsign_templates`, que já existe), mais "Sem modelo". Um valor salvo fora da lista aparece pelo id. Vazio vira `nil` (`normalizes`). *Custo:* com o ZapSign fora do ar, o seletor só mostra o valor atual e um aviso.
14. **O Testar passa a ter três escolhas:** "Sem roteiro" (como hoje), "Lead sem tese (passos comuns)" e as teses. O modo simulado é só "Rascunho" ou "Piloto total", porque os modos "até…" dependem de conversa. A tese que o "assunto" escolhe volta no teste e vale nas mensagens seguintes. O modo simulado é o atributo virtual `Lead#copiloto_modo_simulado`, que só o lead descartável usa.
15. **Teste e real seguem um caminho só:** `RamonBaseTool#no_roteiro` mais `Ramon::Roteiro::Teste.com_lead`. Saem `Teste.atual`, `Teste.registrar`, `Teste.rodar` e `Teste.painel`.
16. **`registrar_dados_contrato` é escrita interna direta**, de nível "interna", não sugestão. Grava aos poucos, o endereço soma às chaves que já existem e campo em branco não apaga nada. Nome de uma palavra e CPF inválido são recusados campo a campo. CPF que já é de outro contato não é gravado: sai sino ao responsável (sem o número) e a IA passa para humano. O painel continua com o próprio caminho de gravação, que substitui o hash inteiro, e os dois escrevem as mesmas chaves. *Custo:* são dois caminhos de gravação; no painel o campo em branco apaga, na IA não.
17. **No Testar (qualquer playground) a `registrar_dados_contrato` só simula,** mesmo com "Testar com o caso". O Testar nunca grava dado pessoal. *Custo:* a gravação de verdade só se prova pelo console (Task 11).
18. **O CPF fica mascarado (`***`) nos parâmetros da tela Execuções (`ToolRun`),** por causa da LGPD. O texto da tool não repete o CPF.
19. **Fonte única:** os desfechos ficam em `Ramon::Roteiro` (`QUALIFICADO`, `DESQUALIFICADO`, `HUMANO`, `DESFECHO_DA_ACAO`, `SEM_SAIDA`). Os níveis ficam em `Ramon::CopilotoLimite` (`QUALIFICACAO`, `REUNIAO`, `CONTRATO`, `CONTRATO_FALHOU`), e `CopilotoModo::LIMITES` usa esses nomes. As ações das saídas continuam em `RoteiroPasso::ACOES`.
20. **i18n em `en.json` E `pt_BR/ramon.json` (ruling do controlador, precedente F2/F3 — a tela do escritório é pt_BR).** Toda chave nova entra nos dois arquivos, com o texto em português no pt_BR. *Custo:* nenhum.

**Perguntas abertas:** nenhuma bloqueante. Gate em produção: o "aprovado" dos textos (Task 12) antes do merge do PR de textos e do `seed[2]`.

## Global Constraints

- Branch `feat/roteiro-f5-correcoes` no worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-roteiro`, criada de `origin/ramon` em `5edf2e5` (já em uso). PR com base `ramon`.
- **Ruby não roda local** (o Smart App Control bloqueia). Spec Ruby só se valida no **CI do PR**. Lint antes do push: `rubocop-vps <arquivos>` (Git Bash, cerca de 10 s). Limites: `Metrics/MethodLength` 19, `Metrics/AbcSize` 26, `Metrics/ClassLength` 175, linha 150, `RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50. Se um `Metrics/*` acusar, extrair método privado sem desligar o cop. O `rubocop-vps` não pega cops que leem o schema; esses o CI pega.
- **JS roda local:** `node_modules/.bin/vitest run --no-cache <caminhos>` e `pnpm eslint` (ou `node_modules/.bin/eslint <arquivos>`).
- **`spec/enterprise` não roda no CI.** O `run_foss_spec.yml` apaga `enterprise/` e `spec/enterprise/`. Toda regra nova fica em `app/` com spec em `spec/services`, `spec/models` ou `spec/requests`. As mudanças em `enterprise/` são finas, e a prova delas é o `rails runner` da Task 11.
- **Lições de spec:** em spec de service, usar a constante explícita (`Ramon::Roteiro`, `Ramon::CopilotoModo`…). Nunca `described_class` em exemplo novo ou mexido, e nunca `stub_const`: o embaralhamento de shards e o reload de código do CI quebraram os dois. Para ENV, usar `with_modified_env`. Comparar erro por `error.class.name`.
- **Migração nova:** `db/schema.rb` editado à mão, como na F4. Versão do topo = `2026_10_14_200001`. View pelo scenic: `db/views/bi_roteiro_v02.sql` mais `update_view :bi_roteiro, version: 2, revert_to_version: 1`.
- **i18n: chave nova em `en.json` E `pt_BR/ramon.json` (ou o pt_BR do arquivo de en tocado), como F2/F3.** Vue: `<script setup>`, só Tailwind, eventos em camelCase, nenhuma string solta no template.
- **Texto que fala com o cliente fica fora do PR de código.** Isso inclui instruções e skills em `db/seeds/ramon/inteligencia/assistentes.yml` e mensagens a leads. Vai em PR draft separado (`feat/roteiro-f5-textos`) com doc de aprovado em `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-14-roteiro-f5-textos.md`. É ativado só depois do "aprovado" do Eduardo: merge, deploy e `rails "ramon:inteligencia:seed[2]"`. É o mesmo padrão da F3 (PR #244).
- **Produção hoje:** conta 2; `RAMON_COPILOTO_MODO_DEFAULT=piloto_limitado`; nenhuma caixa com `ramon_copiloto_modo`; só a tese "Auxílio-acidente (B36)" (id 3) deve ganhar modelo do ZapSign, e nenhuma tese tem ainda. **O fail-safe (Task 4) vale em produção no deploy:** no `piloto_limitado`, um turno com ferramenta que falhou passa a virar rascunho.
- **Deploy:** `docker pull ghcr.io/doods-maker/ramon-hub:sha-<7>`, depois `docker tag … :v4.15.1-ramon`, depois `docker compose run --rm --no-deps chatwoot-web bundle exec rails db:migrate`, depois `docker compose up -d chatwoot-web chatwoot-worker` (em `/opt/intranet-ramon`). **Prova:** `cat f.rb | ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails runner "eval(STDIN.read)"'`, dentro de uma transação com `raise ActiveRecord::Rollback`. Merge e deploy são autônomos com o CI 100% verde.
- Python: `PYTHONUTF8=1` no console do Windows. A credencial do Metabase nunca entra no repo (o Eduardo roda pelo `!`).
- Commits: Conventional Commits, assunto sem citar Claude, terminando com o rodapé de atribuição da sessão que executar. Nunca `git add -A`: só os caminhos de cada task.

### Quem mexe em quê (conflitos — executar na ordem 1 → 12)

| Arquivo | Tasks |
|---|---|
| `app/services/ramon/roteiro.rb` | 1, 3, 5 |
| `app/services/ramon/roteiro/registro.rb` | 2, 3 |
| `app/services/ramon/roteiro/efeitos.rb` | 2, 5 |
| `app/services/ramon/copiloto_limite.rb` | 1, 2, 5, 6 |
| `app/services/ramon/copiloto_modo.rb` | 1, 2, 4, 7 |
| `app/services/ramon/contrato_automatico.rb` | 1, 6, 10 |
| `app/models/concerns/lead_roteiro.rb` (novo) | 1, 5, 9 |
| `app/services/ramon/roteiro/teste.rb` | 3, 9 |
| `enterprise/app/services/captain/assistant/agent_runner_service.rb` | 3, 4 |
| `enterprise/lib/captain/tools/base_public_tool.rb` | 4, 10 |
| `app/javascript/dashboard/i18n/locale/en/ramon.json` | 8, 9 |
| `spec/services/ramon/roteiro_spec.rb` | 2, 3, 4, 5 |
| `spec/services/ramon/copiloto_modo_spec.rb` | 2, 4, 7 |
| `spec/services/ramon/roteiro/teste_spec.rb` | 3, 9 |

Sem arquivo em comum com as outras (dá para fazer em paralelo depois da Task 2): as Tasks 7 (front do modo, que só acrescenta `contar` no `copiloto_modo.rb`) e 8 (modelo de contrato na tela).

## Review Focus

1. **Uma ferramenta falha no mesmo turno em que a IA passa para a equipe** → a mensagem fixa de handoff sai e nenhum texto livre da IA sai direto (Task 4, exemplo "handoff + falhou").
2. **Reabrir um caso "equipe" cujo modo de antes era `manual`** → a conversa continua aberta com o humano, sem voltar ao robô (Task 5, exemplo "modo de antes manual").
3. **A IA recebe um CPF que já é de outro contato** (o lead passou o de um parente) → não troca de dono nem sobrescreve, a equipe é avisada sem o número e a IA passa para humano (Task 10).
4. **O endereço chega em partes** (rua num turno, número no outro) **sobre um endereço já salvo pelo painel** (CEP) → nenhuma chave se perde e campo em branco não apaga (Task 10, 1º exemplo).
5. **No Testar, a pessoa troca a seleção enquanto a resposta não volta, ou o "assunto" de um lead sem tese escolhe a tese** → a resposta atrasada não grava estado, e as mensagens seguintes seguem na tese escolhida (Task 9).

---

### Task 1: Fonte única dos desfechos e limites + leituras do lead (`LeadRoteiro`)

**Files:**
- Modify: `app/services/ramon/roteiro.rb` (constantes)
- Modify: `app/services/ramon/copiloto_limite.rb` (constantes e leituras do lead)
- Modify: `app/services/ramon/copiloto_modo.rb` (`LIMITES` usa as constantes do limite)
- Modify: `app/services/ramon/contrato_automatico.rb` (sem `MODO`; usa o lead)
- Modify: `app/models/copilot_suggestion.rb:40`
- Modify: `app/models/lead.rb` (include e `reabrir_roteiro`)
- Create: `app/models/concerns/lead_roteiro.rb`
- Create: `spec/models/lead_roteiro_spec.rb`
- Modify: `spec/services/ramon/copiloto_limite_spec.rb` (1 exemplo)

**Interfaces:**
- Consumes: `Ramon::CopilotoModo.of(conversation)`.
- Produces:
  - `Ramon::Roteiro::QUALIFICADO`, `DESQUALIFICADO`, `HUMANO` (String); `Ramon::Roteiro::DESFECHO_DA_ACAO` (`{ 'concluir' => QUALIFICADO, 'desqualificar' => DESQUALIFICADO, 'humano' => HUMANO }`); `Ramon::Roteiro::SEM_SAIDA = 'sem_saida'`
  - `Ramon::CopilotoLimite::QUALIFICACAO`, `REUNIAO`, `CONTRATO`; `NIVEIS = [QUALIFICACAO, REUNIAO, CONTRATO]`
  - `Lead#copiloto_modo -> String | nil` (nil = sem conversa), `Lead#contrato_enviado? -> Boolean`, `Lead#desfecho_roteiro -> String | nil`, `Lead#nome_completo? -> Boolean`

- [ ] **Step 1: Spec do concern (falha)**

`spec/models/lead_roteiro_spec.rb`:

```ruby
require 'rails_helper'

# Leituras do roteiro e do modo da IA no lead (F5, revisão integrada item 13).
RSpec.describe LeadRoteiro do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:lead) { create(:lead, account: account, conversation: conversation) }

  it 'copiloto_modo: o modo efetivo da conversa (atributo → caixa → env); sem conversa, nil' do
    conversation.update!(custom_attributes: {})
    inbox.update!(ramon_copiloto_modo: 'piloto_ate_reuniao')
    expect(lead.reload.copiloto_modo).to eq('piloto_ate_reuniao')

    conversation.update!(custom_attributes: { 'copiloto_modo' => 'manual' })
    expect(lead.reload.copiloto_modo).to eq('manual')
    expect(create(:lead, account: account).copiloto_modo).to be_nil
  end

  it 'contrato_enviado? e desfecho_roteiro leem o estado gravado no lead' do
    expect([lead.contrato_enviado?, lead.desfecho_roteiro]).to eq([false, nil])

    lead.update!(custom_attributes: { 'zapsign' => { 'sign_url' => 'https://zap/x' }, 'roteiro' => { 'desfecho' => 'humano' } })
    expect([lead.reload.contrato_enviado?, lead.desfecho_roteiro]).to eq([true, 'humano'])
  end

  it 'nome_completo?: o nome do contato (senão o do lead) com 2 palavras ou mais' do
    lead.update!(name: 'Maria')
    expect(lead.nome_completo?).to be(false)

    lead.update!(contact: create(:contact, account: account, name: 'Maria Souza'))
    expect(lead.reload.nome_completo?).to be(true)
  end
end
```

Em `spec/services/ramon/copiloto_limite_spec.rb`, antes do último `end`:

```ruby
  it 'os níveis seguem a ordem dos modos "sozinha até…" (fonte única)' do
    expect(Ramon::CopilotoModo::LIMITES.values).to eq(Ramon::CopilotoLimite::NIVEIS)
  end
```

- [ ] **Step 2: Constantes do roteiro**

Em `app/services/ramon/roteiro.rb`, logo depois de `ASSUNTO = 'assunto'.freeze`:

```ruby
  # Desfechos do roteiro (spec §3.2) — fonte única: a ação da saída que encerra → o desfecho.
  QUALIFICADO = 'qualificado'.freeze
  DESQUALIFICADO = 'desqualificado'.freeze
  HUMANO = 'humano'.freeze
  DESFECHO_DA_ACAO = { 'concluir' => QUALIFICADO, 'desqualificar' => DESQUALIFICADO, 'humano' => HUMANO }.freeze
  # Saída que o motor monta quando nada casa ou o destino não existe (spec §5: equipe + aviso ao admin).
  SEM_SAIDA = 'sem_saida'.freeze
```

- [ ] **Step 3: O concern `LeadRoteiro`**

`app/models/concerns/lead_roteiro.rb`:

```ruby
# Leituras do roteiro da tese e do modo da IA no lead — fonte única para Ramon::CopilotoLimite,
# Ramon::ContratoAutomatico e Ramon::Roteiro::Efeitos (F5, revisão integrada item 13).
module LeadRoteiro
  extend ActiveSupport::Concern

  # Modo efetivo da IA na conversa do lead (Ramon::CopilotoModo.of: atributo → caixa → env); nil = lead sem conversa.
  def copiloto_modo
    conversation && Ramon::CopilotoModo.of(conversation)
  end

  def contrato_enviado?
    custom_attributes&.dig('zapsign', 'sign_url').present?
  end

  def desfecho_roteiro
    custom_attributes&.dig('roteiro', 'desfecho')
  end

  # Nome do signatário do contrato: o do contato, senão o do lead — 2 palavras ou mais (Ramon::ContratoAutomatico).
  def nome_completo?
    (contact&.name.presence || name).to_s.split.size >= 2
  end
end
```

Em `app/models/lead.rb`, trocar

```ruby
  include LeadCasoCalculo
```

por

```ruby
  include LeadCasoCalculo
  include LeadRoteiro
```

e, no `reabrir_roteiro`, trocar `Ramon::Roteiro.reabrir(self, se: 'desqualificado')` por `Ramon::Roteiro.reabrir(self, se: Ramon::Roteiro::DESQUALIFICADO)`.

Em `app/models/copilot_suggestion.rb`, no `dismiss!`, trocar `Ramon::Roteiro.reabrir(lead, se: 'desqualificado')` por `Ramon::Roteiro.reabrir(lead, se: Ramon::Roteiro::DESQUALIFICADO)`.

- [ ] **Step 4: `CopilotoLimite` e `CopilotoModo` com as constantes e as leituras do lead**

Em `app/services/ramon/copiloto_limite.rb`, trocar

```ruby
  NIVEIS = %w[qualificacao reuniao contrato].freeze
  NOMES = { 'qualificacao' => 'lead qualificado', 'reuniao' => 'reunião marcada', 'contrato' => 'contrato enviado' }.freeze
```

por

```ruby
  QUALIFICACAO = 'qualificacao'.freeze
  REUNIAO = 'reuniao'.freeze
  CONTRATO = 'contrato'.freeze
  NIVEIS = [QUALIFICACAO, REUNIAO, CONTRATO].freeze
  NOMES = { QUALIFICACAO => 'lead qualificado', REUNIAO => 'reunião marcada', CONTRATO => 'contrato enviado' }.freeze
```

Trocar os métodos `verificar`, `encerrar` e `nivel` inteiros por:

```ruby
  # @return [String, nil] o limite encerrado agora
  def verificar(lead)
    limite = Ramon::CopilotoModo::LIMITES[lead.copiloto_modo]
    encerrar(lead, limite) if limite && atingido?(limite, lead)
  end

  # Idempotente: fora de um modo "até…" (já encerrado, ou nunca esteve) não faz nada.
  def encerrar(lead, limite, motivo = nil)
    modo = lead.copiloto_modo
    return unless lead.conversation && Ramon::CopilotoModo::LIMITES.key?(modo)

    conversa = lead.conversation
    carimbo = { 'limite' => limite, 'modo' => modo, 'motivo' => motivo, 'em' => Time.zone.now.iso8601 }.compact
    conversa.update!(custom_attributes: (conversa.custom_attributes || {}).merge('copiloto_modo' => 'rascunho',
                                                                                 'copiloto_limite' => carimbo))
    avisar(lead, limite, motivo)
    limite
  end
```

```ruby
  # Qualificação = só o desfecho qualificado do roteiro (desqualificado/equipe já encerram pelos efeitos da F1).
  def nivel(lead)
    return CONTRATO if lead.won_at.present? || lead.contrato_enviado?
    return REUNIAO if reuniao?(lead)

    QUALIFICACAO if lead.desfecho_roteiro == Ramon::Roteiro::QUALIFICADO
  end
```

Em `app/services/ramon/copiloto_modo.rb`, trocar

```ruby
  LIMITES = { 'piloto_ate_qualificacao' => 'qualificacao', 'piloto_ate_reuniao' => 'reuniao',
              'piloto_ate_contrato' => 'contrato' }.freeze
```

por

```ruby
  LIMITES = { 'piloto_ate_qualificacao' => Ramon::CopilotoLimite::QUALIFICACAO, 'piloto_ate_reuniao' => Ramon::CopilotoLimite::REUNIAO,
              'piloto_ate_contrato' => Ramon::CopilotoLimite::CONTRATO }.freeze
```

(O `CopilotoLimite` não lê nada do `CopilotoModo` ao carregar, então não há ciclo de autoload.)

- [ ] **Step 5: `ContratoAutomatico` sem `MODO` e pelo lead**

Em `app/services/ramon/contrato_automatico.rb`: apagar a linha `MODO = 'piloto_ate_contrato'.freeze`; trocar a 1ª linha do `preparar`

```ruby
    return unless lead.conversation && Ramon::CopilotoModo.of(lead.conversation) == MODO
```

por

```ruby
    return unless lead.conversation && Ramon::CopilotoModo::LIMITES[lead.copiloto_modo] == Ramon::CopilotoLimite::CONTRATO
```

e, no `faltando`, trocar

```ruby
    nome = lead.contact&.name.presence || lead.name
    (nome.to_s.split.size < 2 ? ['nome completo'] : []) + OBRIGATORIOS.slice(*vazios).values
```

por

```ruby
    (lead.nome_completo? ? [] : ['nome completo']) + OBRIGATORIOS.slice(*vazios).values
```

- [ ] **Step 6: Lint + commit** (os specs rodam no CI do PR)

```bash
rubocop-vps app/services/ramon/roteiro.rb app/services/ramon/copiloto_limite.rb app/services/ramon/copiloto_modo.rb \
  app/services/ramon/contrato_automatico.rb app/models/copilot_suggestion.rb app/models/lead.rb \
  app/models/concerns/lead_roteiro.rb spec/models/lead_roteiro_spec.rb spec/services/ramon/copiloto_limite_spec.rb
git add app/services/ramon/roteiro.rb app/services/ramon/copiloto_limite.rb app/services/ramon/copiloto_modo.rb \
  app/services/ramon/contrato_automatico.rb app/models/copilot_suggestion.rb app/models/lead.rb \
  app/models/concerns/lead_roteiro.rb spec/models/lead_roteiro_spec.rb spec/services/ramon/copiloto_limite_spec.rb
git commit -m "refactor(roteiro): desfechos e limites numa fonte única; leituras do lead em LeadRoteiro"
```

---

### Task 2: Efeitos enxutos — avisos em `AvisoDaIa`, modo em `CopilotoModo`, `Registro` legível, aviso ao admin no roteiro sem saída

**Files:**
- Create: `app/services/ramon/aviso_da_ia.rb`
- Create: `spec/services/ramon/aviso_da_ia_spec.rb`
- Modify: `app/services/ramon/copiloto_modo.rb` (`MODO_ANTES`, `trocar`, `restaurar`)
- Modify: `app/services/ramon/copiloto_limite.rb` (`avisar`)
- Modify: `app/services/ramon/roteiro/efeitos.rb` (conteúdo inteiro)
- Modify: `app/services/ramon/roteiro/registro.rb` (conteúdo inteiro)
- Modify: `spec/services/ramon/copiloto_modo_spec.rb` (1 exemplo)
- Modify: `spec/services/ramon/roteiro_spec.rb` (1 exemplo)

**Interfaces:**
- Consumes: as constantes da Task 1; `Lead#copiloto_modo`.
- Produces:
  - `Ramon::AvisoDaIa.avisar(lead, label, titulo, corpo, admins: false)`: sino e push ao closer/SDR; sem eles, ou com `admins: true`, também aos administradores.
  - `Ramon::CopilotoModo::MODO_ANTES = 'copiloto_modo_antes_roteiro'`; `Ramon::CopilotoModo.trocar(conversa, valor)` (guarda o 1º modo de antes); `Ramon::CopilotoModo.restaurar(conversa)` (devolve; sem modo de antes, tira o atributo).
  - `Ramon::Roteiro::Efeitos.desqualificacao(lead) -> :nada | :perder | :sugerir` (o predicado único); `Efeitos.direto?(lead)`; `Efeitos.reabrir(lead)` (a assinatura muda na Task 5); `Efeitos.tirar_etiqueta(conversa)`.
  - `Ramon::Roteiro::Registro`: `@passos`, `@estado`, `normalizar_resposta`, `motivo_da_recusa`, `aguarda_equipe?`.

- [ ] **Step 1: Specs (falham)**

`spec/services/ramon/aviso_da_ia_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Ramon::AvisoDaIa' do # rubocop:disable RSpec/DescribeClass -- constante explícita (reload no CI)
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:sdr) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account) }

  def avisados = Notification.where(primary_actor: lead, notification_type: 'ramon_fluxo_aviso').pluck(:user_id)

  it 'avisa o SDR/closer do lead; sem eles, os administradores' do
    Ramon::AvisoDaIa.avisar(lead, 'x', 't', 'c')
    expect(avisados).to eq([admin.id])

    Notification.delete_all
    lead.update_columns(sdr_id: sdr.id) # rubocop:disable Rails/SkipsModelValidations -- sem atribuir a conversa
    Ramon::AvisoDaIa.avisar(lead.reload, 'x', 't', 'c')
    expect(avisados).to eq([sdr.id])
  end

  it 'admins: true avisa o responsável e também os administradores (roteiro sem saída, spec §5)' do
    lead.update_columns(sdr_id: sdr.id) # rubocop:disable Rails/SkipsModelValidations -- sem atribuir a conversa
    Ramon::AvisoDaIa.avisar(lead.reload, 'x', 't', 'c', admins: true)
    expect(avisados).to contain_exactly(sdr.id, admin.id)
  end
end
```

Em `spec/services/ramon/copiloto_modo_spec.rb`, antes do último `end`:

```ruby
  # Revisão F5 item 4: modo de antes vazio não vira nil gravado — volta a valer o padrão da caixa.
  it 'trocar guarda o 1º modo de antes; restaurar devolve, e sem modo de antes tira o atributo' do
    conversation.update!(custom_attributes: {})
    inbox.update!(ramon_copiloto_modo: 'piloto_ate_reuniao')

    Ramon::CopilotoModo.trocar(conversation, 'manual')
    Ramon::CopilotoModo.trocar(conversation, 'rascunho')
    expect(conversation.reload.custom_attributes).to eq('copiloto_modo' => 'rascunho', Ramon::CopilotoModo::MODO_ANTES => nil)

    Ramon::CopilotoModo.restaurar(conversation)
    expect(conversation.reload.custom_attributes).to eq({})
    expect(Ramon::CopilotoModo.of(conversation)).to eq('piloto_ate_reuniao')
  end
```

Em `spec/services/ramon/roteiro_spec.rb`, depois do exemplo `'nada casando vai para a equipe com sino ao gestor'`:

```ruby
  # Spec §5: roteiro sem saída = configuração quebrada → além do responsável, os administradores ficam sabendo.
  it 'roteiro sem saída avisa o SDR do lead e também os administradores' do
    admin = create(:user, account: account, role: :administrator)
    sdr = create(:user, account: account, role: :agent)
    lead.update_columns(sdr_id: sdr.id) # rubocop:disable Rails/SkipsModelValidations -- sem atribuir a conversa
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim')
    registrar('sequela', 'nao sei dizer')

    avisados = Notification.where(primary_actor: lead, notification_type: 'ramon_fluxo_aviso').pluck(:user_id)
    expect(avisados).to contain_exactly(sdr.id, admin.id)
  end
```

- [ ] **Step 2: `Ramon::AvisoDaIa`**

`app/services/ramon/aviso_da_ia.rb`:

```ruby
# Sino + push da IA para a equipe (roteiro da tese, limites dos modos "sozinha até…", dados do contrato): ao
# closer/SDR do lead e, sem eles ou quando pedido (roteiro sem saída, spec §5), também aos administradores da conta.
module Ramon::AvisoDaIa
  module_function

  def avisar(lead, label, titulo, corpo, admins: false)
    ids = [lead.closer_id || lead.sdr_id].compact
    ids |= Ramon::Papeis.gestor_ids(lead.account) if admins || ids.empty?
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso', user_ids: ids,
                                       meta: { 'label' => label.truncate(200) }).perform
    Ramon::NtfyPushJob.perform_later(lead.id, title: titulo, body: corpo.to_s.truncate(200))
  end
end
```

- [ ] **Step 3: Troca de modo em `CopilotoModo`; aviso do limite em `AvisoDaIa`**

Em `app/services/ramon/copiloto_modo.rb`, depois de `DEFAULT = 'rascunho'.freeze`:

```ruby
  # Modo de antes do roteiro (decisão 13/10): o 1º guardado vale até o reabrir devolver.
  MODO_ANTES = 'copiloto_modo_antes_roteiro'.freeze
```

e, antes do `end` final do módulo:

```ruby
  # Troca o modo da conversa guardando o de antes (o 1º vale até o restaurar) — desqualificado/equipe do roteiro.
  def trocar(conversa, valor)
    attrs = conversa.custom_attributes || {}
    antes = attrs.key?(MODO_ANTES) ? {} : { MODO_ANTES => attrs['copiloto_modo'] }
    conversa.update!(custom_attributes: attrs.merge(antes).merge('copiloto_modo' => valor))
  end

  # Devolve o modo guardado por trocar. Sem modo de antes, tira o atributo: volta a valer o padrão da caixa/env.
  def restaurar(conversa)
    attrs = conversa.reload.custom_attributes || {}
    return unless attrs.key?(MODO_ANTES)

    antes = attrs[MODO_ANTES]
    sem = attrs.except(MODO_ANTES, 'copiloto_modo')
    conversa.update!(custom_attributes: antes ? sem.merge('copiloto_modo' => antes) : sem)
  end
```

Em `app/services/ramon/copiloto_limite.rb`, no `avisar`, trocar `Ramon::Roteiro::Efeitos.avisar(` por `Ramon::AvisoDaIa.avisar(`.

- [ ] **Step 4: `Efeitos` (conteúdo inteiro)**

`app/services/ramon/roteiro/efeitos.rb`:

```ruby
# Consequências fixas de uma saída do roteiro (spec 2026-10-13 §3.4) — configuradas pelo admin no passo; a IA não
# decide. Por modo da conversa (decisões 13/10): etiqueta e "passar para a equipe" valem direto em qualquer modo;
# etapa (só aberta) e Perdido só direto nos modos diretos (piloto total e "sozinha até…") — nos outros, e sem
# conversa, viram sugestão no Cockpit. Perdido de verdade = etiqueta desqualificado-ia + IA calada (a conversa fica com
# o robô). Histórico: LeadActivity 'roteiro'. Modo da conversa: Ramon::CopilotoModo; avisos: Ramon::AvisoDaIa.
module Ramon::Roteiro::Efeitos
  ETIQUETA_DESQUALIFICADO = 'desqualificado-ia'.freeze
  MOTIVO_PERDA_PADRAO = 'Sem viabilidade'.freeze

  module_function

  def aplicar(lead, passo, saida)
    efeitos = saida['efeitos'] || {}
    etiquetar(lead, efeitos['etiqueta'])
    mover(lead, efeitos['etapa'], passo)
    desqualificar(lead, passo, saida) if saida['acao'] == 'desqualificar'
    humano(lead, saida) if saida['acao'] == 'humano'
    anotar(lead, "#{passo.titulo} → #{resumo(saida)}") if Ramon::Roteiro::DESFECHO_DA_ACAO.key?(saida['acao']) || efeitos.values.any?(&:present?)
    Ramon::CopilotoLimite.verificar(lead)
  end

  # Etapa e Perdido direto no piloto total e nos modos "sozinha até…" (F3), pelo modo efetivo da conversa do lead.
  def direto?(lead)
    Ramon::CopilotoModo.direto?(lead.copiloto_modo)
  end

  # O que a desqualificação faz agora — predicado único (o Registro marca aguarda_equipe com ele):
  # :nada (lead ganho ou perdido), :perder (modo direto) ou :sugerir (o Perdido vira sugestão no Cockpit).
  def desqualificacao(lead)
    return :nada if lead.won_at || lead.lost_at

    direto?(lead) ? :perder : :sugerir
  end

  # Label do Chatwoot é minúscula (Label#title.downcase).
  def etiquetar(lead, etiqueta)
    return if etiqueta.blank? || lead.conversation.nil?

    lead.conversation.reload.add_labels([etiqueta.to_s.downcase])
  end

  # Só etapa aberta: ganho nunca; perdido só pela saída desqualificar. Nunca para trás (como registrar_reuniao!).
  def mover(lead, nome, passo)
    return if nome.blank?

    etapa = lead.account.lead_stages.find_by(name: nome, is_won: false, is_lost: false)
    return anotar(lead, "etapa '#{nome}' nao existe no funil") if etapa.nil?
    return if lead.lead_stage.position >= etapa.position
    return lead.update!(lead_stage: etapa) if direto?(lead)

    sugerir(lead, 'move_stage', 'etapa_sugerida' => etapa.name, 'justificativa' => "roteiro da IA: #{passo.titulo}")
  end

  def desqualificar(lead, passo, saida)
    motivo_perda = saida['motivo_perda'].presence || MOTIVO_PERDA_PADRAO
    case desqualificacao(lead)
    when :perder then perder(lead, motivo_perda)
    when :sugerir
      sugerir(lead, 'acao', 'acao' => 'perdido', 'lost_reason' => motivo_perda,
                            'texto' => "Marcar como perdido (#{motivo_perda}) - roteiro: #{passo.titulo}, #{saida['motivo']}")
    end
  end

  def perder(lead, motivo_perda)
    perdido = lead.account.lead_stages.find_by(is_lost: true)
    lead.update!(lead_stage: perdido, lost_reason: motivo_perda) if perdido
    calar(lead)
  end

  # A mensagem de encerramento desta resposta ainda sai: o ResponseBuilderJob guarda o modo do início da resposta.
  # Também chamada ao aprovar o Perdido sugerido pelo roteiro (CopilotSuggestion#marcar_perdido).
  def calar(lead)
    etiquetar(lead, ETIQUETA_DESQUALIFICADO)
    Ramon::CopilotoModo.trocar(lead.conversation, 'manual') if lead.conversation
  end

  # Roteiro reaberto (Ramon::Roteiro.reabrir): devolve o modo de antes e tira a etiqueta de desqualificado.
  def reabrir(lead)
    conversa = lead.conversation
    if conversa
      Ramon::CopilotoModo.restaurar(conversa)
      tirar_etiqueta(conversa)
    end
    anotar(lead, 'roteiro reaberto')
  end

  def tirar_etiqueta(conversa)
    return unless conversa.label_list.include?(ETIQUETA_DESQUALIFICADO)

    conversa.update_labels(conversa.label_list - [ETIQUETA_DESQUALIFICADO])
  end

  # Como as tools de escrita: pendente igual (mesmo caso, mesmo tipo/ação) não vira duas.
  def sugerir(lead, kind, payload)
    pendentes = lead.account.copilot_suggestions.pending.where(lead_id: lead.id, kind: kind)
    return if pendentes.any? { |s| s.payload['acao'] == payload['acao'] }

    lead.account.copilot_suggestions.create!(
      lead: lead, kind: kind, status: 'pending', run_at: Time.current,
      payload: payload.merge('origem' => 'roteiro', 'lead_name' => lead.name, 'stage_name' => lead.lead_stage&.name)
    )
  end

  # Mesmo caminho da tool handoff (bot_handoff!). Roteiro sem saída (configuração quebrada, spec §5) avisa também os
  # administradores, além do responsável.
  def humano(lead, saida)
    conversa = lead.conversation
    conversa.bot_handoff! if conversa&.pending?
    Ramon::CopilotoModo.trocar(conversa, 'rascunho') if conversa
    motivo = saida['motivo']
    Ramon::AvisoDaIa.avisar(lead, "IA passou #{lead.name} para a equipe: #{motivo}", "IA passou para a equipe: #{lead.name}",
                            motivo, admins: saida['id'] == Ramon::Roteiro::SEM_SAIDA)
  end

  def resumo(saida)
    case Ramon::Roteiro::DESFECHO_DA_ACAO[saida['acao']]
    when Ramon::Roteiro::DESQUALIFICADO then "desqualificado: #{saida['motivo']}"
    when Ramon::Roteiro::HUMANO then "passou para a equipe: #{saida['motivo']}"
    when Ramon::Roteiro::QUALIFICADO then 'qualificado'
    else saida['acao']
    end
  end

  def anotar(lead, texto)
    lead.lead_activities.create!(account: lead.account, kind: 'roteiro', to_value: texto.truncate(250))
  end
end
```

(Se o `rubocop-vps` acusar a linha do `anotar` em `aplicar`, extrair `def anota?(saida, efeitos) = Ramon::Roteiro::DESFECHO_DA_ACAO.key?(saida['acao']) || efeitos.values.any?(&:present?)`.)

- [ ] **Step 5: `Registro` (conteúdo inteiro, mesmo comportamento)**

`app/services/ramon/roteiro/registro.rb`:

```ruby
# Registra a resposta da IA num passo do roteiro: normaliza, faz a conta, escolhe a saída, avança o estado e aplica
# os efeitos (spec 2026-10-13 §3.4 e §5). Porta de entrada: Ramon::Roteiro.registrar.
class Ramon::Roteiro::Registro
  SEGUIR = { 'id' => 'seguir', 'acao' => 'seguir' }.freeze

  def initialize(lead)
    @lead = lead
    @passos = Ramon::Roteiro.passos(lead)
    @estado = Ramon::Roteiro.estado(lead)
  end

  # @return { erro: } | { estado:, proximo:, calc:, mensagem: }
  def call(chave:, valor: nil, saida_id: nil)
    @passo = @passos.find { |p| p.chave == chave.to_s }
    erro = motivo_da_recusa(chave)
    return { erro: erro } if erro

    normal, erro = normalizar_resposta(valor, saida_id)
    return { erro: erro } if erro
    return { erro: 'Informe o assunto em texto no valor.' } if assunto? && normal.blank?

    calc = calcular(normal)
    saida = saida_de(saida_id, normal, calc)
    return { erro: "A saida #{saida_id} nao existe neste passo." } if saida.nil?

    gravar(normal, calc, saida)
  end

  private

  def normalizar_resposta(valor, saida_id)
    normal, erro = Ramon::Roteiro::Resposta.normalizar(@passo, valor)
    erro ||= 'Informe o valor da resposta ou o saida_id.' if normal.nil? && saida_id.blank?
    [normal, erro]
  end

  def motivo_da_recusa(chave)
    return 'Este caso nao tem roteiro.' if @passos.empty?
    return "O roteiro ja terminou (#{@estado['desfecho']}). Nao registre mais passos." if @estado['desfecho']

    "Passo #{chave} nao existe. Passos: #{@passos.map(&:chave).join(', ')}." if @passo.nil?
  end

  # Campos da calculadora vêm das respostas; o do próprio passo, da resposta de agora.
  def calcular(valor)
    return if @passo.calculadora.blank?

    campos = @passo.calculadora_campos.transform_values do |chave|
      chave == @passo.chave ? valor : @estado.dig('respostas', chave, 'valor')
    end
    Ramon::Roteiro::Calculadoras.calcular(@passo.calculadora, campos)
  end

  # Sem saídas = só coleta (segue). Com saídas e nada casando = roteiro sem saída (equipe).
  def escolher(saida_id, comparado)
    return SEGUIR if @passo.saidas.blank?
    return @passo.saidas.find { |s| s['id'].to_s == saida_id.to_s } if saida_id.present?

    @passo.saidas.find { |s| Ramon::Roteiro::Resposta.casa?(s['quando'], comparado) } || sem_saida('nenhuma saida casou')
  end

  def saida_de(saida_id, normal, calc)
    return assunto(normal) if assunto?

    escolher(saida_id, calc ? calc[:resultado] : normal)
  end

  def assunto?
    @passo.thesis_id.nil? && @passo.chave == Ramon::Roteiro::ASSUNTO
  end

  # Passo comum "assunto" (F3): a resposta casa com nome/palavras-chave das teses. Casou com uma → o lead ganha a tese
  # e o roteiro segue nos passos dela (as respostas dos comuns ficam); nenhuma ou mais de uma → equipe.
  def assunto(texto)
    tese = Ramon::TeseAutomatica.por_texto(@lead.account, texto)
    return { 'id' => 'sem_tese', 'acao' => 'humano', 'motivo' => 'assunto sem tese cadastrada' } if tese.nil?

    @lead.update!(thesis: tese)
    @passos = Ramon::Roteiro.passos(@lead)
    @estado = Ramon::Roteiro.estado(@lead)
    { 'id' => 'tese', 'acao' => 'seguir' }
  end

  def gravar(valor, calc, saida)
    guardar_resposta(valor, calc, saida)
    saida = avancar(saida)
    @estado['aguarda_equipe'] = true if aguarda_equipe?(saida)
    proximo = @estado['desfecho'] ? nil : Ramon::Roteiro.proximo(@passos, @estado)
    @estado['passo'] = proximo&.chave # bi_roteiro (F4): onde o lead parou
    ActiveRecord::Base.transaction do
      @lead.update!(custom_attributes: (@lead.custom_attributes || {}).merge('roteiro' => @estado))
      Ramon::Roteiro::Efeitos.aplicar(@lead, @passo, saida)
    end
    { estado: @estado, proximo: proximo, calc: calc, mensagem: saida['mensagem'] }
  end

  def guardar_resposta(valor, calc, saida)
    # Correção de um passo já respondido: vale a nova resposta e o roteiro volta a seguir dali (decisão 13/10) —
    # se o passo estiver antes do cursor; resposta adiantada corrigida não pula os anteriores.
    Ramon::Roteiro.voltar_cursor(@passos, @estado, @passo.chave) if @estado['respostas'].key?(@passo.chave)
    @estado['respostas'][@passo.chave] = { 'valor' => valor, 'calc' => calc&.stringify_keys, 'saida' => saida['id'],
                                           'em' => Time.zone.now.iso8601 }.compact
  end

  # ir_para move o cursor; seguir/ir_para sem passo pela frente = concluir (qualificado) — menos numa tese sem
  # passos próprios: ao fim dos comuns a IA volta para a triagem de sempre, sem desfecho (decisão 13/10).
  def avancar(saida)
    if saida['acao'] == 'ir_para'
      return avancar(sem_saida("destino #{saida['alvo']} nao existe")) if @passos.none? { |p| p.chave == saida['alvo'] }

      @estado['cursor'] = saida['alvo']
    end
    saida = saida.merge('acao' => 'concluir') if acabou?(saida)
    encerrar(saida)
    saida
  end

  # O Perdido vai virar sugestão (aguardando a equipe) — o mesmo predicado que os Efeitos usam para decidir.
  def aguarda_equipe?(saida)
    saida['acao'] == 'desqualificar' && Ramon::Roteiro::Efeitos.desqualificacao(@lead) == :sugerir
  end

  def acabou?(saida)
    %w[seguir ir_para].include?(saida['acao']) && Ramon::Roteiro.proximo(@passos, @estado).nil? && @passos.any?(&:thesis_id)
  end

  def encerrar(saida)
    desfecho = Ramon::Roteiro::DESFECHO_DA_ACAO[saida['acao']]
    return if desfecho.nil?

    @estado.merge!('desfecho' => desfecho, 'motivo' => saida['motivo'], 'decisivo' => @passo.chave)
  end

  def sem_saida(detalhe)
    { 'id' => Ramon::Roteiro::SEM_SAIDA, 'acao' => 'humano', 'motivo' => "roteiro sem saida no passo #{@passo.chave} (#{detalhe})" }
  end
end
```

- [ ] **Step 6: Conferir que ninguém mais chama o que saiu**

```bash
grep -rn "Efeitos\.avisar\|Efeitos\.modo\|Efeitos\.restaurar\|Efeitos::MODO_ANTES\|Efeitos::ENCERRA\|Registro::DESFECHOS\|vira_sugestao_de_perdido" app enterprise lib spec
```

Esperado: nenhuma linha.

- [ ] **Step 7: Lint + commit**

```bash
rubocop-vps app/services/ramon/aviso_da_ia.rb app/services/ramon/copiloto_modo.rb app/services/ramon/copiloto_limite.rb \
  app/services/ramon/roteiro/efeitos.rb app/services/ramon/roteiro/registro.rb spec/services/ramon/aviso_da_ia_spec.rb \
  spec/services/ramon/copiloto_modo_spec.rb spec/services/ramon/roteiro_spec.rb
git add app/services/ramon/aviso_da_ia.rb app/services/ramon/copiloto_modo.rb app/services/ramon/copiloto_limite.rb \
  app/services/ramon/roteiro/efeitos.rb app/services/ramon/roteiro/registro.rb spec/services/ramon/aviso_da_ia_spec.rb \
  spec/services/ramon/copiloto_modo_spec.rb spec/services/ramon/roteiro_spec.rb
git commit -m "refactor(roteiro): avisos e troca de modo fora dos Efeitos; roteiro sem saída avisa os admins"
```

---

### Task 3: Teste × real num caminho só + handoff do roteiro por sinal

**Files:**
- Modify: `app/services/ramon/roteiro.rb` (`texto_atual`)
- Modify: `app/services/ramon/roteiro/registro.rb` (`handoff` no resultado)
- Modify: `app/services/ramon/roteiro/teste.rb` (conteúdo inteiro)
- Modify: `enterprise/lib/captain/tools/ramon_base_tool.rb` (`no_roteiro`)
- Modify: `enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb` (conteúdo inteiro)
- Modify: `enterprise/lib/captain/tools/roteiro_registrar_tool.rb` (conteúdo inteiro)
- Modify: `enterprise/app/services/captain/assistant/agent_runner_service.rb` (`add_usage_metadata_callback`, `track_handoff_usage`)
- Modify: `spec/enterprise/services/captain/assistant/agent_runner_service_spec.rb` (volta a chamada de 4 argumentos — não roda no CI, mas fica coerente)
- Modify: `spec/services/ramon/roteiro/teste_spec.rb` (conteúdo inteiro)
- Modify: `spec/services/ramon/roteiro_spec.rb` (1 exemplo e 1 linha)

**Interfaces:**
- Consumes: `Ramon::Roteiro::HUMANO` (Task 1); `Ramon::Roteiro.atual/descrever/resumo/registrar`.
- Produces:
  - `Ramon::Roteiro.texto_atual(lead) -> String | nil` (nil = sem roteiro)
  - `Ramon::Roteiro.registrar(...)` devolve também `handoff: Boolean` (desfecho `humano` agora, com conversa ligada)
  - `Ramon::Roteiro::Teste.com_lead(account, teste) { |lead| … } -> resultado do bloco`; grava em `teste['estado']` o estado depois do bloco. `Teste.resposta(account, teste)` continua.
  - `Captain::Tools::RamonBaseTool#no_roteiro(tool_context, lead_id) { |lead| … }` (privado)
  - `Captain::Tools::RoteiroRegistrarTool::HANDOFF = :ramon_roteiro_handoff` (chave no `tool_context.state`)

- [ ] **Step 1: Specs (falham)**

`spec/services/ramon/roteiro/teste_spec.rb` (conteúdo inteiro):

```ruby
require 'rails_helper'

# Testar com tese (F2) pelo mesmo caminho do lead real (F5, revisão integrada item 11).
RSpec.describe 'Ramon::Roteiro::Teste' do # rubocop:disable RSpec/DescribeClass -- constante explícita (reload no CI)
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:teste) { Ramon::Roteiro::Teste.de_params(account, { 'thesis_id' => thesis.id.to_s }) }

  def atual(teste) = Ramon::Roteiro::Teste.com_lead(account, teste) { |lead| Ramon::Roteiro.texto_atual(lead) }

  def registrar(teste, **resposta)
    Ramon::Roteiro::Teste.com_lead(account, teste) { |lead| Ramon::Roteiro.registrar(lead, **resposta) }
  end

  before do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'recebeu', position: 0, titulo: 'Recebeu',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'humano', 'motivo' => 'recebeu' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', position: 1, titulo: 'Renda', tipo_resposta: 'numero')
  end

  it 'roda o motor de verdade, devolve o estado no teste e não grava nada' do
    expect(atual(teste)).to include('Passo atual: Recebeu')

    res = registrar(teste, chave: 'recebeu', valor: 'nao')
    expect(Ramon::Roteiro.resumo(res)).to include('Passo atual: Renda')
    expect(teste['estado'].dig('respostas', 'recebeu', 'valor')).to eq('nao')
    expect(atual(teste)).to include('Passo atual: Renda')
    expect([Lead.count, LeadActivity.count, CopilotSuggestion.count]).to eq([0, 0, 0])
  end

  it 'equipe no teste: desfecho no estado e no painel, sem sino e sem handoff (não há conversa)' do
    create(:user, account: account, role: :administrator)
    expect(registrar(teste, chave: 'recebeu', valor: 'sim')[:handoff]).to be(false)
    expect(teste['estado']).to include('desfecho' => 'humano', 'motivo' => 'recebeu')

    resposta = Ramon::Roteiro::Teste.resposta(account, teste)
    expect(resposta).to include('thesis_id' => thesis.id, 'estado' => teste['estado'])
    expect(resposta['painel']).to include('desfecho' => 'humano')
    expect([Notification.count, Lead.count]).to eq([0, 0])
  end

  it 'valor inválido volta o erro para a IA e o estado do teste não muda' do
    expect(registrar(teste, chave: 'recebeu', valor: 'talvez')).to eq(erro: 'Responda sim ou nao.')
    expect(teste['estado']).to be_nil
  end

  it 'de_params: só tese da conta; sem tese = sem teste; estado vira Hash simples' do
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: create(:thesis, account: create(:account)).id })).to be_nil
    expect(Ramon::Roteiro::Teste.de_params(account, nil)).to be_nil
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: thesis.id, estado: { 'respostas' => {} } }))
      .to eq('thesis_id' => thesis.id, 'estado' => { 'respostas' => {} })
  end
end
```

Em `spec/services/ramon/roteiro_spec.rb`, depois do exemplo novo da Task 2:

```ruby
  # Revisão F5 item 12: o handoff do roteiro é um sinal no resultado (a tool o põe no state), não um texto.
  it 'o resultado sinaliza handoff só quando o roteiro acabou de passar para a equipe com conversa' do
    expect(registrar('tem_advogado', 'nao')[:handoff]).to be(false)
    registrar('recebeu_auxilio', 'sim')
    expect(registrar('sequela', 'nao sei dizer')[:handoff]).to be(true)

    sem_conversa = create(:lead, account: account, thesis: thesis, lead_stage: novo)
    Ramon::Roteiro.registrar(sem_conversa, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(sem_conversa.reload, chave: 'recebeu_auxilio', valor: 'sim')
    expect(Ramon::Roteiro.registrar(sem_conversa.reload, chave: 'sequela', valor: 'nao sei')[:handoff]).to be(false)
  end
```

E no exemplo `'descrever mostra o passo, as saídas do texto e o que já foi respondido'`, logo depois da linha `.and include('ficou = ficou alguma limitacao').and include('tem_advogado=nao')`, acrescentar:

```ruby
    expect(Ramon::Roteiro.texto_atual(lead.reload)).to eq(texto)
```

- [ ] **Step 2: `texto_atual` e `handoff`**

Em `app/services/ramon/roteiro.rb`, logo depois do método `atual`:

```ruby
  # Texto do passo atual para a IA (tool roteiro_passo_atual, no lead real ou no Testar); nil = sem roteiro.
  def texto_atual(lead)
    atual = atual(lead)
    atual && descrever(atual[:passo], atual[:estado])
  end
```

Em `app/services/ramon/roteiro/registro.rb`: o comentário `# @return { erro: } | { estado:, proximo:, calc:, mensagem: }` passa a ser `# @return { erro: } | { estado:, proximo:, calc:, mensagem:, handoff: }`; a última linha do `gravar` vira

```ruby
    { estado: @estado, proximo: proximo, calc: calc, mensagem: saida['mensagem'], handoff: handoff? }
```

e, logo depois do `gravar`:

```ruby
  # O roteiro acabou de passar o caso para a equipe com a conversa ligada (Efeitos.humano fez o bot_handoff!): a tool
  # sinaliza o handoff ao runner pelo state — nada depende do texto devolvido à IA.
  def handoff?
    @estado['desfecho'] == Ramon::Roteiro::HUMANO && @lead.conversation.present?
  end
```

- [ ] **Step 3: `Teste` (conteúdo inteiro)**

`app/services/ramon/roteiro/teste.rb`:

```ruby
# Testar com tese (spec §3.8.5): o motor de verdade num lead descartável, dentro de uma transação desfeita — nada
# fica gravado (lead, respostas, histórico, sugestões, sino). As tools do roteiro passam pelo mesmo caminho do lead
# real (Captain::Tools::RamonBaseTool#no_roteiro): só o lead muda. O estado do roteiro vai e volta pelo Testar.
# teste = { 'thesis_id' => id, 'estado' => estado do roteiro ou nil }
# ponytail: o push do ntfy (perform_later) sai da transação, acha o lead apagado e não envia.
module Ramon::Roteiro::Teste
  NOME = 'Teste do roteiro'.freeze

  module_function

  # Do corpo do playground: só tese da conta; estado vira Hash simples (chaves texto).
  def de_params(account, roteiro)
    roteiro = (roteiro || {}).to_h.with_indifferent_access
    tese = account.theses.find_by(id: roteiro[:thesis_id]) if roteiro[:thesis_id].present?
    tese && { 'thesis_id' => tese.id, 'estado' => roteiro[:estado].presence&.to_hash }
  end

  # Roda o bloco com o lead descartável e devolve o resultado dele; o estado do roteiro depois volta para o teste.
  # Erro no bloco desfaz tudo e sobe (a tool trata, como no lead real).
  def com_lead(account, teste)
    resultado = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      lead = account.leads.create!(name: NOME, thesis_id: teste['thesis_id'], lead_stage: etapa_aberta(account),
                                   custom_attributes: { 'roteiro' => teste['estado'] }.compact)
      resultado = yield lead
      teste['estado'] = lead.reload.custom_attributes['roteiro']
      raise ActiveRecord::Rollback
    end
    resultado
  end

  def etapa_aberta(account)
    account.lead_stages.where(is_won: false, is_lost: false).order(:position).first
  end

  # O que o Testar recebe de volta: o estado (vai de novo na próxima mensagem) e o passo a passo para a tela.
  def resposta(account, teste)
    painel = com_lead(account, teste) { |lead| Ramon::Roteiro::Painel.montar(lead) }
    { 'thesis_id' => teste['thesis_id'], 'estado' => teste['estado'], 'painel' => painel }
  end
end
```

- [ ] **Step 4: Tools finas e handoff por sinal**

Em `enterprise/lib/captain/tools/ramon_base_tool.rb`, depois do `resolver_lead`:

```ruby
  # Roteiro do caso — ou, no Testar com roteiro (F2), o lead descartável de Ramon::Roteiro::Teste: as tools do roteiro
  # rodam pelo mesmo caminho e só o lead muda (nada fica gravado no teste).
  def no_roteiro(tool_context, lead_id, &)
    teste = tool_context.state&.dig(:roteiro_teste)
    return ::Ramon::Roteiro::Teste.com_lead(@assistant.account, teste, &) if teste

    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    yield lead
  end
```

`enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb` (conteúdo inteiro):

```ruby
# Leitura: o passo do roteiro da tese que a IA pergunta agora (spec roteiro da tese §3.5). Toda a regra fica em
# Ramon::Roteiro (testada no CI); aqui só resolve o caso (real ou do Testar) e devolve o texto.
class Captain::Tools::RoteiroPassoAtualTool < Captain::Tools::RamonBaseTool
  SEM_ROTEIRO = 'Esta tese nao tem roteiro. Siga a triagem de sempre (playbook da tese e registrar qualificacao).'.freeze

  description 'Diz o passo atual do roteiro de qualificacao da tese do caso: o que descobrir, como perguntar, as ' \
              'opcoes e o que ja foi respondido. Chame antes de cada pergunta de qualificacao.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false

  def perform(tool_context, lead_id: nil)
    no_roteiro(tool_context, lead_id) { |lead| ::Ramon::Roteiro.texto_atual(lead) || SEM_ROTEIRO }
  end
end
```

`enterprise/lib/captain/tools/roteiro_registrar_tool.rb` (conteúdo inteiro):

```ruby
# Escrita interna (nada sai para o cliente): grava a resposta do lead num passo do roteiro. O motor faz a conta,
# escolhe a saida e aplica as consequencias fixas (etiqueta, etapa, Perdido, passar para a equipe).
class Captain::Tools::RoteiroRegistrarTool < Captain::Tools::RamonBaseTool
  # Sinal no state da execucao: o roteiro acabou de passar o caso para a equipe (Efeitos.humano ja fez bot_handoff!).
  # O AgentRunnerService le o sinal e trata como handoff — nada depende do texto devolvido a IA.
  HANDOFF = :ramon_roteiro_handoff

  description 'Registra a resposta do lead a um passo do roteiro da tese. Informe a chave do passo e o valor ' \
              '(sim/nao, uma das opcoes, numero, data AAAA-MM-DD ou texto). Em passo de texto livre, informe tambem ' \
              'o saida_id que melhor descreve a resposta. Devolve o proximo passo ou o desfecho.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false
  param :chave, type: 'string', desc: 'Chave do passo (vem do Passo atual do roteiro)', required: true
  param :valor, type: 'string', desc: 'Resposta do lead, no formato do passo', required: false
  param :saida_id, type: 'string', desc: 'Id da saida escolhida (passo de texto livre)', required: false

  def perform(tool_context, chave: nil, valor: nil, saida_id: nil, lead_id: nil)
    res = no_roteiro(tool_context, lead_id) { |lead| ::Ramon::Roteiro.registrar(lead, chave: chave, valor: valor, saida_id: saida_id) }
    return res if res.is_a?(String) # SEM_LEAD

    tool_context.state[HANDOFF] = true if res[:handoff]
    res[:erro] || ::Ramon::Roteiro.resumo(res)
  end
end
```

Em `enterprise/app/services/captain/assistant/agent_runner_service.rb`, trocar

```ruby
  def add_usage_metadata_callback(runner)
    handoff_tool_name = Captain::Tools::HandoffTool.new(@assistant).name
    roteiro_tool_name = Captain::Tools::RoteiroRegistrarTool.new(@assistant).name

    # Tool tracking always runs — process_response in the job consumes the resulting
    # handoff_tool_called flag regardless of whether OTEL is enabled.
    runner.on_tool_complete do |tool_name, tool_result, context_wrapper|
      # Saída "humano" do roteiro da tese já fez bot_handoff! (Ramon::Roteiro::Efeitos.humano): conta como handoff.
      roteiro_handoff = tool_name.to_s == roteiro_tool_name && tool_result.to_s.include?(Captain::Tools::RoteiroRegistrarTool::HANDOFF)
      track_handoff_usage(tool_name, handoff_tool_name, context_wrapper, roteiro_handoff)
    end
```

por

```ruby
  def add_usage_metadata_callback(runner)
    handoff_tool_name = Captain::Tools::HandoffTool.new(@assistant).name

    # Tool tracking always runs — process_response in the job consumes the resulting
    # handoff_tool_called flag regardless of whether OTEL is enabled.
    runner.on_tool_complete do |tool_name, _tool_result, context_wrapper|
      track_handoff_usage(tool_name, handoff_tool_name, context_wrapper)
    end
```

e

```ruby
  def track_handoff_usage(tool_name, handoff_tool_name, context_wrapper, roteiro_handoff)
    return unless context_wrapper&.context
    return unless tool_name.to_s == handoff_tool_name || roteiro_handoff
```

por

```ruby
  # ramon: a saída "humano" do roteiro já fez bot_handoff! (Ramon::Roteiro::Efeitos.humano) e marca o state da
  # execução (RoteiroRegistrarTool::HANDOFF) — conta como handoff pelo sinal, nunca pelo texto da tool.
  def track_handoff_usage(tool_name, handoff_tool_name, context_wrapper)
    return unless context_wrapper&.context
    return unless tool_name.to_s == handoff_tool_name || context_wrapper.context.dig(:state, Captain::Tools::RoteiroRegistrarTool::HANDOFF)
```

Em `spec/enterprise/services/captain/assistant/agent_runner_service_spec.rb` (perto da linha 270), trocar

```ruby
                         Struct.new(:context).new({}),
                         false)
```

por

```ruby
                         Struct.new(:context).new({}))
```

- [ ] **Step 5: Conferir que nada mais usa o caminho velho nem o texto**

```bash
grep -rn "Teste\.\(atual\|registrar\|rodar\|painel\)\|registrar_em_teste\|RoteiroRegistrarTool::HANDOFF\b.*include?\|'Roteiro encerrado: humano'" app enterprise lib spec
```

Esperado: nenhuma linha.

- [ ] **Step 6: Lint + commit**

```bash
rubocop-vps app/services/ramon/roteiro.rb app/services/ramon/roteiro/registro.rb app/services/ramon/roteiro/teste.rb \
  enterprise/lib/captain/tools/ramon_base_tool.rb enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb \
  enterprise/lib/captain/tools/roteiro_registrar_tool.rb enterprise/app/services/captain/assistant/agent_runner_service.rb \
  spec/services/ramon/roteiro/teste_spec.rb spec/services/ramon/roteiro_spec.rb
git add app/services/ramon/roteiro.rb app/services/ramon/roteiro/registro.rb app/services/ramon/roteiro/teste.rb \
  enterprise/lib/captain/tools/ramon_base_tool.rb enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb \
  enterprise/lib/captain/tools/roteiro_registrar_tool.rb enterprise/app/services/captain/assistant/agent_runner_service.rb \
  spec/enterprise/services/captain/assistant/agent_runner_service_spec.rb spec/services/ramon/roteiro/teste_spec.rb \
  spec/services/ramon/roteiro_spec.rb
git commit -m "refactor(roteiro): Testar e lead real pelo mesmo caminho; handoff do roteiro por sinal, não por texto"
```

(O `AgentRunnerService` está no teto do `Metrics/ClassLength`: o saldo desta task é −2 linhas de código.)

---

### Task 4: Fail-safe — ferramenta que falhou faz a resposta do turno virar rascunho

**Files:**
- Modify: `app/services/ramon/copiloto_modo.rb` (`envia?`)
- Modify: `enterprise/lib/captain/tools/base_public_tool.rb` (`FALHOU` + rescue)
- Modify: `enterprise/app/services/captain/assistant/agent_runner_service.rb` (`process_agent_result`)
- Modify: `enterprise/app/jobs/captain/conversation/response_builder_job.rb` (`create_outgoing_message`)
- Modify: `spec/services/ramon/copiloto_modo_spec.rb` (1 exemplo)
- Modify: `spec/services/ramon/roteiro_spec.rb` (1 exemplo)

**Interfaces:**
- Consumes: `tool_context.state` (ai-agents: `context[:state] ||= {}`; o mesmo hash do `result.context[:state]`).
- Produces:
  - `Ramon::CopilotoModo.envia?(modo, handoff:, logistica_ok:, falhou: false) -> Boolean`
  - `Captain::Tools::BasePublicTool::FALHOU = :ramon_ferramenta_falhou`
  - resposta do `AgentRunnerService#generate_response` com a chave `'ferramenta_falhou' => Boolean`

- [ ] **Step 1: Specs (falham)**

Em `spec/services/ramon/copiloto_modo_spec.rb`, antes do último `end`:

```ruby
  # Spec roteiro §5 (fail-safe): ferramenta que falhou no turno → rascunho em qualquer modo; a mensagem de handoff
  # (logística) ainda sai. Review Focus 1.
  it 'envia? com ferramenta que falhou: nunca envia texto livre direto, só o handoff' do
    (Ramon::CopilotoModo::MODOS - %w[manual rascunho]).each do |modo|
      expect(Ramon::CopilotoModo.envia?(modo, handoff: false, logistica_ok: true, falhou: true)).to be(false)
      expect(Ramon::CopilotoModo.envia?(modo, handoff: true, logistica_ok: nil, falhou: true)).to be(true)
    end
    expect(Ramon::CopilotoModo.envia?('rascunho', handoff: true, logistica_ok: true, falhou: false)).to be(false)
    expect(Ramon::CopilotoModo.envia?('piloto_total', handoff: false, logistica_ok: nil)).to be(true)
  end
```

Em `spec/services/ramon/roteiro_spec.rb`, depois do exemplo `'valor inválido não grava nada'`:

```ruby
  # Spec §5: erro no meio do registro desfaz tudo e sobe para a tool — o BasePublicTool marca o turno (falhou) e a
  # resposta vira rascunho.
  it 'erro nos efeitos desfaz o registro inteiro e sobe a exceção' do
    allow(Ramon::Roteiro::Efeitos).to receive(:aplicar).and_raise(RuntimeError, 'boom')

    expect { registrar('tem_advogado', 'sim') }.to raise_error(RuntimeError, 'boom')
    expect(lead.reload.custom_attributes['roteiro']).to be_nil
  end
```

- [ ] **Step 2: `envia?` com `falhou`**

Em `app/services/ramon/copiloto_modo.rb`, trocar

```ruby
  # Handoff é logística por definição (constraint global) — nunca vira rascunho
  # em piloto_limitado. logistica_ok nil (não classificado) é fail-safe: rascunho.
  def envia?(modo, handoff:, logistica_ok:)
    piloto?(modo) && (handoff || modo != 'piloto_limitado' || logistica_ok == true)
  end
```

por

```ruby
  # Handoff é logística por definição (constraint global) — nunca vira rascunho. logistica_ok nil (não classificado)
  # é fail-safe: rascunho. falhou = uma ferramenta falhou no turno (spec roteiro §5): rascunho em qualquer modo.
  def envia?(modo, handoff:, logistica_ok:, falhou: false)
    return false unless piloto?(modo)
    return true if handoff

    !falhou && (modo != 'piloto_limitado' || logistica_ok == true)
  end
```

- [ ] **Step 3: A tool marca, o runner devolve, o job decide**

Em `enterprise/lib/captain/tools/base_public_tool.rb`, logo depois da constante `ERRO_NA_TOOL`:

```ruby

  # ramon (roteiro F5, spec §5 fail-safe): a ferramenta que falhou marca o turno no state da execução; o
  # AgentRunnerService devolve 'ferramenta_falhou' e o ResponseBuilderJob faz a resposta do turno virar rascunho.
  FALHOU = :ramon_ferramenta_falhou
```

e no `rescue` do `execute`, trocar

```ruby
    Rails.logger.error("#{self.class.name}: falhou (#{e.class}: #{e.message})")
    registrar_execucao(tool_context, params, "#{e.class}: #{e.message}", 'erro', inicio)
```

por

```ruby
    Rails.logger.error("#{self.class.name}: falhou (#{e.class}: #{e.message})")
    tool_context&.state&.store(FALHOU, true)
    registrar_execucao(tool_context, params, "#{e.class}: #{e.message}", 'erro', inicio)
```

Em `enterprise/app/services/captain/assistant/agent_runner_service.rb`, no `process_agent_result`, logo depois da linha `response['handoff_tool_called'] = …`:

```ruby
    response['ferramenta_falhou'] = result.context&.dig(:state, Captain::Tools::BasePublicTool::FALHOU) || false
```

Em `enterprise/app/jobs/captain/conversation/response_builder_job.rb`, no `create_outgoing_message`, trocar

```ruby
    return create_draft_note(message_content) unless Ramon::CopilotoModo.envia?(modo, handoff: @enviando_handoff, logistica_ok: @logistica_ok)
```

por

```ruby
    # ramon (roteiro F5, spec §5): ferramenta que falhou no turno → a resposta vira rascunho em qualquer modo.
    envia = Ramon::CopilotoModo.envia?(modo, handoff: @enviando_handoff, logistica_ok: @logistica_ok,
                                             falhou: @response&.dig('ferramenta_falhou') == true)
    return create_draft_note(message_content) unless envia
```

(O erro dentro do `Registro#gravar` desfaz a transação e sobe. O rescue do `BasePublicTool#execute` pega e marca o turno: é o mesmo caminho, provado pelo spec do Step 1 e pela prova da Task 11.)

- [ ] **Step 4: Lint + commit**

```bash
rubocop-vps app/services/ramon/copiloto_modo.rb enterprise/lib/captain/tools/base_public_tool.rb \
  enterprise/app/services/captain/assistant/agent_runner_service.rb enterprise/app/jobs/captain/conversation/response_builder_job.rb \
  spec/services/ramon/copiloto_modo_spec.rb spec/services/ramon/roteiro_spec.rb
git add app/services/ramon/copiloto_modo.rb enterprise/lib/captain/tools/base_public_tool.rb \
  enterprise/app/services/captain/assistant/agent_runner_service.rb enterprise/app/jobs/captain/conversation/response_builder_job.rb \
  spec/services/ramon/copiloto_modo_spec.rb spec/services/ramon/roteiro_spec.rb
git commit -m "fix(copiloto): ferramenta que falhou no turno faz a resposta virar rascunho (fail-safe da spec)"
```

---

### Task 5: Reabrir respeita o limite do modo + trocar a tese zera o roteiro na hora

**Files:**
- Modify: `app/services/ramon/roteiro.rb` (`reabrir`)
- Modify: `app/services/ramon/roteiro/efeitos.rb` (`reabrir` + `devolver_ao_robo`)
- Modify: `app/services/ramon/copiloto_limite.rb` (`desfazer`)
- Modify: `app/models/concerns/lead_roteiro.rb` (callback)
- Modify: `spec/services/ramon/roteiro_reabrir_spec.rb` (4 exemplos)
- Modify: `spec/services/ramon/roteiro_spec.rb` (1 exemplo)

**Interfaces:**
- Consumes: `Ramon::CopilotoModo.restaurar`, `Efeitos.tirar_etiqueta` (Task 2); `Ramon::Roteiro::QUALIFICADO/HUMANO`, `CopilotoLimite::QUALIFICACAO` (Task 1).
- Produces:
  - `Ramon::Roteiro::Efeitos.reabrir(lead, desfecho)` (a assinatura muda: recebe o desfecho reaberto)
  - `Ramon::CopilotoLimite.desfazer(conversa, limite)`: volta o modo do carimbo e apaga o carimbo daquele limite
  - `Lead` `before_save :reiniciar_roteiro` (tese mudou e há roteiro gravado)

- [ ] **Step 1: Specs (falham)**

Em `spec/services/ramon/roteiro_reabrir_spec.rb`, antes do último `end`:

```ruby
  # Revisão F5 3a: tirar do Perdido direto para "Reunião agendada" no "até reunião" não volta a enviar direto.
  it 'tirar do Perdido para além do limite devolve o modo e o limite já encerra' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_ate_reuniao' })
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'sim') # modo direto: Perdido + IA calada
    expect(lead.reload.lost_at).to be_present

    lead.update!(lead_stage: account.lead_stages.find_by!(name: 'Reunião agendada'))

    expect(conversation.reload.custom_attributes).to include('copiloto_modo' => 'rascunho',
                                                             'copiloto_limite' => include('limite' => 'reuniao'))
  end

  # Revisão F5 3b: quem foi para a equipe saiu do robô (bot_handoff!); reabrir devolve ao robô no modo de antes.
  it 'reabrir quem foi para a equipe devolve a conversa ao robô no modo de antes' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_limitado' })
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(lead.reload, chave: 'sequela', valor: 'nao sei') # nada casa → equipe
    expect(conversation.reload.status).to eq('open')

    expect(Ramon::Roteiro.reabrir(lead.reload)).to be(true)
    expect(conversation.reload.status).to eq('pending')
    expect(conversation.custom_attributes['copiloto_modo']).to eq('piloto_limitado')
  end

  # Review Focus 2: modo de antes manual = a equipe segue com a conversa.
  it 'reabrir quem foi para a equipe com modo de antes manual deixa a conversa com o humano' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'manual' })
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(lead.reload, chave: 'sequela', valor: 'nao sei')

    Ramon::Roteiro.reabrir(lead.reload)
    expect(conversation.reload.status).to eq('open')
    expect(conversation.custom_attributes['copiloto_modo']).to eq('manual')
  end

  # Revisão F5 3c: reabrir um qualificado desfaz o limite que ele causou.
  it 'reabrir um qualificado no "até qualificar" apaga o carimbo e volta o modo' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_ate_qualificacao' })
    Ramon::Roteiro.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(lead.reload, chave: 'sequela', saida_id: 'ficou')
    expect(conversation.reload.custom_attributes['copiloto_limite']).to include('limite' => 'qualificacao')

    Ramon::Roteiro.reabrir(lead.reload)
    expect(conversation.reload.custom_attributes).to eq('copiloto_modo' => 'piloto_ate_qualificacao')
  end
```

Em `spec/services/ramon/roteiro_spec.rb`, depois do exemplo `'trocar a tese depois de desqualificar num comum pergunta o comum de novo'`:

```ruby
  # Revisão F5 item 5: o estado gravado zera na troca (o limite dos modos e a bi_roteiro leem o atributo cru).
  it 'trocar a tese depois do desfecho zera o roteiro gravado na hora, mantendo os comuns' do
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim')
    registrar('sequela', 'ficou', saida_id: 'ficou')
    expect(lead.reload.desfecho_roteiro).to eq('qualificado')

    bpc = create(:thesis, account: account)
    create(:roteiro_passo, account: account, thesis: bpc, chave: 'renda', position: 1)
    lead.update!(thesis: bpc)

    salvo = lead.reload.custom_attributes['roteiro']
    expect(salvo).to include('tese_id' => bpc.id, 'passo' => 'renda')
    expect(salvo.keys).not_to include('desfecho', 'motivo', 'decisivo')
    expect(salvo['respostas'].keys).to eq(['tem_advogado'])
  end
```

- [ ] **Step 2: `reabrir` com o desfecho e o limite**

Em `app/services/ramon/roteiro.rb`, no `reabrir`, trocar `Efeitos.reabrir(lead)` por `Efeitos.reabrir(lead, est['desfecho'])`.

Em `app/services/ramon/roteiro/efeitos.rb`, trocar o método `reabrir` inteiro (o da Task 2) por:

```ruby
  # Roteiro reaberto (Ramon::Roteiro.reabrir): devolve o modo de antes, desfaz o limite "qualificação" que o desfecho
  # causou e tira a etiqueta de desqualificado; o caso que tinha ido para a equipe volta ao robô. No fim confere o
  # limite do modo de novo — o lead pode já estar além dele (ex.: tirado do Perdido direto para "Reunião agendada").
  def reabrir(lead, desfecho)
    conversa = lead.conversation
    if conversa
      Ramon::CopilotoModo.restaurar(conversa)
      Ramon::CopilotoLimite.desfazer(conversa, Ramon::CopilotoLimite::QUALIFICACAO) if desfecho == Ramon::Roteiro::QUALIFICADO
      tirar_etiqueta(conversa)
      devolver_ao_robo(conversa) if desfecho == Ramon::Roteiro::HUMANO
    end
    anotar(lead, 'roteiro reaberto')
    Ramon::CopilotoLimite.verificar(lead)
  end

  # A equipe recebeu o caso pelo handoff (conversa aberta): volta ao robô se o modo restaurado deixa a IA responder.
  def devolver_ao_robo(conversa)
    conversa.update!(status: :pending) if conversa.open? && Ramon::CopilotoModo.of(conversa) != 'manual'
  end
```

Em `app/services/ramon/copiloto_limite.rb`, depois do `encerrar`:

```ruby
  # Reabrir o roteiro desfaz o limite que o desfecho causou: volta o modo de antes do carimbo e apaga o carimbo.
  def desfazer(conversa, limite)
    attrs = conversa.reload.custom_attributes || {}
    carimbo = attrs['copiloto_limite']
    return unless carimbo.is_a?(Hash) && carimbo['limite'] == limite && Ramon::CopilotoModo::MODOS.include?(carimbo['modo'])

    conversa.update!(custom_attributes: attrs.except('copiloto_limite').merge('copiloto_modo' => carimbo['modo']))
  end
```

- [ ] **Step 3: A troca de tese zera o roteiro na hora**

Em `app/models/concerns/lead_roteiro.rb`, logo depois de `extend ActiveSupport::Concern`:

```ruby

  included do
    # Spec §3.2: trocar a tese reinicia o roteiro na hora (as respostas dos comuns ficam) — o limite dos modos e a
    # bi_roteiro leem o estado gravado, não o calculado. O modo da conversa não muda.
    before_save :reiniciar_roteiro, if: -> { persisted? && will_save_change_to_thesis_id? && custom_attributes&.key?('roteiro') }
  end
```

e, antes do `end` final do módulo:

```ruby

  private

  def reiniciar_roteiro
    estado = Ramon::Roteiro.estado(self)
    estado['passo'] = Ramon::Roteiro.proximo(Ramon::Roteiro.passos(self), estado)&.chave
    self.custom_attributes = custom_attributes.merge('roteiro' => estado)
  end
```

(O `Registro#assunto` faz `@lead.update!(thesis: tese)` e logo depois relê `Ramon::Roteiro.estado(@lead)`. Com o callback, ele relê o estado já zerado, que é o mesmo resultado de antes.)

- [ ] **Step 4: Lint + commit**

```bash
rubocop-vps app/services/ramon/roteiro.rb app/services/ramon/roteiro/efeitos.rb app/services/ramon/copiloto_limite.rb \
  app/models/concerns/lead_roteiro.rb spec/services/ramon/roteiro_reabrir_spec.rb spec/services/ramon/roteiro_spec.rb
git add app/services/ramon/roteiro.rb app/services/ramon/roteiro/efeitos.rb app/services/ramon/copiloto_limite.rb \
  app/models/concerns/lead_roteiro.rb spec/services/ramon/roteiro_reabrir_spec.rb spec/services/ramon/roteiro_spec.rb
git commit -m "fix(roteiro): reabrir respeita o limite do modo e devolve ao robô; trocar a tese zera o roteiro na hora"
```

---

### Task 6: Contrato que não saiu contado à parte + `bi_roteiro` v02 + card de limites

**Files:**
- Modify: `app/services/ramon/copiloto_limite.rb` (`CONTRATO_FALHOU`)
- Modify: `app/services/ramon/contrato_automatico.rb` (`parar`)
- Modify: `spec/services/ramon/contrato_automatico_spec.rb`
- Create: `db/views/bi_roteiro_v02.sql`
- Create: `db/migrate/20261014200001_update_bi_roteiro_to_v02.rb`
- Modify: `db/schema.rb` (versão + bloco `create_view "bi_roteiro"`)
- Modify: `spec/db/bi_roteiro_view_spec.rb` (2 exemplos)
- Modify: `scripts/metabase_bi_ia_cards.py` (SQL do card de limites)

**Interfaces:**
- Consumes: `Ramon::CopilotoLimite.encerrar` (Task 1).
- Produces: `Ramon::CopilotoLimite::CONTRATO_FALHOU = 'contrato_falhou'`. A view `bi_roteiro` tem as mesmas colunas de v01, com `aguarda_equipe` agora `false` para lead perdido, mais a coluna `limite_motivo` (texto) no fim.

- [ ] **Step 1: Specs (falham)**

Em `spec/services/ramon/contrato_automatico_spec.rb`: trocar todas as ocorrências de `described_class` por `Ramon::ContratoAutomatico` (lição do CI) e, no exemplo `'cadastro incompleto: não gera, diz o que falta, encerra o modo e avisa'`, trocar

```ruby
    expect(conversation.reload.custom_attributes['copiloto_limite']).to include('limite' => 'contrato', 'motivo' => include('CPF'))
```

por

```ruby
    # Revisão F5 item 2: contrato que não saiu não conta como "contrato enviado" no Metabase.
    expect(conversation.reload.custom_attributes['copiloto_limite']).to include('limite' => 'contrato_falhou', 'motivo' => include('CPF'))
```

E, no fim do exemplo `'ZapSign fora do ar: não quebra, encerra o modo com o motivo'`:

```ruby
    expect(conversation.custom_attributes['copiloto_limite']).to include('limite' => 'contrato_falhou')
```

Em `spec/db/bi_roteiro_view_spec.rb`, antes do último `end`:

```ruby
  # Revisão F5 item 6: Perdido aprovado não fica "aguardando a equipe" (como o painel do lead).
  it 'aguarda_equipe só enquanto o lead não está perdido' do
    roteiro = { 'tese_id' => thesis.id, 'desfecho' => 'desqualificado', 'aguarda_equipe' => true, 'respostas' => {} }
    lead = create(:lead, account: account, thesis: thesis, lead_stage: novo, custom_attributes: { 'roteiro' => roteiro })
    expect(linha(lead)['aguarda_equipe']).to be(true)

    lead.update!(lead_stage: account.lead_stages.find_by!(is_lost: true), lost_reason: 'Sem viabilidade')
    expect(linha(lead)['aguarda_equipe']).to be(false)
  end

  # Revisão F5 item 2: contrato que não saiu tem limite próprio e o motivo aparece.
  it 'contrato que não saiu aparece como limite próprio, com o motivo' do
    limite = { 'limite' => 'contrato_falhou', 'modo' => 'piloto_ate_contrato', 'motivo' => 'CPF, rua', 'em' => '2026-10-14T11:00:00-03:00' }
    lead = create(:lead, account: account, thesis: thesis, lead_stage: novo, conversation: conversa('copiloto_limite' => limite))
    expect(linha(lead)).to include('limite_atingido' => 'contrato_falhou', 'limite_motivo' => 'CPF, rua')
  end
```

- [ ] **Step 2: Limite próprio para o contrato que não saiu**

Em `app/services/ramon/copiloto_limite.rb`, trocar

```ruby
  NOMES = { QUALIFICACAO => 'lead qualificado', REUNIAO => 'reunião marcada', CONTRATO => 'contrato enviado' }.freeze
```

por

```ruby
  # O contrato automático não saiu (falta dado ou o ZapSign falhou): encerra o modo como um limite, mas conta à parte
  # (bi_roteiro, card de limites) — 'contrato' fica só para o contrato que de fato saiu.
  CONTRATO_FALHOU = 'contrato_falhou'.freeze
  NOMES = { QUALIFICACAO => 'lead qualificado', REUNIAO => 'reunião marcada', CONTRATO => 'contrato enviado',
            CONTRATO_FALHOU => 'contrato não saiu na hora' }.freeze
```

Em `app/services/ramon/contrato_automatico.rb`, no `parar`, trocar

```ruby
    Ramon::CopilotoLimite.encerrar(lead, 'contrato', "contrato nao saiu na hora: falta #{falta.join(', ')}")
```

por

```ruby
    Ramon::CopilotoLimite.encerrar(lead, Ramon::CopilotoLimite::CONTRATO_FALHOU, falta.join(', '))
```

(O sino fica: "IA chegou ao limite (contrato não saiu na hora) com <lead>: CPF, rua - conversa em rascunho".)

- [ ] **Step 3: View v02, migração e schema**

`db/views/bi_roteiro_v02.sql`:

```sql
-- Roteiro da tese por lead (spec 2026-10-13 §3.9; v01 = F4). Fonte: leads.custom_attributes->'roteiro' (motor F1;
-- 'passo' = próximo a perguntar) e o carimbo copiloto_limite da conversa (F3). Sem o texto das respostas (spec §5).
-- v02 (F5): aguarda_equipe só enquanto o lead não está perdido (como o painel do lead) e limite_motivo = o motivo do
-- carimbo (ex.: o que faltou quando o contrato não saiu na hora, limite 'contrato_falhou').
SELECT l.id AS lead_id,
       l.account_id,
       l.conversation_id,
       l.created_at AS lead_criado_em,
       l.custom_attributes ? 'roteiro' AS em_roteiro,
       (l.custom_attributes #>> '{roteiro,tese_id}')::bigint AS thesis_id,
       t.name AS thesis_name,
       l.custom_attributes #>> '{roteiro,passo}' AS passo_atual,
       l.custom_attributes #>> '{roteiro,desfecho}' AS desfecho,
       l.custom_attributes #>> '{roteiro,motivo}' AS motivo,
       l.custom_attributes #>> '{roteiro,decisivo}' AS passo_decisivo,
       COALESCE((l.custom_attributes #>> '{roteiro,aguarda_equipe}')::boolean, false) AND l.lost_at IS NULL AS aguarda_equipe,
       r.respondidos,
       r.iniciado_em,
       r.ultima_resposta_em,
       c.custom_attributes ->> 'copiloto_modo' AS modo,
       c.custom_attributes #>> '{copiloto_limite,limite}' AS limite_atingido,
       (c.custom_attributes #>> '{copiloto_limite,em}')::timestamptz AS limite_em,
       c.custom_attributes #>> '{copiloto_limite,motivo}' AS limite_motivo
FROM leads l
LEFT JOIN theses t ON t.id = (l.custom_attributes #>> '{roteiro,tese_id}')::bigint
LEFT JOIN conversations c ON c.id = l.conversation_id
CROSS JOIN LATERAL (
  SELECT COUNT(*) AS respondidos,
         MIN((e.v ->> 'em')::timestamptz) AS iniciado_em,
         MAX((e.v ->> 'em')::timestamptz) AS ultima_resposta_em
  FROM jsonb_each(COALESCE(l.custom_attributes #> '{roteiro,respostas}', '{}'::jsonb)) AS e(chave, v)
) r
WHERE l.custom_attributes ? 'roteiro' OR c.custom_attributes ? 'copiloto_limite'
```

`db/migrate/20261014200001_update_bi_roteiro_to_v02.rb`:

```ruby
# bi_roteiro v02 (roteiro F5): aguarda_equipe some com o Perdido aprovado e entra limite_motivo (contrato que não saiu).
class UpdateBiRoteiroToV02 < ActiveRecord::Migration[7.1]
  def change
    update_view :bi_roteiro, version: 2, revert_to_version: 1
  end
end
```

`db/schema.rb`:
- topo: `ActiveRecord::Schema[7.1].define(version: 2026_10_14_200001) do`
- no bloco `create_view "bi_roteiro", sql_definition: <<-SQL … SQL`, trocar a linha

```
      COALESCE(((l.custom_attributes #>> '{roteiro,aguarda_equipe}'::text[]))::boolean, false) AS aguarda_equipe,
```

por

```
      (COALESCE(((l.custom_attributes #>> '{roteiro,aguarda_equipe}'::text[]))::boolean, false) AND (l.lost_at IS NULL)) AS aguarda_equipe,
```

e a linha

```
      ((c.custom_attributes #>> '{copiloto_limite,em}'::text[]))::timestamp with time zone AS limite_em
```

por

```
      ((c.custom_attributes #>> '{copiloto_limite,em}'::text[]))::timestamp with time zone AS limite_em,
      (c.custom_attributes #>> '{copiloto_limite,motivo}'::text[]) AS limite_motivo
```

- [ ] **Step 4: Card de limites mostra o contrato que não saiu**

Em `scripts/metabase_bi_ia_cards.py`, no `CARDS_ROTEIRO`, trocar o valor do card `"Roteiro: limites atingidos nos modos 'sozinha até…' (30d)"` (mesmo nome: o script atualiza o SQL no lugar) por:

```python
    "Roteiro: limites atingidos nos modos 'sozinha até…' (30d)": dict(display="bar", sql=f"""
SELECT CASE limite_atingido WHEN 'contrato_falhou' THEN 'contrato não saiu' ELSE limite_atingido END AS limite,
       COUNT(DISTINCT conversation_id) AS conversas
FROM bi_roteiro
WHERE account_id = {ACCOUNT_ID} AND limite_atingido IS NOT NULL AND limite_em > now() - interval '30 days'
GROUP BY 1 ORDER BY 1"""),
```

Conferir:

```bash
PYTHONUTF8=1 python -m py_compile scripts/metabase_bi_ia_cards.py && echo OK
PYTHONUTF8=1 python -c "import sys; sys.path.insert(0, 'scripts'); import metabase_bi_ia_cards as m; print([(h, r, len(c)) for h, r, c in m.BLOCOS])"
```

Esperado: `OK` e `[('Inteligência — rascunhos da IA e 1ª resposta', 56, 4), ('Inteligência — roteiro da tese', 97, 4)]`.

- [ ] **Step 5: Lint + commit**

```bash
rubocop-vps app/services/ramon/copiloto_limite.rb app/services/ramon/contrato_automatico.rb \
  spec/services/ramon/contrato_automatico_spec.rb db/migrate/20261014200001_update_bi_roteiro_to_v02.rb spec/db/bi_roteiro_view_spec.rb
git add app/services/ramon/copiloto_limite.rb app/services/ramon/contrato_automatico.rb spec/services/ramon/contrato_automatico_spec.rb \
  db/views/bi_roteiro_v02.sql db/migrate/20261014200001_update_bi_roteiro_to_v02.rb db/schema.rb spec/db/bi_roteiro_view_spec.rb \
  scripts/metabase_bi_ia_cards.py
git commit -m "fix(bi): contrato que não saiu conta à parte; bi_roteiro v02 (aguarda_equipe some no Perdido, motivo do limite)"
```

---

### Task 7: O front mostra o modo que o backend usa (padrão da caixa) + contagem da tela Assistentes

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js` (conteúdo inteiro)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/copilotoModo.spec.js`
- Modify: `app/javascript/dashboard/components-next/message/PilotoCarimbo.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/CopilotoModoSelector.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/CopilotoModoSelector.spec.js`
- Modify: `app/javascript/dashboard/components-next/captain/pageComponents/inbox/ConnectInboxForm.vue`
- Modify: `app/javascript/dashboard/components-next/captain/pageComponents/inbox/specs/ConnectInboxForm.spec.js`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue`
- Modify: `app/services/ramon/copiloto_modo.rb` (`contar`)
- Modify: `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb` (`cartao`, `conversas_por_modo`)
- Modify: `spec/services/ramon/copiloto_modo_spec.rb` (2 exemplos)

**Interfaces:**
- Consumes: getter `inboxes/getInbox` (já existe; devolve `{}` sem a caixa); `inbox.ramon_copiloto_modo` no payload da caixa (F3).
- Produces:
  - JS: `copilotoModoDe(chat, inbox) -> string` (atributo → `inbox.ramon_copiloto_modo` → `modoDefault()`); `tomDoModo(modo) -> string` (classe `TOM`)
  - Ruby: `Ramon::CopilotoModo.contar(conversas) -> Hash{modo => n}`
  - API `stats` da tela Assistentes: cada caixa ganha `modo_padrao`

- [ ] **Step 1: Specs (falham)**

Em `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/copilotoModo.spec.js`, trocar a 1ª linha por

```js
import { copilotoModoDe, modoDefault, tomDoModo } from '../copilotoModo';
import { TOM } from '../ui';
```

e, antes do `});` final:

```js
  it('sem atributo vale o padrão da caixa, antes do padrão do servidor (como Ramon::CopilotoModo.of)', () => {
    window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
    expect(
      copilotoModoDe({}, { ramon_copiloto_modo: 'piloto_ate_reuniao' })
    ).toBe('piloto_ate_reuniao');
    expect(copilotoModoDe({}, { ramon_copiloto_modo: null })).toBe(
      'piloto_limitado'
    );
    expect(
      copilotoModoDe(
        { custom_attributes: { copiloto_modo: 'manual' } },
        { ramon_copiloto_modo: 'piloto_total' }
      )
    ).toBe('manual');
  });
  it('tomDoModo: uma cor por família de modo', () => {
    expect(tomDoModo('manual')).toBe(TOM.slate);
    expect(tomDoModo('rascunho')).toBe(TOM.blue);
    expect(tomDoModo('piloto_limitado')).toBe(TOM.amber);
    expect(tomDoModo('piloto_ate_contrato')).toBe(TOM.ruby);
  });
```

Em `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/CopilotoModoSelector.spec.js`, no `mountSelector`, acrescentar o parâmetro `inbox = {}` e o getter:

```js
const mountSelector = ({
  chat = { id: 42, custom_attributes: {} },
  inbox = {},
  updateCustomAttributes = vi.fn().mockResolvedValue(),
  toggleStatus = vi.fn().mockResolvedValue(),
} = {}) => {
  const store = createStore({
    state: () => ({ chat }),
    getters: {
      getSelectedChat: state => state.chat,
      'inboxes/getInbox': () => () => inbox,
    },
    actions: { updateCustomAttributes, toggleStatus },
  });
```

e um exemplo novo no `describe` principal:

```js
  it('sem atributo mostra o modo padrão da caixa (o mesmo que o servidor usa)', () => {
    const { wrapper } = mountSelector({
      chat: { id: 42, inbox_id: 7, custom_attributes: {} },
      inbox: { id: 7, ramon_copiloto_modo: 'piloto_total' },
    });
    expect(wrapper.find('[data-testid="copiloto-modo-btn"]').text()).toContain(
      'Piloto total'
    );
  });
```

Em `app/javascript/dashboard/components-next/captain/pageComponents/inbox/specs/ConnectInboxForm.spec.js`: `import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';` no topo; `const montar = (inboxes = []) => {` e `inboxes: { namespaced: true, getters: { getInboxes: () => inboxes } },`; e o exemplo novo:

```js
  it('com a caixa escolhida, avisa com o modo padrão dela', async () => {
    window.chatwootConfig = { ramonCopilotoModoDefault: 'piloto_limitado' };
    const wrapper = montar([
      { id: 7, name: 'Teste', ramon_copiloto_modo: 'piloto_ate_reuniao' },
    ]);
    await wrapper.findComponent(ComboBox).vm.$emit('update:modelValue', 7);
    expect(wrapper.find('[data-testid="aviso-conectar-caixa"]').text()).toContain(
      'RAMON.COPILOTO.MODOS.piloto_ate_reuniao.NOME'
    );
  });
```

Em `spec/services/ramon/copiloto_modo_spec.rb`, antes do último `end`:

```ruby
  # Revisão F5 item 4: tela Assistentes conta pelo modo efetivo, com o padrão de cada caixa.
  it 'contar: conversas pelo modo efetivo, com o padrão de cada caixa' do
    outra = create(:inbox, account: inbox.account, ramon_copiloto_modo: 'piloto_total')
    create(:conversation, account: inbox.account, inbox: inbox)
    create(:conversation, account: inbox.account, inbox: outra)
    create(:conversation, account: inbox.account, inbox: outra, custom_attributes: { 'copiloto_modo' => 'manual' })

    with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
      expect(Ramon::CopilotoModo.contar(inbox.account.conversations))
        .to eq('piloto_limitado' => 1, 'piloto_total' => 1, 'manual' => 1)
    end
  end

  # Front (helpers/copilotoModo.js) e backend com a mesma lista: a tela mostra o que o servidor faz.
  it 'a lista de modos do front é a mesma do backend' do
    js = Rails.root.join('app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js').read
    expect(js[/export const MODOS = \[(.*?)\];/m, 1].scan(/'([a-z_]+)'/).flatten).to eq(Ramon::CopilotoModo::MODOS)
  end
```

Rodar e ver falhar:

```bash
node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/copilotoModo.spec.js \
  app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/CopilotoModoSelector.spec.js \
  app/javascript/dashboard/components-next/captain/pageComponents/inbox/specs/ConnectInboxForm.spec.js
```

Esperado: FAIL (`tomDoModo` não existe; o seletor mostra "Rascunho"; o aviso mostra `piloto_limitado`).

- [ ] **Step 2: Um módulo JS para o modo**

`app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js` (conteúdo inteiro):

```js
import { TOM } from './ui';

// Mesma lista de Ramon::CopilotoModo::MODOS (spec/services/ramon/copiloto_modo_spec.rb confere as duas).
export const MODOS = [
  'manual',
  'rascunho',
  'piloto_limitado',
  'piloto_total',
  'piloto_ate_qualificacao',
  'piloto_ate_reuniao',
  'piloto_ate_contrato',
];

// Padrão do servidor (env RAMON_COPILOTO_MODO_DEFAULT), vindo do layout.
export const modoDefault = () => {
  const m = window.chatwootConfig?.ramonCopilotoModoDefault;
  return MODOS.includes(m) ? m : 'rascunho';
};

// Modo efetivo da conversa no front — a mesma ordem de Ramon::CopilotoModo.of: atributo da conversa → padrão da caixa
// (inbox.ramon_copiloto_modo) → padrão do servidor.
export const copilotoModoDe = (chat, inbox) => {
  const m = chat?.custom_attributes?.copiloto_modo;
  if (MODOS.includes(m)) return m;
  const daCaixa = inbox?.ramon_copiloto_modo;
  return MODOS.includes(daCaixa) ? daCaixa : modoDefault();
};

// rascunho = azul (nada sai sem humano); piloto = âmbar (limitado) ou vermelho (a IA envia).
export const tomDoModo = modo => {
  if (modo === 'manual') return TOM.slate;
  if (modo === 'rascunho') return TOM.blue;
  return modo === 'piloto_limitado' ? TOM.amber : TOM.ruby;
};
```

- [ ] **Step 3: Componentes leem a caixa da conversa**

`app/javascript/dashboard/components-next/message/PilotoCarimbo.vue`: depois de `const currentChat = useMapGetter('getSelectedChat');`:

```js
const getInbox = useMapGetter('inboxes/getInbox');
```

e trocar

```js
const aindaEmPiloto = computed(() =>
  copilotoModoDe(currentChat.value).startsWith('piloto_')
);
```

por

```js
const aindaEmPiloto = computed(() =>
  copilotoModoDe(
    currentChat.value,
    getInbox.value?.(currentChat.value?.inbox_id)
  ).startsWith('piloto_')
);
```

`app/javascript/dashboard/routes/dashboard/ramon/components/conversation/CopilotoModoSelector.vue`: depois de `const currentChat = useMapGetter('getSelectedChat');`:

```js
const getInbox = useMapGetter('inboxes/getInbox');
```

e trocar `const modo = computed(() => copilotoModoDe(currentChat.value));` por

```js
// Sem atributo vale o padrão da caixa — o mesmo que o servidor usa (Ramon::CopilotoModo.of).
const modo = computed(() =>
  copilotoModoDe(
    currentChat.value,
    getInbox.value?.(currentChat.value?.inbox_id)
  )
);
```

`app/javascript/dashboard/components-next/captain/pageComponents/inbox/ConnectInboxForm.vue`: trocar o import `import { modoDefault } from …copilotoModo';` por `import { copilotoModoDe } from 'dashboard/routes/dashboard/ramon/helpers/copilotoModo';` e o `avisoConexao` inteiro por:

```js
// Conectar liga a IA na caixa na hora — o aviso diz em que modo as conversas novas nascem: o padrão da caixa
// escolhida, senão o do servidor (Ramon::CopilotoModo.default).
const avisoConexao = computed(() => {
  const caixa = formState.inboxes.value.find(
    inbox => inbox.id === state.inboxId
  );
  return t('CAPTAIN.INBOXES.FORM.AVISO_RASCUNHO', {
    modo: t(`RAMON.COPILOTO.MODOS.${copilotoModoDe({}, caixa)}.NOME`),
  });
});
```

`app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue`:
- trocar o import `{ MODOS, modoDefault }` por `{ MODOS, tomDoModo }`;
- apagar o bloco `// rascunho = azul …` + `const MODO_TOM = { … };`;
- depois de `const modoNome = …`, acrescentar:

```js
// Modo em que as conversas novas nascem: o padrão de cada caixa do assistente (Ramon::CopilotoModo.default).
const modosPadrao = cartao =>
  [...new Set(cartao.caixas.map(caixa => caixa.modo_padrao))]
    .map(modoNome)
    .join(', ');
```

- no template, trocar `modo: modoNome(modoDefault()),` por `modo: modosPadrao(cartao),` e `:class="[CHIP, MODO_TOM[item.modo]]"` por `:class="[CHIP, tomDoModo(item.modo)]"`.

- [ ] **Step 4: Contagem no backend**

Em `app/services/ramon/copiloto_modo.rb`, antes do `trocar`:

```ruby
  # Conversas por modo efetivo, em lote (tela Assistentes): atributo válido → padrão da caixa → env — o mesmo que .of.
  def contar(conversas)
    padroes = Inbox.where(id: conversas.distinct.pluck(:inbox_id)).to_h { |caixa| [caixa.id, default(caixa)] }
    conversas.group(:inbox_id, Arel.sql("conversations.custom_attributes->>'copiloto_modo'")).count
             .each_with_object(Hash.new(0)) do |((caixa, modo), total), soma|
      soma[MODOS.include?(modo) ? modo : padroes.fetch(caixa) { default }] += total
    end
  end
```

Em `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb`, no `cartao`, trocar

```ruby
    caixas = assistant.inboxes.order(:id).pluck(:id, :name, :channel_type)
                      .map { |id, name, tipo| { id: id, name: name, channel_type: tipo } }
```

por

```ruby
    caixas = assistant.inboxes.order(:id).map do |caixa|
      { id: caixa.id, name: caixa.name, channel_type: caixa.channel_type, modo_padrao: Ramon::CopilotoModo.default(caixa) }
    end
```

e o `conversas_por_modo` inteiro (com o comentário) por:

```ruby
  # Conversas abertas nas caixas do assistente pelo modo efetivo, com o padrão de cada caixa (Ramon::CopilotoModo.contar).
  def conversas_por_modo(inbox_ids)
    Ramon::CopilotoModo.contar(Current.account.conversations.where(status: :open, inbox_id: inbox_ids))
  end
```

- [ ] **Step 5: Rodar, lint e commit**

```bash
node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/copilotoModo.spec.js \
  app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/CopilotoModoSelector.spec.js \
  app/javascript/dashboard/components-next/captain/pageComponents/inbox/specs/ConnectInboxForm.spec.js \
  app/javascript/dashboard/components-next/message/specs/PilotoCarimbo.spec.js
node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js \
  app/javascript/dashboard/components-next/message/PilotoCarimbo.vue \
  app/javascript/dashboard/routes/dashboard/ramon/components/conversation/CopilotoModoSelector.vue \
  app/javascript/dashboard/components-next/captain/pageComponents/inbox/ConnectInboxForm.vue \
  app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue
rubocop-vps app/services/ramon/copiloto_modo.rb enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb \
  spec/services/ramon/copiloto_modo_spec.rb
```

Esperado: vitest PASS (as specs antigas do seletor e do carimbo continuam passando, porque o getter ausente vira `undefined?.()`); eslint e rubocop sem ofensas.

```bash
git add app/javascript/dashboard/routes/dashboard/ramon/helpers/copilotoModo.js \
  app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/copilotoModo.spec.js \
  app/javascript/dashboard/components-next/message/PilotoCarimbo.vue \
  app/javascript/dashboard/routes/dashboard/ramon/components/conversation/CopilotoModoSelector.vue \
  app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/CopilotoModoSelector.spec.js \
  app/javascript/dashboard/components-next/captain/pageComponents/inbox/ConnectInboxForm.vue \
  app/javascript/dashboard/components-next/captain/pageComponents/inbox/specs/ConnectInboxForm.spec.js \
  app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue app/services/ramon/copiloto_modo.rb \
  enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb spec/services/ramon/copiloto_modo_spec.rb
git commit -m "fix(copiloto): a tela mostra o modo que o servidor usa (padrão da caixa) e a contagem segue a caixa"
```

---

### Task 8: Modelo de contrato do ZapSign na tela da tese (Playbooks)

**Files:**
- Modify: `app/controllers/api/v1/accounts/theses_controller.rb` (`permitted_params`)
- Modify: `app/views/api/v1/accounts/theses/show.json.jbuilder`
- Modify: `app/models/thesis.rb` (`normalizes`)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` (`RAMON.PLAYBOOKS`)
- Modify: `spec/requests/api/v1/accounts/theses_controller_spec.rb`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js`

**Interfaces:**
- Consumes: `LeadsAPI.zapsignTemplates()` → `[{ token, name }]` (`GET /leads/zapsign_templates`, que já existe).
- Produces: `PATCH /theses/:id` aceita `zapsign_template_id` (vazio vira `nil`); o `show` devolve `zapsign_template_id`.

- [ ] **Step 1: Specs (falham)**

Em `spec/requests/api/v1/accounts/theses_controller_spec.rb`, antes do último `end`:

```ruby
  describe 'modelo de contrato do ZapSign (roteiro F5)' do
    it 'grava, devolve no show e limpa com vazio' do
      thesis = account.theses.create!(name: 'Tese Modelo', position: 61)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", params: { zapsign_template_id: 'modelo-aa' },
                                                                  headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['zapsign_template_id']).to eq('modelo-aa')

      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", params: { zapsign_template_id: '' },
                                                                  headers: admin.create_new_auth_token, as: :json
      expect(thesis.reload.zapsign_template_id).to be_nil
    end
  end
```

Em `app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js`, depois do `vi.mock('dashboard/api/roteiroPassos', …)`:

```js
vi.mock('dashboard/api/leads', () => ({
  default: {
    zapsignTemplates: vi.fn(() =>
      Promise.resolve({
        data: [{ token: 'modelo-aa', name: 'Contrato auxílio-acidente' }],
      })
    ),
  },
}));
```

e antes do `});` final:

```js
  it('escolhe o modelo de contrato do ZapSign da tese', async () => {
    const { wrapper, store } = mountPlaybooks();
    await flushPromises();
    await wrapper.findAll('[data-testid="playbooks-item"]')[0].trigger('click');
    const campo = wrapper.find('[data-testid="playbooks-zapsign-modelo"]');
    expect(campo.text()).toContain('Contrato auxílio-acidente');

    await campo.setValue('modelo-aa');
    expect(store.dispatch).toHaveBeenLastCalledWith(
      'theses/update',
      expect.objectContaining({ id: 1, zapsign_template_id: 'modelo-aa' })
    );
  });
```

```bash
node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js
```

Esperado: FAIL (o campo não existe).

- [ ] **Step 2: Backend**

`app/controllers/api/v1/accounts/theses_controller.rb`, no `permitted_params`:

```ruby
    params.permit(:name, :description, :area, :active, :honorario_percentual, :honorario_n_mensalidades,
                  :honorario_minimo_qtd, :honorario_minimo_base, :honorario_na_tabela, :zapsign_template_id, palavras_chave: [])
```

`app/views/api/v1/accounts/theses/show.json.jbuilder`, depois de `json.palavras_chave @thesis.palavras_chave`:

```ruby
json.zapsign_template_id @thesis.zapsign_template_id
```

`app/models/thesis.rb`, depois das associações:

```ruby
  # Modelo do ZapSign do modo "sozinha até o contrato" (F3); vazio na tela = sem modelo.
  normalizes :zapsign_template_id, with: ->(v) { v.presence }
```

- [ ] **Step 3: Tela**

Em `app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue`:
- import, depois de `import RoteiroPassosAPI from 'dashboard/api/roteiroPassos';`: `import LeadsAPI from 'dashboard/api/leads';`
- no `detail` (reactive), depois de `palavrasChave: '',`: `zapsignTemplateId: '',`
- no `syncDetail`, depois de `detail.palavrasChave = …`: `detail.zapsignTemplateId = thesis.zapsign_template_id || '';`
- no `saveDetail`, depois de `palavras_chave: textoParaLista(detail.palavrasChave),`: `zapsign_template_id: detail.zapsignTemplateId || null,`
- depois do `saveActive`:

```js
// Modelos do ZapSign (a mesma lista do painel do lead) — o modo "sozinha até o contrato" usa o da tese. Valor salvo que
// não vier na lista (ZapSign fora do ar, modelo apagado) aparece pelo id.
const modelosZapsign = ref([]);
const modelosErro = ref(false);
const carregarModelos = async () => {
  try {
    const { data } = await LeadsAPI.zapsignTemplates();
    modelosZapsign.value = data;
  } catch {
    modelosErro.value = true;
  }
};
const opcoesModelo = computed(() => {
  const atual = detail.zapsignTemplateId;
  const lista = modelosZapsign.value;
  return atual && !lista.some(tpl => tpl.token === atual)
    ? [...lista, { token: atual, name: atual }]
    : lista;
});
```

- no `onMounted`, depois de `store.dispatch('leadConfig/get');`: `carregarModelos();`
- no template, logo depois do `<p data-testid="playbooks-honorario-padrao" …>…</p>`:

```vue
              <label
                :class="ROTULO"
                :title="$t('RAMON.PLAYBOOKS.ZAPSIGN_MODELO_AJUDA')"
              >
                {{ $t('RAMON.PLAYBOOKS.ZAPSIGN_MODELO') }}
                <select
                  v-model="detail.zapsignTemplateId"
                  data-testid="playbooks-zapsign-modelo"
                  :class="CAMPO"
                  @change="saveDetail"
                >
                  <option value="">
                    {{ $t('RAMON.PLAYBOOKS.ZAPSIGN_SEM_MODELO') }}
                  </option>
                  <option
                    v-for="tpl in opcoesModelo"
                    :key="tpl.token"
                    :value="tpl.token"
                  >
                    {{ tpl.name }}
                  </option>
                </select>
              </label>
              <p
                v-if="modelosErro"
                data-testid="playbooks-zapsign-erro"
                :class="[AVISO, TOM.amber]"
              >
                {{ $t('RAMON.PLAYBOOKS.ZAPSIGN_MODELOS_ERRO') }}
              </p>
```

Em `app/javascript/dashboard/i18n/locale/en/ramon.json`, no bloco `RAMON.PLAYBOOKS`, depois de `"HONORARIO_NA_TABELA": …,`:

```json
      "ZAPSIGN_MODELO": "Contract template (ZapSign)",
      "ZAPSIGN_MODELO_AJUDA": "Used by \"on its own until the contract\" to generate the contract on the spot. No template = the contract never goes out automatically for this thesis.",
      "ZAPSIGN_SEM_MODELO": "No template",
      "ZAPSIGN_MODELOS_ERRO": "Couldn't load the ZapSign templates right now — the saved one is kept.",
```

- [ ] **Step 4: Rodar, lint e commit**

```bash
node_modules/.bin/vitest run --no-cache app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js
node_modules/.bin/eslint app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue
rubocop-vps app/controllers/api/v1/accounts/theses_controller.rb app/models/thesis.rb spec/requests/api/v1/accounts/theses_controller_spec.rb
git add app/controllers/api/v1/accounts/theses_controller.rb app/views/api/v1/accounts/theses/show.json.jbuilder app/models/thesis.rb \
  app/javascript/dashboard/routes/dashboard/ramon/pages/Playbooks.vue app/javascript/dashboard/i18n/locale/en/ramon.json \
  spec/requests/api/v1/accounts/theses_controller_spec.rb app/javascript/dashboard/routes/dashboard/ramon/pages/specs/Playbooks.spec.js
git commit -m "feat(playbooks): modelo de contrato do ZapSign por tese na tela"
```

---

### Task 9: Testar sem tese (passos comuns, inclusive o "assunto") e com o modo simulado

**Files:**
- Modify: `app/services/ramon/roteiro/teste.rb` (`de_params`, `com_lead`)
- Modify: `app/models/concerns/lead_roteiro.rb` (`copiloto_modo_simulado`)
- Modify: `spec/services/ramon/roteiro/teste_spec.rb` (1 exemplo trocado, 2 novos)
- Modify: `app/javascript/dashboard/components-next/captain/assistant/testarConversas.js` (conteúdo inteiro)
- Modify: `app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/playground/Index.vue`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` (`RAMON.ROTEIRO_IA.TESTAR`)
- Modify: `app/javascript/dashboard/components-next/captain/assistant/specs/testarConversas.spec.js`
- Modify: `app/javascript/dashboard/components-next/captain/assistant/specs/AssistantPlayground.spec.js`

**Interfaces:**
- Consumes: `Teste.com_lead` (Task 3); `Lead#copiloto_modo` (Task 1); `Efeitos.desqualificacao` (Task 2).
- Produces:
  - `Ramon::Roteiro::Teste.de_params(account, roteiro) -> nil | { 'thesis_id' => id|nil, 'estado' => Hash|nil, 'modo' => String }`. Devolve nil sem `roteiro` ou com tese de outra conta. `thesis_id` nil é lead sem tese. `modo` é um dos `CopilotoModo::MODOS` (padrão `rascunho`).
  - `com_lead` grava em `teste` o `estado` e o `thesis_id` depois do bloco (o "assunto" pode ter escolhido a tese).
  - `Lead#copiloto_modo_simulado` (atributo virtual): `copiloto_modo` sem conversa devolve esse valor.
  - JS: `SEM_TESE = 'sem_tese'`; `escolherRoteiro(id, selecao)`; `pedidoDoRoteiro(roteiro) -> null | { thesis_id, estado, modo }`; o `roteiroDe(id)` passa a ser `{ selecao, modo, thesisId, estado, painel }`.

- [ ] **Step 1: Specs Ruby (falham)**

Em `spec/services/ramon/roteiro/teste_spec.rb`, trocar o exemplo `'de_params: …'` inteiro por:

```ruby
  it 'de_params: tese da conta ou lead sem tese; tese de outra conta ou nada = sem teste; modo do Testar' do
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: create(:thesis, account: create(:account)).id })).to be_nil
    expect(Ramon::Roteiro::Teste.de_params(account, nil)).to be_nil
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: thesis.id, estado: { 'respostas' => {} } }))
      .to eq('thesis_id' => thesis.id, 'estado' => { 'respostas' => {} }, 'modo' => 'rascunho')
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: '', modo: 'piloto_total' }))
      .to eq('thesis_id' => nil, 'estado' => nil, 'modo' => 'piloto_total')
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: thesis.id, modo: 'xablau' })['modo']).to eq('rascunho')
  end

  # Revisão F5 item 9 + Review Focus 5: lead sem tese roda os comuns; a tese que o "assunto" escolhe volta no teste.
  it 'sem tese: o assunto escolhe a tese e as próximas mensagens seguem nela' do
    thesis.update!(palavras_chave: ['xablau'])
    create(:roteiro_passo, account: account, thesis: nil, chave: 'assunto', position: 0, titulo: 'Assunto', tipo_resposta: 'texto')
    sem_tese = Ramon::Roteiro::Teste.de_params(account, { thesis_id: '' })
    expect(atual(sem_tese)).to include('chave: assunto')

    registrar(sem_tese, chave: 'assunto', valor: 'quero saber do xablau')
    expect(sem_tese['thesis_id']).to eq(thesis.id)
    expect(atual(sem_tese)).to include('Passo atual: Recebeu')
    expect([Lead.count, thesis.leads.count]).to eq([0, 0])
  end

  it 'modo simulado: em piloto total o Perdido vale na hora (sem aguardar a equipe); em rascunho vira sugestão' do
    outra = create(:thesis, account: account)
    create(:roteiro_passo, account: account, thesis: outra, chave: 'advogado', position: 0, titulo: 'Advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado' }])
    direto = Ramon::Roteiro::Teste.de_params(account, { thesis_id: outra.id, modo: 'piloto_total' })
    rascunho = Ramon::Roteiro::Teste.de_params(account, { thesis_id: outra.id })

    registrar(direto, chave: 'advogado', valor: 'sim')
    registrar(rascunho, chave: 'advogado', valor: 'sim')
    expect(direto['estado']).not_to have_key('aguarda_equipe')
    expect(rascunho['estado']).to include('aguarda_equipe' => true)
    expect([Lead.count, CopilotSuggestion.count]).to eq([0, 0])
  end
```

- [ ] **Step 2: Backend do Testar**

Em `app/services/ramon/roteiro/teste.rb`, trocar o comentário `# teste = { 'thesis_id' => id, 'estado' => estado do roteiro ou nil }` por `# teste = { 'thesis_id' => id ou nil (lead sem tese), 'estado' => estado do roteiro ou nil, 'modo' => modo simulado }`. Trocar o `de_params` inteiro (com o comentário) por:

```ruby
  # Do corpo do playground. nil = Testar sem roteiro (ou tese de outra conta). thesis_id vazio = lead sem tese: roda os
  # passos comuns, inclusive o "assunto". modo = o simulado (rascunho; piloto_total aplica etapa/Perdido na hora).
  def de_params(account, roteiro)
    roteiro = (roteiro || {}).to_h.with_indifferent_access
    return if roteiro.empty?

    tese = account.theses.find_by(id: roteiro[:thesis_id]) if roteiro[:thesis_id].present?
    return if roteiro[:thesis_id].present? && tese.nil?

    modo = Ramon::CopilotoModo::MODOS.include?(roteiro[:modo]) ? roteiro[:modo] : Ramon::CopilotoModo::DEFAULT
    { 'thesis_id' => tese&.id, 'estado' => roteiro[:estado].presence&.to_hash, 'modo' => modo }
  end
```

e, no `com_lead`, trocar

```ruby
      resultado = yield lead
      teste['estado'] = lead.reload.custom_attributes['roteiro']
```

por

```ruby
      lead.copiloto_modo_simulado = teste['modo']
      resultado = yield lead
      lead.reload
      # o "assunto" pode ter escolhido a tese do lead sem tese: ela vale nas próximas mensagens do Testar
      teste.merge!('estado' => lead.custom_attributes['roteiro'], 'thesis_id' => lead.thesis_id)
```

Em `app/models/concerns/lead_roteiro.rb`, no bloco `included do`, depois do `before_save`:

```ruby
    # Testar (Ramon::Roteiro::Teste): o lead descartável não tem conversa; o modo simulado faz etapa e Perdido se
    # comportarem como no modo escolhido.
    attr_accessor :copiloto_modo_simulado
```

e trocar o `copiloto_modo` (com o comentário) por:

```ruby
  # Modo efetivo da IA na conversa do lead (Ramon::CopilotoModo.of: atributo → caixa → env); sem conversa, o modo
  # simulado do Testar (nil fora dele).
  def copiloto_modo
    conversation ? Ramon::CopilotoModo.of(conversation) : copiloto_modo_simulado
  end
```

- [ ] **Step 3: Specs do front (falham)**

`app/javascript/dashboard/components-next/captain/assistant/specs/testarConversas.spec.js`: trocar o import por

```js
import {
  SEM_TESE,
  conversaDe,
  escolherRoteiro,
  garantirConversa,
  limparConversa,
  pedidoDoRoteiro,
  roteiroDe,
} from '../testarConversas';
```

e o exemplo `'roteiro do Testar: limpar a conversa zera o estado e mantém a tese'` inteiro por:

```js
  it('roteiro do Testar: limpar zera o estado e volta à tese da seleção', () => {
    garantirConversa(1);
    escolherRoteiro(1, SEM_TESE);
    // o "assunto" escolheu a tese 3 durante a conversa
    Object.assign(roteiroDe(1), { thesisId: 3, estado: { a: 1 }, painel: {} });
    limparConversa(1);
    expect(roteiroDe(1)).toEqual({
      selecao: SEM_TESE,
      modo: 'rascunho',
      thesisId: null,
      estado: null,
      painel: null,
    });
    escolherRoteiro(1, '');
  });

  it('pedidoDoRoteiro: nada sem seleção; lead sem tese manda thesis_id nulo e o modo', () => {
    garantirConversa(1);
    expect(pedidoDoRoteiro(roteiroDe(1))).toBeNull();
    escolherRoteiro(1, '5');
    roteiroDe(1).modo = 'piloto_total';
    expect(pedidoDoRoteiro(roteiroDe(1))).toEqual({
      thesis_id: 5,
      estado: null,
      modo: 'piloto_total',
    });
    escolherRoteiro(1, SEM_TESE);
    expect(pedidoDoRoteiro(roteiroDe(1)).thesis_id).toBeNull();
    escolherRoteiro(1, '');
    roteiroDe(1).modo = 'rascunho';
  });
```

`app/javascript/dashboard/components-next/captain/assistant/specs/AssistantPlayground.spec.js`: trocar o import de `../testarConversas` por

```js
import {
  SEM_TESE,
  conversaDe,
  escolherRoteiro,
  limparConversa,
  roteiroDe,
} from '../testarConversas';
```

No exemplo `'roteiro em teste: manda a tese e o estado, guarda o que volta'`: trocar `roteiroDe(1).thesisId = 3;` por `escolherRoteiro(1, '3');`, `roteiro: { thesis_id: 3, estado: null }` por `roteiro: { thesis_id: 3, estado: null, modo: 'rascunho' }` e a última linha `roteiroDe(1).thesisId = null;` por `escolherRoteiro(1, '');`. No exemplo `'roteiro em teste: resposta atrasada de outra tese não grava o estado'`: trocar `roteiroDe(1).thesisId = 3;` por `escolherRoteiro(1, '3');`, `roteiroDe(1).thesisId = 4;` por `escolherRoteiro(1, '4');` e a última linha por `escolherRoteiro(1, '');`. E acrescentar:

```js
  it('lead sem tese: manda thesis_id nulo e guarda a tese que o assunto escolheu', async () => {
    CaptainAssistant.playground.mockResolvedValue({
      data: {
        response: 'Entendi!',
        roteiro: { thesis_id: 9, estado: { tese_id: 9 }, painel: { passos: [] } },
      },
    });
    const wrapper = mount(AssistantPlayground, { props: { assistantId: 1 } });
    escolherRoteiro(1, SEM_TESE);
    await enviar(wrapper, 'sofri um acidente de trabalho');
    await flushPromises();
    expect(CaptainAssistant.playground).toHaveBeenCalledWith(
      expect.objectContaining({
        roteiro: { thesis_id: null, estado: null, modo: 'rascunho' },
      })
    );
    expect(roteiroDe(1)).toMatchObject({ selecao: SEM_TESE, thesisId: 9 });
    escolherRoteiro(1, '');
  });
```

```bash
node_modules/.bin/vitest run --no-cache app/javascript/dashboard/components-next/captain/assistant/specs/testarConversas.spec.js \
  app/javascript/dashboard/components-next/captain/assistant/specs/AssistantPlayground.spec.js
```

Esperado: FAIL (`escolherRoteiro` não existe).

- [ ] **Step 4: Front do Testar**

`app/javascript/dashboard/components-next/captain/assistant/testarConversas.js` (conteúdo inteiro):

```js
// Conversas do Testar (I-PG3): ficam guardadas enquanto a página do hub estiver aberta — trocar de tela
// ou de assistente não apaga. ponytail: memória da página (F5 ou fechar a aba limpa); nada do caso fica
// gravado no navegador. Upgrade, se pedirem sobreviver ao F5: sessionStorage por assistente.
import { reactive } from 'vue';

const conversas = reactive({});
// Roteiro em teste (F2/F5): a seleção ('' = sem roteiro · SEM_TESE = lead sem tese · id da tese), o modo simulado e
// o que o servidor devolve a cada resposta (nada é gravado). thesisId muda quando o "assunto" escolhe a tese.
const roteiros = reactive({});
export const SEM_TESE = 'sem_tese';
const teseDa = selecao =>
  selecao && selecao !== SEM_TESE ? Number(selecao) : null;

export const garantirConversa = id => {
  if (!conversas[id]) conversas[id] = [];
  if (!roteiros[id])
    roteiros[id] = {
      selecao: '',
      modo: 'rascunho',
      thesisId: null,
      estado: null,
      painel: null,
    };
};

export const conversaDe = id => conversas[id] || [];

export const roteiroDe = id => roteiros[id];

// Trocar a seleção recomeça o roteiro do teste (a conversa fica — limpe-a para começar do zero).
export const escolherRoteiro = (id, selecao) => {
  Object.assign(roteiros[id], {
    selecao,
    thesisId: teseDa(selecao),
    estado: null,
    painel: null,
  });
};

// O que vai no corpo do playground; null = Testar sem roteiro.
export const pedidoDoRoteiro = roteiro =>
  roteiro?.selecao
    ? { thesis_id: roteiro.thesisId, estado: roteiro.estado, modo: roteiro.modo }
    : null;

export const limparConversa = id => {
  conversas[id] = [];
  // a seleção e o modo ficam; o roteiro recomeça junto com a conversa (inclusive a tese que o "assunto" escolheu)
  const roteiro = roteiros[id];
  if (roteiro)
    Object.assign(roteiro, {
      thesisId: teseDa(roteiro.selecao),
      estado: null,
      painel: null,
    });
};
```

`app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue`:
- no import de `./testarConversas`, acrescentar `pedidoDoRoteiro,` (ordem alfabética, depois de `limparConversa,`);
- no `sendMessage`, trocar

```js
  // roteiro em teste (tese escolhida no Testar): vai o estado, volta o novo — nada é gravado (F2)
  const roteiro = roteiroDe(assistantId);
```

por

```js
  // roteiro em teste (seleção do Testar): vai o estado e o modo, volta o novo — nada é gravado (F2/F5)
  const roteiro = roteiroDe(assistantId);
  const selecaoEnviada = roteiro?.selecao;
```

e

```js
      roteiro: roteiro?.thesisId
        ? { thesis_id: roteiro.thesisId, estado: roteiro.estado }
        : null,
    });
    if (
      data.roteiro &&
      roteiro &&
      data.roteiro.thesis_id === roteiro.thesisId
    ) {
      Object.assign(roteiro, {
        estado: data.roteiro.estado,
        painel: data.roteiro.painel,
      });
    }
```

por

```js
      roteiro: pedidoDoRoteiro(roteiro),
    });
    // resposta atrasada de outra seleção não grava o estado; a tese pode ter vindo do "assunto"
    if (data.roteiro && roteiro && roteiro.selecao === selecaoEnviada) {
      Object.assign(roteiro, {
        thesisId: data.roteiro.thesis_id,
        estado: data.roteiro.estado,
        painel: data.roteiro.painel,
      });
    }
```

`app/javascript/dashboard/routes/dashboard/captain/assistants/playground/Index.vue`:
- import de `testarConversas`: `{ SEM_TESE, escolherRoteiro, garantirConversa, roteiroDe }`;
- trocar o bloco `// Trocar a tese recomeça …` + `const escolherTese = …;` por:

```js
// Modos que o Testar simula (sem conversa, os "sozinha até…" não se aplicam): rascunho = etapa e Perdido viram
// sugestão; piloto total = aplicados na hora, no lead descartável.
const MODOS_DO_TESTE = ['rascunho', 'piloto_total'];
const escolherSelecao = evento =>
  escolherRoteiro(assistantId.value, evento.target.value);
const escolherModo = evento => {
  roteiro.value.modo = evento.target.value;
};
```

- no template, trocar o `<select data-testid="testar-roteiro-tese" …>…</select>` inteiro por:

```vue
          <select
            data-testid="testar-roteiro-tese"
            class="!w-60 shrink-0"
            :class="SELECT"
            :value="roteiro?.selecao || ''"
            :title="t('RAMON.ROTEIRO_IA.TESTAR.AJUDA')"
            :aria-label="t('RAMON.ROTEIRO_IA.TESTAR.AJUDA')"
            @change="escolherSelecao"
          >
            <option value="">
              {{ t('RAMON.ROTEIRO_IA.TESTAR.SEM_TESE') }}
            </option>
            <option :value="SEM_TESE">
              {{ t('RAMON.ROTEIRO_IA.TESTAR.LEAD_SEM_TESE') }}
            </option>
            <option v-for="tese in teses" :key="tese.id" :value="String(tese.id)">
              {{ tese.name }}
            </option>
          </select>
          <select
            v-if="roteiro?.selecao"
            data-testid="testar-roteiro-modo"
            class="!w-48 shrink-0"
            :class="SELECT"
            :value="roteiro.modo"
            :title="t('RAMON.ROTEIRO_IA.TESTAR.MODO_AJUDA')"
            :aria-label="t('RAMON.ROTEIRO_IA.TESTAR.MODO_AJUDA')"
            @change="escolherModo"
          >
            <option v-for="modo in MODOS_DO_TESTE" :key="modo" :value="modo">
              {{ t(`RAMON.COPILOTO.MODOS.${modo}.NOME`) }}
            </option>
          </select>
```

Em `app/javascript/dashboard/i18n/locale/en/ramon.json`, trocar o bloco `RAMON.ROTEIRO_IA.TESTAR` por:

```json
      "TESTAR": {
        "SEM_TESE": "No script",
        "LEAD_SEM_TESE": "Lead without a thesis (shared steps, incl. subject)",
        "AJUDA": "Pick a thesis (or a lead without one) for the AI to follow the script. The script really runs, but nothing is saved.",
        "MODO_AJUDA": "Mode simulated in the test: in Draft, stage changes and Lost become suggestions; in Full pilot they apply on the spot. Nothing is saved."
      }
```

- [ ] **Step 5: Rodar, lint e commit**

```bash
node_modules/.bin/vitest run --no-cache app/javascript/dashboard/components-next/captain/assistant/specs/
node_modules/.bin/eslint app/javascript/dashboard/components-next/captain/assistant/testarConversas.js \
  app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue \
  app/javascript/dashboard/routes/dashboard/captain/assistants/playground/Index.vue
rubocop-vps app/services/ramon/roteiro/teste.rb app/models/concerns/lead_roteiro.rb spec/services/ramon/roteiro/teste_spec.rb
git add app/services/ramon/roteiro/teste.rb app/models/concerns/lead_roteiro.rb spec/services/ramon/roteiro/teste_spec.rb \
  app/javascript/dashboard/components-next/captain/assistant/testarConversas.js \
  app/javascript/dashboard/components-next/captain/assistant/AssistantPlayground.vue \
  app/javascript/dashboard/routes/dashboard/captain/assistants/playground/Index.vue \
  app/javascript/dashboard/i18n/locale/en/ramon.json \
  app/javascript/dashboard/components-next/captain/assistant/specs/testarConversas.spec.js \
  app/javascript/dashboard/components-next/captain/assistant/specs/AssistantPlayground.spec.js
git commit -m "feat(testar): roteiro com lead sem tese (assunto) e modo simulado (rascunho ou piloto total)"
```

---

### Task 10: Ferramenta `registrar_dados_contrato` — a IA guarda no lead os dados do contrato

**Files:**
- Create: `app/services/ramon/dados_contrato.rb`
- Create: `spec/services/ramon/dados_contrato_spec.rb`
- Modify: `app/services/ramon/contrato_automatico.rb` (`dados_faltando`)
- Create: `enterprise/lib/captain/tools/registrar_dados_contrato_tool.rb`
- Modify: `config/agents/tools.yml`
- Modify: `enterprise/lib/captain/tools/base_public_tool.rb` (CPF mascarado no `ToolRun`)

**Interfaces:**
- Consumes: `Ramon::ZapsignContractService.new(lead).preview['faltando']` (as chaves `{{…}}` vazias); `Ramon::AvisoDaIa.avisar` (Task 2); `Lead#nome_completo?` (Task 1); a validação do `Contact#cpf` (`RamonPessoa`: `cpf: true`, única na conta, normalizada no `before_validation`).
- Produces:
  - `Ramon::DadosContrato.gravar(lead, dados) -> { erro: String } | { gravado: [campo], recusado: { campo => motivo }, falta: [..], complementar: [..] }`. `dados` aceita as chaves `nome cpf estado_civil profissao cep rua numero complemento bairro cidade uf` (String ou Symbol).
  - `Ramon::DadosContrato.texto(res) -> String` (o que a IA lê); `Ramon::DadosContrato::CPF_EM_USO`
  - `Ramon::ContratoAutomatico.dados_faltando(lead) -> [..]` (nome completo, CPF, rua, número, cidade)
  - tool `registrar_dados_contrato` (nível `interna`, sistema `funil`)

- [ ] **Step 1: Spec (falha)**

`spec/services/ramon/dados_contrato_spec.rb`:

```ruby
require 'rails_helper'

# A IA grava os dados do contrato no contato do lead (roteiro F5, item 16) — onde o painel e o ZapSign leem.
RSpec.describe 'Ramon::DadosContrato' do # rubocop:disable RSpec/DescribeClass -- constante explícita (reload no CI)
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'João', custom_attributes: { 'endereco' => { 'cep' => '88701000' } }) }
  let(:lead) { create(:lead, account: account, contact: contact) }
  let!(:admin) { create(:user, account: account, role: :administrator) }

  def gravar(dados) = Ramon::DadosContrato.gravar(lead, dados)

  # Review Focus 4: em partes, sobre o endereço do painel, e branco não apaga.
  it 'grava aos poucos no contato, onde o painel e o ZapSign leem, e diz o que falta' do
    res = gravar(nome: 'João da Silva', cpf: '529.982.247-25', rua: 'Rua das Flores', uf: 'sc')
    expect(res[:gravado]).to contain_exactly('nome', 'cpf', 'rua', 'uf')
    expect(res[:falta]).to eq(%w[número cidade])
    expect([contact.reload.name, contact.cpf]).to eq(['João da Silva', '52998224725'])
    expect(contact.custom_attributes['endereco']).to eq('cep' => '88701000', 'rua' => 'Rua das Flores', 'uf' => 'SC')

    res = gravar('numero' => '100', 'cidade' => 'Tubarão', 'estado_civil' => 'casado', 'profissao' => '')
    expect(res.slice(:falta, :complementar)).to eq(falta: [], complementar: %w[profissão bairro])
    expect(contact.reload.custom_attributes).to include('estado_civil' => 'casado',
                                                         'endereco' => include('numero' => '100', 'rua' => 'Rua das Flores'))
  end

  it 'nome de uma palavra e CPF inválido não são gravados; o resto é' do
    res = gravar(nome: 'João', cpf: '111.111.111-11', cidade: 'Tubarão')
    expect(res[:recusado].keys).to eq(%w[nome cpf])
    expect(res[:gravado]).to eq(['cidade'])
    expect(contact.reload.cpf).to be_nil
    expect(Ramon::DadosContrato.texto(res)).to include('Nao gravei nome').and include('Ainda falta para o contrato: nome completo, CPF')
  end

  # Review Focus 3: CPF de outra pessoa nunca troca de dono nem sobrescreve.
  it 'CPF de outro contato da conta: não grava, avisa a equipe e manda a IA passar para humano' do
    create(:contact, account: account, cpf: '52998224725')
    res = gravar(cpf: '529.982.247-25', rua: 'Rua A')

    expect(res[:recusado]).to eq('cpf' => Ramon::DadosContrato::CPF_EM_USO)
    expect(contact.reload.cpf).to be_nil
    expect(contact.custom_attributes['endereco']).to include('rua' => 'Rua A')
    expect(Notification.where(user: admin, primary_actor: lead, notification_type: 'ramon_fluxo_aviso').count).to eq(1)
    expect(Ramon::DadosContrato.texto(res)).to include('passe para humano')
    expect(Ramon::DadosContrato.texto(res)).not_to include('529')
  end

  it 'lead sem contato: erro para a IA, nada gravado' do
    expect(Ramon::DadosContrato.gravar(create(:lead, account: account), cpf: '52998224725')).to include(:erro)
  end
end
```

- [ ] **Step 2: `dados_faltando` no `ContratoAutomatico`**

Em `app/services/ramon/contrato_automatico.rb`, trocar o `faltando` inteiro por:

```ruby
  def faltando(lead, modelo)
    return ['modelo de contrato da tese'] if modelo.blank?

    dados_faltando(lead)
  end

  # O que falta no cadastro para o contrato sair sozinho — também guia a IA que coleta os dados (Ramon::DadosContrato).
  def dados_faltando(lead)
    vazios = Ramon::ZapsignContractService.new(lead).preview['faltando']
    (lead.nome_completo? ? [] : ['nome completo']) + OBRIGATORIOS.slice(*vazios).values
  end
```

(A prévia não depende do modelo: `variaveis` é igual para todos.)

- [ ] **Step 3: `Ramon::DadosContrato`**

`app/services/ramon/dados_contrato.rb`:

```ruby
# A IA grava os dados do contrato no CONTATO do lead (roteiro F5; decisão do Eduardo 14/10, reverte a pergunta A da F3)
# nos mesmos campos que o "Dados do contrato" do painel e o Ramon::ZapsignContractService leem: contact.name,
# contact.cpf e custom_attributes 'endereco' (hash), 'estado_civil' e 'profissao'. Grava aos poucos: o que vier em
# branco não apaga nada e o endereço soma às chaves que já existem (o painel tem o próprio caminho, que substitui).
# CPF que já é de outro contato da conta não é gravado: a equipe é avisada e a IA passa para humano.
# LGPD: name/cpf entram na trilha do audited (RamonPessoa); o texto para a IA nunca repete o CPF.
module Ramon::DadosContrato
  ENDERECO = %w[cep rua numero complemento bairro cidade uf].freeze
  CAMPOS = (%w[nome cpf estado_civil profissao] + ENDERECO).freeze
  CPF_EM_USO = 'ja esta no cadastro de outra pessoa'.freeze
  # Saem em branco no contrato mas não seguram o envio (os que seguram: ContratoAutomatico::OBRIGATORIOS).
  COMPLEMENTARES = { '{{estado civil}}' => 'estado civil', '{{profissão}}' => 'profissão', '{{bairro}}' => 'bairro' }.freeze

  module_function

  # @return { erro: } | { gravado: [campo], recusado: { campo => motivo }, falta: [..], complementar: [..] }
  def gravar(lead, dados)
    contato = lead.contact
    return { erro: 'Este caso nao tem contato no hub: passe para humano.' } if contato.nil?

    dados = normalizar(dados)
    recusado = {}
    nome!(contato, dados['nome'], recusado)
    cpf!(contato, dados['cpf'], recusado)
    contato.custom_attributes = atributos(contato.custom_attributes || {}, dados)
    contato.save!
    avisar_cpf_em_uso(lead) if recusado['cpf'] == CPF_EM_USO
    { gravado: dados.keys - recusado.keys, recusado: recusado }.merge(faltando(lead.reload))
  rescue ActiveRecord::RecordInvalid => e
    { erro: "Nao gravei: #{e.record.errors.full_messages.to_sentence}" }
  end

  def normalizar(dados)
    dados.to_h.transform_keys(&:to_s).slice(*CAMPOS).transform_values { |valor| valor.to_s.squish }.compact_blank
  end

  def nome!(contato, nome, recusado)
    return if nome.nil?
    return recusado['nome'] = 'tem uma palavra so - peca o nome completo, como no documento' if nome.split.size < 2

    contato.name = nome
  end

  # A validação do próprio contato (formato + única na conta) decide; recusado, volta o CPF de antes.
  def cpf!(contato, cpf, recusado)
    return if cpf.nil?

    contato.cpf = cpf
    contato.valid?
    erros = contato.errors.details[:cpf].pluck(:error)
    return if erros.empty?

    contato.cpf = contato.cpf_was
    recusado['cpf'] = erros.include?(:taken) ? CPF_EM_USO : 'nao e um CPF valido - confira os numeros com o lead'
  end

  def atributos(attrs, dados)
    endereco = dados.slice(*ENDERECO)
    endereco['uf'] = endereco['uf'].upcase if endereco['uf']
    endereco['cep'] = endereco['cep'].delete('^0-9') if endereco['cep']
    attrs = attrs.merge('endereco' => (attrs['endereco'].is_a?(Hash) ? attrs['endereco'] : {}).merge(endereco)) if endereco.any?
    attrs.merge(dados.slice('estado_civil', 'profissao'))
  end

  def faltando(lead)
    vazios = Ramon::ZapsignContractService.new(lead).preview['faltando']
    { falta: Ramon::ContratoAutomatico.dados_faltando(lead), complementar: COMPLEMENTARES.slice(*vazios).values }
  end

  def avisar_cpf_em_uso(lead)
    Ramon::AvisoDaIa.avisar(lead, "IA: o CPF que #{lead.name} informou ja esta no cadastro de outra pessoa - confira com ele",
                            "CPF ja cadastrado: #{lead.name}", 'O CPF informado pertence a outro contato da conta.')
  end

  # Texto para a IA (tool registrar_dados_contrato).
  def texto(res)
    return res[:erro] if res[:erro]

    partes = []
    partes << "Gravado no cadastro: #{res[:gravado].join(', ')}." if res[:gravado].any?
    res[:recusado].each { |campo, motivo| partes << "Nao gravei #{campo}: #{motivo}." }
    partes << 'Nao insista no CPF: diga que alguem da equipe confere com ele e passe para humano.' if res[:recusado]['cpf'] == CPF_EM_USO
    partes << (res[:falta].any? ? "Ainda falta para o contrato: #{res[:falta].join(', ')}." : 'Cadastro completo para o contrato.')
    partes << "Se ainda nao souber, pergunte tambem: #{res[:complementar].join(', ')}." if res[:complementar].any?
    partes.join(' ')
  end
end
```

- [ ] **Step 4: A tool, o catálogo e o CPF mascarado em Execuções**

`enterprise/lib/captain/tools/registrar_dados_contrato_tool.rb`:

```ruby
# Escrita interna (nada sai para o cliente): a IA grava no cadastro do lead os dados do contrato que ele informou.
# Toda a regra fica em Ramon::DadosContrato (testada no CI). No Testar so simula: dado pessoal nunca e gravado por la.
class Captain::Tools::RegistrarDadosContratoTool < Captain::Tools::RamonBaseTool
  CAMPOS = %i[nome cpf cep rua numero complemento bairro cidade uf estado_civil profissao].freeze

  description 'Grava no cadastro do lead os dados do contrato que ele informou: nome completo, CPF, endereco (CEP, rua, ' \
              'numero, complemento, bairro, cidade, UF), estado civil e profissao. Pode gravar aos poucos, so o que ' \
              'ele ja disse. Devolve o que ainda falta para o contrato. Nada e enviado ao lead.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false
  param :nome, type: 'string', desc: 'Nome completo, como no documento', required: false
  param :cpf, type: 'string', desc: 'CPF (so numeros ou com pontos e traco)', required: false
  param :cep, type: 'string', desc: 'CEP', required: false
  param :rua, type: 'string', desc: 'Rua (logradouro)', required: false
  param :numero, type: 'string', desc: 'Numero da casa', required: false
  param :complemento, type: 'string', desc: 'Complemento (apto, bloco)', required: false
  param :bairro, type: 'string', desc: 'Bairro', required: false
  param :cidade, type: 'string', desc: 'Cidade', required: false
  param :uf, type: 'string', desc: 'UF (sigla do estado)', required: false
  param :estado_civil, type: 'string', desc: 'Estado civil', required: false
  param :profissao, type: 'string', desc: 'Profissao', required: false

  def perform(tool_context, lead_id: nil, **dados)
    dados = dados.slice(*CAMPOS)
    return "[TESTE] gravaria no cadastro: #{dados.compact_blank.keys.join(', ')}. Nada foi gravado." if testar?(tool_context)

    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    ::Ramon::DadosContrato.texto(::Ramon::DadosContrato.gravar(lead, dados))
  end

  private

  # Testar (playground, com ou sem roteiro, inclusive "Testar com o caso"): nunca grava dado pessoal.
  def testar?(tool_context)
    tool_context&.state&.dig(:source).to_s == 'playground' || tool_context&.state&.dig(:roteiro_teste).present?
  end
end
```

Em `config/agents/tools.yml`, logo depois do bloco `- id: preparar_contrato_zapsign` (antes de `- id: preparar_caso_advbox`):

```yaml
- id: registrar_dados_contrato
  title: 'Gravar dados do contrato'
  description: 'Grava no cadastro do lead nome completo, CPF, endereço, estado civil e profissão; devolve o que falta para o contrato'
  icon: 'person-add'
  nivel: interna
  sistema: funil
```

Em `enterprise/lib/captain/tools/base_public_tool.rb`, depois da constante `FALHOU` (Task 4):

```ruby

  # ramon (roteiro F5, LGPD): dado pessoal fora da tela Execuções.
  PARAMS_SENSIVEIS = %i[cpf].freeze
```

e, no `registrar_execucao`, trocar

```ruby
      params: params.except(:lead_id).transform_values(&:to_s),
```

por

```ruby
      params: params.except(:lead_id).to_h { |chave, valor| [chave, PARAMS_SENSIVEIS.include?(chave) ? '***' : valor.to_s] },
```

(A ferramenta fica disponível ao Atendimento quando a skill "Fechar contrato" passar a citá-la com `tool://registrar_dados_contrato`. Isso acontece no PR de textos (Task 12), depois do deploy deste código, porque o `Captain::Scenario` valida os ids do catálogo.)

- [ ] **Step 5: Lint + commit**

```bash
rubocop-vps app/services/ramon/dados_contrato.rb app/services/ramon/contrato_automatico.rb spec/services/ramon/dados_contrato_spec.rb \
  enterprise/lib/captain/tools/registrar_dados_contrato_tool.rb enterprise/lib/captain/tools/base_public_tool.rb
git add app/services/ramon/dados_contrato.rb app/services/ramon/contrato_automatico.rb spec/services/ramon/dados_contrato_spec.rb \
  enterprise/lib/captain/tools/registrar_dados_contrato_tool.rb config/agents/tools.yml enterprise/lib/captain/tools/base_public_tool.rb
git commit -m "feat(inteligencia): ferramenta registrar_dados_contrato — a IA guarda no lead os dados do ZapSign"
```

---

### Task 11: PR, CI, merge, deploy, prova e Metabase

**Files:**
- Create: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-14-roteiro-f5-entrega.md` (fora do repo do hub)
- Modify: `C:\Users\dudsl\.claude\projects\C--Users-dudsl-RAdvogados\memory\roteiro-da-tese.md`

- [ ] **Step 1: Medir o efeito do fail-safe antes de subir** (só leitura)

```bash
echo 'p Captain::ToolRun.where(status: "erro").where("created_at > ?", 14.days.ago).group(:tool_name).count' \
  | ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails runner "eval(STDIN.read)"'
```

Anotar o resultado no corpo do PR e no doc de entrega: é quantos turnos em `piloto_limitado` teriam virado rascunho (decisão 2).

- [ ] **Step 2: Push e PR** (se o classificador barrar, o push é do Eduardo via `!`)

```bash
git push -u origin feat/roteiro-f5-correcoes
gh pr create --base ramon --title "fix(roteiro): correções da revisão integrada + IA grava dados do contrato (F5)" --body-file <corpo>
```

Corpo:
- parágrafo de produto: "a resposta vira rascunho quando uma ferramenta falha; reabrir o roteiro respeita o limite do modo e devolve a conversa ao robô; trocar a tese zera o roteiro; o Metabase separa o contrato que não saiu; o modelo de contrato entra na tela da tese; o Testar roda sem tese e simula o modo; a tela mostra o modo padrão da caixa; nova ferramenta para a IA guardar os dados do contrato";
- as **Decisões que tomei sem perguntar** do topo e o número do Step 1;
- "How to test" = a prova do Step 5 + o smoke do Step 7;
- o aviso: **a ferramenta nova só é usada depois do PR de textos (aprovado do Eduardo)**, e o fail-safe vale em produção no deploy;
- rodapé de atribuição.

- [ ] **Step 3: CI 100% verde.** Se um spec ou o lint ficar vermelho: corrigir, rodar `rubocop-vps` e fazer um commit novo (sem amend). Se o download de actions der 429 ou 503, rodar o job de novo.

- [ ] **Step 4: Merge (squash) e deploy** (regime autônomo com CI verde, CLAUDE.md do ramon-hub). A migração é só a view. Na VPS (`ssh root@185.194.216.67`, `cd /opt/intranet-ramon`):

```bash
docker pull ghcr.io/doods-maker/ramon-hub:sha-<7>
docker tag ghcr.io/doods-maker/ramon-hub:sha-<7> ghcr.io/doods-maker/ramon-hub:v4.15.1-ramon
docker compose run --rm --no-deps chatwoot-web bundle exec rails db:migrate
docker compose up -d chatwoot-web chatwoot-worker
```

Conferir a label da imagem e o login com 200 em https://chat.ramonantonio.adv.br (cerca de 2 minutos depois do `up`). **Nada é ligado**: nenhuma tese ganha modelo e nenhuma caixa ganha modo.

- [ ] **Step 5: Prova em produção sem deixar rastro.** Tudo roda numa transação desfeita. Os `after_*_commit` não rodam lá dentro, então os callbacks do Lead são chamados à mão. Gravar em `prova-f5.rb` (scratchpad) e rodar com `cat prova-f5.rb | ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails runner "eval(STDIN.read)"'`:

```ruby
ActiveRecord::Base.transaction do
  a = Account.find(2)
  asst = Captain::Assistant.where(account_id: a.id).order(:id).first!
  caixa = a.inboxes.where('name ILIKE ?', '%teste%').first!
  novo = a.lead_stages.where(is_won: false, is_lost: false).order(:position).first
  tese = a.theses.create!(name: "Prova F5 #{Time.now.to_i}", position: 999)
  RoteiroPasso.create!(account: a, thesis: tese, chave: 'prova', titulo: 'Prova', position: 1, tipo_resposta: 'sim_nao',
                       saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'concluir' },
                                { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'humano', 'motivo' => 'prova F5' }])
  c = a.contacts.create!(name: 'Prova Cinco')
  ci = ContactInbox.create!(contact: c, inbox: caixa, source_id: "prova-f5-#{Time.now.to_i}")
  conv = a.conversations.create!(inbox: caixa, contact: c, contact_inbox: ci, status: :pending,
                                 custom_attributes: { 'copiloto_modo' => 'piloto_total' })
  lead = a.leads.create!(name: 'Prova F5', lead_stage: novo, contact: c, conversation: conv, thesis: tese)
  novo_ctx = -> { Agents::ToolContext.new(run_context: Agents::RunContext.new({ state: { conversation: { id: conv.id } } })) }

  puts '--- 1. fail-safe: ferramenta falhou → sinal → rascunho'
  p Ramon::CopilotoModo.envia?('piloto_total', handoff: false, logistica_ok: nil, falhou: true)        # => false
  f = Captain::Tools::RoteiroPassoAtualTool.new(asst)
  f.define_singleton_method(:perform) { |*_a, **_k| raise 'prova F5' }
  ctx = novo_ctx.call
  p f.execute(ctx) == Captain::Tools::BasePublicTool::ERRO_NA_TOOL                                     # => true
  p ctx.state[Captain::Tools::BasePublicTool::FALHOU]                                                  # => true
  res = Agents::RunResult.new(output: 'oi', messages: [], usage: nil, error: nil, context: ctx.context)
  p Captain::Assistant::AgentRunnerService.new(assistant: asst).send(:process_agent_result, res)['ferramenta_falhou'] # => true
  job = Captain::Conversation::ResponseBuilderJob.new
  { conversation: conv, assistant: asst, copiloto_modo: 'piloto_total', response: { 'ferramenta_falhou' => true } }
    .each { |k, v| job.instance_variable_set(:"@#{k}", v) }
  m = job.send(:create_outgoing_message, 'resposta da prova F5')
  p [m.private, m.content.start_with?('RASCUNHO')]                                                     # => [true, true]

  puts '--- 2. handoff do roteiro pelo sinal'
  ctx2 = novo_ctx.call
  puts Captain::Tools::RoteiroRegistrarTool.new(asst).execute(ctx2, chave: 'prova', valor: 'nao').lines.first # Registrado.
  p ctx2.state[Captain::Tools::RoteiroRegistrarTool::HANDOFF]                                           # => true
  p [conv.reload.status, conv.custom_attributes['copiloto_modo']]                                      # => ["open", "rascunho"]

  puts '--- 3. reabrir: devolve ao robô, desfaz o limite qualificação e respeita o limite'
  p Ramon::Roteiro.reabrir(lead.reload)                                                                # => true
  p [conv.reload.status, conv.custom_attributes['copiloto_modo']]                                      # => ["pending", "piloto_total"]
  conv.update!(custom_attributes: { 'copiloto_modo' => 'piloto_ate_qualificacao' })
  Ramon::Roteiro.registrar(lead.reload, chave: 'prova', valor: 'sim')
  p conv.reload.custom_attributes.slice('copiloto_modo', 'copiloto_limite')                            # rascunho + limite qualificacao
  Ramon::Roteiro.reabrir(lead.reload)
  p conv.reload.custom_attributes                                                                      # => {"copiloto_modo"=>"piloto_ate_qualificacao"}
  lead.update_columns(lead_stage_id: a.lead_stages.find_by!(label: Ramon::ReuniaoAgendamento::STAGE_LABEL).id)
  conv.update!(custom_attributes: { 'copiloto_modo' => 'manual', Ramon::CopilotoModo::MODO_ANTES => 'piloto_ate_reuniao' })
  Ramon::Roteiro::Efeitos.reabrir(lead.reload, Ramon::Roteiro::DESQUALIFICADO)
  p conv.reload.custom_attributes.slice('copiloto_modo', 'copiloto_limite')                            # rascunho + limite reuniao

  puts '--- 4. trocar a tese zera o roteiro gravado'
  Ramon::Roteiro.registrar(lead.reload, chave: 'prova', valor: 'sim')
  p lead.reload.desfecho_roteiro                                                                       # => "qualificado"
  lead.update!(thesis: a.theses.where.not(id: tese.id).first!)
  p lead.reload.custom_attributes['roteiro'].slice('tese_id', 'desfecho')                             # tese nova, sem desfecho

  puts '--- 5. registrar_dados_contrato grava no contato'
  base = Array.new(9) { rand(10) }
  2.times { base << ((base.each_with_index.sum { |d, i| d * (base.size + 1 - i) } * 10) % 11 % 10) }
  puts Captain::Tools::RegistrarDadosContratoTool.new(asst).execute(novo_ctx.call, nome: 'Prova Cinco Silva', cpf: base.join,
                                                                                   rua: 'Rua da Prova', numero: '5', cidade: 'Tubarão')
  # Gravado no cadastro: nome, cpf, rua, numero, cidade. Cadastro completo para o contrato. Se ainda nao souber, …
  p c.reload.slice(:name, :cpf), c.custom_attributes['endereco']                                     # nome, CPF (11 dígitos) e o hash do endereço
  p Captain::ToolRun.where(conversation_id: conv.id, tool_name: 'registrar_dados_contrato').last&.params&.dig('cpf') # => "***"

  puts '--- 6. bi_roteiro v02'
  p ActiveRecord::Base.connection.select_all(
    "SELECT em_roteiro, desfecho, aguarda_equipe, limite_atingido, limite_motivo FROM bi_roteiro WHERE lead_id = #{lead.id}"
  ).to_a # => [{"em_roteiro"=>true, "desfecho"=>nil, "aguarda_equipe"=>false, "limite_atingido"=>"reuniao", "limite_motivo"=>nil}]
  raise ActiveRecord::Rollback
end
p Account.find(2).theses.where('name LIKE ?', 'Prova F5%').count # => 0
```

Os 4 SQLs dos cards contra o banco de produção, só leitura, a partir do worktree:

```bash
PYTHONUTF8=1 python -c "import json, sys; sys.path.insert(0, 'scripts'); import metabase_bi_ia_cards as m; print('\n'.join('p ActiveRecord::Base.connection.select_all(%s).to_a.first(3)' % json.dumps(c['sql']) for c in m.CARDS_ROTEIRO.values()))" \
  | ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails runner "eval(STDIN.read)"'
```

Esperado: 4 linhas `[]` (ou poucas linhas) e nenhum erro de SQL. Se um resultado divergir do esperado nos comentários, parar e diagnosticar (`superpowers:systematic-debugging`) antes de seguir.

- [ ] **Step 6: Metabase (o Eduardo roda pelo `!`).** O classificador barra o Claude de ler a chave. Os cards são idempotentes pelo nome: o script atualiza o SQL do card de limites no lugar. Primeiro sem `--apply` (espera-se `[ATUALIZAR SQL]` no card de limites e `[JA OK]` / `[DASHBOARD JA OK]` no resto), depois:

```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-roteiro && export PYTHONUTF8=1 METABASE_URL=https://bi.ramonantonio.adv.br METABASE_ADMIN_KEY=$(grep -oE 'mb_[^[:space:]]+' /c/Users/dudsl/RAdvogados/conhecimento/metabase-credenciais.txt) && python scripts/metabase_bi_ia_cards.py --apply
```

- [ ] **Step 7: Doc de entrega para o Eduardo:** `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-14-roteiro-f5-entrega.md`, com estas seções:
  1. **No ar:** PR, squash, sha da VPS, migração `20261014200001` aplicada, o que a prova mostrou e o número do Step 1.
  2. **O que mudou para você** (em linguagem de gente): os 20 itens das decisões, resumidos.
  3. **Metabase:** o comando do Step 6.
  4. **Smoke** (em bloco por seção, não pergunta a pergunta):
     - **A. Playbooks:** Configurações → Playbooks → "Auxílio-acidente (B36)" → o seletor "Modelo de contrato (ZapSign)" lista os modelos da conta. Escolher o de auxílio-acidente só quando quiser ligar o "sozinha até o contrato" (é o gate da F3).
     - **B. Testar:** escolher "Lead sem tese" e mandar "oi, sofri um acidente de trabalho". O cartão do roteiro mostra o "assunto" e depois os passos de auxílio-acidente. Trocar o modo para "Piloto total" e fazer um caminho de desqualificação: o cartão não mostra "aguardando a equipe".
     - **C. Conversa:** numa caixa com modo padrão (quando você escolher um), uma conversa sem modo próprio mostra o modo da caixa no seletor. O mesmo vale para a tela Assistentes.
     - **D. Painel do lead:** reabrir um roteiro que foi para a equipe devolve a conversa para "pendente" (robô).
     - **E. Metabase:** o card de limites mostra "contrato não saiu" quando acontecer (hoje não há caso).
  5. **Textos:** ponteiro para `2026-10-14-roteiro-f5-textos.md` (Task 12).

- [ ] **Step 8: Registro:** atualizar `memory\roteiro-da-tese.md` com o PR, o squash, o sha da VPS, a migração `20261014200001` aplicada, a prova OK, os cards (aplicados ou aguardando o `!`), o smoke em `comercial\docs\2026-10-14-roteiro-f5-entrega.md` AGUARDA Eduardo, e os textos da F5 com PR draft aguardando o "aprovado".

---

### Task 12: Textos que falam com o cliente — PR draft + doc de aprovado (gate do Eduardo)

**Files:**
- Modify (branch `feat/roteiro-f5-textos`, criada de `origin/ramon` **depois** do merge da Task 11): `db/seeds/ramon/inteligencia/assistentes.yml`
- Create: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-14-roteiro-f5-textos.md` (fora do repo do hub)

**Interfaces:**
- Consumes: a tool `registrar_dados_contrato` no catálogo (Task 10, já em produção). O `Captain::Scenario` recusa skill que cita tool fora do catálogo, e é por isso que esta task vem depois do deploy.
- Produces: a skill "Fechar contrato" passa a usar `tool://registrar_dados_contrato`, que fica disponível ao Atendimento.

- [ ] **Step 1: Branch**

```bash
git fetch origin && git switch -c feat/roteiro-f5-textos origin/ramon
```

- [ ] **Step 2: Os 3 trechos no seed (assistente Atendimento)**

**Item 1 (diretriz global).** Em `db/seeds/ramon/inteligencia/assistentes.yml`, trocar

```yaml
      - "Não peça CPF, endereço ou dados sensíveis antes de o lead demonstrar interesse em avançar; peça só o que a próxima etapa exige."
```

por

```yaml
      - "Não peça CPF, endereço ou outros dados pessoais antes de o lead decidir fechar. Depois que ele decidir, peça só o que ainda falta para o contrato, como manda a skill Fechar contrato — e nunca repita o CPF inteiro de volta na conversa."
```

**Item 2 (descrição da skill "Fechar contrato").** Trocar

```yaml
        description: O lead decidiu fechar — preparar contrato e caso, com aprovação humana (exceto no modo "sozinha até o contrato", em que o contrato sai na hora).
```

por

```yaml
        description: O lead decidiu fechar — completar os dados do contrato e preparar contrato e caso, com aprovação humana (exceto no modo "sozinha até o contrato", em que o contrato sai na hora).
```

**Item 3 (instrução da skill "Fechar contrato", inteira).** Trocar o `instruction: |` da skill pelo texto abaixo, na mesma indentação:

```yaml
        instruction: |
          Quando o lead decidir fechar, comece pelos dados do contrato: chame
          [Gravar dados do contrato](tool://registrar_dados_contrato) com o que ele já contou nesta conversa (nome
          completo, CPF, endereço, estado civil, profissão) — ela grava no cadastro e devolve o que ainda falta.
          Se faltar algo, peça com calma e carinho, um ou dois itens por mensagem, explicando que é para preencher o
          contrato (ex.: "Pra eu deixar seu contrato prontinho, me passa seu CPF?"). A cada resposta, grave de novo com
          a mesma ferramenta. O nome é o completo, como no documento; o endereço precisa de rua, número e cidade (CEP,
          bairro e complemento ajudam). Estado civil e profissão: pergunte se ainda não souber, sem insistir.
          Se a ferramenta disser que o CPF já está no cadastro de outra pessoa, não insista nem explique o motivo: diga
          que alguém da equipe confere com ele por aqui e passe para humano.
          Com o cadastro completo, chame [Preparar contrato no ZapSign](tool://preparar_contrato_zapsign).
          Se ela devolver "Contrato gerado" com um link, envie o link ao lead numa frase curta: é o contrato de
          honorários + procuração, para assinar pelo celular; explique o honorário mais uma vez, com clareza.
          Nos outros casos ela só deixa uma sugestão pendente: diga ao lead que a equipe vai enviar o contrato para
          assinatura pelo celular, explique o honorário mais uma vez e passe para humano. Nunca afirme que o
          contrato existe sem o link na mão. Depois que o humano confirmar que o caso foi fechado,
          [Abrir caso no AdvBox](tool://preparar_caso_advbox) — também só deixa sugestão; quem aplica é o humano.
```

- [ ] **Step 3: Doc de aprovado.** `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-14-roteiro-f5-textos.md`, no padrão de `2026-10-14-roteiro-f3-textos.md`:
  - cabeçalho: "**Rascunho — aguarda aprovado do Eduardo.** O código da F5 já está no ar (a ferramenta existe, mas nenhuma skill a usa). Estes 3 trechos vão no PR draft `feat/roteiro-f5-textos` e só valem depois do seu aprovado: merge, deploy e `rails "ramon:inteligencia:seed[2]"`."
  - **§1 Textos que mudam (antes → depois):** itens **1**, **2** e **3** do Step 2, exatos, numerados para aprovar um a um (os links `tool://` explicados: "Gravar dados do contrato", "Preparar contrato no ZapSign" e "Abrir caso no AdvBox" são as ferramentas).
  - **§2 O que isso muda na conversa:** a IA pede os dados só depois de o lead decidir fechar, um ou dois por mensagem, e guarda no cadastro do lead (o mesmo "Dados do contrato" do painel). CPF de outra pessoa → a IA para e a equipe recebe o sino. No modo "sozinha até o contrato" (com o modelo da tese escolhido), isso fecha o ciclo e o contrato sai sozinho. Nos outros modos, a sugestão de contrato continua no Cockpit, agora com o cadastro preenchido.
  - **§3 Atenção:** se a skill "Fechar contrato" foi editada na tela, o seed não a sobrescreve (regra das skills editadas). Nesse caso eu colo o texto na tela depois do seu aprovado.
  - pedido final: "Responda **aprovado** (ou ajuste os itens 1–3)."

- [ ] **Step 4: Commit e PR draft**

```bash
git add db/seeds/ramon/inteligencia/assistentes.yml
git commit -m "feat(inteligencia): IA pede e guarda os dados do contrato antes de prepará-lo (aguarda aprovado)"
git push -u origin feat/roteiro-f5-textos
gh pr create --draft --base ramon --title "feat(inteligencia): IA pede e guarda os dados do contrato (F5, aguarda aprovado)" --body-file <corpo>
```

Corpo: parágrafo de produto, o link para o doc de aprovado, o aviso "**não mergear sem o aprovado do Eduardo**" e o rodapé de atribuição.

- [ ] **Step 5: Gate. Só depois do "aprovado" do Eduardo:** marcar como pronto (`gh pr ready`), esperar o CI verde, fazer o merge (squash) e o deploy com a imagem nova (sem migração: `docker pull`, `docker tag`, `docker compose up -d chatwoot-web chatwoot-worker`). Depois:

```bash
ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails "ramon:inteligencia:seed[2]"'
echo 'p Captain::Scenario.joins(:assistant).where(captain_assistants: { account_id: 2 }, title: "Fechar contrato").pluck(:tools)' \
  | ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails runner "eval(STDIN.read)"'
```

Esperado: a lista de tools da skill inclui `registrar_dados_contrato`. Se ele ajustar o texto: editar o YAML, fazer um commit novo no mesmo PR e pedir o aprovado de novo. Registrar no `memory\roteiro-da-tese.md` que os textos da F5 estão ativos.

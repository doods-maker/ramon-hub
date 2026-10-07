# Inteligência A4 — FAQ a partir das conversas + atalhos do Copiloto — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (1) **"Virar FAQ" com 1 clique** numa resposta enviada ao lead — cria FAQ **pendente** com a pergunta que o lead fez logo antes, sem IA; (2) **gerar FAQs das conversas resolvidas** no Atendimento com prompt da banca, conversa pseudonimizada, modelo escolhido na tela Uso e custo, linha própria de custo e pausa pelo teto de gasto; (3) **atalhos da banca no painel do Copiloto** ("Situação do processo deste cliente", "O que falta de documento", "Preparar a reunião"; fora de conversa: "Agenda do dia", "Funil hoje", "Prazos da semana no AdvBox") — e o painel passa a rodar **as skills do Copiloto do Escritório** (hoje ele roda um chat do upstream que não enxerga AdvBox nem o caso).

**Architecture:** As regras que importam (de onde vem a pergunta, o que é mascarado, o que vai ao LLM, a pausa pelo teto, o contexto do caso que o Copiloto recebe) ficam em dois módulos **FOSS** (`Ramon::FaqDeConversa`, `Ramon::CopilotoPainel`), testados no CI. O que toca `Captain::*` (endpoint "virar FAQ", `ConversationFaqService`, `Captain::Copilot::SkillsService` + 3 linhas no `ResponseJob`) é casca fina no `enterprise/`. Front: um item novo no menu da mensagem (`VirarFaqMenuItem.vue`), o painel do Copiloto abre no assistente da equipe e mostra os atalhos. Sem migração, sem env nova.

**Tech Stack:** Rails 7.1 / RSpec (só no CI; `spec/enterprise` é apagado no CI), Vue 3.5 `<script setup>`, vue-i18n 9, Vitest 3 + @vue/test-utils, Histoire (story dos prints).

**Spec:** `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-05-inteligencia-tela-a-tela.md` §13 "Ideias além" — **I-X1** (FAQ a partir de conversa com 1 clique), **I-X2** (ligar "gerar FAQ de conversas resolvidas"), **I-X3** (atalhos da banca no Copiloto da conversa); regras gerais no topo do backlog (rascunho ao cliente, honorário 30% + 3 nas FAQs, FAQ por busca de texto, visual branco/preto). Plano de referência de estilo: `docs/superpowers/plans/2026-10-06-automacoes-fluxo-b4-lembretes.md`.

## Escopo registrado com o Eduardo (A4) e o que já existe

Itens: (1) FAQ a partir de uma conversa com 1 clique; (2) gerar FAQs a partir das conversas resolvidas; (3) atalhos do Copiloto. Regras: FAQ gerada nasce **PENDENTE** e só vale depois de aprovada por humano; custo de IA plugado no que o **#215** instrumentou; teto de gasto; nada fala com cliente sem aprovação; LGPD — nada de CPF/documentos ao LLM sem necessidade.

Conferido no código (base `079a04c`):

| Peça | Situação | Onde |
|---|---|---|
| FAQ de conversa nasce **pendente** | **já entregue** (o gerador já grava `status: 'pending'`, `documentable: conversation`); a A4 só trava isso no spec | `enterprise/app/services/captain/llm/conversation_faq_service.rb:68-77` |
| Busca do assistente só usa FAQ **aprovada** | **já entregue** (`.approved.search` em todos os pontos) | `faq_lookup_tool.rb:9`, `search_documentation_service.rb:16`, `search_reply_documentation_service.rb:35-37` |
| Aprovar FAQ | **já entregue**, só administrador (`bulk_actions`/`update` → `AssistantPolicy` admin) | `enterprise/app/policies/captain/assistant_policy.rb:18-28` |
| Chave "gerar FAQ de conversas resolvidas" | **já existe** na tela Configurações do assistente (`feature_faq`); o listener roda ao resolver conversa em caixa conectada | `AssistantBasicSettingsForm.vue:133-134`, `captain_listener.rb:8-11` |
| #215 — uso/custo da geração de FAQ de conversa | **parcial**: a chamada já grava em `ramon_llm_chamadas` (via `instrument_llm_call`), mas com função crua `conversation_faq` (sem rótulo), modelo do env antigo (`CAPTAIN_OPEN_AI_MODEL`), sem teto | `lib/integrations/llm_instrumentation.rb:12-14`, `lib/ramon/llm_uso.rb:10-13`, `lib/llm/base_ai_service.rb:31-34` |
| Gerador de FAQ de conversa — LGPD/custo | **a fazer**: manda a conversa **inteira, sem corte e sem pseudonimizar** (nome, CPF, telefone) com prompt genérico em inglês ("help center") | `conversation_faq_service.rb:10,121-124`, `conversation_llm_formatter.rb:38-47` |
| "Virar FAQ" na mensagem | **a fazer** (criar FAQ pela API é só admin; não há item no menu) | `assistant_responses_controller.rb:3`, `MessageContextMenu.vue` |
| #218 — skills de rotina dos POPs | **já entregue** (só seed): "Anotar atendimento ou pedir por tarefa", "Lançar andamento do INSS", "Explicar andamento ao cliente" — somam-se a "Situação do processo", "Revisão de documentos do caso", "Preparar reunião", "Agenda do dia", "Funil hoje", "Consultas no AdvBox". **Mas só rodam no Testar** | `db/seeds/ramon/inteligencia/assistentes.yml:126-295` |
| "Situação do processo deste cliente" dentro da conversa | **parcial**: existe como **"Perguntar ao AdvBox"** no menu de IA do editor (`Ramon::AdvboxPerguntaService`, panorama dos processos) — fora do painel do Copiloto | `CopilotMenuBar.vue:139-143`, `tasks_controller.rb:40-42` |
| Painel do Copiloto na conversa usando as skills | **a fazer**: o painel roda `Captain::Copilot::ChatService` (upstream), cujas ferramentas são só busca de conversa/contato/artigo/Linear — **não enxerga AdvBox, documentos do caso nem as skills**; e abre no assistente da caixa (o Atendimento) | `enterprise/app/jobs/captain/copilot/response_job.rb:18-26`, `chat_service.rb:63-76`, `CopilotContainer.vue:50-69` |
| Atalhos do painel | **a fazer**: "Resumir / Sugerir / Avaliar 0–5" e "Alta prioridade / Listar contatos" fixos do upstream | `CopilotEmptyState.vue:18-43` |
| #214 — Casos de teste | não se cruza com a A4 (fonte `teste` à parte; nada aqui roda em modo teste) | — |

## Global Constraints

- Worktree `C:\Users\dudsl\RAdvogados\comercial\projetos\ramon-hub-wt-intel-a4`, branch `feat/inteligencia-a4`, base `origin/ramon` **079a04c** (B1–B3 + B4.1 no ar, #213–#218 no ar). **Todo `arquivo:linha` deste plano é do commit base**; se uma task anterior mexeu no arquivo, use o trecho citado como âncora. Nunca `git push`, nunca abrir PR, nunca `git stash`, nunca `git add -A` (gate do Eduardo / sessão principal).
- **Nada fala com o cliente.** A FAQ de 1 clique e a gerada nascem `pending` e o assistente só lê `approved`; só administrador aprova. O Copiloto responde **no painel** da equipe; escrita no AdvBox segue a regra de ouro das skills (prévia + "confirma?"). Nenhuma mensagem sai para o lead nesta fatia.
- **LGPD:** pergunta, resposta e conversa passam pelo `Ramon::Pseudonymizer.mask` (nome do contato e do lead, CPF, RG, telefone, e-mail, CEP, endereço viram `[marcador]`) **antes** de gravar a FAQ e antes de ir ao LLM; a conversa vai **cortada nos últimos 8.000 caracteres** e sem notas privadas. O Copiloto recebe do caso só: data de hoje, nº da conversa, nº do caso (`lead_id`) e o nome do cliente (a busca de processo no AdvBox precisa dele) — nunca CPF, telefone, documento ou o texto da conversa.
- **Custo/teto:** toda chamada nova passa pelo `Ramon::LlmUso` do #215 (geração de FAQ de conversa = função `faq_conversa`; painel do Copiloto = função `copiloto_painel`). A geração **automática** pausa quando o gasto do dia (fuso de Brasília) chega ao teto do alerta (`accounts.settings['ramon_ia_teto_diario_usd']`); sem teto definido, não pausa. "Virar FAQ" não usa IA.
- **Sem migração, sem env nova.** `captain_assistant_responses` já tem `status`, `documentable` polimórfico; `ramon_llm_chamadas.funcao` é string livre. Se alguma task achar que precisa de coluna: pare e pergunte (não há Postgres local).
- **Rubocop do fork** (o CI barra): `Metrics/AbcSize` 26, `Metrics/MethodLength` 19, `Metrics/CyclomaticComplexity` 7, `Metrics/PerceivedComplexity` 8, `Metrics/ClassLength` 175, `Metrics/ModuleLength` 100, `Metrics/BlockLength` 30 (fora de spec), linha 150, `Style/HashSyntax` `EnforcedShorthandSyntax: never` (sempre `chave: valor`), `Naming/MethodParameterName` mínimo 3 letras, `rubocop-rspec` (`RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50, `RSpec/ContextWording` — `context` só começando com when/with/without em inglês: **use `describe`** para frases em pt-BR; `RSpec/SpecFilePathFormat` — spec de `A::B` em `spec/.../a/b_spec.rb`; prefira `Struct` a `double`). **`app/models/lead.rb`, `app/services/ramon/advbox_event_processor.rb` e `app/finders/conversation_finder.rb` estão no limite de 175 linhas: nenhuma linha nova neles** (a A4 não toca nenhum). Tamanhos na base (linhas de código): `lib/ramon/llm_uso.rb` 90/100 (vai a ~92), `conversation_faq_service.rb` 108/175, `response_job.rb` 23.
- **CI FOSS apaga `enterprise/` e `spec/enterprise/` antes do RSpec** (`.github/workflows/run_foss_spec.yml:103-106`) — os specs enterprise desta fatia **não rodam no CI** (servem de documentação e prova manual); por isso a lógica fica nos módulos FOSS, com spec que roda. Código FOSS **não** referencia `Captain::*`. Rota nova do enterprise fica atrás de `if ChatwootApp.enterprise?` (como `post :call` em `config/routes.rb:226`). O Rubocop roda no repositório inteiro, `enterprise/` incluído.
- **Sem Ruby local:** specs Ruby são escritos e conferidos à mão (rastrear cada linha) e quem valida é o CI. Sem `NOW()` no SQL; `travel_to` só em sequência, nunca aninhado. `Message` tem `default_scope { order(created_at: :asc) }` (`app/models/message.rb:126`): para pegar id/max use `.reorder(...)` antes de `pick`/`pluck` (lição do `.distinct.pluck`).
- **Front:** i18n novo em `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json`, blocos `CAPTAIN_RAMON.FAQ_CONVERSA` e `CAPTAIN_RAMON.COPILOTO_ATALHOS`, **no fim de `CAPTAIN_RAMON` (depois de `MESSAGE_TEMPLATES`)**, mesma posição e mesma ordem de chaves nos dois arquivos; strings sem `@`, `|`, `{`, `}` crus; editar os JSON à mão (Edit). Rótulos novos da tela Uso e custo em `ramonIaUso.json` (a trava `UsoCustoI18n.spec.js` compara a ordem). Texto da chave do assistente em `integrations.json` (só en e pt_BR). Tailwind only, kit `ramon/helpers/ui.js` (`TOM`), evento custom camelCase, sem texto cru no template, toda `<ul>/<ol>` nova com `list-none` (a A4 não cria lista).
- **Vitest:** `node_modules` é junção para `ramon-hub-wt-fluxos-b2\node_modules` (nunca `rm -rf node_modules`). Config local **já existe e está fora do git** (`.git/info/exclude`) `vitest.local.config.ts`:
  `TZ=UTC npx vitest run <arquivos ou pastas> --config vitest.local.config.ts`
  Os testes rodam com locale **en** (`vitest.setup.js`) — afirmações sobre texto usam o texto em inglês. ESLint: `./node_modules/.bin/eslint <arquivos>` (erro `Delete ␍` = CRLF do checkout Windows, ignorar; warnings `@intlify/vue-i18n/no-dynamic-keys` são aceitos).
- **Commits:** Conventional Commits em pt-BR, sem citar Claude no assunto; corpo termina com:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR`
  Commitar só os caminhos da task (`git add <arquivos>`).
- **Rito de telas do Eduardo:** visual branco/preto do hub com destaque azul e fundos translúcidos; entrega com página de prints **mockup × real** em `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a4\comparar.html` para ele aprovar **antes do merge** (Tasks 1 e 8).

## Review Focus

1. **Lead que manda a pergunta em várias bolhas, com nota privada no meio, ou resposta sem pergunta antes** — a FAQ pega todas as bolhas do lead desde a última resposta enviada (a nota privada não corta), e resposta sem pergunta/nota privada/mensagem do lead é recusada com texto claro. Teste: Task 2 (`.de_mensagem` — "junta as bolhas…", "recusa…").
2. **Dado pessoal na pergunta, na resposta ou na conversa** (nome do contato e do lead, CPF, telefone) — sai mascarado na FAQ gravada e no texto que vai ao LLM; nota privada (RASCUNHO) nunca vai. Teste: Task 2 ("…mascara os dados pessoais", "`.texto` manda só o fim…"), Task 6 ("o contexto não leva telefone nem e-mail").
3. **Clique duplo / 2º clique na mesma resposta** — uma FAQ só; o 2º diz "já virou FAQ". Teste: Task 4 ("clique duplo…", "2º clique…") e Task 3 (spec enterprise, documentação).
4. **Gasto do dia passou do teto** — a geração automática para naquele dia; sem teto, segue. Teste: Task 2 (`.pausada?`).
5. **Painel do Copiloto com o Atendimento escolhido antes pela pessoa, conta sem assistente da equipe, ou `stats` falhando** — o painel continua como antes (comandos do upstream, ChatService); a escolha da pessoa vence. Teste: Task 7 (`escolherAssistente` e "assistente de leads segue com os comandos de antes"); e erro do agente vira mensagem no painel (o "pensando" não fica girando) — Task 6 (spec enterprise, documentação).

---

## Mapa de arquivos

| Arquivo | Task | Responsabilidade |
|---|---|---|
| `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a4\mockup.html` + PNGs (fora do repo) | 1, 8 | mockup alvo; depois `comparar.html` |
| `app/services/ramon/faq_de_conversa.rb` (novo) + `spec/services/ramon/faq_de_conversa_spec.rb` | 2 | pergunta/resposta da FAQ de 1 clique, texto ao LLM, prompt da banca, pausa pelo teto |
| `enterprise/app/controllers/api/v1/accounts/conversations/faqs_controller.rb` (novo) + `config/routes.rb` + `spec/enterprise/controllers/api/v1/accounts/conversations/faqs_controller_spec.rb` | 3 | `POST /conversations/:id/faqs` (virar FAQ) |
| `app/javascript/dashboard/api/captain/faqDeConversa.js` (novo), `modules/conversations/components/VirarFaqMenuItem.vue` (novo), `MessageContextMenu.vue`, `components-next/message/Message.vue`, i18n `ramon.json` + specs | 4 | item "Virar FAQ" no menu da mensagem |
| `enterprise/app/services/captain/llm/conversation_faq_service.rb`, `lib/ramon/llm_uso.rb`, `integrations.json`, `ramonIaUso.json` + specs | 5 | geração das conversas resolvidas (LGPD, prompt, modelo, custo, teto) |
| `app/services/ramon/copiloto_painel.rb` (novo), `enterprise/app/services/captain/copilot/skills_service.rb` (novo), `enterprise/app/jobs/captain/copilot/response_job.rb`, `lib/ramon/llm_uso.rb`, `ramonIaUso.json` + specs | 6 | painel do Copiloto roda as skills com o contexto do caso |
| `components-next/copilot/{escolherAssistente.js (novo), CopilotEmptyState.vue, Copilot.vue}`, `components/copilot/CopilotContainer.vue`, i18n `ramon.json` + specs | 7 | painel abre no Copiloto da equipe e mostra os atalhos |
| `components-next/copilot/InteligenciaA4.story.vue` (novo) | 8 | variantes para os prints |

---

### Task 1: Mockup alvo (claro e escuro) — antes de codar

**Files:**
- Create (fora do repositório, não commitar): `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a4\mockup.html`, `mockup-claro.png`, `mockup-escuro.png`

**Interfaces:**
- Produces: o alvo visual que a Task 8 compara com os prints reais. Textos idênticos aos das chaves i18n das Tasks 4 e 7.

- [ ] **Step 1: Escrever o mockup** — HTML estático com Tailwind CDN (`<script src="https://cdn.tailwindcss.com"></script>`), cores do hub (fundo branco/preto, borda cinza fina, destaque azul `#2563EB`, fundos coloridos translúcidos), três quadros lado a lado (empilham no celular, `max-width: 360px` cada):
  1. **Menu da mensagem** aberto sobre uma bolha do atendente ("Maria, a perícia do INSS é gratuita."), itens na ordem: Responder · Copiar · Traduzir · ─ · Copiar link · Criar resposta pronta · **Virar FAQ** (ícone de livro) · ─ · Apagar. Abaixo, o aviso (toast) escuro: "FAQ criada como pendente. Um administrador aprova antes de o assistente usar." com o link azul "Ver FAQs pendentes".
  2. **Painel do Copiloto, conversa aberta** — cabeçalho "Copiloto"; título "Comece a usar o Copiloto"; frase "Pergunte sobre o caso aberto: processo no AdvBox, documentos, reunião. Nada sai para o cliente."; rótulo pequeno "Experimente estes comandos"; 3 linhas-botão (cartão branco/preto, borda fina, raio 8px, ícone em quadradinho azul translúcido à esquerda e `›` à direita): "Situação do processo deste cliente" (ícone balança) · "O que falta de documento" (arquivo com check) · "Preparar a reunião" (calendário com check). Rodapé: seletor de assistente "Copiloto do Escritório" e o campo de mensagem.
  3. **Painel do Copiloto, fora de conversa** — mesmos elementos com "Agenda do dia" (calendário) · "Funil hoje" (funil) · "Prazos da semana no AdvBox" (relógio).
  Use só dados fictícios ("Maria Exemplo").

- [ ] **Step 2: PNGs** (Git Bash):

```bash
D="/c/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-07-inteligencia-a4"
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
"$CHROME" --headless=new --hide-scrollbars --window-size=1200,760 --screenshot="$D/mockup-claro.png" "file:///C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-07-inteligencia-a4/mockup.html"
"$CHROME" --headless=new --hide-scrollbars --force-dark-mode --window-size=1200,760 --screenshot="$D/mockup-escuro.png" "file:///C:/Users/dudsl/RAdvogados/comercial/docs/mockups/2026-10-07-inteligencia-a4/mockup.html?dark=1"
```
Expected: 2 PNGs. (O mockup lê `?dark=1` e põe `class="dark"` no `<html>`; Tailwind CDN com `darkMode: 'class'`.) Abrir os dois e conferir: nenhum texto em inglês, nenhum fundo chapado colorido.

- [ ] **Step 3:** sem commit (fora do repo). Anotar no relatório da task o caminho da pasta.

---

### Task 2: `Ramon::FaqDeConversa` — pergunta da FAQ de 1 clique, texto ao LLM, prompt da banca e pausa pelo teto (FOSS, roda no CI)

**Files:**
- Create: `app/services/ramon/faq_de_conversa.rb`
- Test: `spec/services/ramon/faq_de_conversa_spec.rb` (novo)

**Interfaces:**
- Consumes: `Ramon::Pseudonymizer.mask(texto, names:)` (`lib/ramon/pseudonymizer.rb:23`); `Ramon::IaGastoAlerta.teto(account)` e `.gasto_hoje(account_id)` (`app/services/ramon/ia_gasto_alerta.rb:10,14`); `Conversation#to_llm_text(config)` (`app/models/concerns/llm_formattable.rb:4`, `token_limit` em `conversation_llm_formatter.rb:31`).
- Produces:
  - `Ramon::FaqDeConversa::Recusa < StandardError` — `message` é o código para o front: `'SEM_RESPOSTA'` ou `'SEM_PERGUNTA'`.
  - `Ramon::FaqDeConversa.de_mensagem(mensagem) → { question: String, answer: String }` (pseudonimizados; pergunta ≤ 500 caracteres) ou `raise Recusa`.
  - `Ramon::FaqDeConversa.texto(conversa) → String` (fim da conversa, ≤ 8.000 caracteres de mensagens, sem notas privadas, pseudonimizado).
  - `Ramon::FaqDeConversa::PROMPT` (String congelada, pede JSON `{"faqs": [{"question", "answer"}]}`).
  - `Ramon::FaqDeConversa.pausada?(account) → Boolean`.

- [ ] **Step 1: Write the failing test** — criar `spec/services/ramon/faq_de_conversa_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::FaqDeConversa do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria Souza', email: 'maria@exemplo.com') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }

  def msg(tipo, texto, privada: false)
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: tipo,
                     content: texto, private: privada)
  end

  describe '.de_mensagem' do
    it 'junta as bolhas do lead desde a última resposta enviada e mascara os dados pessoais', :aggregate_failures do
      msg(:incoming, 'Oi, quanto custa?')
      msg(:outgoing, 'Você só paga se ganhar.')
      msg(:incoming, 'Sou a Maria Souza, CPF 123.456.789-09')
      msg(:outgoing, 'Anotei aqui.', privada: true)
      msg(:incoming, 'Precisa pagar a perícia?')
      resposta = msg(:outgoing, 'Maria, a perícia do INSS é gratuita.')

      faq = described_class.de_mensagem(resposta)

      expect(faq[:question]).to eq("Sou a [nome], CPF [cpf]\nPrecisa pagar a perícia?")
      expect(faq[:answer]).to eq('[nome], a perícia do INSS é gratuita.')
    end

    it 'mascara também o nome do lead (diferente do contato)' do
      create(:lead, account: account, conversation_id: conversa.id, name: 'Joana Dores')
      msg(:incoming, 'A Joana pode ir no meu lugar?')
      resposta = msg(:outgoing, 'Pode sim.')

      expect(described_class.de_mensagem(resposta)[:question]).to eq('A [nome] pode ir no meu lugar?')
    end

    it 'corta pergunta muito longa' do
      msg(:incoming, 'a' * 900)
      resposta = msg(:outgoing, 'Certo.')

      expect(described_class.de_mensagem(resposta)[:question].length).to eq(described_class::LIMITE_PERGUNTA)
    end

    it 'recusa nota privada, mensagem do lead e resposta sem pergunta antes', :aggregate_failures do
      nota = msg(:outgoing, 'nota interna', privada: true)
      expect { described_class.de_mensagem(nota) }.to raise_error(described_class::Recusa, 'SEM_RESPOSTA')

      do_lead = msg(:incoming, 'Oi')
      expect { described_class.de_mensagem(do_lead) }.to raise_error(described_class::Recusa, 'SEM_RESPOSTA')

      msg(:outgoing, 'Olá!')
      sozinha = msg(:outgoing, 'Posso ajudar?')
      expect { described_class.de_mensagem(sozinha) }.to raise_error(described_class::Recusa, 'SEM_PERGUNTA')
    end
  end

  describe '.texto' do
    it 'manda o fim da conversa sem notas privadas e com os dados mascarados', :aggregate_failures do
      msg(:incoming, 'Meu telefone é (48) 99999-8888, sou a Maria Souza')
      msg(:outgoing, 'RASCUNHO segredo interno', privada: true)

      texto = described_class.texto(conversa)

      expect(texto).to include('[telefone]', '[nome]')
      expect(texto).not_to include('99999')
      expect(texto).not_to include('Maria')
      expect(texto).not_to include('segredo')
    end

    it 'corta no limite: o começo de uma conversa longa não vai', :aggregate_failures do
      msg(:incoming, 'a' * 5_000)
      msg(:incoming, 'b' * 5_000)

      texto = described_class.texto(conversa)

      expect(texto).to include('b' * 100)
      expect(texto).not_to include('a' * 100)
    end
  end

  describe '.pausada?' do
    it 'só pausa com teto definido e o gasto do dia no teto', :aggregate_failures do
      expect(described_class.pausada?(account)).to be(false)

      account.update!(settings: (account.settings || {}).merge(Ramon::IaGastoAlerta::CHAVE_TETO => '1.00'))
      LlmChamada.create!(account: account, funcao: 'atendimento', custo_usd: 0.5)
      expect(described_class.pausada?(account)).to be(false)

      LlmChamada.create!(account: account, funcao: 'atendimento', custo_usd: 0.5)
      expect(described_class.pausada?(account)).to be(true)
    end
  end

  it 'o prompt traz a regra do honorário e proíbe dado pessoal', :aggregate_failures do
    expect(described_class::PROMPT).to include('30% dos atrasados + 3 parcelas do benefício')
    expect(described_class::PROMPT).to include('sem nome, CPF')
  end
end
```

Rastreio à mão: `'Sou a Maria Souza, CPF 123.456.789-09'` → `name_tokens(['Maria Souza', nil])` = `['Maria Souza', 'Maria', 'Souza']` (maior primeiro) → `Sou a [nome], CPF 123.456.789-09` → `CPF` → `[cpf]`. A nota privada (outgoing, `private: true`) não conta como "última resposta enviada" → as duas bolhas do lead entram. O `'a' * 5_000` some porque o formatter percorre do fim e para quando passa de 8.000 (`conversation_llm_formatter.rb:53-62`).

- [ ] **Step 2: Run test to verify it fails** — sem Ruby local: conferir à mão que `Ramon::FaqDeConversa` não existe (`grep -rn "FaqDeConversa" app lib` vazio). O CI validará.

- [ ] **Step 3: Write minimal implementation** — criar `app/services/ramon/faq_de_conversa.rb`:

```ruby
# FAQ a partir das conversas (Inteligência A4) — as peças sem Captain, que o CI testa:
#   - de_mensagem: "Virar FAQ" (I-X1) — a pergunta é o que o lead escreveu logo antes da resposta. SEM IA.
#   - texto + PROMPT: o que vai ao LLM na geração das conversas resolvidas (I-X2).
#   - pausada?: a geração automática para no dia em que o gasto chega ao teto do alerta (tela Uso e custo).
# LGPD: pergunta, resposta e conversa passam pelo Ramon::Pseudonymizer (nome do contato e do lead, CPF, RG,
# telefone, e-mail, CEP, endereço viram [marcador]); quem aprova a FAQ ajusta o texto.
# A FAQ nasce PENDENTE e o assistente só lê as aprovadas (faq_lookup_tool.rb: .approved.search).
module Ramon::FaqDeConversa
  class Recusa < StandardError; end

  LIMITE_CONVERSA = 8_000 # caracteres do fim da conversa (mesmo teto dos passos de IA dos fluxos)
  LIMITE_PERGUNTA = 500
  PROMPT = <<~TXT.freeze
    Você lê uma conversa de WhatsApp entre um escritório de advocacia previdenciária e trabalhista (Support Agent)
    e um lead (User), e transforma em FAQs curtas o que pode servir para OUTROS leads.
    Responda APENAS JSON válido, sem markdown: {"faqs": [{"question": "...", "answer": "..."}]}.
    Regras:
    - Só perguntas que o lead fez e que o atendente (Support Agent) respondeu; ignore o que o Bot escreveu.
    - Pergunta genérica, como outro lead perguntaria; resposta curta, só com o que o atendente disse.
    - Nada do caso concreto: sem nome, CPF, telefone, endereço, datas ou valores da pessoa; não copie marcadores como [nome].
    - Nunca prometa resultado nem prazo do INSS ou da Justiça.
    - Honorário só se o atendente falou, e sempre como 30% dos atrasados + 3 parcelas do benefício.
    - No máximo 3 FAQs. Se nada servir para outros leads, responda {"faqs": []}.
    - Escreva em português do Brasil.
  TXT

  module_function

  def de_mensagem(mensagem)
    raise Recusa, 'SEM_RESPOSTA' unless mensagem.outgoing? && !mensagem.private? && mensagem.content.present?

    pergunta = pergunta_antes(mensagem)
    raise Recusa, 'SEM_PERGUNTA' if pergunta.blank?

    nomes = nomes(mensagem.conversation)
    { question: Ramon::Pseudonymizer.mask(pergunta, names: nomes).truncate(LIMITE_PERGUNTA),
      answer: Ramon::Pseudonymizer.mask(mensagem.content, names: nomes) }
  end

  # As bolhas do lead entre a resposta anterior enviada (nota privada não conta) e esta.
  def pergunta_antes(mensagem)
    mensagens = mensagem.conversation.messages
    anterior = mensagens.where(message_type: :outgoing, private: false, id: ...mensagem.id).reorder(id: :desc).pick(:id) || 0
    mensagens.where(message_type: :incoming, id: (anterior + 1)...mensagem.id).reorder(:id).pluck(:content).compact_blank.join("\n")
  end

  def texto(conversa)
    Ramon::Pseudonymizer.mask(conversa.to_llm_text(token_limit: LIMITE_CONVERSA), names: nomes(conversa))
  end

  def pausada?(account)
    teto = Ramon::IaGastoAlerta.teto(account)
    teto.to_f.positive? && Ramon::IaGastoAlerta.gasto_hoje(account.id) >= teto
  end

  def nomes(conversa)
    [conversa.contact&.name, conversa.account.leads.find_by(conversation_id: conversa.id)&.name]
  end
end
```

Conferir o comprimento das duas linhas de `pergunta_antes` (≤ 150; se passar, quebrar a cadeia antes de `.reorder`).

- [ ] **Step 4: Run test to verify it passes** — rastrear à mão cada exemplo contra o código (Step 1 já traz o rastreio). Rubocop à mão: `module_function` + métodos curtos; `Style/HashSyntax` (sempre `chave: valor`); nenhuma referência a `Captain::*`.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/faq_de_conversa.rb spec/services/ramon/faq_de_conversa_spec.rb
git commit -m "feat(inteligencia): regras da FAQ a partir da conversa — pergunta do lead, dados mascarados e pausa pelo teto" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 3: Endpoint "virar FAQ" — `POST /conversations/:id/faqs` (enterprise)

**Files:**
- Create: `enterprise/app/controllers/api/v1/accounts/conversations/faqs_controller.rb`
- Modify: `config/routes.rb:160` (depois de `resource :ramon_copilot, …`)
- Test: `spec/enterprise/controllers/api/v1/accounts/conversations/faqs_controller_spec.rb` (novo — **não roda no CI**, documentação + prova manual)

**Interfaces:**
- Consumes: `Ramon::FaqDeConversa.de_mensagem` e `::Recusa` (Task 2); `Api::V1::Accounts::Conversations::BaseController#conversation` (acha pelo `display_id` e autoriza `show?` — `app/controllers/api/v1/accounts/conversations/base_controller.rb:6-9`).
- Produces: `POST /api/v1/accounts/:account_id/conversations/:conversation_id/faqs` com `{ message_id }` →
  - `201 { id, assistant_id, ja_existia: false }` (FAQ nova, `status: pending`, `documentable: a conversa`);
  - `200 { id, assistant_id, ja_existia: true }` (a mesma resposta já tinha virado FAQ — pendente ou aprovada);
  - `422 { erro: 'SEM_RESPOSTA' | 'SEM_PERGUNTA' | 'SEM_ASSISTENTE' }`; `404` mensagem de outra conversa; `401` quem não vê a conversa.

- [ ] **Step 1: Write the failing test** — criar `spec/enterprise/controllers/api/v1/accounts/conversations/faqs_controller_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Conversations::Faqs', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistente) { create(:captain_assistant, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/faqs" }

  before do
    create(:inbox_member, user: agente, inbox: inbox)
    create(:captain_inbox, captain_assistant: assistente, inbox: inbox)
    create(:message, account: account, conversation: conversa, inbox: inbox, message_type: :incoming, content: 'A perícia é paga?')
  end

  def resposta(texto = 'Não, é gratuita.', privada: false)
    create(:message, account: account, conversation: conversa, inbox: inbox, message_type: :outgoing, content: texto, private: privada)
  end

  def virar(mensagem, usuario = agente)
    post url, params: { message_id: mensagem.id }, headers: usuario.create_new_auth_token, as: :json
  end

  it 'cria a FAQ PENDENTE ligada à conversa e o 2º clique devolve a mesma', :aggregate_failures do
    mensagem = resposta
    virar(mensagem)

    expect(response).to have_http_status(:created)
    faq = assistente.responses.last
    expect(faq).to have_attributes(question: 'A perícia é paga?', answer: 'Não, é gratuita.', status: 'pending', documentable: conversa)

    virar(mensagem)
    expect(response.parsed_body).to include('id' => faq.id, 'assistant_id' => assistente.id, 'ja_existia' => true)
    expect(assistente.responses.count).to eq(1)
  end

  it 'nota privada não vira FAQ (422 SEM_RESPOSTA)', :aggregate_failures do
    virar(resposta('nota', privada: true))

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq('erro' => 'SEM_RESPOSTA')
  end

  it 'caixa sem assistente usa o assistente que atende alguma caixa; sem nenhum, 422 SEM_ASSISTENTE', :aggregate_failures do
    outra = create(:inbox, account: account)
    create(:inbox_member, user: agente, inbox: outra)
    conversa_outra = create(:conversation, account: account, inbox: outra)
    create(:message, account: account, conversation: conversa_outra, inbox: outra, message_type: :incoming, content: 'Oi?')
    mensagem = create(:message, account: account, conversation: conversa_outra, inbox: outra, message_type: :outgoing, content: 'Olá!')
    post "/api/v1/accounts/#{account.id}/conversations/#{conversa_outra.display_id}/faqs",
         params: { message_id: mensagem.id }, headers: agente.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('assistant_id' => assistente.id)

    CaptainInbox.delete_all
    virar(resposta('Outra resposta.'))
    expect(response.parsed_body).to eq('erro' => 'SEM_ASSISTENTE')
  end

  it 'quem não vê a conversa não cria' do
    de_fora = create(:user, account: account, role: :agent)
    virar(resposta, de_fora)

    expect(response).to have_http_status(:unauthorized)
  end
end
```

- [ ] **Step 2: Run test to verify it fails** — à mão: a rota não existe (`grep -n "faqs" config/routes.rb` não acha nada no bloco de conversas).

- [ ] **Step 3: Write minimal implementation**

Em `config/routes.rb`, logo depois da linha `resource :ramon_copilot, only: [:create], controller: 'ramon_copilot'` (dentro de `scope module: :conversations do`):

```ruby
              # ramon: "Virar FAQ" numa resposta da conversa (Inteligência A4 — I-X1)
              resources :faqs, only: [:create] if ChatwootApp.enterprise?
```

Criar `enterprise/app/controllers/api/v1/accounts/conversations/faqs_controller.rb`:

```ruby
# "Virar FAQ" (Inteligência A4 — I-X1): uma resposta enviada ao lead vira FAQ PENDENTE do assistente que
# atende leads, com a pergunta que o lead fez logo antes (Ramon::FaqDeConversa — sem IA, dados mascarados).
# Quem vê a conversa pode criar; só administrador aprova (update/bulk_actions = AssistantPolicy admin).
# Clicar de novo na mesma resposta devolve a mesma FAQ.
class Api::V1::Accounts::Conversations::FaqsController < Api::V1::Accounts::Conversations::BaseController
  def create
    mensagem = @conversation.messages.find(params[:message_id])
    assistente = assistente_de_leads
    return render(json: { erro: 'SEM_ASSISTENTE' }, status: :unprocessable_content) if assistente.nil?

    faq = Ramon::FaqDeConversa.de_mensagem(mensagem)
    existente = assistente.responses.find_by(documentable: @conversation, answer: faq[:answer])
    return render(json: corpo(existente, true)) if existente

    render json: corpo(assistente.responses.create!(faq.merge(status: :pending, documentable: @conversation)), false),
           status: :created
  rescue Ramon::FaqDeConversa::Recusa => e
    render json: { erro: e.message }, status: :unprocessable_content
  end

  private

  # O assistente da caixa desta conversa; se a caixa não tem, o primeiro que atende alguma caixa (o Atendimento).
  def assistente_de_leads
    @conversation.inbox.captain_assistant ||
      Current.account.captain_assistants.joins(:captain_inboxes).order(:id).first
  end

  def corpo(faq, ja_existia)
    { id: faq.id, assistant_id: faq.assistant_id, ja_existia: ja_existia }
  end
end
```

- [ ] **Step 4: Run test to verify it passes** — rastrear à mão: `create(:captain_inbox, captain_assistant:, inbox:)` liga `inbox.captain_assistant` (`enterprise/app/models/enterprise/concerns/inbox.rb:5-8`); `find_by(documentable: @conversation, …)` funciona no polimórfico; `Pundit::NotAuthorizedError` vira 401 no `Api::BaseController`. Rubocop: `create` ≤ 19 linhas, AbcSize < 26.

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb enterprise/app/controllers/api/v1/accounts/conversations/faqs_controller.rb spec/enterprise/controllers/api/v1/accounts/conversations/faqs_controller_spec.rb
git commit -m "feat(inteligencia): endpoint para virar FAQ pendente a partir de uma resposta da conversa" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 4: Front — "Virar FAQ" no menu da mensagem

**Files:**
- Create: `app/javascript/dashboard/api/captain/faqDeConversa.js`
- Create: `app/javascript/dashboard/modules/conversations/components/VirarFaqMenuItem.vue`
- Modify: `app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue:14-24` (import/registro) e `:237-245` (item depois de "Criar resposta pronta")
- Modify: `app/javascript/dashboard/components-next/message/Message.vue:374-397` (`contextMenuEnabledOptions`)
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` (bloco `CAPTAIN_RAMON.FAQ_CONVERSA` no fim de `CAPTAIN_RAMON`)
- Test: `app/javascript/dashboard/modules/conversations/components/specs/VirarFaqMenuItem.spec.js` (novo), `app/javascript/dashboard/modules/conversations/components/specs/textosA4.spec.js` (novo)

**Interfaces:**
- Consumes: `POST conversations/:id/faqs` (Task 3); `useAccount().accountScopedRoute`; rota `captain_assistants_responses_pending` (`captain.routes.js:86-90`, param `assistantId`); `useAlert(message, { type: 'link', to, message })` (padrão de `RodarFluxo.vue:64-71`).
- Produces: `FaqDeConversaAPI.virarFaq(conversationId, messageId)`; `<VirarFaqMenuItem :conversation-id :message-id @close>`; opção `virarFaq` em `contextMenuEnabledOptions`; chaves `CAPTAIN_RAMON.FAQ_CONVERSA.{MENU, CRIADA, JA_EXISTIA, VER_PENDENTES, ERROS.{SEM_RESPOSTA, SEM_PERGUNTA, SEM_ASSISTENTE, GERAL}}`; `textosA4.spec.js` com a lista `BLOCOS = ['FAQ_CONVERSA']` (a Task 7 acrescenta `'COPILOTO_ATALHOS'`).

- [ ] **Step 1: Write the failing tests**

`app/javascript/dashboard/modules/conversations/components/specs/VirarFaqMenuItem.spec.js`:

```js
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import FaqDeConversaAPI from 'dashboard/api/captain/faqDeConversa';
import VirarFaqMenuItem from '../VirarFaqMenuItem.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/api/captain/faqDeConversa', () => ({
  default: { virarFaq: vi.fn() },
}));

const montar = () =>
  mount(VirarFaqMenuItem, {
    props: { conversationId: 12, messageId: 345 },
    global: { stubs: { 'fluent-icon': true } },
  });

const clicar = async wrapper => {
  await wrapper.find('[data-testid="virar-faq"]').trigger('click');
  await flushPromises();
};

describe('Virar FAQ (menu da mensagem)', () => {
  it('cria a FAQ pendente e o aviso leva às pendentes do assistente', async () => {
    FaqDeConversaAPI.virarFaq.mockResolvedValue({
      data: { id: 9, assistant_id: 3, ja_existia: false },
    });
    const wrapper = montar();

    await clicar(wrapper);

    expect(FaqDeConversaAPI.virarFaq).toHaveBeenCalledWith(12, 345);
    expect(useAlert).toHaveBeenCalledWith(
      'FAQ created as pending. An administrator approves it before the assistant uses it.',
      {
        type: 'link',
        to: {
          name: 'captain_assistants_responses_pending',
          params: { assistantId: 3 },
        },
        message: 'See pending FAQs',
      }
    );
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('2º clique na mesma resposta avisa que já virou FAQ', async () => {
    FaqDeConversaAPI.virarFaq.mockResolvedValue({
      data: { id: 9, assistant_id: 3, ja_existia: true },
    });
    const wrapper = montar();

    await clicar(wrapper);

    expect(useAlert.mock.calls[0][0]).toBe(
      'This reply is already a FAQ (pending or approved).'
    );
  });

  it.each([
    ['SEM_PERGUNTA', 'No lead question found before this reply.'],
    ['QUALQUER', 'Could not create the FAQ. Try again.'],
  ])('erro %s vira texto claro', async (erro, texto) => {
    FaqDeConversaAPI.virarFaq.mockRejectedValue({
      response: { data: { erro } },
    });
    const wrapper = montar();

    await clicar(wrapper);

    expect(useAlert).toHaveBeenCalledWith(texto);
    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('clique duplo enquanto envia chama a API uma vez', async () => {
    FaqDeConversaAPI.virarFaq.mockResolvedValue({
      data: { id: 9, assistant_id: 3, ja_existia: false },
    });
    const wrapper = montar();
    const item = wrapper.find('[data-testid="virar-faq"]');

    await item.trigger('click');
    await item.trigger('click');
    await flushPromises();

    expect(FaqDeConversaAPI.virarFaq).toHaveBeenCalledTimes(1);
  });
});
```

`app/javascript/dashboard/modules/conversations/components/specs/textosA4.spec.js`:

```js
import { createI18n } from 'vue-i18n/dist/vue-i18n.cjs.prod.js';
import en from 'dashboard/i18n/locale/en/ramon.json';
import pt from 'dashboard/i18n/locale/pt_BR/ramon.json';

// Blocos de texto da Inteligência A4 (menu "Virar FAQ" e atalhos do Copiloto).
const BLOCOS = ['FAQ_CONVERSA'];

const folhas = (obj, prefixo = '') =>
  Object.entries(obj).flatMap(([k, v]) =>
    typeof v === 'object'
      ? folhas(v, `${prefixo}${k}.`)
      : [[`${prefixo}${k}`, v]]
  );

describe.each(BLOCOS)('textos da A4: %s', bloco => {
  const textosEn = en.CAPTAIN_RAMON[bloco];
  const textosPt = pt.CAPTAIN_RAMON[bloco];

  it('en e pt_BR têm as mesmas chaves, na mesma ordem', () => {
    expect(folhas(textosPt).map(([k]) => k)).toEqual(
      folhas(textosEn).map(([k]) => k)
    );
  });

  it.each([
    ['en', textosEn],
    ['pt_BR', textosPt],
  ])('%s: sem @ | e chaves soltas', (_l, textos) => {
    folhas(textos).forEach(([chave, texto]) => {
      expect([chave, /[@|{}]/.test(texto)]).toEqual([chave, false]);
    });
  });

  // Trava de sintaxe: o compilador de PRODUÇÃO lança em qualquer erro.
  it.each([
    ['en', en, textosEn],
    ['pt_BR', pt, textosPt],
  ])('%s: compila no vue-i18n de produção', (loc, raiz, textos) => {
    const i18n = createI18n({
      legacy: false,
      locale: loc,
      messages: { [loc]: raiz },
      missingWarn: false,
      fallbackWarn: false,
    });
    const erros = [];
    folhas(textos).forEach(([chave]) => {
      const completa = `CAPTAIN_RAMON.${bloco}.${chave}`;
      try {
        if (i18n.global.t(completa) === completa) erros.push(completa);
      } catch (e) {
        erros.push(`${completa}: ${e.message}`);
      }
    });
    expect(erros).toEqual([]);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/modules/conversations/components/specs --config vitest.local.config.ts`
Expected: FAIL (`VirarFaqMenuItem.vue` não existe; `CAPTAIN_RAMON.FAQ_CONVERSA` indefinido).

- [ ] **Step 3: Write minimal implementation**

`app/javascript/dashboard/api/captain/faqDeConversa.js`:

```js
/* global axios */
import ApiClient from '../ApiClient';

// "Virar FAQ" numa resposta da conversa (Inteligência A4): cria FAQ PENDENTE.
class FaqDeConversa extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  virarFaq(conversationId, messageId) {
    return axios.post(`${this.url}/${conversationId}/faqs`, {
      message_id: messageId,
    });
  }
}

export default new FaqDeConversa();
```

`app/javascript/dashboard/modules/conversations/components/VirarFaqMenuItem.vue`:

```vue
<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import FaqDeConversaAPI from 'dashboard/api/captain/faqDeConversa';
import MenuItem from 'dashboard/components/widgets/conversation/contextMenu/menuItem.vue';

const props = defineProps({
  conversationId: { type: Number, required: true },
  messageId: { type: Number, required: true },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const K = 'CAPTAIN_RAMON.FAQ_CONVERSA';
const ERROS = ['SEM_RESPOSTA', 'SEM_PERGUNTA', 'SEM_ASSISTENTE'];
const enviando = ref(false);

// 1 clique: a FAQ nasce PENDENTE; o aviso leva às pendentes (só administrador aprova).
const virarFaq = async () => {
  if (enviando.value) return;
  enviando.value = true;
  try {
    const { data } = await FaqDeConversaAPI.virarFaq(
      props.conversationId,
      props.messageId
    );
    useAlert(t(`${K}.${data.ja_existia ? 'JA_EXISTIA' : 'CRIADA'}`), {
      type: 'link',
      to: accountScopedRoute('captain_assistants_responses_pending', {
        assistantId: data.assistant_id,
      }),
      message: t(`${K}.VER_PENDENTES`),
    });
  } catch (e) {
    const codigo = e.response?.data?.erro;
    useAlert(t(`${K}.ERROS.${ERROS.includes(codigo) ? codigo : 'GERAL'}`));
  } finally {
    enviando.value = false;
    emit('close');
  }
};
</script>

<template>
  <MenuItem
    :option="{ icon: 'book-outline', label: t(`${K}.MENU`) }"
    variant="icon"
    data-testid="virar-faq"
    @click.stop="virarFaq"
  />
</template>
```

`MessageContextMenu.vue` — acrescentar o import junto dos outros (depois da linha 16 `import NextButton …`):

```js
import VirarFaqMenuItem from './VirarFaqMenuItem.vue';
```

registrar em `components` (linhas 19-24):

```js
  components: {
    AddCannedModal,
    MenuItem,
    ContextMenu,
    NextButton,
    VirarFaqMenuItem,
  },
```

e, no template, logo depois do `MenuItem` de `enabledOptions['cannedResponse']` (linhas 237-245):

```vue
        <VirarFaqMenuItem
          v-if="enabledOptions['virarFaq']"
          :conversation-id="conversationId"
          :message-id="messageId"
          @close="handleClose"
        />
```

`Message.vue` — em `contextMenuEnabledOptions` (linha 389, depois de `cannedResponse: …`):

```js
    // ramon (A4): só resposta enviada ao lead (não nota privada) vira FAQ pendente
    virarFaq:
      isOutgoing &&
      hasText &&
      !props.private &&
      !isMessageDeleted.value &&
      !isFailedOrProcessing,
```

`ramon.json` — no fim de `CAPTAIN_RAMON`, depois do fechamento de `MESSAGE_TEMPLATES`. Em `pt_BR/ramon.json`, trocar o fim do arquivo

```json
        "DISABLED": "Desativado"
      }
    }
  }
}
```
por
```json
        "DISABLED": "Desativado"
      }
    },
    "FAQ_CONVERSA": {
      "MENU": "Virar FAQ",
      "CRIADA": "FAQ criada como pendente. Um administrador aprova antes de o assistente usar.",
      "JA_EXISTIA": "Esta resposta já virou FAQ (pendente ou aprovada).",
      "VER_PENDENTES": "Ver FAQs pendentes",
      "ERROS": {
        "SEM_RESPOSTA": "Só uma resposta enviada ao lead vira FAQ.",
        "SEM_PERGUNTA": "Não achei pergunta do lead antes desta resposta.",
        "SEM_ASSISTENTE": "Nenhum assistente atende leads ainda: conecte o Atendimento a uma caixa.",
        "GERAL": "Não consegui criar a FAQ. Tente de novo."
      }
    }
  }
}
```
e em `en/ramon.json`, trocar
```json
        "DISABLED": "Disabled"
      }
    }
  }
}
```
por
```json
        "DISABLED": "Disabled"
      }
    },
    "FAQ_CONVERSA": {
      "MENU": "Turn into FAQ",
      "CRIADA": "FAQ created as pending. An administrator approves it before the assistant uses it.",
      "JA_EXISTIA": "This reply is already a FAQ (pending or approved).",
      "VER_PENDENTES": "See pending FAQs",
      "ERROS": {
        "SEM_RESPOSTA": "Only a reply sent to the lead can become a FAQ.",
        "SEM_PERGUNTA": "No lead question found before this reply.",
        "SEM_ASSISTENTE": "No assistant serves leads yet: connect the customer service assistant to an inbox.",
        "GERAL": "Could not create the FAQ. Try again."
      }
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/modules/conversations/components/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/api/captain/faqDeConversa.js app/javascript/dashboard/modules/conversations/components app/javascript/dashboard/components-next/message/Message.vue
node -e "require('./app/javascript/dashboard/i18n/locale/pt_BR/ramon.json');require('./app/javascript/dashboard/i18n/locale/en/ramon.json')"
```
Expected: 2 arquivos verdes (4 + 5 casos no `VirarFaqMenuItem`; 5 no `textosA4`); eslint sem `error`; os dois JSON carregam.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/api/captain/faqDeConversa.js app/javascript/dashboard/modules/conversations/components/VirarFaqMenuItem.vue app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue app/javascript/dashboard/components-next/message/Message.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/modules/conversations/components/specs/VirarFaqMenuItem.spec.js app/javascript/dashboard/modules/conversations/components/specs/textosA4.spec.js
git commit -m "feat(inteligencia): Virar FAQ no menu da mensagem — FAQ pendente com 1 clique" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 5: Gerar FAQs das conversas resolvidas — LGPD, prompt da banca, modelo da tela, custo próprio e pausa pelo teto

**Files:**
- Modify: `enterprise/app/services/captain/llm/conversation_faq_service.rb:6-24` (initialize + guarda) e `:121-124` (`system_prompt`)
- Modify: `lib/ramon/llm_uso.rb:10-13` (`FUNCOES`)
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/integrations.json:524` (`ALLOW_CONVERSATION_FAQS`)
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramonIaUso.json` (`ESCOLHA.FUNCOES.documentos`, `ESCOLHA.DESCRICOES.documentos`, `FUNCOES.faq_conversa` novo depois de `documentos`)
- Test: `spec/lib/ramon/llm_uso_spec.rb` (1 exemplo novo); `spec/enterprise/services/captain/llm/conversation_faq_service_spec.rb` (1 `describe` novo — não roda no CI)

**Interfaces:**
- Consumes: `Ramon::FaqDeConversa.texto`, `::PROMPT`, `.pausada?` (Task 2); `Ramon::LlmEscolha.para(account, 'documentos')` (`lib/ramon/llm_escolha.rb:20`).
- Produces: função `faq_conversa` em `ramon_llm_chamadas` (rótulo "FAQ de conversa" na tela Uso e custo); a escolha de modelo "Documentos" passa a valer para as duas gerações de FAQ (rótulo "FAQs geradas (documentos e conversas)").

- [ ] **Step 1: Write the failing tests**

Em `spec/lib/ramon/llm_uso_spec.rb`, depois do exemplo `.de_instrumentacao traduz o feature_name…` (linha 75):

```ruby
  it '.de_instrumentacao: a FAQ de conversa tem linha própria na tela' do
    dados = described_class.de_instrumentacao(account_id: 1, feature_name: 'conversation_faq', model: 'deepseek-chat')

    expect(dados).to include(funcao: 'faq_conversa', model: 'deepseek-chat')
  end
```

Em `spec/enterprise/services/captain/llm/conversation_faq_service_spec.rb`, antes do último `end` do `describe '#generate_and_deduplicate'`:

```ruby
    describe 'regras da banca (Inteligência A4)' do
      it 'não chama a IA no dia em que o gasto chegou ao teto' do
        allow(Ramon::FaqDeConversa).to receive(:pausada?).and_return(true)

        expect(RubyLLM).not_to receive(:chat)
        expect(service.generate_and_deduplicate).to eq([])
      end

      it 'manda a conversa pseudonimizada com o prompt da banca', :aggregate_failures do
        allow(Ramon::FaqDeConversa).to receive(:texto).and_return('conversa mascarada')
        allow(captain_assistant.responses).to receive(:where).and_return([])

        service.generate_and_deduplicate

        expect(mock_chat).to have_received(:with_instructions).with(Ramon::FaqDeConversa::PROMPT)
        expect(mock_chat).to have_received(:ask).with('conversa mascarada')
      end
    end
```

(O `service` do spec é `let` preguiçoso — o stub de `texto` vale porque o `initialize` só roda no 1º uso.)

- [ ] **Step 2: Run test to verify it fails** — à mão: `FUNCOES` não tem `conversation_faq` (`lib/ramon/llm_uso.rb:10-13`); o serviço usa `conversation.to_llm_text` e o prompt do upstream.

- [ ] **Step 3: Write minimal implementation**

`lib/ramon/llm_uso.rb` — `FUNCOES` passa a ser:

```ruby
  FUNCOES = {
    'summarize' => 'resumo', 'assistant' => 'atendimento', 'copilot' => 'copiloto_captain',
    'faq_generator' => 'documentos', 'faq_generation' => 'documentos', 'paginated_faq_generation' => 'documentos',
    'conversation_faq' => 'faq_conversa'
  }.freeze
```

`conversation_faq_service.rb` — `initialize` (linhas 6-11) passa a ser:

```ruby
  def initialize(assistant, conversation)
    super()
    @assistant = assistant
    @conversation = conversation
    # FORK-PONTO (ramon, A4): fim da conversa, sem notas privadas e pseudonimizado (LGPD) — Ramon::FaqDeConversa
    @content = Ramon::FaqDeConversa.texto(conversation)
    # ramon: modelo das "FAQs geradas" (tela Uso e custo — a mesma escolha dos Documentos)
    @model = Ramon::LlmEscolha.para(conversation.account, 'documentos')[:model]
  end
```

`generate_and_deduplicate` (linhas 15-16):

```ruby
  def generate_and_deduplicate
    # ramon: no dia em que o gasto chega ao teto do alerta, a geração automática para
    return [] if no_human_interaction? || Ramon::FaqDeConversa.pausada?(conversation.account)
```

`system_prompt` (linhas 121-124):

```ruby
  # FORK-PONTO (ramon, A4): prompt da banca — FAQ genérica, sem dado pessoal, regras da OAB, no máximo 3
  def system_prompt
    Ramon::FaqDeConversa::PROMPT
  end
```

`integrations.json` — só `en` e `pt_BR`, linha 524:
- pt_BR: `"ALLOW_CONVERSATION_FAQS": "Gerar FAQs pendentes das conversas resolvidas (só valem depois que um administrador aprovar)",`
- en: `"ALLOW_CONVERSATION_FAQS": "Generate pending FAQs from resolved conversations (they only count after an administrator approves them)",`

`ramonIaUso.json` (mesma posição nos dois):
- `IA_USO.ESCOLHA.FUNCOES.documentos`: pt `"FAQs geradas (documentos e conversas)"`, en `"Generated FAQs (documents and conversations)"`.
- `IA_USO.ESCOLHA.DESCRICOES.documentos`: pt `"Gera as FAQs pendentes a partir de um documento enviado e das conversas resolvidas."`, en `"Generates pending FAQs from an uploaded document and from resolved conversations."`.
- `IA_USO.FUNCOES`: nova linha logo depois de `"documentos": …` — pt `"faq_conversa": "FAQ de conversa",`, en `"faq_conversa": "Conversation FAQ",`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/pages/specs/UsoCustoI18n.spec.js app/javascript/dashboard/routes/dashboard/captain/pages/specs/UsoCusto.spec.js --config vitest.local.config.ts
node -e "for (const l of ['en','pt_BR']) { require('./app/javascript/dashboard/i18n/locale/'+l+'/integrations.json'); require('./app/javascript/dashboard/i18n/locale/'+l+'/ramonIaUso.json') }"
```
Expected: verdes (a trava compara a ordem das chaves); JSON carregam. Ruby rastreado à mão: `de_instrumentacao` → `funcao_captain('conversation_faq')` → `'faq_conversa'`; `FUNCOES` em 3 linhas ≤ 150.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/llm/conversation_faq_service.rb lib/ramon/llm_uso.rb app/javascript/dashboard/i18n/locale/en/integrations.json app/javascript/dashboard/i18n/locale/pt_BR/integrations.json app/javascript/dashboard/i18n/locale/en/ramonIaUso.json app/javascript/dashboard/i18n/locale/pt_BR/ramonIaUso.json spec/lib/ramon/llm_uso_spec.rb spec/enterprise/services/captain/llm/conversation_faq_service_spec.rb
git commit -m "feat(inteligencia): FAQs das conversas resolvidas com prompt da banca, conversa mascarada, custo próprio e pausa pelo teto" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 6: Painel do Copiloto roda as skills do Copiloto do Escritório, com o contexto do caso (backend)

**Files:**
- Create: `app/services/ramon/copiloto_painel.rb` + `spec/services/ramon/copiloto_painel_spec.rb` (FOSS, roda no CI)
- Create: `enterprise/app/services/captain/copilot/skills_service.rb` + `spec/enterprise/services/captain/copilot/skills_service_spec.rb` (não roda no CI)
- Modify: `enterprise/app/jobs/captain/copilot/response_job.rb:17-27`
- Modify: `lib/ramon/llm_uso.rb:58-61` (`registrar_agente`)
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramonIaUso.json` (`FUNCOES.copiloto_painel` depois de `copiloto_captain`; `ESCOLHA.DESCRICOES.atendimento`)
- Test: `spec/lib/ramon/llm_uso_spec.rb` (1 exemplo novo)

**Interfaces:**
- Consumes: `CopilotThread#previous_history → [{ content:, role: 'user'|'assistant' }]` (`enterprise/app/models/copilot_thread.rb:37-47`); `Captain::Assistant::AgentRunnerService.new(assistant:, source:).generate_response(message_history:) → Hash` com `'response'`, `'reasoning'` (`agent_runner_service.rb:16-41`, erro = `'reasoning' => 'Error occurred: …'`, `'response' => 'conversation_handoff'`); `Ramon::CockpitMetrics::TIME_ZONE`.
- Produces:
  - `Ramon::CopilotoPainel.contexto(account, display_id) → String`; `Ramon::CopilotoPainel.com_contexto(historico, account, display_id) → Array<Hash>` (contexto na frente **só** da última mensagem do usuário; o histórico salvo fica limpo).
  - `Captain::Copilot::SkillsService.usa?(assistant) → Boolean` (v2 ligado + assistente **sem caixa** + skills ligadas); `.new(assistant, conversation_id:, copilot_thread_id:).responder → CopilotMessage` (sempre cria a resposta `assistant` — em erro, o texto `ERRO`).
  - Função `copiloto_painel` em `ramon_llm_chamadas` (source `'copiloto_painel'`).

- [ ] **Step 1: Write the failing tests**

`spec/services/ramon/copiloto_painel_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::CopilotoPainel do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria Souza', email: 'maria@exemplo.com', phone_number: '+5548999998888') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }

  before { travel_to Time.zone.parse('2026-10-07 15:00:00 UTC') }

  describe '.contexto' do
    it 'leva o caso, o nome do cliente e a data de hoje — sem telefone nem e-mail', :aggregate_failures do
      lead = create(:lead, account: account, conversation_id: conversa.id, name: 'Maria Souza')

      texto = described_class.contexto(account, conversa.display_id)

      expect(texto).to include("caso #{lead.id} do hub (lead_id=#{lead.id})", 'cliente Maria Souza', "conversa ##{conversa.display_id}")
      expect(texto).to start_with('Contexto: hoje é 07/10/2026; a equipe')
      expect(texto).not_to include('99999')
      expect(texto).not_to include('maria@exemplo.com')
    end

    it 'conversa sem caso usa o nome do contato' do
      expect(described_class.contexto(account, conversa.display_id)).to include('sem caso no hub', 'cliente Maria Souza')
    end

    it 'sem conversa aberta diz isso (e a data)' do
      expect(described_class.contexto(account, nil)).to eq('Contexto: hoje é 07/10/2026; nenhuma conversa aberta na tela.')
    end
  end

  it '.com_contexto põe o contexto só na última pergunta da pessoa', :aggregate_failures do
    historico = [{ role: 'user', content: 'primeira' }, { role: 'assistant', content: 'resposta' }, { role: 'user', content: 'segunda' }]

    novo = described_class.com_contexto(historico, account, nil)

    expect(novo[0]).to eq(role: 'user', content: 'primeira')
    expect(novo[1]).to eq(role: 'assistant', content: 'resposta')
    expect(novo[2][:content]).to eq("Contexto: hoje é 07/10/2026; nenhuma conversa aberta na tela.\n\nsegunda")
    expect(historico[2][:content]).to eq('segunda')
  end
end
```

(15:00 UTC = 12:00 em Brasília → 07/10. `travel_to` no `before` — um só, sem aninhar.)

Em `spec/lib/ramon/llm_uso_spec.rb`, no fim do `describe` principal:

```ruby
  it '.registrar_agente: o painel do Copiloto tem linha própria (não soma no Atendimento)' do
    assistente = Struct.new(:id, :account_id, :account).new(7, account.id, account)
    resultado = Struct.new(:usage, :error).new(Struct.new(:input_tokens, :output_tokens).new(10, 2), nil)

    described_class.registrar_agente(assistant: assistente, result: resultado, inicio: described_class.agora_ms, source: 'copiloto_painel')

    expect(LlmChamada.last).to have_attributes(funcao: 'copiloto_painel', assistant_id: 7, input_tokens: 10, output_tokens: 2)
  end
```

`spec/enterprise/services/captain/copilot/skills_service_spec.rb` (documentação; não roda no CI):

```ruby
require 'rails_helper'

RSpec.describe Captain::Copilot::SkillsService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:copiloto) { create(:captain_assistant, account: account) }
  let(:thread) { create(:captain_copilot_thread, account: account, user: user, assistant: copiloto) }
  let(:runner) { instance_double(Captain::Assistant::AgentRunnerService) }

  before do
    create(:captain_copilot_message, copilot_thread: thread, message_type: :user, message: { content: 'Situação do processo?' })
    allow(Captain::Assistant::AgentRunnerService).to receive(:new)
      .with(assistant: copiloto, source: 'copiloto_painel').and_return(runner)
  end

  def responder = described_class.new(copiloto, conversation_id: nil, copilot_thread_id: thread.id).responder

  it 'roda o agente com o contexto na pergunta e grava a resposta no painel', :aggregate_failures do
    allow(runner).to receive(:generate_response).and_return({ 'response' => 'Processo em perícia.' })

    expect(responder).to have_attributes(message_type: 'assistant', message: { 'content' => 'Processo em perícia.' })
    expect(runner).to have_received(:generate_response) do |message_history:|
      expect(message_history.last[:content]).to start_with('Contexto: hoje é')
    end
  end

  it 'erro do agente vira mensagem no painel (o "pensando" não fica girando)' do
    allow(runner).to receive(:generate_response).and_return({ 'response' => 'conversation_handoff', 'reasoning' => 'Error occurred: x' })

    expect(responder.message['content']).to eq(described_class::ERRO)
  end

  it '.usa? só para assistente da equipe (sem caixa) com skills ligadas e v2', :aggregate_failures do
    account.enable_features!('captain_integration_v2')
    create(:captain_scenario, assistant: copiloto, account: account, enabled: true)
    expect(described_class.usa?(copiloto.reload)).to be(true)

    create(:captain_inbox, captain_assistant: copiloto, inbox: create(:inbox, account: account))
    expect(described_class.usa?(copiloto.reload)).to be(false)
  end
end
```

- [ ] **Step 2: Run test to verify it fails** — à mão: `Ramon::CopilotoPainel` não existe; `registrar_agente` grava `'atendimento'` para qualquer source que não seja `'fluxo'` (`lib/ramon/llm_uso.rb:60`).

- [ ] **Step 3: Write minimal implementation**

`app/services/ramon/copiloto_painel.rb`:

```ruby
# Painel do Copiloto na conversa (Inteligência A4 — I-X3): o que o agente da equipe recebe do caso aberto.
# LGPD: só a data de hoje, o nº da conversa, o nº do caso (lead_id — as skills usam "caso N") e o nome do
# cliente (a busca de processo no AdvBox precisa dele). CPF, telefone, documentos e o texto da conversa NÃO vão:
# as skills buscam o que precisam pelas ferramentas, como no Testar.
module Ramon::CopilotoPainel
  module_function

  def contexto(account, display_id)
    hoje = Time.find_zone!(Ramon::CockpitMetrics::TIME_ZONE).today.strftime('%d/%m/%Y')
    conversa = account.conversations.find_by(display_id: display_id) if display_id.present?
    return "Contexto: hoje é #{hoje}; nenhuma conversa aberta na tela." if conversa.nil?

    lead = account.leads.find_by(conversation_id: conversa.id)
    nome = (lead&.name.presence || conversa.contact&.name).to_s.strip.presence || 'sem nome'
    caso = lead ? "caso #{lead.id} do hub (lead_id=#{lead.id})" : 'sem caso no hub'
    "Contexto: hoje é #{hoje}; a equipe está com a conversa ##{conversa.display_id} aberta — #{caso}, cliente #{nome}. " \
      '"Este cliente" ou "este caso" é este.'
  end

  # Contexto na frente só da última pergunta da pessoa (o que vai ao agente); o histórico salvo não muda.
  def com_contexto(historico, account, display_id)
    ultima = historico.rindex { |item| item[:role].to_s == 'user' }
    return historico if ultima.nil?

    historico.each_with_index.map do |item, indice|
      indice == ultima ? item.merge(content: "#{contexto(account, display_id)}\n\n#{item[:content]}") : item
    end
  end
end
```

(Os dois ramos começam com `Contexto: hoje é DD/MM/AAAA;` — o spec do `SkillsService` confere esse começo.)

`enterprise/app/services/captain/copilot/skills_service.rb`:

```ruby
# FORK-PONTO (ramon) — Inteligência A4 (I-X3): no painel do Copiloto da conversa, o assistente da EQUIPE
# (sem caixa conectada) com skills ligadas roda o MESMO agente do Testar (skills + ferramentas da banca),
# não o Captain::Copilot::ChatService do upstream (só busca conversa/contato/artigo). O de leads segue no upstream.
# Nada vai ao cliente: a resposta fica no painel; escrita no AdvBox segue a regra de ouro (prévia + "confirma?").
# Contexto do caso: Ramon::CopilotoPainel (LGPD). Uso e custo: source 'copiloto_painel'.
class Captain::Copilot::SkillsService
  ERRO = 'Não consegui responder agora. Tente de novo em instantes.'.freeze

  def self.usa?(assistant)
    assistant.account.feature_enabled?('captain_integration_v2') && assistant.inboxes.none? && assistant.scenarios.enabled.exists?
  end

  def initialize(assistant, conversation_id:, copilot_thread_id:)
    @assistant = assistant
    @conversation_id = conversation_id
    @thread = assistant.account.copilot_threads.find(copilot_thread_id)
  end

  def responder
    historico = Ramon::CopilotoPainel.com_contexto(@thread.previous_history, @assistant.account, @conversation_id)
    resposta = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, source: 'copiloto_painel')
                                                     .generate_response(message_history: historico)
    @thread.copilot_messages.create!(message: { content: texto(resposta) }, message_type: :assistant)
  end

  private

  def texto(resposta)
    falhou = resposta['reasoning'].to_s.start_with?('Error occurred') || resposta['response'] == 'conversation_handoff'
    falhou ? ERRO : resposta['response'].to_s
  end
end
```

`response_job.rb` — `generate_chat_response` passa a começar assim (o resto igual):

```ruby
  def generate_chat_response(assistant:, conversation_id:, user_id:, copilot_thread_id:, message:)
    # FORK-PONTO (ramon): assistente da equipe com skills → o agente do Testar (Inteligência A4, I-X3)
    if copilot_thread_id.present? && Captain::Copilot::SkillsService.usa?(assistant)
      return Captain::Copilot::SkillsService.new(assistant, conversation_id: conversation_id,
                                                            copilot_thread_id: copilot_thread_id).responder
    end

    service = Captain::Copilot::ChatService.new(
```

`lib/ramon/llm_uso.rb` — constante nova logo depois de `CAMPOS` (linha 15):

```ruby
  # source do runner do agente v2 → função na tela (o resto soma no Atendimento)
  FUNCAO_DO_AGENTE = { 'fluxo' => 'fluxo', 'copiloto_painel' => 'copiloto_painel' }.freeze
```

e, em `registrar_agente` (linha 60), trocar `funcao: source == 'fluxo' ? 'fluxo' : 'atendimento',` por `funcao: FUNCAO_DO_AGENTE.fetch(source.to_s, 'atendimento'),` (mesma linha, mesmos demais campos).

`ramonIaUso.json` (mesma posição nos dois):
- `IA_USO.FUNCOES`: nova linha logo depois de `"copiloto_captain": …` — pt `"copiloto_painel": "Copiloto (painel da conversa)",`, en `"copiloto_painel": "Copilot (conversation panel)",`.
- `IA_USO.ESCOLHA.DESCRICOES.atendimento`: pt `"O agente que responde no WhatsApp, o Testar e o painel do Copiloto na conversa."`, en `"The agent that answers on WhatsApp, the Test screen and the Copilot panel in the conversation."`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/routes/dashboard/captain/pages/specs --config vitest.local.config.ts
```
Expected: verdes (trava do `ramonIaUso`). Ruby rastreado à mão: `com_contexto` não altera o hash original (`merge` devolve novo); `llm_uso.rb` ≤ 100 linhas de código; linha do `usa?` ≤ 150; `responder` AbcSize baixo.

- [ ] **Step 5: Commit**

```bash
git add app/services/ramon/copiloto_painel.rb spec/services/ramon/copiloto_painel_spec.rb enterprise/app/services/captain/copilot/skills_service.rb spec/enterprise/services/captain/copilot/skills_service_spec.rb enterprise/app/jobs/captain/copilot/response_job.rb lib/ramon/llm_uso.rb spec/lib/ramon/llm_uso_spec.rb app/javascript/dashboard/i18n/locale/en/ramonIaUso.json app/javascript/dashboard/i18n/locale/pt_BR/ramonIaUso.json
git commit -m "feat(copiloto): painel da conversa roda as skills do Copiloto do Escritório com o contexto do caso" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 7: Front — painel abre no Copiloto da equipe e mostra os atalhos da banca

**Files:**
- Create: `app/javascript/dashboard/components-next/copilot/escolherAssistente.js`
- Modify: `app/javascript/dashboard/components/copilot/CopilotContainer.vue:1-69,125-155` (stats, escolha, props)
- Modify: `app/javascript/dashboard/components-next/copilot/Copilot.vue:17-34,160-164` (2 props repassadas)
- Modify: `app/javascript/dashboard/components-next/copilot/CopilotEmptyState.vue` (arquivo inteiro)
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramon.json` (bloco `CAPTAIN_RAMON.COPILOTO_ATALHOS` depois de `FAQ_CONVERSA`)
- Modify: `app/javascript/dashboard/modules/conversations/components/specs/textosA4.spec.js` (`BLOCOS`)
- Test: `app/javascript/dashboard/components-next/copilot/specs/escolherAssistente.spec.js`, `app/javascript/dashboard/components-next/copilot/specs/CopilotEmptyState.spec.js` (novos)

**Interfaces:**
- Consumes: `CaptainAssistantAPI.stats() → { data: { payload: [{ id, publico: 'lead'|'equipe', … }] } }` (A2; liberado a todos os papéis — `assistant_policy.rb:10-12`); backend da Task 6 (o painel manda `conversation_id: currentChat.id` como já mandava).
- Produces: `escolherAssistente({ assistants, preferredId, equipeIds, inboxAssistantId }) → assistant | undefined`; props `equipe: Boolean`, `naConversa: Boolean` em `Copilot.vue` e `CopilotEmptyState.vue`; chaves `CAPTAIN_RAMON.COPILOTO_ATALHOS.{KICKOFF, SITUACAO, DOCUMENTOS, REUNIAO, AGENDA, FUNIL, PRAZOS}.{LABEL, CONTENT}` (`KICKOFF` é folha).

- [ ] **Step 1: Write the failing tests**

`app/javascript/dashboard/components-next/copilot/specs/escolherAssistente.spec.js`:

```js
import { escolherAssistente } from '../escolherAssistente';

const ATENDIMENTO = { id: 1, name: 'Atendimento' };
const COPILOTO = { id: 2, name: 'Copiloto do Escritório' };
const base = {
  assistants: [ATENDIMENTO, COPILOTO],
  preferredId: null,
  equipeIds: [2],
  inboxAssistantId: 1,
};

describe('assistente do painel do Copiloto', () => {
  it('abre no assistente da equipe, mesmo com a caixa ligada ao Atendimento', () => {
    expect(escolherAssistente(base)).toBe(COPILOTO);
  });

  it('a escolha da pessoa vence', () => {
    expect(escolherAssistente({ ...base, preferredId: 1 })).toBe(ATENDIMENTO);
  });

  it('sem assistente da equipe (ou stats falhou): o da caixa, como antes', () => {
    expect(escolherAssistente({ ...base, equipeIds: [] })).toBe(ATENDIMENTO);
  });

  it('sem nada: o primeiro; sem assistentes: nenhum', () => {
    expect(
      escolherAssistente({ ...base, equipeIds: [], inboxAssistantId: null })
    ).toBe(ATENDIMENTO);
    expect(escolherAssistente({ ...base, assistants: [] })).toBeUndefined();
  });
});
```

`app/javascript/dashboard/components-next/copilot/specs/CopilotEmptyState.spec.js`:

```js
import { mount } from '@vue/test-utils';
import CopilotEmptyState from '../CopilotEmptyState.vue';

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 2 } }),
}));

const montar = props =>
  mount(CopilotEmptyState, {
    props: { hasAssistants: true, ...props },
    global: { stubs: { RouterLink: true } },
  });

const rotulos = wrapper => wrapper.findAll('button').map(b => b.text());

describe('atalhos do painel do Copiloto', () => {
  it('equipe com conversa aberta: os 3 atalhos do caso; o clique manda o pedido', async () => {
    const wrapper = montar({ equipe: true, naConversa: true });

    expect(rotulos(wrapper)).toEqual([
      "This client's case status",
      'Missing documents',
      'Prepare the meeting',
    ]);
    expect(wrapper.text()).toContain('Nothing goes to the client.');

    await wrapper.findAll('button')[0].trigger('click');
    expect(wrapper.emitted('useSuggestion')[0][0]).toContain('AdvBox');
  });

  it('equipe fora de conversa: agenda, funil e prazos', () => {
    expect(rotulos(montar({ equipe: true, naConversa: false }))).toEqual([
      "Today's agenda",
      'Funnel today',
      "This week's AdvBox deadlines",
    ]);
  });

  it('assistente de leads segue com os comandos de antes', () => {
    expect(rotulos(montar({ equipe: false, naConversa: true }))).toEqual([
      'Summarize this conversation',
      'Suggest an answer',
      'Rate this conversation',
    ]);
    expect(rotulos(montar({ equipe: false, naConversa: false }))).toEqual([
      'High priority conversations',
      'List contacts',
    ]);
  });
});
```

Em `textosA4.spec.js`: `const BLOCOS = ['FAQ_CONVERSA', 'COPILOTO_ATALHOS'];`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `TZ=UTC npx vitest run app/javascript/dashboard/components-next/copilot/specs app/javascript/dashboard/modules/conversations/components/specs --config vitest.local.config.ts`
Expected: FAIL (`escolherAssistente` não existe; atalhos e bloco i18n ausentes).

- [ ] **Step 3: Write minimal implementation**

`app/javascript/dashboard/components-next/copilot/escolherAssistente.js`:

```js
// Assistente do painel do Copiloto: o que a pessoa escolheu → o da equipe (ramon A4: atalhos da banca
// e skills do Copiloto do Escritório) → o da caixa da conversa (como era) → o primeiro.
export const escolherAssistente = ({
  assistants,
  preferredId,
  equipeIds,
  inboxAssistantId,
}) =>
  assistants.find(a => a.id === preferredId) ||
  assistants.find(a => equipeIds.includes(a.id)) ||
  assistants.find(a => a.id === inboxAssistantId) ||
  assistants[0];
```

`CopilotContainer.vue`:
- imports: `import CaptainAssistantAPI from 'dashboard/api/captain/assistant';` e `import { escolherAssistente } from 'dashboard/components-next/copilot/escolherAssistente';`
- trocar o bloco `const activeAssistant = computed(() => { … });` (linhas 50-69) por:

```js
// ramon (A4): ids dos assistentes da equipe (sem caixa) — o painel abre neles e mostra os atalhos da banca.
const equipeIds = ref([]);

const activeAssistant = computed(() =>
  escolherAssistente({
    assistants: assistants.value,
    preferredId: uiSettings.value.preferred_captain_assistant_id,
    equipeIds: equipeIds.value,
    inboxAssistantId: inboxAssistant.value?.id,
  })
);
```

- no `onMounted`, dentro do `if (isEnterprise)`, depois do `dispatch`:

```js
    CaptainAssistantAPI.stats()
      .then(({ data }) => {
        equipeIds.value = data.payload
          .filter(a => a.publico === 'equipe')
          .map(a => a.id);
      })
      .catch(() => {}); // sem stats o painel segue como era (assistente da caixa)
```

- no template, no `<Copilot …>`, acrescentar:

```vue
      :equipe="equipeIds.includes(activeAssistant?.id)"
      :na-conversa="!!currentChat?.id"
```

(`selectedAssistantId` fica sem uso? Ele já não era lido no `computed` antigo — só no `setAssistant`; não mexer.)

`Copilot.vue` — em `defineProps` acrescentar:

```js
  // ramon (A4): assistente da equipe e conversa aberta → atalhos da banca no estado vazio
  equipe: { type: Boolean, default: false },
  naConversa: { type: Boolean, default: false },
```

e no `<CopilotEmptyState …>` (linhas 160-164):

```vue
      <CopilotEmptyState
        v-else
        :has-assistants="hasAssistants"
        :equipe="equipe"
        :na-conversa="naConversa"
        @use-suggestion="sendMessage"
      />
```

`CopilotEmptyState.vue` — arquivo inteiro:

```vue
<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui.js';
import Icon from '../icon/Icon.vue';

const props = defineProps({
  hasAssistants: { type: Boolean, default: false },
  // ramon (A4): assistente da equipe → atalhos da banca (rodam as skills do Copiloto do Escritório)
  equipe: { type: Boolean, default: false },
  naConversa: { type: Boolean, default: false },
});

const emit = defineEmits(['useSuggestion']);
const { t } = useI18n();
const route = useRoute();

const routePromptMap = {
  conversations: [
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.LABEL',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.CONTENT',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.SUGGEST.LABEL',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.SUGGEST.CONTENT',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.RATE.LABEL',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.RATE.CONTENT',
    },
  ],
  dashboard: [
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.HIGH_PRIORITY.LABEL',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.HIGH_PRIORITY.CONTENT',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.LIST_CONTACTS.LABEL',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.LIST_CONTACTS.CONTENT',
    },
  ],
};

const K = 'CAPTAIN_RAMON.COPILOTO_ATALHOS';
const ATALHOS_EQUIPE = {
  conversa: [
    { chave: 'SITUACAO', icone: 'i-lucide-scale' },
    { chave: 'DOCUMENTOS', icone: 'i-lucide-file-check' },
    { chave: 'REUNIAO', icone: 'i-lucide-calendar-check' },
  ],
  geral: [
    { chave: 'AGENDA', icone: 'i-lucide-calendar-days' },
    { chave: 'FUNIL', icone: 'i-lucide-filter' },
    { chave: 'PRAZOS', icone: 'i-lucide-alarm-clock' },
  ],
};

const promptOptions = computed(() => {
  if (props.equipe) {
    return ATALHOS_EQUIPE[props.naConversa ? 'conversa' : 'geral'].map(
      ({ chave, icone }) => ({
        label: `${K}.${chave}.LABEL`,
        prompt: `${K}.${chave}.CONTENT`,
        icone,
      })
    );
  }
  return routePromptMap[props.naConversa ? 'conversations' : 'dashboard'];
});

const handleSuggestion = opt => {
  emit('useSuggestion', t(opt.prompt));
};
</script>

<template>
  <div class="flex-1 flex flex-col gap-6 px-2">
    <div class="flex flex-col space-y-4 py-4">
      <Icon icon="i-woot-captain" class="text-n-slate-9 text-4xl" />
      <div class="space-y-1">
        <h3 class="text-base font-medium text-n-slate-12 leading-8">
          {{ $t('CAPTAIN.COPILOT.PANEL_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 leading-6">
          {{
            equipe
              ? t('CAPTAIN_RAMON.COPILOTO_ATALHOS.KICKOFF')
              : $t('CAPTAIN.COPILOT.KICK_OFF_MESSAGE')
          }}
        </p>
      </div>
    </div>
    <div v-if="!hasAssistants" class="w-full space-y-2">
      <p class="text-sm text-n-slate-11 leading-6">
        {{ $t('CAPTAIN.ASSISTANTS.NO_ASSISTANTS_AVAILABLE') }}
      </p>
      <router-link
        :to="{
          name: 'captain_assistants_create_index',
          params: {
            accountId: route.params.accountId,
          },
        }"
        class="text-n-slate-11 underline hover:text-n-slate-12"
      >
        {{ $t('CAPTAIN.ASSISTANTS.ADD_NEW') }}
      </router-link>
    </div>
    <div v-else class="w-full space-y-2">
      <span class="text-xs text-n-slate-10 block">
        {{ $t('CAPTAIN.COPILOT.TRY_THESE_PROMPTS') }}
      </span>
      <div class="space-y-1">
        <button
          v-for="prompt in promptOptions"
          :key="prompt.label"
          class="w-full flex items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-left text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-2"
          @click="handleSuggestion(prompt)"
        >
          <span class="flex min-w-0 items-center gap-2">
            <span
              v-if="prompt.icone"
              class="flex size-6 shrink-0 items-center justify-center rounded-md"
              :class="TOM.blue"
            >
              <Icon :icon="prompt.icone" class="size-3.5" />
            </span>
            <span class="truncate">{{ t(prompt.label) }}</span>
          </span>
          <Icon icon="i-lucide-chevron-right" class="shrink-0 text-n-slate-10" />
        </button>
      </div>
    </div>
  </div>
</template>
```

`ramon.json` — depois do fechamento de `FAQ_CONVERSA` (`"GERAL": …` + `}` de `ERROS` + `}` do bloco), acrescentar `,` e o bloco. pt_BR:

```json
    "COPILOTO_ATALHOS": {
      "KICKOFF": "Pergunte sobre o caso aberto: processo no AdvBox, documentos, reunião. Nada sai para o cliente.",
      "SITUACAO": {
        "LABEL": "Situação do processo deste cliente",
        "CONTENT": "Qual a situação do processo deste cliente no AdvBox? Traga número, fase, responsável, última movimentação com data e tarefas em aberto."
      },
      "DOCUMENTOS": {
        "LABEL": "O que falta de documento",
        "CONTENT": "O que falta de documento neste caso? Separe o que já chegou, o que falta (e por que importa) e o texto pronto para pedir ao cliente."
      },
      "REUNIAO": {
        "LABEL": "Preparar a reunião",
        "CONTENT": "Prepare a reunião deste caso: o que já temos, o que falta, estimativa de valores e honorário, prescrição e as 3 objeções mais prováveis com a resposta da casa."
      },
      "AGENDA": {
        "LABEL": "Agenda do dia",
        "CONTENT": "Qual a agenda do escritório hoje? Reuniões, tarefas vencendo, atrasadas e prazos do AdvBox, e o que fazer primeiro."
      },
      "FUNIL": {
        "LABEL": "Funil hoje",
        "CONTENT": "Como está o funil hoje? Meta do dia, conversão por etapa com o gargalo, SLA de primeira resposta e perdas por tese."
      },
      "PRAZOS": {
        "LABEL": "Prazos da semana no AdvBox",
        "CONTENT": "Quais as tarefas e prazos do AdvBox desta semana, de segunda a domingo? Lista curta por dia."
      }
    }
```

en (mesma posição):

```json
    "COPILOTO_ATALHOS": {
      "KICKOFF": "Ask about the open case: AdvBox lawsuit, documents, meeting. Nothing goes to the client.",
      "SITUACAO": {
        "LABEL": "This client's case status",
        "CONTENT": "What is the status of this client's lawsuit in AdvBox? Bring number, phase, owner, last movement with date and open tasks."
      },
      "DOCUMENTOS": {
        "LABEL": "Missing documents",
        "CONTENT": "Which documents are missing in this case? Split what arrived, what is missing (and why it matters) and the ready text to ask the client."
      },
      "REUNIAO": {
        "LABEL": "Prepare the meeting",
        "CONTENT": "Prepare this case's meeting: what we have, what is missing, value and fee estimate, prescription and the 3 most likely objections with the firm's answer."
      },
      "AGENDA": {
        "LABEL": "Today's agenda",
        "CONTENT": "What is the office agenda today? Meetings, tasks due, overdue and AdvBox deadlines, and what to do first."
      },
      "FUNIL": {
        "LABEL": "Funnel today",
        "CONTENT": "How is the funnel today? Daily goal, conversion by stage with the bottleneck, first response SLA and losses by thesis."
      },
      "PRAZOS": {
        "LABEL": "This week's AdvBox deadlines",
        "CONTENT": "What are this week's AdvBox tasks and deadlines, Monday to Sunday? Short list by day."
      }
    }
```

(O `'` de "client's" não quebra o vue-i18n; a trava de produção confirma.)

- [ ] **Step 4: Run tests to verify they pass**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/components-next/copilot/specs app/javascript/dashboard/modules/conversations/components/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/components-next/copilot app/javascript/dashboard/components/copilot/CopilotContainer.vue
```
Expected: verdes (4 + 3 nos novos; `textosA4` agora 10 casos); eslint sem `error`.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/components-next/copilot/escolherAssistente.js app/javascript/dashboard/components-next/copilot/CopilotEmptyState.vue app/javascript/dashboard/components-next/copilot/Copilot.vue app/javascript/dashboard/components/copilot/CopilotContainer.vue app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json app/javascript/dashboard/components-next/copilot/specs/escolherAssistente.spec.js app/javascript/dashboard/components-next/copilot/specs/CopilotEmptyState.spec.js app/javascript/dashboard/modules/conversations/components/specs/textosA4.spec.js
git commit -m "feat(copiloto): atalhos da banca no painel e abertura no Copiloto do Escritório" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

---

### Task 8: Story + prints + página mockup × real (aprovação do Eduardo antes do merge)

**Files:**
- Create: `app/javascript/dashboard/components-next/copilot/InteligenciaA4.story.vue`
- Create (fora do repo): `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a4\{claro,escuro}-{menu,copiloto-conversa,copiloto-geral,copiloto-resposta}.png` e `comparar.html`

**Interfaces:**
- Consumes: `VirarFaqMenuItem` (Task 4), `Copilot` com `equipe`/`naConversa` (Task 7), `MenuItem`. **Quem tira os prints é o controlador** (harness Vite + Chrome headless no `tmp/` não versionado de outro worktree, com router/store/i18n); esta task acrescenta a story e monta a página.

- [ ] **Step 1: Story** — criar `InteligenciaA4.story.vue` (dados fictícios):

```vue
<script setup>
import Copilot from './Copilot.vue';
import MenuItem from 'dashboard/components/widgets/conversation/contextMenu/menuItem.vue';
import VirarFaqMenuItem from 'dashboard/modules/conversations/components/VirarFaqMenuItem.vue';

const COPILOTO = { id: 2, name: 'Copiloto do Escritório' };
const ASSISTENTES = [{ id: 1, name: 'Atendimento (rascunho)' }, COPILOTO];
const RESPOSTA = [
  { id: 1, message_type: 'user', message: { content: 'Situação do processo deste cliente' } },
  {
    id: 2,
    message_type: 'assistant',
    message: {
      content:
        'Processo 5001234-56.2026.4.04.7207 (Maria Exemplo) — fase: perícia agendada para 20/10. Responsável: Dra. Exemplo. Última movimentação 02/10: intimação da perícia. Tarefa aberta: avisar a cliente.',
    },
  },
];
</script>

<template>
  <Story title="Ramon/Inteligência A4" :layout="{ type: 'grid', width: '360px' }">
    <Variant title="Menu da mensagem">
      <div class="w-56 rounded-md bg-n-background p-1 shadow-xl">
        <MenuItem :option="{ icon: 'clipboard', label: $t('CONVERSATION.CONTEXT_MENU.COPY') }" variant="icon" />
        <MenuItem :option="{ icon: 'link', label: $t('CONVERSATION.CONTEXT_MENU.COPY_PERMALINK') }" variant="icon" />
        <MenuItem :option="{ icon: 'comment-add', label: $t('CONVERSATION.CONTEXT_MENU.CREATE_A_CANNED_RESPONSE') }" variant="icon" />
        <VirarFaqMenuItem :conversation-id="12" :message-id="345" />
      </div>
    </Variant>
    <Variant title="Copiloto na conversa">
      <div class="h-[640px]">
        <Copilot :messages="[]" conversation-inbox-type="Channel::Whatsapp" :assistants="ASSISTENTES" :active-assistant="COPILOTO" equipe na-conversa />
      </div>
    </Variant>
    <Variant title="Copiloto fora da conversa">
      <div class="h-[640px]">
        <Copilot :messages="[]" conversation-inbox-type="" :assistants="ASSISTENTES" :active-assistant="COPILOTO" equipe />
      </div>
    </Variant>
    <Variant title="Copiloto respondeu">
      <div class="h-[640px]">
        <Copilot :messages="RESPOSTA" conversation-inbox-type="Channel::Whatsapp" :assistants="ASSISTENTES" :active-assistant="COPILOTO" equipe na-conversa />
      </div>
    </Variant>
  </Story>
</template>
```

Rodar `./node_modules/.bin/eslint --fix app/javascript/dashboard/components-next/copilot/InteligenciaA4.story.vue` e depois sem `--fix` → sem `error`.

- [ ] **Step 2: Commit da story**

```bash
git add app/javascript/dashboard/components-next/copilot/InteligenciaA4.story.vue
git commit -m "test(inteligencia): story da A4 para os prints de aprovação" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR"
```

- [ ] **Step 3: Prints (controlador)** — claro e escuro, 360 px de largura, das 4 variantes, salvos como `claro-menu.png`, `claro-copiloto-conversa.png`, `claro-copiloto-geral.png`, `claro-copiloto-resposta.png` e os `escuro-*` correspondentes na pasta da Task 1. Checklist para conferir nos prints: "Virar FAQ" com ícone de livro, mesma pele dos outros itens; atalhos em cartão branco (claro) / preto (escuro) com borda fina, ícone em quadradinho **azul translúcido**, `›` cinza; frase "Pergunte sobre o caso aberto… Nada sai para o cliente."; nenhum texto em inglês no pt_BR; nada de fundo chapado colorido; a resposta do Copiloto legível nos dois temas.

- [ ] **Step 4: `comparar.html`** — mesma estrutura de `comercial\docs\mockups\2026-10-06-ia-uso-custo\comparar.html` (tokens claro/escuro, `.par` 2 colunas que viram 1 no celular): título "Inteligência A4 — FAQ a partir da conversa + atalhos do Copiloto"; por tela, **mockup à esquerda × real à direita** (`mockup-claro.png` recortado não é preciso — mostrar o mockup inteiro uma vez no topo, e depois os pares real claro × real escuro); abaixo, em texto, o que não tem print: (a) o aviso "FAQ criada como pendente. Um administrador aprova antes de o assistente usar." com link "Ver FAQs pendentes"; (b) a chave renomeada em Configurações do assistente: "Gerar FAQs pendentes das conversas resolvidas (só valem depois que um administrador aprovar)"; (c) Uso e custo ganha as linhas "FAQ de conversa" e "Copiloto (painel da conversa)", e a escolha "FAQs geradas (documentos e conversas)". Abrir no navegador e conferir que todas as imagens carregam.

- [ ] **Step 5:** Entregar o caminho `C:\Users\dudsl\RAdvogados\comercial\docs\mockups\2026-10-07-inteligencia-a4\comparar.html` ao Eduardo. **Merge só com o "aprovado" dele.**

---

### Task 9: Verificação final + texto do PR

**Files:** nenhum novo.

- [ ] **Step 1: Front inteiro tocado**

```bash
TZ=UTC npx vitest run app/javascript/dashboard/components-next/copilot/specs app/javascript/dashboard/modules/conversations/components/specs app/javascript/dashboard/routes/dashboard/captain/pages/specs app/javascript/dashboard/components-next/message/specs --config vitest.local.config.ts
./node_modules/.bin/eslint app/javascript/dashboard/components-next/copilot app/javascript/dashboard/components/copilot app/javascript/dashboard/modules/conversations/components app/javascript/dashboard/components-next/message/Message.vue app/javascript/dashboard/api/captain/faqDeConversa.js
git status --short
```
Expected: tudo verde; eslint sem `error`; `git status` limpo (sem `vitest.local.config.ts`).

- [ ] **Step 2: Varredura de regras**

```bash
git diff 079a04c --stat -- app/models/lead.rb app/services/ramon/advbox_event_processor.rb app/finders/conversation_finder.rb db/migrate db/schema.rb .env.example
grep -rn "Captain::" app/services/ramon/faq_de_conversa.rb app/services/ramon/copiloto_painel.rb lib/ramon/llm_uso.rb
grep -n "faqs" config/routes.rb
git diff 079a04c --stat
```
Expected: 1º vazio (sem migração, sem env, nenhum arquivo no limite); 2º vazio; a rota com `if ChatwootApp.enterprise?`; o diff só com os arquivos do Mapa.

- [ ] **Step 3: Texto do PR (não abrir — gate do Eduardo)** — deixar no relatório final:

```markdown
Inteligência A4 — FAQ a partir das conversas + atalhos do Copiloto.

1. **Virar FAQ (1 clique):** no menu (⋮) de uma resposta enviada ao lead, "Virar FAQ" cria uma FAQ **pendente** com a pergunta que o lead fez logo antes e a resposta do atendente — sem IA, com nome, CPF, telefone e afins trocados por [marcadores]. O aviso leva às FAQs pendentes; só administrador aprova; clicar de novo não duplica.
2. **FAQs das conversas resolvidas:** a chave já existente em Configurações do assistente passa a usar um prompt da banca (FAQ genérica, sem dado pessoal, regras da OAB, honorário 30% + 3, no máximo 3 por conversa), manda só o fim da conversa e mascarado, usa o modelo escolhido em Uso e custo ("FAQs geradas"), aparece em linha própria ("FAQ de conversa") e **para no dia em que o gasto chega ao teto do alerta**. As FAQs nascem pendentes. **A chave continua desligada até o Eduardo ligar.**
3. **Atalhos do Copiloto:** o painel do Copiloto na conversa abre no Copiloto do Escritório e mostra "Situação do processo deste cliente", "O que falta de documento" e "Preparar a reunião" (fora de conversa: "Agenda do dia", "Funil hoje", "Prazos da semana no AdvBox"). O painel passa a rodar as **skills** do Copiloto (as mesmas do Testar), sabendo qual é o caso aberto (nº do caso e nome do cliente — nunca CPF, telefone ou a conversa). Nada sai para o cliente. Custo em linha própria ("Copiloto (painel da conversa)").

Sem migração, sem env nova.

## Closes
- Backlog `comercial\docs\2026-10-05-inteligencia-tela-a-tela.md` §13: I-X1, I-X2, I-X3.

## How to test
1. Numa conversa com o lead, ⋮ numa resposta enviada → "Virar FAQ" → aviso + link → a FAQ aparece em Inteligência → FAQs pendentes, com [nome]/[cpf] no lugar dos dados; aprovar.
2. Configurações do Atendimento → ligar "Gerar FAQs pendentes das conversas resolvidas" → resolver uma conversa de teste com troca de mensagens → FAQs pendentes da conversa; Uso e custo mostra "FAQ de conversa".
3. Abrir o painel do Copiloto numa conversa com caso → os 3 atalhos → "Situação do processo deste cliente" responde com o processo do AdvBox; Uso e custo mostra "Copiloto (painel da conversa)".

## What changed
- `Ramon::FaqDeConversa` (pergunta da FAQ, texto ao LLM, prompt, pausa pelo teto) e `Ramon::CopilotoPainel` (contexto do caso) — FOSS, com spec no CI.
- `POST conversations/:id/faqs` (enterprise); `ConversationFaqService` com as regras da banca; `Captain::Copilot::SkillsService` + desvio no `Captain::Copilot::ResponseJob` para o assistente da equipe.
- `Ramon::LlmUso`: funções `faq_conversa` e `copiloto_painel`.
- Front: item "Virar FAQ" no menu da mensagem; painel do Copiloto abre no assistente da equipe com os atalhos; rótulos novos em Uso e custo e na chave do assistente.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
```

- [ ] **Step 4: Smoke em bloco (para o Eduardo, depois do deploy)** — anotar no relatório, por seção, sem perguntas passo a passo: **A. Virar FAQ** (passos 1 do How to test + clicar 2× na mesma resposta → "já virou FAQ"; nota privada não mostra o item). **B. FAQ de conversa** (ligar a chave, resolver conversa de teste, conferir pendentes e a linha no Uso e custo; desligar se não gostar). **C. Copiloto** (os 3 atalhos numa conversa com caso; os 3 gerais fora de conversa; trocar para o Atendimento no seletor → volta aos comandos de antes). **D. Uso e custo** (as duas linhas novas com custo).

---

## Operação depois do deploy

Deploy de sempre (`docker compose pull chatwoot-web chatwoot-worker && docker compose up -d chatwoot-web chatwoot-worker`), **sem migração** e **sem env nova**. Nada muda sozinho para o cliente: "Virar FAQ" e o painel do Copiloto só agem quando alguém da equipe clica; a geração automática de FAQ continua **desligada** até o Eduardo ligar a chave no Atendimento (Inteligência → Configurações do Atendimento). Para desligar: a mesma chave. Se o teto do alerta (Uso e custo) estiver vazio, a geração automática não pausa — sugerido definir um teto antes de ligar.

## Ponto de conflito com a A3 (wt-intel-a3, em paralelo) e ordem de merge

| Arquivo | A4 mexe | A3 provavelmente mexe | Risco |
|---|---|---|---|
| `i18n/locale/{en,pt_BR}/ramon.json` | 2 blocos novos no **fim** de `CAPTAIN_RAMON` (depois de `MESSAGE_TEMPLATES`) | blocos de FAQ por tese, testar pergunta, Documentos/colar texto, Execuções | médio — se a A3 também acrescentar no fim, conflito de texto puro: manter os dois blocos, na mesma ordem nos dois arquivos, e rodar `textosA4.spec.js` + a trava da A3 |
| `i18n/locale/{en,pt_BR}/integrations.json` | 1 linha (`ALLOW_CONVERSATION_FAQS`, l. 524) | textos de FAQs/Documentos (I-FQ, I-DO) | baixo (linhas diferentes) |
| `config/routes.rb` | 2 linhas no bloco `scope module: :conversations` | talvez rota de "testar pergunta" no namespace `captain` | baixo |
| `Sidebar.vue` | **não mexe** | provável | nenhum |
| Telas de FAQ (`responses/*`, `ResponseCard.vue`, `assistant_responses_controller.rb`, `api/captain/response.js`) | **não mexe** (só linka a rota `captain_assistants_responses_pending`; API nova em arquivo próprio) | sim (filtro por tese, testar pergunta) | nenhum — se a A3 renomear a rota `captain_assistants_responses_pending`, ajustar o `VirarFaqMenuItem` |
| `assistentes.yml` / seed | não mexe | I-SK5 (seed respeita edição) | nenhum |

**Ordem proposta:** a **A3 entra primeiro** (é maior e mexe nas telas de FAQ); a A4 rebaseia em cima dela antes do merge, resolve o `ramon.json` mantendo os blocos das duas e roda de novo os specs de i18n das duas fatias. Se a A4 ficar pronta e aprovada antes, pode entrar primeiro — aí quem rebaseia é a A3, com a mesma regra. As fatias B4.x mexem em `CAPTAIN_RAMON.FLUXOS` (meio do arquivo) — sem sobreposição com o fim do bloco.

## Decisões novas que dependem do Eduardo

| # | Decisão | Proposta do plano | Onde |
|---|---|---|---|
| N1 | Quem pode usar "Virar FAQ" | Qualquer pessoa da equipe que vê a conversa cria a FAQ **pendente**; só administrador aprova (como hoje) | Task 3 |
| N2 | Como nasce a pergunta da FAQ de 1 clique | **Sem IA** (custo zero): a pergunta é o que o lead escreveu logo antes da resposta, com nome/CPF/telefone trocados por [marcadores]; quem aprova ajusta o texto. Alternativa: a IA reescreve como pergunta genérica (≈ US$ 0,001 por FAQ) | Task 2 |
| N3 | Ligar a geração de FAQ das conversas resolvidas | **Você liga na tela** (Configurações do Atendimento) depois de testar; não forçar pelo seed (o seed sobrescreveria quem desligar) | Operação |
| N4 | Teto de gasto | A geração **automática** para no dia em que o gasto chega ao teto do alerta (se houver teto); "Virar FAQ" não usa IA; o painel do Copiloto **não** é barrado (alguém clicou) — só conta no Uso e custo | Tasks 2, 5, 6 |
| N5 | Modelo da FAQ de conversa | O mesmo escolhido para "Documentos", que passa a se chamar "FAQs geradas (documentos e conversas)"; o custo sai em linha própria "FAQ de conversa" | Task 5 |
| N6 | Painel do Copiloto abre em qual assistente | No **Copiloto do Escritório** (antes abria no Atendimento, o da caixa); se você escolher outro no seletor, vale a sua escolha. O painel passa a rodar as skills (mesmo agente do Testar) e usa o modelo do Atendimento (o agente é o mesmo do Testar) | Tasks 6, 7 |
| N7 | Quais atalhos | Na conversa: "Situação do processo deste cliente", "O que falta de documento", "Preparar a reunião". Fora: "Agenda do dia", "Funil hoje", "Prazos da semana no AdvBox". **"Anotar esta conversa no AdvBox" (skill do #218) fica de fora**: exigiria mandar a conversa inteira ao LLM — fica para quando você quiser | Task 7 |
| N8 | O que o Copiloto recebe do caso | Data de hoje, nº da conversa, nº do caso e o **nome** do cliente (a busca no AdvBox precisa); nunca CPF, telefone, documento ou o texto da conversa | Task 6 |
| N9 | "Perguntar ao AdvBox" no menu de IA do editor | Fica como está (já entrega o panorama dos processos dentro da resposta); o atalho do painel é o caminho completo (dossiê, tarefas) | — |


## Respostas do Eduardo (07/10/2026)

Todas as "Decisões novas que dependem do Eduardo" deste plano foram **ACEITAS como propostas** (formulário de 07/10).

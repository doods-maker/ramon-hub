# Casa Única — intranet embutida no Chatwoot (fork da casca)

> **Status:** rascunho de design, aguardando revisão do Eduardo.
> **Data:** 2026-06-24.
> **Regra de aprovação:** Claude redige; Eduardo aprova/comita/deploya. Nada
> aqui foi commitado nem implementado.
> **Relacionado:** [[intranet-chatwoot-v2]] (arquitetura A1 já no ar) e
> `2026-06-24-painel-lead-cockpit-design.md` (cockpit do Painel do Lead).

## Objetivo

Ter **uma casa só**: o Chatwoot como casca e a **intranet (Next.js, o cérebro
atual)** embutida numa lateral/aba alternável, mesma URL e login único — sem
abrir outra aba nem logar de novo. A intranet continua acessível por fora. O
kanban e a inteligência (SDR, qualificação por IA, Kit do Closer) passam a ser
acessíveis **de dentro do Chatwoot**, e seguem vinculados às conversas.

## Decisões travadas (nesta conversa, 2026-06-24)

- **Casca = Chatwoot (fork)**, **cérebro = intranet (Next.js, como já é).**
- **Embutir via iframe de painel inteiro** (não microfrontend, não reverse-proxy).
- **Login único por token HMAC** assinado pelo Chatwoot e validado pela intranet.
- **WhatsApp:** segue Cloud API oficial pelo canal nativo do Chatwoot — o item
  "WhatsApp HTTP API / múltiplas instâncias" do anexo original **sai do escopo**.
- **Lead scoring:** calculado **na intranet**, alimentado por webhook do Chatwoot.
- **Selos nativos** de score/fase dentro da conversa do Chatwoot — feitos via
  **custom attributes** (renderização nativa, sem editar componente do core).

### Por que NÃO microfrontend (registro da decisão)

A intranet é Next.js (React) e a casca do Chatwoot é Vue. Module Federation
exigiria: arrancar a UI da intranet do runtime do Next (roteamento, server
components, data fetching, middleware) e reescrevê-la como componentes client-side;
dois runtimes (React+Vue) na mesma página; dois bundlers (webpack/turbopack vs
Vite) e Tailwind dos dois colidindo; mais arquivos do core tocados (build,
bootstrap, router) → mais dor de merge. Ganho real sobre o iframe: só apagar a
"bordinha" cosmética. Para 2–3 usuários, não compensa. Comunicação Chatwoot↔
intranet resolve-se com **postMessage** (já usado no Dashboard App).

## Visão de arquitetura

```
                 chat.ramonantonio.adv.br  (Chatwoot — fork da casca)
   ┌──────────────────────────────────────────────────────────────┐
   │  sidebar:  [💬 Conversas] [📊 Funil] [🏢 Intranet] ← novo item  │
   │                                                                │
   │   rota nova /ramon  ───────────────►  <iframe>                 │
   │                                          src = app.../?sso=TOKEN│
   │   endpoint Rails novo  /ramon/sso_token (assina HMAC)          │
   │   ▲ postMessage (telefone/conversa) ──┘                        │
   └───┼────────────────────────────────────────────────────────────┘
       │ webhook (msgs/conversas)         ▲ PATCH custom_attributes (score/fase)
       ▼                                  │
                 app.ramonantonio.adv.br  (intranet — cérebro, INALTERADA por fora)
   ┌──────────────────────────────────────────────────────────────┐
   │  /kanban  /sdr  /conhecimento  /embed/kit (Painel do Lead)     │
   │  aceita ?sso=TOKEN → valida HMAC → abre sessão (mapa por email)│
   │  calcula score (interações, tempo, recência) → Supabase        │
   └──────────────────────────────────────────────────────────────┘
                 Supabase (fonte da verdade do funil)  +  Postgres do Chatwoot (conversas)
```

A intranet continua acessível por fora (login Supabase normal); dentro do
Chatwoot ela entra já logada via SSO. O **Painel do Lead** (`/embed/kit`), já no
ar, continua na lateral da conversa; o **novo painel-intranet** é um destino de
topo separado (a intranet inteira).

## 1. O fork do Chatwoot (a casca) — minimizando dor de merge

Regra de ouro: **adicionar, quase nunca editar.**

- **Arquivos NOVOS, namespace `ramon/`:** componente Vue do painel, rota, controller
  Rails do SSO. Upstream nunca toca neles → zero conflito.
- **Edições em pontos de registro (poucos, previsíveis):** registrar o item na
  sidebar e a rota no índice — ~2–3 linhas em ~3 arquivos do core, conflito
  trivial. Manter **lista documentada** desses arquivos para cada merge ser uma
  checagem rápida.
- **Selo nativo SEM tocar o core:** score/temperatura/fase como **custom
  attributes** do contato — o Chatwoot já os renderiza nativamente na lateral da
  conversa. Selo nativo com zero edição de componente. (Opcional futuro: selo no
  cabeçalho da conversa = 1 componente editado.)
- **Nunca tocar `enterprise/`** (licença separada).
- **Git:** upstream como remote; mudanças como camada fina rebaseada sobre cada
  *release tag*; smoke test após cada merge.

## 2. Login único (SSO HMAC)

1. Painel Vue chama `GET /ramon/sso_token` (sessão Devise sabe quem está logado).
2. Rails assina HMAC curto `{email, papel, exp}` (reusa `EMBED_HMAC_SECRET`).
3. Painel monta `<iframe src="app.../?sso=TOKEN">`.
4. Intranet valida HMAC (reusa `lib/embed-token.ts`), mapeia email→usuário, abre
   sessão própria. Login Supabase normal segue valendo para acesso externo.

`chat.` e `app.` são subdomínios do mesmo domínio → o handshake por token evita
a dor de cookie de terceiros.

## 3. Kanban (na intranet)

Página nova `/kanban` no Next.js. **Colunas = etapas** (reusa o mapa canônico
existente). **Cards = leads.** Arrastar → muda `leads.etapa` → o **sync
bidirecional já construído** empurra o label `fase:*` para a conversa no Chatwoot.
Vínculo com o Chatwoot sai de graça porque o kanban é a própria intranet.
Ordenação manual dentro da coluna = coluna `leads.ordem`.

## 4. Lead scoring (na intranet)

Webhook do Chatwoot estende para eventos de **mensagem** → `/api/chatwoot/webhook`.
A intranet calcula `score` + `temperatura` (frio/morno/quente) a partir de
interações, tempo de resposta e recência; grava na Supabase; e **empurra de
volta** ao Chatwoot como custom attribute (→ selo nativo). Job: a intranet roda
em Docker na VPS — worker/cron pequeno recalcula no evento + um passe periódico
para decaimento por recência. Sem Sidekiq.

## 5. Modelo de dados (deltas)

- **Supabase:** `leads.score int`, `leads.temperatura text`, `leads.ordem int`,
  `leads.score_atualizado_em timestamptz`; **persistir `chatwoot_conversation_id`**
  (o `extrairDeConversa` já captura, mas não grava — pendência já anotada).
  Opcional: tabela `lead_score_eventos` para auditoria.
- **Chatwoot:** definições de custom attribute `lead_score`, `temperatura`, `fase`.
  **Nenhuma tabela nova no Chatwoot.**

## 6. Roadmap em fases (entrega → usa → calibra)

- **Fase 1 (MVP — a casa única):** fork da casca = item na sidebar + rota iframe +
  endpoint SSO; intranet aceita SSO. Resultado: uma aba, alterna para a intranet,
  login único. *(é o "requisito principal")*
- **Fase 2:** Kanban na intranet (colunas=etapas, drag-drop → sync existente).
- **Fase 3:** Scoring (webhook de mensagens → cálculo → custom attribute → selo
  nativo).
- **Fase 4 (opcional):** selo no cabeçalho nativo da conversa, se o custom
  attribute não for proeminente o bastante.

## 7. Riscos e mitigação

- **Merge com upstream (o maior):** footprint mínimo + lista documentada de
  arquivos do core tocados + namespace `ramon/` + rebase em release tags. Mesmo
  fino, um fork é **manutenção contínua** — a mitigação é forkar só a casca.
- **iframe/CSP:** a intranet precisa permitir ser enquadrada por `chat.`
  (`frame-ancestors`); padrão já existe para `/embed`.
- **Token SSO:** curto, single-use, HMAC, só https.
- **Realtime do score:** simples (recalcula no evento + poll). Não
  super-engenheirar para 2–3 usuários.

## Pontos em aberto para a próxima sessão

- Confirmar os nomes/arquivos exatos da sidebar e do índice de rotas na versão
  atual do Chatwoot que está na VPS (inspecionar o código do fork antes de mexer).
- Definir os critérios e pesos do score (interações × tempo de resposta ×
  recência × tags) — calibrar pela dor real, não adivinhar.
- Decidir o mapa email(Chatwoot) → usuário(intranet) para o SSO (2–3 usuários).

---

*Próximo passo após aprovação: gerar o plano de implementação (writing-plans),
começando pela Fase 1.*

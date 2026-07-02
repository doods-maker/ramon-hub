# Painel do Lead → Cockpit do Comercial

**Data:** 2026-06-24
**Projeto:** intranet-ramon (Next.js 15 + Supabase + Chatwoot)
**Autor do desenho:** Claude (rascunho) · aprovação: Eduardo

## Contexto e problema

O **Painel do Lead** (`/embed/kit`) é um Dashboard App embutido na lateral do
Chatwoot. Hoje ele é **só leitura** e mostra *tudo de uma vez*: cabeçalho, etiquetas,
notas, o **Kit do Closer inteiro** (resumo+veredito, roteiro, documentos, pitch+objeções,
próximo passo) e histórico de etapas.

Eduardo faz **SDR e Closer no mesmo fio do WhatsApp**, dentro do Chatwoot. Na prática,
ele **sai do Chatwoot** no meio da conversa para: (1) consultar conhecimento/tese,
(2) mexer no funil (mudar etapa, nota), (3) rodar triagem/gerar kit, (4) pegar modelo
de mensagem. Cada saída é atrito.

**Objetivo:** transformar o painel de *vitrine fixa* em **cockpit** — mostra o conteúdo
certo conforme a etapa do lead, **escreve de volta** (intranet + Chatwoot espelhado) e
traz o bom da intranet (conhecimento/playbook) pra dentro, eliminando as saídas.

## Princípios e guardas

- **O painel NUNCA manda nada pro lead.** Mudar etapa, nota, rodar triagem são ações
  **internas** de CRM — não vão "pro mundo", logo são **um-clique, sem aprovação caso a
  caso** (decisão do Eduardo). Enviar mensagem ao lead continua **manual, no Chatwoot**.
  Isso preserva a regra de aprovação da constituição (`comercial/CLAUDE.md` §3).
- **Fonte da verdade do funil = intranet** (`leads.etapa`). O Chatwoot reflete; a
  reconciliação bidirecional usa **mapa canônico fixo + guarda de igualdade** (ver Fase 4).
- **Reuso, não reescrita.** Estende-se o que já existe (`/api/embed/kit`, webhook do
  Chatwoot, `lib/playbook`, `lib/conhecimento`, `/api/triagem`, `/api/pra-fechar/gerar-kit`).

## Visão geral da arquitetura

```
Chatwoot (inbox)
  └─ iframe: Painel do Lead (/embed/kit)  ── postMessage telefone ──┐
        ├─ GET  /api/embed/kit      (leitura: contexto do lead)     │  auth: HMAC estático
        ├─ POST /api/embed/acoes    (escrita: etapa / nota / kit)   │  (lib/embed-token)
        └─ GET  /api/embed/consulta (playbook da tese + busca KB)   ┘
                         │
                    Supabase (leads, lead_notas, lead_etapa_historico, casos, ...)
                         │
        intranet → Chatwoot: lib/chatwoot/api.ts (set label/atributos da conversa)
        Chatwoot → intranet: /api/chatwoot/webhook (conversation_updated → etapa)
```

O painel continua sem sessão do Supabase (cookie domain-locked não flui pro iframe);
toda chamada carrega o **token HMAC** já usado hoje (`lib/embed-token`), adequado para
dado interno combinado com o CSP `frame-ancestors` (só o nosso Chatwoot embute).

---

## Fase 1 — Layout stage-aware + enxugar (só frontend)

O painel lê `lead.etapa` e prioriza o conteúdo por momento, em vez de despejar tudo.

- **`novo` / `qualificando` → modo SDR:** cabeçalho → **roteiro de perguntas** →
  **próximo passo** → (gaveta) consulta. Esconde pitch/objeções/documentos.
- **`agendado` / fechando → modo Closer:** cabeçalho → **resumo+veredito** →
  **pitch+objeções** → **documentos** → próximo passo.
- **`fechado` / `perdido`:** modo enxuto — cabeçalho + histórico (lead encerrado).
- **Histórico / notas / etiquetas:** sempre presentes, mas em **gavetas recolhidas**
  (`<details>`), fora da primeira dobra.

Sem mudança de dados nem de API. Só reorganização de `app/embed/kit/page.tsx`,
extraindo um mapa `etapa → seções visíveis` e componentes de gaveta.

**Entregável:** painel mais limpo, conteúdo certo por etapa. Sobe e é usável sozinho.

## Fase 2 — Consulta rápida (leitura: playbook + conhecimento)

Gaveta "Consulta" no painel, com duas fontes que hoje obrigam a trocar de aba:

- **Playbook SDR da tese do lead:** mostra as seções `qualificacao` / `objecao` /
  `documento` (de `lib/playbook` + tabela do playbook) da **tese do caso** do lead.
- **Busca na base de conhecimento:** campo de busca que chama `/api/conhecimento/buscar`
  (full-text Postgres + síntese DeepSeek, já existente) — confirmar B31/B91, NTEP,
  Súmula 47, prescrição, honorário, sem sair do Chatwoot.

Novo endpoint **`GET /api/embed/consulta`** (auth HMAC): dado o lead/telefone, devolve o
playbook da tese; a busca livre reusa `/api/conhecimento/buscar` (precisa aceitar auth
HMAC além da sessão, ou um proxy via `/api/embed/consulta?q=`). **Decisão:** proxiar pela
rota embed (`/api/embed/consulta?q=...`) para manter uma única porta autenticada por HMAC.

**Entregável:** consulta de tese/conhecimento dentro do painel. Leitura pura, risco baixo.

## Fase 3 — Ações write-back (etapa, nota, triagem)

Barra de ações compacta sempre visível no topo do painel:

- **Mudar etapa:** dropdown (`novo → qualificando → agendado → fechado / perdido`).
  Grava `leads.etapa` + insere em `lead_etapa_historico`. Um-clique.
- **+ Nota:** campo curto → insere em `lead_notas` (autor = usuário-sistema do embed,
  ou nulo). Um-clique.
- **Rodar triagem / Gerar kit:** quando o lead não tem `caso_id`/kit, dispara o fluxo
  existente. **Decisão:** o endpoint embed chama internamente a lógica de
  `/api/triagem` e `/api/pra-fechar/gerar-kit` (extrair a lógica para funções de
  serviço reusáveis se hoje estiver acoplada à rota). Um-clique.

Novo endpoint **`POST /api/embed/acoes`** (auth HMAC), corpo
`{ acao: "mudar_etapa" | "add_nota" | "rodar_triagem" | "gerar_kit", ... }`. Valida a
ação contra um allow-list; nunca executa nada que envie mensagem ao lead. Após gravar,
o painel re-busca o contexto (revalida o `GET /api/embed/kit`).

**Entregável:** as três ações que mais tiram o Eduardo do Chatwoot, resolvidas dentro
dele. Mata os atritos 2 e 3.

## Fase 4 — Sync bidirecional Chatwoot ↔ intranet

O degrau mais pesado, por último. Espelha o funil no inbox do Chatwoot.

### Mapa canônico (fixo, em código)

| `leads.etapa` | label Chatwoot |
|---|---|
| novo | `fase:novo` |
| qualificando | `fase:qualificando` |
| agendado | `fase:agendado` |
| fechado | `fase:fechado` |
| perdido | `fase:perdido` |

Invariante: **uma única label `fase:*` por conversa**. Custom attributes da conversa
espelham `valor_estimado`, `origem`, `tese`, `viabilidade` (somente leitura no Chatwoot).

### Intranet → Chatwoot

Novo cliente **`lib/chatwoot/api.ts`** (saída REST, autenticado por
`CHATWOOT_API_TOKEN` + `CHATWOOT_ACCOUNT_ID`, novos segredos no `intranet.env`):
- `definirFaseConversa(conversationId, etapa)` — remove outras `fase:*`, adiciona a certa.
- `definirAtributosConversa(conversationId, attrs)`.

Disparado sempre que `leads.etapa` muda (na ação write-back da Fase 3 e em qualquer
outro ponto que altere a etapa). Precisa do `chatwoot_conversation_id` do lead —
**já é extraído** por `extrairDeConversa` (`lib/chatwoot/eventos.ts`), só **não é
persistido** hoje. Fase 4 persiste em `contatos.chatwoot_conversation_id` (ou
`leads.chatwoot_conversation_id`) no handler de `conversation_created`.

### Chatwoot → intranet

Estende `/api/chatwoot/webhook` para tratar **`conversation_updated`**: lê as labels da
conversa, encontra a `fase:*`, mapeia de volta para `etapa` e atualiza `leads.etapa`
(+ histórico). Adicionar o evento `Conversation updated` na config do webhook do Chatwoot.

### Anti-loop (a parte crítica)

**Guarda de igualdade:** antes de gravar (dos dois lados), compara o valor que chegou
com o atual; **se já é igual, no-op**. Como ambos os lados convergem para o mesmo valor,
o eco morre em **um salto** — sem precisar de timestamp nem flag de origem.
Conflito de edição simultânea (raríssimo numa operação de 1-2 pessoas) = **last-write-wins**
pela ordem de chegada. Aceito conscientemente dado o porte.

**Entregável:** o inbox inteiro do Chatwoot reflete o funil (cor da etapa por conversa),
e mudar a label no Chatwoot move a etapa na intranet. Fecha o atrito 1 visualmente.

---

## Fora de escopo (decidido)

- **Modelos de mensagem** → viram **Canned Responses nativas do Chatwoot**
  (`/saudacao`, `/docs`, `/followup`), criadas em Settings → Canned Responses. **Não**
  são construídas no painel. (Atrito 4 resolvido fora.) Sincronizar os `modelos` da
  intranet → Canned Responses fica como ideia futura, não neste escopo.
- Envio de mensagem ao lead pelo painel (viola a regra de aprovação; fica no Chatwoot).
- MCP do Chatwoot / IA operando o Chatwoot (ideia futura, não é o caminho do painel).

## Componentes tocados (resumo)

| Arquivo | Fase | Mudança |
|---|---|---|
| `app/embed/kit/page.tsx` | 1,2,3 | layout stage-aware, gaveta consulta, barra de ações |
| `app/api/embed/kit/route.ts` | — | sem mudança (já devolve etapa/tese/caso) |
| `app/api/embed/consulta/route.ts` | 2 | **novo** — playbook da tese + proxy de busca KB |
| `app/api/embed/acoes/route.ts` | 3 | **novo** — etapa / nota / triagem / kit (allow-list) |
| `lib/chatwoot/api.ts` | 4 | **novo** — cliente REST de saída (labels/atributos) |
| `app/api/chatwoot/webhook/route.ts` | 4 | `conversation_updated` → etapa; persistir conversation_id |
| `lib/chatwoot/eventos.ts` | 4 | helper p/ ler label `fase:*` do payload (puro, testável) |
| migração `supabase/14_*.sql` | 4 | coluna `chatwoot_conversation_id` (próximo nº livre após `13_chatwoot.sql`) |

## Testes

- **Fase 1:** lógica `etapa → seções visíveis` pura e testada (Vitest).
- **Fase 2:** `/api/embed/consulta` — playbook da tese certa; proxy KB autenticado.
- **Fase 3:** `/api/embed/acoes` — allow-list (rejeita ação fora da lista), grava etapa
  + histórico, grava nota; nunca dispara envio externo.
- **Fase 4:** mapa etapa↔label puro e testado; **guarda de igualdade** (no-op quando já
  igual) coberta por teste — é o que garante que o loop morre.

## Sequenciamento

Fases 1 → 2 → 3 → 4, cada uma **independente e usável**. Casa com a filosofia do Eduardo:
entregar, USAR, calibrar pela dor real — com o pedaço arriscado (sync) por último.

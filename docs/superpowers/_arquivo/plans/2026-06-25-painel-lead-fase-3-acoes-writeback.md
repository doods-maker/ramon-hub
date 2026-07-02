# Painel do Lead — Fase 3: Ações write-back (etapa, nota, gerar kit, rodar triagem) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao Painel do Lead (embed no Chatwoot) uma barra de ações que escreve de volta — mudar etapa do funil, adicionar nota, (re)gerar o Kit do Closer, e **rodar uma triagem nova usando a transcrição da conversa do Chatwoot como texto-fonte** — tudo dentro do Chatwoot, sem trocar de aba.

**Architecture:** Um único endpoint embed `POST /api/embed/acoes` (autenticado por HMAC, cliente admin) executa um conjunto fechado de ações (allow-list). Lógica de validação (allow-list de ações + etapas válidas) e de montagem da transcrição ficam em libs puras testadas. A triagem reusa `lib/triagem` + `lib/kit-closer`; a transcrição vem da API REST do Chatwoot (`lib/chatwoot/api.ts`), usando o `conversation_id` que chega vivo no `appContext` (postMessage) — sem depender da persistência da Fase 4. Um componente cliente (`AcoesLead.tsx`) consome tudo na lateral do Chatwoot.

**Tech Stack:** Next.js 15 (App Router), TypeScript, Tailwind, Supabase (Postgres, cliente admin/service-role no embed), DeepSeek/Anthropic via `lib/ai`+`lib/triagem`+`lib/kit-closer`, API REST do Chatwoot, Vitest (node, `lib/**/*.test.ts`).

**Branch:** criar `feat/painel-lead-acoes` a partir de `main` (confirmar com `git branch --show-current`).

## Global Constraints

- **Idioma:** PT-BR em código, comentários e UI.
- **O painel NUNCA manda nada pro lead.** Todas as ações são **internas de CRM** (mudar etapa, nota, triagem, kit) → **um-clique, sem aprovação caso a caso** (decisão do Eduardo no spec do cockpit). Enviar mensagem ao lead continua **manual, no Chatwoot**. Nenhuma ação desta fase envia mensagem externa.
- **Auth do embed:** HMAC estático — `validarTokenEmbed(process.env.EMBED_HMAC_SECRET, token)` de `@/lib/embed-token`. Sem sessão Supabase no iframe → usar `criarClienteAdmin()` (service role) nas rotas embed.
- **Telefone canônico:** E.164 só dígitos via `normalizarTelefone` de `@/lib/chatwoot/eventos`.
- **Allow-list rígida:** a rota só executa ações em `ACOES`. Qualquer `acao` fora da lista → 400. Nunca há caminho que dispare envio ao lead.
- **Etapas canônicas (fixas, batem com o CHECK do banco):** `novo`, `qualificando`, `agendado`, `fechado`, `perdido`.
- **Viabilidade canônica:** `alta`, `media`, `baixa`.
- **Reuso, não reescrita:** `analisarCaso` (`@/lib/triagem`), `gerarKitCloser` (`@/lib/kit-closer`), padrões de `app/api/embed/kit/route.ts` e `app/api/embed/consulta/route.ts`.
- **Escrita sem usuário de sessão:** `lead_notas.autor_id`, `lead_etapa_historico.mudou_por` e `casos.responsavel_id` são **nullable** → gravar `null` neles.

---

## Task 0: Pré-requisito manual (env do Chatwoot na VPS)

**Files:** nenhum (config de runtime, manual — fica registrado aqui)

> A ação **rodar_triagem** (Task 7) lê a conversa pela API do Chatwoot e precisa do ID da conta. As demais ações (etapa/nota/gerar_kit) **não** dependem disto e podem ser entregues antes.

- [ ] **Step 1: Adicionar `CHATWOOT_ACCOUNT_ID` ao `intranet.env.example`**

Em `intranet.env.example`, logo após a linha `CHATWOOT_API_TOKEN=`, adicionar:
```bash
# ID numérico da conta no Chatwoot (URL: .../app/accounts/<ID>/...). Necessário p/ ler conversas via API.
CHATWOOT_ACCOUNT_ID=
```

- [ ] **Step 2: (Manual, Eduardo — antes do deploy da Task 7)** No `intranet.env` da VPS (`/opt/intranet-ramon/intranet.env`), preencher `CHATWOOT_ACCOUNT_ID` com o número que aparece na URL do Chatwoot (`https://chat.ramonantonio.adv.br/app/accounts/<ID>/dashboard`), e confirmar que `CHATWOOT_URL` e `CHATWOOT_API_TOKEN` estão preenchidos. Sem isso, `rodar_triagem` retorna erro claro (não quebra o resto do painel).

- [ ] **Step 3: Commit**

```bash
git add intranet.env.example
git commit -m "chore(env): CHATWOOT_ACCOUNT_ID para leitura de conversas (Fase 3)"
```

---

## Task 1: Lib pura — allow-list de ações + etapas válidas

**Files:**
- Create: `lib/embed-acoes.ts`
- Test: `lib/embed-acoes.test.ts`

**Interfaces:**
- Produces:
  - `ETAPAS: readonly ["novo","qualificando","agendado","fechado","perdido"]`, `type Etapa`
  - `ACOES: readonly ["mudar_etapa","add_nota","gerar_kit","rodar_triagem"]`, `type Acao`
  - `acaoValida(a: unknown): a is Acao`
  - `etapaValida(e: unknown): e is Etapa`

- [ ] **Step 1: Escrever o teste que falha**

Create `lib/embed-acoes.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { ACOES, ETAPAS, acaoValida, etapaValida } from "./embed-acoes";

describe("allow-list de ações", () => {
  it("ACOES são exatamente as 4 ações internas", () => {
    expect(ACOES).toEqual(["mudar_etapa", "add_nota", "gerar_kit", "rodar_triagem"]);
  });
  it("acaoValida aceita as conhecidas e rejeita o resto", () => {
    expect(acaoValida("mudar_etapa")).toBe(true);
    expect(acaoValida("rodar_triagem")).toBe(true);
    expect(acaoValida("enviar_mensagem")).toBe(false); // jamais
    expect(acaoValida("")).toBe(false);
    expect(acaoValida(undefined)).toBe(false);
  });
});

describe("etapas válidas", () => {
  it("ETAPAS batem com o CHECK do banco", () => {
    expect(ETAPAS).toEqual(["novo", "qualificando", "agendado", "fechado", "perdido"]);
  });
  it("etapaValida só aceita as 5", () => {
    expect(etapaValida("agendado")).toBe(true);
    expect(etapaValida("arquivado")).toBe(false);
    expect(etapaValida(null)).toBe(false);
  });
});
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `npx vitest run lib/embed-acoes.test.ts`
Expected: FAIL — `Failed to resolve import "./embed-acoes"`.

- [ ] **Step 3: Implementar o módulo puro**

Create `lib/embed-acoes.ts`:
```ts
// Painel do Lead (Fase 3) — allow-list das ações internas de CRM e etapas válidas.
// PURO (sem React, sem I/O). A rota /api/embed/acoes só executa o que estiver aqui;
// nenhuma ação desta lista envia mensagem ao lead (envio é manual, no Chatwoot).

export const ETAPAS = ["novo", "qualificando", "agendado", "fechado", "perdido"] as const;
export type Etapa = (typeof ETAPAS)[number];

export const ACOES = ["mudar_etapa", "add_nota", "gerar_kit", "rodar_triagem"] as const;
export type Acao = (typeof ACOES)[number];

export function acaoValida(a: unknown): a is Acao {
  return typeof a === "string" && (ACOES as readonly string[]).includes(a);
}

export function etapaValida(e: unknown): e is Etapa {
  return typeof e === "string" && (ETAPAS as readonly string[]).includes(e);
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `npx vitest run lib/embed-acoes.test.ts`
Expected: PASS — 4 testes verdes.

- [ ] **Step 5: Commit**

```bash
git add lib/embed-acoes.ts lib/embed-acoes.test.ts
git commit -m "feat(acoes): lib pura — allow-list de ações + etapas válidas"
```

---

## Task 2: Rota embed — `/api/embed/acoes` (mudar_etapa + add_nota + GET agentes)

**Files:**
- Create: `app/api/embed/acoes/route.ts`
- Verify: `npx tsc --noEmit` + `npm run build`

**Interfaces:**
- Consumes: `validarTokenEmbed` (`@/lib/embed-token`), `normalizarTelefone` (`@/lib/chatwoot/eventos`), `criarClienteAdmin` (`@/lib/supabase/server`), `acaoValida`/`etapaValida` (`@/lib/embed-acoes`).
- Produces:
  - `GET ?token` → `{ agentes: {id,nome,area}[] }` (para o seletor de triagem)
  - `POST ?token` body `{ acao, telefone, ... }`:
    - `mudar_etapa` `{ etapa }` → grava `leads.etapa` + `lead_etapa_historico`. Resp `{ ok:true, etapa }`.
    - `add_nota` `{ conteudo }` → insere `lead_notas`. Resp `{ ok:true }`.
    - (`gerar_kit` e `rodar_triagem` chegam nas Tasks 4 e 7 — aqui retornam 400 "ação não implementada".)

> **Nota de reuso:** o helper `acharLeadId` repete o padrão já presente em `app/api/embed/kit/route.ts` e `app/api/embed/consulta/route.ts` (contato→lead, fallback lead por telefone). Mantém-se inline para a rota ser autocontida, seguindo o padrão atual do código.

- [ ] **Step 1: Implementar a rota (esqueleto + 2 ações)**

Create `app/api/embed/acoes/route.ts`:
```ts
// API do Painel do Lead (Fase 3): ações write-back INTERNAS de CRM, todas
// autenticadas pelo token HMAC do embed (sem sessão Supabase no iframe).
// Allow-list rígida (lib/embed-acoes) — NENHUMA ação envia mensagem ao lead.
//   GET  ?token        → lista de agentes ativos (para o seletor de triagem)
//   POST ?token        → { acao, telefone, ... }: mudar_etapa | add_nota | gerar_kit | rodar_triagem
import { NextResponse } from "next/server";
import { criarClienteAdmin } from "@/lib/supabase/server";
import { validarTokenEmbed } from "@/lib/embed-token";
import { normalizarTelefone } from "@/lib/chatwoot/eventos";
import { acaoValida, etapaValida } from "@/lib/embed-acoes";

// Resolve o lead pelo telefone — mesma regra da /api/embed/kit e /api/embed/consulta.
async function acharLeadId(
  admin: ReturnType<typeof criarClienteAdmin>,
  telefone: string,
): Promise<string | null> {
  const { data: contato } = await admin
    .from("contatos")
    .select("lead_id")
    .eq("telefone", telefone)
    .maybeSingle();
  if (contato?.lead_id) return contato.lead_id;
  const { data: l } = await admin
    .from("leads")
    .select("id")
    .eq("telefone", telefone)
    .order("criado_em", { ascending: false })
    .limit(1)
    .maybeSingle();
  return l?.id ?? null;
}

export async function GET(req: Request) {
  const url = new URL(req.url);
  if (!validarTokenEmbed(process.env.EMBED_HMAC_SECRET, url.searchParams.get("token"))) {
    return NextResponse.json({ erro: "não autorizado" }, { status: 403 });
  }
  const admin = criarClienteAdmin();
  const { data } = await admin
    .from("agentes")
    .select("id, nome, area")
    .eq("ativo", true)
    .order("nome", { ascending: true });
  return NextResponse.json({ agentes: (data as { id: string; nome: string; area: string }[]) ?? [] });
}

export async function POST(req: Request) {
  const url = new URL(req.url);
  if (!validarTokenEmbed(process.env.EMBED_HMAC_SECRET, url.searchParams.get("token"))) {
    return NextResponse.json({ erro: "não autorizado" }, { status: 403 });
  }

  const corpo = await req.json().catch(() => ({}));
  const acao = corpo?.acao;
  if (!acaoValida(acao)) return NextResponse.json({ erro: "ação inválida" }, { status: 400 });

  const telefone = normalizarTelefone(corpo?.telefone);
  if (!telefone) return NextResponse.json({ erro: "telefone ausente" }, { status: 400 });

  const admin = criarClienteAdmin();
  const leadId = await acharLeadId(admin, telefone);
  if (!leadId) return NextResponse.json({ erro: "lead não encontrado" }, { status: 404 });

  // ── mudar_etapa ──────────────────────────────────────────────────────────
  if (acao === "mudar_etapa") {
    const novaEtapa = corpo?.etapa;
    if (!etapaValida(novaEtapa)) return NextResponse.json({ erro: "etapa inválida" }, { status: 400 });

    const { data: lead } = await admin.from("leads").select("etapa").eq("id", leadId).maybeSingle();
    const atual = lead?.etapa ?? null;
    if (atual === novaEtapa) return NextResponse.json({ ok: true, etapa: novaEtapa }); // no-op

    const { error } = await admin.from("leads").update({ etapa: novaEtapa }).eq("id", leadId);
    if (error) return NextResponse.json({ erro: error.message }, { status: 500 });
    await admin
      .from("lead_etapa_historico")
      .insert({ lead_id: leadId, de_etapa: atual, para_etapa: novaEtapa, mudou_por: null });
    return NextResponse.json({ ok: true, etapa: novaEtapa });
  }

  // ── add_nota ─────────────────────────────────────────────────────────────
  if (acao === "add_nota") {
    const conteudo = typeof corpo?.conteudo === "string" ? corpo.conteudo.trim() : "";
    if (!conteudo) return NextResponse.json({ erro: "nota vazia" }, { status: 400 });
    const { error } = await admin
      .from("lead_notas")
      .insert({ lead_id: leadId, conteudo, autor_id: null });
    if (error) return NextResponse.json({ erro: error.message }, { status: 500 });
    return NextResponse.json({ ok: true });
  }

  // gerar_kit / rodar_triagem chegam nas Tasks 4 e 7.
  return NextResponse.json({ erro: "ação não implementada" }, { status: 400 });
}
```

- [ ] **Step 2: Verificar tipos e build**

Run: `npx tsc --noEmit`
Expected: sem erros.

Run: `npm run build`
Expected: build conclui; rota `/api/embed/acoes` aparece como dinâmica.

- [ ] **Step 3: Commit**

```bash
git add app/api/embed/acoes/route.ts
git commit -m "feat(embed): /api/embed/acoes — mudar_etapa + add_nota + GET agentes"
```

---

## Task 3: Frontend — barra de ações (etapa + nota) no painel

**Files:**
- Create: `app/embed/kit/AcoesLead.tsx`
- Modify: `app/embed/kit/page.tsx`
- Verify: `npx tsc --noEmit` + `npm run build`

**Interfaces:**
- Consumes: a rota `/api/embed/acoes` (GET agentes; POST mudar_etapa/add_nota).
- Produces: `AcoesLead({ token, telefone, conversationId, etapaAtual, temCaso, aoMudar }: { token: string; telefone: string; conversationId: number | null; etapaAtual: string | null; temCaso: boolean; aoMudar: () => void })`.
  - `aoMudar` é chamado após cada ação bem-sucedida para o painel re-buscar o contexto.
  - Nesta task, os controles de **etapa** e **nota** ficam funcionais; o botão de **kit** (Task 4) e o de **triagem + seletor de agente** (Task 7) entram depois. `conversationId`/`temCaso` já vêm nas props para não mexer na assinatura.

- [ ] **Step 1: Implementar o componente (etapa + nota)**

Create `app/embed/kit/AcoesLead.tsx`:
```tsx
"use client";

// Barra de ações do Painel do Lead (Fase 3). Ações INTERNAS de CRM, um-clique,
// sem aprovação caso a caso — NUNCA envia nada ao lead (envio é manual no Chatwoot).
// Fala só com /api/embed/acoes (HMAC). Após cada ação, chama aoMudar() p/ o painel
// re-buscar o contexto. (Kit e Triagem entram nas Tasks 4 e 7.)
import { useState } from "react";
import { ETAPAS } from "@/lib/embed-acoes";

const ROTULO_ETAPA: Record<string, string> = {
  novo: "Novo",
  qualificando: "Qualificando",
  agendado: "Agendado",
  fechado: "Fechado",
  perdido: "Perdido",
};

export default function AcoesLead({
  token,
  telefone,
  conversationId,
  etapaAtual,
  temCaso,
  aoMudar,
}: {
  token: string;
  telefone: string;
  conversationId: number | null;
  etapaAtual: string | null;
  temCaso: boolean;
  aoMudar: () => void;
}) {
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [nota, setNota] = useState("");

  async function postar(corpo: Record<string, unknown>): Promise<boolean> {
    setOcupado(true);
    setErro(null);
    try {
      const r = await fetch(`/api/embed/acoes?token=${encodeURIComponent(token)}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ telefone, ...corpo }),
      });
      const d = await r.json().catch(() => ({}));
      if (!r.ok) {
        setErro(d.erro ?? `falha (${r.status})`);
        return false;
      }
      return true;
    } catch {
      setErro("falha de rede");
      return false;
    } finally {
      setOcupado(false);
    }
  }

  async function mudarEtapa(etapa: string) {
    if (etapa === etapaAtual) return;
    if (await postar({ acao: "mudar_etapa", etapa })) aoMudar();
  }

  async function salvarNota() {
    const conteudo = nota.trim();
    if (!conteudo) return;
    if (await postar({ acao: "add_nota", conteudo })) {
      setNota("");
      aoMudar();
    }
  }

  return (
    <section className="rounded-marca border border-line/10 bg-panel p-3">
      <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-fg-dim">Ações</h2>

      {/* Mudar etapa */}
      <div className="mb-2">
        <label className="mb-1 block text-[11px] text-fg-faint">Etapa do funil</label>
        <select
          disabled={ocupado}
          value={etapaAtual ?? ""}
          onChange={(e) => mudarEtapa(e.target.value)}
          className="w-full rounded-marca border border-line/20 bg-panel2 p-1.5 text-sm"
        >
          {!etapaAtual && <option value="">—</option>}
          {ETAPAS.map((e) => (
            <option key={e} value={e}>{ROTULO_ETAPA[e]}</option>
          ))}
        </select>
      </div>

      {/* Nota rápida */}
      <div className="flex gap-1">
        <input
          value={nota}
          onChange={(e) => setNota(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") salvarNota(); }}
          placeholder="Anotar algo sobre o lead…"
          className="min-w-0 flex-1 rounded-marca border border-line/20 bg-panel2 p-1.5 text-sm"
        />
        <button
          type="button"
          onClick={salvarNota}
          disabled={ocupado || !nota.trim()}
          className="text-xs text-accent hover:underline disabled:text-fg-faint"
        >
          + nota
        </button>
      </div>

      {erro && <p className="mt-1 text-[11px] text-low">{erro}</p>}
    </section>
  );
}
```

- [ ] **Step 2: Capturar `conversation_id` e habilitar re-fetch em `page.tsx`**

Em `app/embed/kit/page.tsx`:

(a) Adicionar o import junto aos outros do topo:
```tsx
import AcoesLead from "./AcoesLead";
```

(b) No componente `EmbedLeadPage`, junto dos outros `useState`, adicionar dois estados (id da conversa e gatilho de recarga):
```tsx
  const [conversationId, setConversationId] = useState<number | null>(null);
  const [versao, setVersao] = useState(0);
```

(c) No `useEffect` de inicialização, dentro de `aoReceber`, no bloco `if (payload?.event === "appContext")`, capturar o id da conversa logo após pegar o telefone:
```tsx
      if (payload?.event === "appContext") {
        const tel = telefoneDoContexto(payload.data);
        if (tel) setTelefone(tel);
        const cid = payload.data?.conversation?.id;
        if (typeof cid === "number") setConversationId(cid);
      }
```

(d) No `useEffect` que busca o painel (o keyed em `[token, telefone]`), adicionar `versao` às dependências para permitir re-buscar após uma ação:
```tsx
  }, [token, telefone, versao]);
```

(e) No `return` principal, logo APÓS o `</header>` e ANTES do bloco dos blocos do Kit (`{kit ? ...`), inserir a barra de ações:
```tsx
      {token && telefone && (
        <AcoesLead
          token={token}
          telefone={telefone}
          conversationId={conversationId}
          etapaAtual={lead?.etapa ?? null}
          temCaso={!!dados.caso_id}
          aoMudar={() => setVersao((v) => v + 1)}
        />
      )}
```

- [ ] **Step 3: Verificar tipos e build**

Run: `npx tsc --noEmit`
Expected: sem erros.

Run: `npm run build`
Expected: build conclui sem erro.

- [ ] **Step 4: Conferência por leitura**

Confirmar por leitura:
- Trocar a etapa no `<select>` → POST `mudar_etapa` → painel recarrega (etapa nova no cabeçalho + nova linha no histórico).
- Escrever nota + "+ nota"/Enter → POST `add_nota` → painel recarrega (nota aparece na gaveta Notas).
Anotar no relatório: "conferência por leitura; visual no Chatwoot fica pro Eduardo".

- [ ] **Step 5: Commit**

```bash
git add app/embed/kit/AcoesLead.tsx app/embed/kit/page.tsx
git commit -m "feat(painel-lead): barra de ações — mudar etapa + nota (write-back)"
```

---

## Task 4: Ação `gerar_kit` (reusa lib/kit-closer)

**Files:**
- Modify: `app/api/embed/acoes/route.ts`
- Modify: `app/embed/kit/AcoesLead.tsx`
- Verify: `npx tsc --noEmit` + `npm run build`

**Interfaces:**
- Consumes: `gerarKitCloser` (`@/lib/kit-closer`).
- Produces: `POST { acao:"gerar_kit", telefone }` → carrega o `caso_id` do lead, regenera o kit. Resp `{ ok:true }` ou erro (422 sem caso/sem análise; 502 falha de IA).

- [ ] **Step 1: Adicionar o import do kit no topo da rota**

Em `app/api/embed/acoes/route.ts`, adicionar junto aos imports:
```ts
import { gerarKitCloser } from "@/lib/kit-closer";
```

- [ ] **Step 2: Implementar a ação (substituir o fallback final)**

Em `app/api/embed/acoes/route.ts`, **substituir** a linha final:
```ts
  // gerar_kit / rodar_triagem chegam nas Tasks 4 e 7.
  return NextResponse.json({ erro: "ação não implementada" }, { status: 400 });
```
por:
```ts
  // ── gerar_kit ────────────────────────────────────────────────────────────
  if (acao === "gerar_kit") {
    const { data: lead } = await admin.from("leads").select("caso_id").eq("id", leadId).maybeSingle();
    const casoId = lead?.caso_id ?? null;
    if (!casoId) return NextResponse.json({ erro: "lead sem caso (rode a triagem antes)" }, { status: 422 });

    const { data: caso } = await admin
      .from("casos")
      .select("id, resultado, viabilidade, cliente_nome, area, agente_id")
      .eq("id", casoId)
      .maybeSingle();
    if (!caso) return NextResponse.json({ erro: "caso não encontrado" }, { status: 404 });
    if (!caso.resultado) return NextResponse.json({ erro: "caso sem análise para gerar o kit" }, { status: 422 });

    const { data: agente } = await admin
      .from("agentes")
      .select("provider, modelo, sensivel")
      .eq("id", caso.agente_id)
      .maybeSingle();
    if (!agente) return NextResponse.json({ erro: "agente do caso não encontrado" }, { status: 404 });

    try {
      const kit = await gerarKitCloser(agente, caso);
      await admin.from("casos").update({ kit_closer: kit, kit_status: "pronto" }).eq("id", casoId);
      return NextResponse.json({ ok: true });
    } catch (e) {
      await admin.from("casos").update({ kit_status: "erro" }).eq("id", casoId);
      return NextResponse.json({ erro: e instanceof Error ? e.message : "falha ao gerar o kit" }, { status: 502 });
    }
  }

  // rodar_triagem chega na Task 7.
  return NextResponse.json({ erro: "ação não implementada" }, { status: 400 });
```

- [ ] **Step 3: Botão "Regerar kit" no componente (quando há caso)**

Em `app/embed/kit/AcoesLead.tsx`, logo ANTES do bloco `{erro && ...}` no final do `return`, inserir:
```tsx
      {temCaso && (
        <div className="mt-2 border-t border-line/10 pt-2">
          <button
            type="button"
            onClick={async () => { if (await postar({ acao: "gerar_kit" })) aoMudar(); }}
            disabled={ocupado}
            className="text-xs text-accent hover:underline disabled:text-fg-faint"
          >
            {ocupado ? "gerando…" : "↻ Regerar kit do closer"}
          </button>
        </div>
      )}
```

- [ ] **Step 4: Verificar tipos e build**

Run: `npx tsc --noEmit`
Expected: sem erros.

Run: `npm run build`
Expected: build conclui sem erro.

- [ ] **Step 5: Commit**

```bash
git add app/api/embed/acoes/route.ts app/embed/kit/AcoesLead.tsx
git commit -m "feat(acoes): gerar_kit no painel (reusa gerarKitCloser)"
```

---

## Task 5: Lib pura — montar transcrição da conversa do Chatwoot

**Files:**
- Create: `lib/chatwoot/transcricao.ts`
- Test: `lib/chatwoot/transcricao.test.ts`

**Interfaces:**
- Produces:
  - `interface MensagemChatwoot { content: string | null; message_type: number; private?: boolean; created_at?: number; sender?: { name?: string | null } | null }`
  - `montarTranscricao(mensagens: MensagemChatwoot[]): string` — só mensagens públicas de entrada (`message_type === 0` = cliente) e saída (`message_type === 1` = atendente), com conteúdo não-vazio, na ordem recebida; rotula `Cliente:`/`Atendente:`; ignora notas privadas e eventos de atividade (`message_type === 2`).

- [ ] **Step 1: Escrever o teste que falha**

Create `lib/chatwoot/transcricao.test.ts`:
```ts
import { describe, it, expect } from "vitest";
import { montarTranscricao, type MensagemChatwoot } from "./transcricao";

const m = (over: Partial<MensagemChatwoot>): MensagemChatwoot => ({
  content: "x",
  message_type: 0,
  private: false,
  ...over,
});

describe("montarTranscricao", () => {
  it("rotula entrada=Cliente e saída=Atendente, na ordem", () => {
    const t = montarTranscricao([
      m({ content: "tive um acidente no trabalho", message_type: 0 }),
      m({ content: "entendi, me conta mais", message_type: 1 }),
      m({ content: "caí da escada", message_type: 0 }),
    ]);
    expect(t).toBe(
      "Cliente: tive um acidente no trabalho\nAtendente: entendi, me conta mais\nCliente: caí da escada",
    );
  });

  it("ignora notas privadas, eventos de atividade e conteúdo vazio", () => {
    const t = montarTranscricao([
      m({ content: "nota interna", private: true }),
      m({ content: "conversa entrou", message_type: 2 }),
      m({ content: "   ", message_type: 0 }),
      m({ content: null, message_type: 1 }),
      m({ content: "tenho CAT?", message_type: 0 }),
    ]);
    expect(t).toBe("Cliente: tenho CAT?");
  });

  it("lista vazia => string vazia", () => {
    expect(montarTranscricao([])).toBe("");
  });
});
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `npx vitest run lib/chatwoot/transcricao.test.ts`
Expected: FAIL — `Failed to resolve import "./transcricao"`.

- [ ] **Step 3: Implementar o módulo puro**

Create `lib/chatwoot/transcricao.ts`:
```ts
// Monta a transcrição de uma conversa do Chatwoot para servir de texto-fonte da
// triagem (Painel do Lead, Fase 3). PURO (sem I/O). Recebe as mensagens cruas da
// API do Chatwoot e devolve um diálogo "Cliente:/Atendente:". O fetch fica em
// lib/chatwoot/api.ts. Convenção do Chatwoot: message_type 0=entrada (cliente),
// 1=saída (atendente), 2=atividade (sistema); `private` = nota interna.

export interface MensagemChatwoot {
  content: string | null;
  message_type: number;
  private?: boolean;
  created_at?: number;
  sender?: { name?: string | null } | null;
}

export function montarTranscricao(mensagens: MensagemChatwoot[]): string {
  return mensagens
    .filter(
      (m) =>
        !m.private &&
        (m.message_type === 0 || m.message_type === 1) &&
        (m.content ?? "").trim().length > 0,
    )
    .map((m) => `${m.message_type === 0 ? "Cliente" : "Atendente"}: ${m.content!.trim()}`)
    .join("\n");
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `npx vitest run lib/chatwoot/transcricao.test.ts`
Expected: PASS — 3 testes verdes.

- [ ] **Step 5: Commit**

```bash
git add lib/chatwoot/transcricao.ts lib/chatwoot/transcricao.test.ts
git commit -m "feat(chatwoot): montar transcrição da conversa (lib pura + teste)"
```

---

## Task 6: Cliente REST — ler mensagens da conversa no Chatwoot

**Files:**
- Create: `lib/chatwoot/api.ts`
- Verify: `npx tsc --noEmit`

**Interfaces:**
- Consumes: `MensagemChatwoot` (`@/lib/chatwoot/transcricao`); env `CHATWOOT_URL`, `CHATWOOT_API_TOKEN`, `CHATWOOT_ACCOUNT_ID`.
- Produces: `buscarMensagensConversa(conversationId: number | string): Promise<MensagemChatwoot[]>` — lança `Error` com mensagem clara se faltar config ou a API falhar.

> Endpoint Chatwoot (Application API): `GET {CHATWOOT_URL}/api/v1/accounts/{ACCOUNT_ID}/conversations/{conversationId}/messages`, header `api_access_token: {CHATWOOT_API_TOKEN}`. A resposta traz `{ payload: MensagemChatwoot[] }`. Sem teste automatizado (I/O puro) — a lógica testável (parsing/rotulagem) está na Task 5.

- [ ] **Step 1: Implementar o cliente**

Create `lib/chatwoot/api.ts`:
```ts
// Cliente REST de LEITURA do Chatwoot. Hoje só busca as mensagens de uma conversa
// (texto-fonte da triagem no Painel do Lead, Fase 3). Usa a Application API do
// Chatwoot autenticada por api_access_token. A montagem da transcrição (pura) fica
// em lib/chatwoot/transcricao.ts. (Escrita de labels/atributos virá na Fase 4.)
import type { MensagemChatwoot } from "./transcricao";

export async function buscarMensagensConversa(
  conversationId: number | string,
): Promise<MensagemChatwoot[]> {
  const base = process.env.CHATWOOT_URL;
  const token = process.env.CHATWOOT_API_TOKEN;
  const conta = process.env.CHATWOOT_ACCOUNT_ID;
  if (!base || !token || !conta) {
    throw new Error("Chatwoot API não configurada (CHATWOOT_URL/CHATWOOT_API_TOKEN/CHATWOOT_ACCOUNT_ID).");
  }

  const u = `${base.replace(/\/$/, "")}/api/v1/accounts/${conta}/conversations/${conversationId}/messages`;
  const r = await fetch(u, { headers: { api_access_token: token } });
  if (!r.ok) throw new Error(`Falha ao ler a conversa no Chatwoot (${r.status}).`);

  const d = await r.json().catch(() => null);
  return (d?.payload as MensagemChatwoot[]) ?? [];
}
```

- [ ] **Step 2: Verificar tipos**

Run: `npx tsc --noEmit`
Expected: sem erros.

- [ ] **Step 3: Commit**

```bash
git add lib/chatwoot/api.ts
git commit -m "feat(chatwoot): cliente REST p/ ler mensagens de uma conversa"
```

---

## Task 7: Ação `rodar_triagem` (transcrição → IA → caso) + seletor de agente

**Files:**
- Modify: `app/api/embed/acoes/route.ts`
- Modify: `app/embed/kit/AcoesLead.tsx`
- Verify: `npx tsc --noEmit` + `npm run build`

**Interfaces:**
- Consumes: `analisarCaso` (`@/lib/triagem`), `gerarKitCloser` (`@/lib/kit-closer`), `buscarMensagensConversa` (`@/lib/chatwoot/api`), `montarTranscricao` (`@/lib/chatwoot/transcricao`).
- Produces: `POST { acao:"rodar_triagem", telefone, conversation_id, agente_id }` → lê a conversa, monta transcrição, roda a IA do agente, **insere um caso** (`responsavel_id: null`), vincula ao lead (`caso_id` + etapa `qualificando` + histórico), e best-effort gera o kit se viável. Resp `{ ok:true, caso_id, viabilidade }`.

- [ ] **Step 1: Adicionar imports no topo da rota**

Em `app/api/embed/acoes/route.ts`, adicionar junto aos imports:
```ts
import { analisarCaso } from "@/lib/triagem";
import { buscarMensagensConversa } from "@/lib/chatwoot/api";
import { montarTranscricao } from "@/lib/chatwoot/transcricao";
```

- [ ] **Step 2: Implementar a ação (substituir o fallback final)**

Em `app/api/embed/acoes/route.ts`, **substituir** a linha final:
```ts
  // rodar_triagem chega na Task 7.
  return NextResponse.json({ erro: "ação não implementada" }, { status: 400 });
```
por:
```ts
  // ── rodar_triagem ────────────────────────────────────────────────────────
  if (acao === "rodar_triagem") {
    const conversationId = corpo?.conversation_id;
    const agenteId = typeof corpo?.agente_id === "string" ? corpo.agente_id : null;
    if (conversationId == null) return NextResponse.json({ erro: "conversa ausente" }, { status: 400 });
    if (!agenteId) return NextResponse.json({ erro: "agente ausente" }, { status: 400 });

    // 1. Transcrição da conversa (texto-fonte).
    let transcricao: string;
    try {
      const msgs = await buscarMensagensConversa(conversationId);
      transcricao = montarTranscricao(msgs);
    } catch (e) {
      return NextResponse.json({ erro: e instanceof Error ? e.message : "erro ao ler a conversa" }, { status: 502 });
    }
    if (!transcricao.trim()) {
      return NextResponse.json({ erro: "conversa sem mensagens para analisar" }, { status: 422 });
    }

    // 2. Agente (precisa estar ativo) e dados do lead.
    const { data: agente } = await admin
      .from("agentes")
      .select("*")
      .eq("id", agenteId)
      .eq("ativo", true)
      .maybeSingle();
    if (!agente) return NextResponse.json({ erro: "agente inválido" }, { status: 400 });

    const { data: lead } = await admin.from("leads").select("nome, etapa").eq("id", leadId).maybeSingle();

    // 3. IA: análise jurídica.
    let resultado: string;
    let viabilidade: string | null;
    try {
      const r = await analisarCaso(agente, transcricao);
      resultado = r.resultado;
      viabilidade = r.viabilidade;
    } catch (e) {
      return NextResponse.json({ erro: e instanceof Error ? e.message : "falha na IA" }, { status: 502 });
    }

    // 4. Salva o caso (sem usuário de sessão → responsavel_id null).
    const { data: caso, error: erroCaso } = await admin
      .from("casos")
      .insert({
        responsavel_id: null,
        cliente_nome: lead?.nome ?? null,
        area: agente.area,
        agente_id: agente.id,
        status: "concluido",
        resultado,
        viabilidade,
        kit_status: "pendente",
        texto_fonte: transcricao,
        concluido_em: new Date().toISOString(),
      })
      .select("id")
      .single();
    if (erroCaso || !caso) return NextResponse.json({ erro: "falha ao salvar o caso" }, { status: 500 });

    // 5. Kit do Closer (best-effort, só viáveis) — falha aqui não quebra a triagem.
    if (viabilidade === "alta" || viabilidade === "media") {
      try {
        const kit = await gerarKitCloser(
          { provider: agente.provider, modelo: agente.modelo, sensivel: agente.sensivel },
          { resultado, viabilidade, cliente_nome: lead?.nome ?? null, area: agente.area },
        );
        await admin.from("casos").update({ kit_closer: kit, kit_status: "pronto" }).eq("id", caso.id);
      } catch {
        await admin.from("casos").update({ kit_status: "erro" }).eq("id", caso.id);
      }
    }

    // 6. Vincula ao lead e avança a etapa (com histórico), se ainda não estiver à frente.
    await admin.from("leads").update({ caso_id: caso.id }).eq("id", leadId);
    if (lead?.etapa === "novo" || lead?.etapa == null) {
      await admin.from("leads").update({ etapa: "qualificando" }).eq("id", leadId);
      await admin
        .from("lead_etapa_historico")
        .insert({ lead_id: leadId, de_etapa: lead?.etapa ?? null, para_etapa: "qualificando", mudou_por: null });
    }

    return NextResponse.json({ ok: true, caso_id: caso.id, viabilidade });
  }

  return NextResponse.json({ erro: "ação não implementada" }, { status: 400 });
```

- [ ] **Step 3: Seletor de agente + botão de triagem no componente**

Em `app/embed/kit/AcoesLead.tsx`:

(a) trocar o import do topo para incluir `useEffect`:
```tsx
import { useEffect, useState } from "react";
```

(b) dentro do componente, junto dos outros estados, adicionar:
```tsx
  const [agentes, setAgentes] = useState<{ id: string; nome: string; area: string }[]>([]);
  const [agenteId, setAgenteId] = useState("");
```

(c) abaixo dos estados, carregar os agentes (só quando o lead NÃO tem caso — é quando o botão aparece):
```tsx
  useEffect(() => {
    if (temCaso) return;
    fetch(`/api/embed/acoes?token=${encodeURIComponent(token)}`)
      .then((r) => (r.ok ? r.json() : { agentes: [] }))
      .then((d) => {
        const lista = (d.agentes as { id: string; nome: string; area: string }[]) ?? [];
        setAgentes(lista);
        if (lista[0]) setAgenteId((a) => a || lista[0].id);
      })
      .catch(() => setAgentes([]));
  }, [token, temCaso]);
```

(d) no `return`, logo ANTES do bloco `{temCaso && (` (o botão de regerar kit da Task 4), inserir o bloco de triagem (aparece quando o lead ainda não tem caso):
```tsx
      {!temCaso && (
        <div className="mt-2 border-t border-line/10 pt-2">
          <label className="mb-1 block text-[11px] text-fg-faint">Rodar triagem com a conversa</label>
          <div className="flex gap-1">
            <select
              value={agenteId}
              onChange={(e) => setAgenteId(e.target.value)}
              disabled={ocupado || !agentes.length}
              className="min-w-0 flex-1 rounded-marca border border-line/20 bg-panel2 p-1.5 text-sm"
            >
              {!agentes.length && <option value="">Sem agentes</option>}
              {agentes.map((a) => (
                <option key={a.id} value={a.id}>{a.nome} · {a.area}</option>
              ))}
            </select>
            <button
              type="button"
              onClick={async () => {
                if (!agenteId) return;
                if (await postar({ acao: "rodar_triagem", conversation_id: conversationId, agente_id: agenteId })) aoMudar();
              }}
              disabled={ocupado || !agenteId || conversationId == null}
              className="shrink-0 text-xs text-accent hover:underline disabled:text-fg-faint"
            >
              {ocupado ? "analisando…" : "✦ triar"}
            </button>
          </div>
          {conversationId == null && (
            <p className="mt-1 text-[11px] text-fg-faint">Abra pela conversa no Chatwoot para triar.</p>
          )}
        </div>
      )}
```

- [ ] **Step 4: Verificar tipos e build**

Run: `npx tsc --noEmit`
Expected: sem erros.

Run: `npm run build`
Expected: build conclui sem erro.

- [ ] **Step 5: Conferência por leitura**

Confirmar por leitura:
- Lead SEM caso + conversa aberta → aparece seletor de agente + "✦ triar"; clicar lê a conversa, roda IA, cria caso, vincula ao lead (etapa → qualificando), painel recarrega e passa a mostrar o kit.
- Sem `conversation_id` (painel aberto fora da conversa) → botão desabilitado + dica.
- `rodar_triagem` nunca envia nada ao lead.
Anotar no relatório: "conferência por leitura; visual no Chatwoot fica pro Eduardo".

- [ ] **Step 6: Commit**

```bash
git add app/api/embed/acoes/route.ts app/embed/kit/AcoesLead.tsx
git commit -m "feat(acoes): rodar_triagem usando a transcrição da conversa do Chatwoot"
```

---

## Task 8: Verificação final

**Files:** nenhum (verificação)

- [ ] **Step 1: Testes**

Run: `npx vitest run`
Expected: todos verdes, incluindo `lib/embed-acoes.test.ts` e `lib/chatwoot/transcricao.test.ts` novos.

- [ ] **Step 2: Build**

Run: `npm run build`
Expected: sem erros; rota `/api/embed/acoes` presente.

- [ ] **Step 3: Allow-list à prova de envio (conferência por leitura)**

Conferir em `app/api/embed/acoes/route.ts` que: (a) toda ação passa por `acaoValida`; (b) não existe nenhum caminho que chame envio ao Chatwoot/WhatsApp (a rota só faz `analisarCaso`/`gerarKitCloser`/escrita no Supabase + `buscarMensagensConversa`, que é **leitura**). Registrar: "nenhuma ação envia mensagem ao lead".

- [ ] **Step 4: UAT visual (humano — Eduardo, no Chatwoot)**

Numa conversa real no Chatwoot, no Painel do Lead:
1. Trocar etapa pelo seletor → confere no cabeçalho + histórico.
2. Adicionar nota → aparece na gaveta Notas.
3. Lead sem caso → escolher agente + "✦ triar" → cria caso a partir da conversa; painel passa a mostrar o kit.
4. Lead com caso → "↻ Regerar kit" → kit atualizado.

---

## Self-Review (feita)

- **Cobertura do spec (cockpit, Fase 3 + decisão "puxar a conversa"):** barra de ações sempre visível ✓ (Task 3); mudar etapa grava `leads.etapa` + `lead_etapa_historico` ✓ (Task 2); +nota grava `lead_notas` ✓ (Task 2); rodar triagem/gerar kit via fluxo existente ✓ (Tasks 4,7); endpoint único `POST /api/embed/acoes` com allow-list ✓ (Tasks 1,2); nunca envia ao lead ✓ (constraint + Task 8.3); triagem usa a **transcrição da conversa do Chatwoot** como fonte ✓ (Tasks 5,6,7), sem depender da Fase 4 (usa `conversation_id` do `appContext`).
- **Placeholders:** nenhum — todo passo tem código/comando e saída esperada. Task 0 (env) e UAT visual são marcados como manuais explicitamente.
- **Consistência de tipos:** `acaoValida`/`etapaValida`/`ETAPAS`/`ACOES` (Task 1) usados na rota (Tasks 2,4,7) e no componente (Task 3). `MensagemChatwoot`/`montarTranscricao` (Task 5) consumidos por `buscarMensagensConversa` (Task 6) e pela rota (Task 7). Assinaturas de `analisarCaso(agente, texto)→{resultado,viabilidade}` e `gerarKitCloser(agente, caso)` conferidas contra `app/api/triagem/route.ts` e `app/api/pra-fechar/gerar-kit/route.ts`. Props de `AcoesLead` (Task 3) estendidas sem mudar a assinatura nas Tasks 4 e 7.

## Não-objetivos (desta fase)

- **Sync bidirecional Chatwoot↔intranet** (labels `fase:*`, custom attributes) — é a **Fase 4** do cockpit, com `lib/chatwoot/api.ts` ganhando a parte de **escrita** e o webhook tratando `conversation_updated`.
- **Escolha de documento/anexo** como fonte da triagem no painel (a fonte aqui é a conversa).
- **Editar/excluir** notas e etapas pelo painel (só adicionar/mudar).

## Deploy (após as tasks, com aprovação do Eduardo)

1. **Sem migração de banco** nesta fase (as tabelas `lead_notas`/`lead_etapa_historico`/`casos` já têm os campos usados, todos nullable onde precisamos).
2. **Env (manual, antes da triagem funcionar):** preencher `CHATWOOT_ACCOUNT_ID` (e confirmar `CHATWOOT_URL`/`CHATWOOT_API_TOKEN`) no `intranet.env` da VPS.
3. Merge → `main` + `git push` (Vercel auto-deploya).
4. VPS: `ssh root@185.194.216.67` → `cd /opt/intranet-ramon && git pull && docker compose up -d --build intranet`.
5. Smoke: `curl -ski https://app.ramonantonio.adv.br/api/embed/acoes | head -1` → **403** (sem token).

## Nota de aprovação

Pela constituição, **quem commita/push/deploya é o Eduardo** (ou Claude com autorização explícita por ocasião). Os passos de commit ficam à disposição; merge/push/deploy idem.

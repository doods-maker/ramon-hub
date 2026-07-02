# Painel do Lead — Fase 2: Consulta rápida (playbook da tese + base de conhecimento)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao Painel do Lead uma gaveta "Consulta" que mostra o playbook da tese do lead (perguntas de qualificação, objeções, documentos) e uma busca na base de conhecimento — tudo dentro do Chatwoot, sem trocar de aba.

**Architecture:** Liga o lead a uma tese via nova coluna `leads.tese_id`. Um endpoint embed (`/api/embed/consulta`, autenticado por HMAC, cliente admin) serve três coisas: o contexto do playbook, a busca de conhecimento (orquestrador compartilhado com a rota de sessão, DRY) e a gravação da tese escolhida. Um componente cliente (`Consulta.tsx`) consome isso na lateral do Chatwoot. Lógica de agrupamento/dedup fica em libs puras testadas.

**Tech Stack:** Next.js 15 (App Router), TypeScript, Tailwind, Supabase (Postgres + RPC full-text `buscar_conhecimento`), DeepSeek via `chamarIA`, Vitest (node, `lib/**/*.test.ts`).

## Global Constraints

- **Idioma de trabalho:** PT-BR em código, comentários e UI.
- **Autenticação do embed:** HMAC estático (`lib/embed-token` → `validarTokenEmbed`), igual à rota `/api/embed/kit`. Sem sessão Supabase no iframe. Use `criarClienteAdmin()` (service role, ignora RLS) nas rotas embed.
- **Telefone canônico:** E.164 só dígitos (`normalizarTelefone` de `lib/chatwoot/eventos`), igual à `/api/embed/kit`.
- **Escrita permitida nesta fase:** SOMENTE gravar `leads.tese_id` (ação interna, um-clique, autorizada). Nenhum envio ao lead, nenhuma outra escrita.
- **Seções do playbook na consulta:** apenas `qualificacao`, `objecao`, `documento` (nessa ordem). As seções `abertura`/`apresentacao` NÃO entram na consulta.
- **DRY:** a busca de conhecimento (RPC + síntese DeepSeek) vira um orquestrador único usado pela rota de sessão e pela rota embed.
- **Etapas/UI:** a gaveta Consulta aparece no painel independentemente da etapa, recolhida (`<details>`), como as outras gavetas da Fase 1.
- **Modelo de dados existente:** `teses(id, nome, descricao, area, ativo, ordem)`; `tese_itens(id, tese_id, secao, titulo, conteudo, ordem)`; `leads(id, ..., caso_id)`. `secao` ∈ `abertura|apresentacao|qualificacao|objecao|documento`.

---

## File Structure

- `supabase/14_tese_lead.sql` — **novo.** Migração: coluna `leads.tese_id` (FK → `teses`, nullable, `on delete set null`) + índice.
- `lib/consulta-lead.ts` — **novo.** Puro: `SECOES_CONSULTA`, `agruparConsulta`, `temPlaybook`.
- `lib/consulta-lead.test.ts` — **novo.** Testes Vitest.
- `lib/conhecimento-busca.ts` — **novo.** `fontesUnicas` (puro) + `buscarConhecimento` (orquestrador RPC+IA).
- `lib/conhecimento-busca.test.ts` — **novo.** Testa `fontesUnicas`.
- `app/api/conhecimento/buscar/route.ts` — **modificar.** Passa a usar `buscarConhecimento` (DRY).
- `app/api/embed/consulta/route.ts` — **novo.** GET contexto / GET busca (`?q=`) / POST setar tese.
- `app/embed/kit/Consulta.tsx` — **novo.** Componente cliente da gaveta Consulta.
- `app/embed/kit/page.tsx` — **modificar.** Renderiza `<Consulta token telefone />`.

---

## Task 1: Migração — `leads.tese_id`

**Files:**
- Create: `supabase/14_tese_lead.sql`

**Interfaces:**
- Consumes: tabelas `leads`, `teses` (já existem).
- Produces: coluna `public.leads.tese_id uuid null references public.teses(id)`.

- [ ] **Step 1: Escrever a migração**

Create `supabase/14_tese_lead.sql`:

```sql
-- 14_tese_lead.sql
-- Liga o lead a uma TESE do playbook (Painel do Lead, Fase 2 do cockpit).
-- O lead existe desde o 1º contato, então a tese pode ser marcada já na
-- qualificação — antes da triagem criar o caso. Nullable: lead sem tese definida.
-- Rode no SQL Editor do Supabase.

alter table public.leads
  add column if not exists tese_id uuid references public.teses (id) on delete set null;

create index if not exists leads_tese_idx on public.leads (tese_id);
```

- [ ] **Step 2: Aplicar no Supabase (manual)**

Abrir o SQL Editor do Supabase do projeto e rodar o conteúdo de `supabase/14_tese_lead.sql`.
Expected: "Success. No rows returned".

- [ ] **Step 3: Verificar a coluna (manual)**

No SQL Editor, rodar:
```sql
select column_name, data_type, is_nullable
from information_schema.columns
where table_name = 'leads' and column_name = 'tese_id';
```
Expected: uma linha — `tese_id | uuid | YES`.

> ⚠️ Esta task não tem teste automatizado (é migração SQL). A verificação é a query do Step 3. O build/tsc local não depende dela.

- [ ] **Step 4: Commit**

```bash
git add supabase/14_tese_lead.sql
git commit -m "feat(db): leads.tese_id liga lead ao playbook da tese (Fase 2)"
```

---

## Task 2: Lib pura — agrupamento do playbook de consulta

**Files:**
- Create: `lib/consulta-lead.ts`
- Test: `lib/consulta-lead.test.ts`

**Interfaces:**
- Consumes: `agruparPorSecao`, tipo `Secao` de `@/lib/playbook`.
- Produces:
  - `SECOES_CONSULTA: Secao[]` = `["qualificacao","objecao","documento"]`
  - `interface ItemConsulta { titulo: string | null; conteudo: string }`
  - `type PlaybookConsulta = Record<"qualificacao"|"objecao"|"documento", ItemConsulta[]>`
  - `agruparConsulta(itens: {secao:string; titulo:string|null; conteudo:string; ordem?:number}[]): PlaybookConsulta`

- [ ] **Step 1: Escrever o teste que falha**

Create `lib/consulta-lead.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { SECOES_CONSULTA, agruparConsulta } from "./consulta-lead";

const itens = [
  { secao: "objecao", titulo: "Tá caro", conteudo: "Explique o êxito", ordem: 1 },
  { secao: "qualificacao", titulo: "Trabalha registrado?", conteudo: "Caracteriza vínculo", ordem: 2 },
  { secao: "qualificacao", titulo: "Tem CAT?", conteudo: "Prova do acidente", ordem: 1 },
  { secao: "documento", titulo: "CNIS", conteudo: "Histórico contributivo", ordem: 1 },
  { secao: "abertura", titulo: null, conteudo: "Olá {{nome}}", ordem: 1 }, // deve ser ignorada
  { secao: "apresentacao", titulo: null, conteudo: "Sobre a tese", ordem: 1 }, // deve ser ignorada
];

describe("SECOES_CONSULTA", () => {
  it("são exatamente qualificacao, objecao, documento (nessa ordem)", () => {
    expect(SECOES_CONSULTA).toEqual(["qualificacao", "objecao", "documento"]);
  });
});

describe("agruparConsulta", () => {
  it("agrupa nas 3 seções e ordena por ordem, ignorando abertura/apresentacao", () => {
    const g = agruparConsulta(itens);
    expect(g.qualificacao.map((i) => i.titulo)).toEqual(["Tem CAT?", "Trabalha registrado?"]);
    expect(g.objecao).toEqual([{ titulo: "Tá caro", conteudo: "Explique o êxito" }]);
    expect(g.documento).toEqual([{ titulo: "CNIS", conteudo: "Histórico contributivo" }]);
    expect(Object.keys(g)).toEqual(["qualificacao", "objecao", "documento"]);
  });
  it("lista vazia => grupos vazios", () => {
    expect(agruparConsulta([])).toEqual({ qualificacao: [], objecao: [], documento: [] });
  });
});
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `npx vitest run lib/consulta-lead.test.ts`
Expected: FAIL — `Failed to resolve import "./consulta-lead"`.

- [ ] **Step 3: Implementar o módulo puro**

Create `lib/consulta-lead.ts`:

```ts
// Consulta do Painel do Lead: shape do playbook da tese para exibição na lateral
// do Chatwoot. PURO (sem React, sem I/O). Mostra só as seções úteis na conversa
// (qualificação, objeções, documentos) — abertura/apresentação ficam de fora.
import { agruparPorSecao, type Secao } from "@/lib/playbook";

export const SECOES_CONSULTA: Secao[] = ["qualificacao", "objecao", "documento"];

export interface ItemConsulta {
  titulo: string | null;
  conteudo: string;
}
export type PlaybookConsulta = Record<"qualificacao" | "objecao" | "documento", ItemConsulta[]>;

// Agrupa os itens da tese nas 3 seções da consulta, cada uma ordenada por `ordem`.
export function agruparConsulta(
  itens: { secao: string; titulo: string | null; conteudo: string; ordem?: number }[],
): PlaybookConsulta {
  const grupos = agruparPorSecao(itens);
  const so = (chave: "qualificacao" | "objecao" | "documento"): ItemConsulta[] =>
    grupos[chave].map((i) => ({ titulo: i.titulo, conteudo: i.conteudo }));
  return {
    qualificacao: so("qualificacao"),
    objecao: so("objecao"),
    documento: so("documento"),
  };
}

```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `npx vitest run lib/consulta-lead.test.ts`
Expected: PASS — 3 testes verdes.

- [ ] **Step 5: Commit**

```bash
git add lib/consulta-lead.ts lib/consulta-lead.test.ts
git commit -m "feat(consulta): lib pura de agrupamento do playbook por seção"
```

---

## Task 3: Lib + refactor — orquestrador único da busca de conhecimento

**Files:**
- Create: `lib/conhecimento-busca.ts`
- Test: `lib/conhecimento-busca.test.ts`
- Modify: `app/api/conhecimento/buscar/route.ts`

**Interfaces:**
- Consumes: `montarContexto` de `@/lib/conhecimento`; `chamarIA` de `@/lib/ai`; `SupabaseClient` de `@supabase/supabase-js`.
- Produces:
  - `interface TrechoBusca { conhecimento_id:string; titulo:string; tipo:string|null; fonte:string|null; conteudo:string; similaridade:number }`
  - `interface FonteBusca { id:string; titulo:string; tipo:string|null; fonte:string|null }`
  - `fontesUnicas(trechos: TrechoBusca[]): FonteBusca[]` (puro)
  - `buscarConhecimento(supabase: SupabaseClient, pergunta: string): Promise<{ resposta:string; fontes: FonteBusca[] }>`

- [ ] **Step 1: Escrever o teste que falha (parte pura)**

Create `lib/conhecimento-busca.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { fontesUnicas, type TrechoBusca } from "./conhecimento-busca";

const t = (id: string, titulo: string): TrechoBusca => ({
  conhecimento_id: id, titulo, tipo: "tese", fonte: null, conteudo: "x", similaridade: 0.5,
});

describe("fontesUnicas", () => {
  it("deduplica por conhecimento_id preservando a ordem de relevância", () => {
    const r = fontesUnicas([t("a", "A"), t("b", "B"), t("a", "A de novo"), t("c", "C")]);
    expect(r.map((f) => f.id)).toEqual(["a", "b", "c"]);
    expect(r[0]).toEqual({ id: "a", titulo: "A", tipo: "tese", fonte: null });
  });
  it("lista vazia => []", () => {
    expect(fontesUnicas([])).toEqual([]);
  });
});
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `npx vitest run lib/conhecimento-busca.test.ts`
Expected: FAIL — `Failed to resolve import "./conhecimento-busca"`.

- [ ] **Step 3: Implementar o orquestrador**

Create `lib/conhecimento-busca.ts`:

```ts
// Busca na base de conhecimento: orquestra a busca full-text (RPC Postgres) + a
// síntese pela IA (DeepSeek) citando as fontes. Usado pela rota de sessão
// (/api/conhecimento/buscar) e pela rota embed (/api/embed/consulta) — DRY.
// Recebe um SupabaseClient já pronto (de sessão OU admin), então serve aos dois.
import type { SupabaseClient } from "@supabase/supabase-js";
import { montarContexto } from "@/lib/conhecimento";
import { chamarIA } from "@/lib/ai";

export interface TrechoBusca {
  conhecimento_id: string;
  titulo: string;
  tipo: string | null;
  fonte: string | null;
  conteudo: string;
  similaridade: number;
}
export interface FonteBusca {
  id: string;
  titulo: string;
  tipo: string | null;
  fonte: string | null;
}

const SISTEMA =
  "Você é um assistente jurídico do escritório. Responda à pergunta USANDO APENAS os trechos " +
  "fornecidos como contexto. Cite as fontes no formato [Fonte N] ao usá-las. Se o contexto não " +
  "for suficiente, diga claramente que não há base na base de conhecimento — não invente. " +
  "Responda em português, de forma objetiva e útil para um advogado.";

// Fontes únicas por documento, na ordem de relevância. PURO (testável).
export function fontesUnicas(trechos: TrechoBusca[]): FonteBusca[] {
  const vistos = new Set<string>();
  const out: FonteBusca[] = [];
  for (const t of trechos) {
    if (vistos.has(t.conhecimento_id)) continue;
    vistos.add(t.conhecimento_id);
    out.push({ id: t.conhecimento_id, titulo: t.titulo, tipo: t.tipo, fonte: t.fonte });
  }
  return out;
}

// Busca + síntese. Lança Error em entrada vazia ou falha de RPC (a rota traduz em HTTP).
export async function buscarConhecimento(
  supabase: SupabaseClient,
  pergunta: string,
): Promise<{ resposta: string; fontes: FonteBusca[] }> {
  const limpa = (pergunta ?? "").trim();
  if (!limpa) throw new Error("Informe a pergunta.");

  const { data, error } = await supabase.rpc("buscar_conhecimento", { consulta: limpa, qtd: 6 });
  if (error) throw new Error("Erro na busca: " + error.message);

  const trechos = (data as TrechoBusca[]) ?? [];
  if (trechos.length === 0) {
    return {
      resposta:
        "Não encontrei nada na base de conhecimento sobre isso. Cadastre teses ou estudos relacionados.",
      fontes: [],
    };
  }

  const contexto = montarContexto(trechos);
  const resposta = await chamarIA({
    provider: "deepseek",
    model: "deepseek-chat",
    system: SISTEMA,
    messages: [{ role: "user", content: `Contexto:\n\n${contexto}\n\n---\n\nPergunta: ${limpa}` }],
  });

  return { resposta, fontes: fontesUnicas(trechos) };
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `npx vitest run lib/conhecimento-busca.test.ts`
Expected: PASS — 2 testes verdes.

- [ ] **Step 5: Refatorar a rota de sessão para usar o orquestrador**

Substituir TODO o corpo de `app/api/conhecimento/buscar/route.ts` por:

```ts
// Rota de API: busca full-text + resposta da IA sobre a base de conhecimento.
// Valida a sessão e delega a busca+síntese ao orquestrador compartilhado
// (lib/conhecimento-busca), que também serve a rota embed do Painel do Lead.
import { NextResponse } from "next/server";
import { criarClienteServidor } from "@/lib/supabase/server";
import { buscarConhecimento } from "@/lib/conhecimento-busca";

export async function POST(req: Request) {
  try {
    const supabase = await criarClienteServidor();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ erro: "Não autenticado." }, { status: 401 });

    const { pergunta } = await req.json();
    if (!pergunta?.trim()) return NextResponse.json({ erro: "Informe a pergunta." }, { status: 400 });

    const resultado = await buscarConhecimento(supabase, pergunta);
    return NextResponse.json(resultado);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Erro inesperado.";
    return NextResponse.json({ erro: msg }, { status: 500 });
  }
}
```

- [ ] **Step 6: Verificar tipos/build da rota refatorada**

Run: `npx tsc --noEmit`
Expected: sem erros.

- [ ] **Step 7: Commit**

```bash
git add lib/conhecimento-busca.ts lib/conhecimento-busca.test.ts app/api/conhecimento/buscar/route.ts
git commit -m "refactor(conhecimento): orquestrador único de busca (DRY) + fontesUnicas puro"
```

---

## Task 4: Rota embed — `/api/embed/consulta`

**Files:**
- Create: `app/api/embed/consulta/route.ts`
- Verify: `npx tsc --noEmit` + `npm run build`

**Interfaces:**
- Consumes: `validarTokenEmbed` (`@/lib/embed-token`), `normalizarTelefone` (`@/lib/chatwoot/eventos`), `criarClienteAdmin` (`@/lib/supabase/server`), `agruparConsulta`/`temPlaybook`/`SECOES_CONSULTA` (`@/lib/consulta-lead`), `buscarConhecimento` (`@/lib/conhecimento-busca`).
- Produces três comportamentos (HMAC obrigatório em todos):
  - `GET ?token&telefone` → `{ encontrado:boolean, lead_id?, tese_atual:{id,nome}|null, playbook:PlaybookConsulta|null, teses:{id,nome}[] }`
  - `GET ?token&q` → `{ resposta:string, fontes:FonteBusca[] }`
  - `POST ?token` body `{ telefone, tese_id }` → `{ ok:true, tese_atual:{id,nome} }`

- [ ] **Step 1: Implementar a rota**

Create `app/api/embed/consulta/route.ts`:

```ts
// API do Dashboard App (gaveta "Consulta" do Painel do Lead). Três usos, todos
// autenticados pelo token HMAC do embed (sem sessão Supabase no iframe):
//   GET ?telefone=...        → contexto do playbook da tese do lead + lista de teses
//   GET ?q=...               → busca na base de conhecimento (proxy do orquestrador)
//   POST {telefone, tese_id} → grava a tese escolhida no lead (lead.tese_id)
import { NextResponse } from "next/server";
import { criarClienteAdmin } from "@/lib/supabase/server";
import { validarTokenEmbed } from "@/lib/embed-token";
import { normalizarTelefone } from "@/lib/chatwoot/eventos";
import { agruparConsulta, SECOES_CONSULTA } from "@/lib/consulta-lead";
import { buscarConhecimento } from "@/lib/conhecimento-busca";

// Resolve o lead pelo telefone — mesma regra da /api/embed/kit (contato → lead,
// fallback lead direto pelo telefone, o mais recente).
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

  // Uso 2: busca na base de conhecimento.
  const q = url.searchParams.get("q");
  if (q != null) {
    try {
      const resultado = await buscarConhecimento(admin, q);
      return NextResponse.json(resultado);
    } catch (e) {
      return NextResponse.json({ erro: e instanceof Error ? e.message : "erro" }, { status: 500 });
    }
  }

  // Uso 1: contexto do playbook.
  const telefone = normalizarTelefone(url.searchParams.get("telefone"));
  if (!telefone) return NextResponse.json({ erro: "telefone ausente" }, { status: 400 });

  const { data: teses } = await admin
    .from("teses")
    .select("id, nome")
    .eq("ativo", true)
    .order("ordem", { ascending: true })
    .order("nome", { ascending: true });
  const listaTeses = (teses as { id: string; nome: string }[]) ?? [];

  const leadId = await acharLeadId(admin, telefone);
  if (!leadId) {
    return NextResponse.json({ encontrado: false, tese_atual: null, playbook: null, teses: listaTeses });
  }

  const { data: lead } = await admin
    .from("leads")
    .select("id, tese_id, teses ( id, nome )")
    .eq("id", leadId)
    .maybeSingle();

  const teseAtualRel = Array.isArray(lead?.teses) ? lead?.teses[0] : lead?.teses;
  const teseAtual = (teseAtualRel as { id: string; nome: string } | null | undefined) ?? null;

  let playbook = null;
  if (lead?.tese_id) {
    const { data: itens } = await admin
      .from("tese_itens")
      .select("secao, titulo, conteudo, ordem")
      .eq("tese_id", lead.tese_id)
      .in("secao", SECOES_CONSULTA)
      .order("secao", { ascending: true })
      .order("ordem", { ascending: true });
    // Devolve sempre a estrutura agrupada (a UI decide como mostrar o vazio).
    playbook = agruparConsulta((itens as any[]) ?? []);
  }

  return NextResponse.json({
    encontrado: true,
    lead_id: leadId,
    tese_atual: teseAtual,
    playbook,
    teses: listaTeses,
  });
}

export async function POST(req: Request) {
  const url = new URL(req.url);
  if (!validarTokenEmbed(process.env.EMBED_HMAC_SECRET, url.searchParams.get("token"))) {
    return NextResponse.json({ erro: "não autorizado" }, { status: 403 });
  }
  const admin = criarClienteAdmin();

  const corpo = await req.json().catch(() => ({}));
  const telefone = normalizarTelefone(corpo?.telefone);
  const teseId = typeof corpo?.tese_id === "string" ? corpo.tese_id : null;
  if (!telefone) return NextResponse.json({ erro: "telefone ausente" }, { status: 400 });
  if (!teseId) return NextResponse.json({ erro: "tese_id ausente" }, { status: 400 });

  // A tese precisa existir e estar ativa (não confiar no cliente).
  const { data: tese } = await admin
    .from("teses")
    .select("id, nome")
    .eq("id", teseId)
    .eq("ativo", true)
    .maybeSingle();
  if (!tese) return NextResponse.json({ erro: "tese inválida" }, { status: 400 });

  const leadId = await acharLeadId(admin, telefone);
  if (!leadId) return NextResponse.json({ erro: "lead não encontrado" }, { status: 404 });

  const { error } = await admin.from("leads").update({ tese_id: teseId }).eq("id", leadId);
  if (error) return NextResponse.json({ erro: error.message }, { status: 500 });

  return NextResponse.json({ ok: true, tese_atual: tese });
}
```

- [ ] **Step 2: Verificar tipos e build**

Run: `npx tsc --noEmit`
Expected: sem erros.

Run: `npm run build`
Expected: build conclui; a rota `/api/embed/consulta` aparece como rota dinâmica.

- [ ] **Step 3: Commit**

```bash
git add app/api/embed/consulta/route.ts
git commit -m "feat(embed): /api/embed/consulta — playbook, busca e setar tese do lead"
```

---

## Task 5: Frontend — gaveta Consulta no painel

**Files:**
- Create: `app/embed/kit/Consulta.tsx`
- Modify: `app/embed/kit/page.tsx` (import + render dentro da lista de gavetas)
- Verify: `npx tsc --noEmit` + `npm run build`

**Interfaces:**
- Consumes: a rota `/api/embed/consulta` (GET contexto, GET `?q=`, POST setar tese).
- Produces: componente `Consulta({ token, telefone }: { token: string; telefone: string })`.

- [ ] **Step 1: Implementar o componente**

Create `app/embed/kit/Consulta.tsx`:

```tsx
"use client";

// Gaveta "Consulta" do Painel do Lead. Mostra o playbook da tese do lead
// (qualificação / objeções / documentos) e uma busca na base de conhecimento —
// tudo dentro do Chatwoot. Se o lead ainda não tem tese, oferece um seletor que
// grava lead.tese_id (única escrita desta gaveta). Lê via /api/embed/consulta.
import { useEffect, useState } from "react";

interface Item { titulo: string | null; conteudo: string }
interface Playbook { qualificacao: Item[]; objecao: Item[]; documento: Item[] }
interface Tese { id: string; nome: string }
interface Contexto {
  encontrado: boolean;
  tese_atual: Tese | null;
  playbook: Playbook | null;
  teses: Tese[];
}
interface Fonte { id: string; titulo: string; tipo: string | null; fonte: string | null }

const ROTULO: Record<keyof Playbook, string> = {
  qualificacao: "Perguntas de qualificação",
  objecao: "Objeções",
  documento: "Documentos",
};

function SecaoPlaybook({ titulo, itens }: { titulo: string; itens: Item[] }) {
  if (itens.length === 0) return null;
  return (
    <div className="mb-2">
      <h3 className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-fg-faint">{titulo}</h3>
      <ul className="space-y-1 text-sm">
        {itens.map((i, n) => (
          <li key={n}>
            {i.titulo && <span className="font-medium">{i.titulo}</span>}
            {i.titulo && <span className="text-fg-dim"> — </span>}
            <span className="text-fg-dim">{i.conteudo}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

export default function Consulta({ token, telefone }: { token: string; telefone: string }) {
  const [ctx, setCtx] = useState<Contexto | null>(null);
  const [salvando, setSalvando] = useState(false);

  const [pergunta, setPergunta] = useState("");
  const [buscando, setBuscando] = useState(false);
  const [resposta, setResposta] = useState<string | null>(null);
  const [fontes, setFontes] = useState<Fonte[]>([]);

  // Carrega o contexto do playbook (tese atual + lista de teses).
  function carregar() {
    fetch(`/api/embed/consulta?telefone=${encodeURIComponent(telefone)}&token=${encodeURIComponent(token)}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => setCtx(d))
      .catch(() => setCtx(null));
  }
  useEffect(() => {
    if (token && telefone) carregar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, telefone]);

  async function escolherTese(teseId: string) {
    if (!teseId) return;
    setSalvando(true);
    try {
      await fetch(`/api/embed/consulta?token=${encodeURIComponent(token)}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ telefone, tese_id: teseId }),
      });
      carregar();
    } finally {
      setSalvando(false);
    }
  }

  async function buscar(e: React.FormEvent) {
    e.preventDefault();
    if (!pergunta.trim()) return;
    setBuscando(true);
    setResposta(null);
    setFontes([]);
    try {
      const r = await fetch(
        `/api/embed/consulta?q=${encodeURIComponent(pergunta.trim())}&token=${encodeURIComponent(token)}`,
      );
      const d = await r.json();
      setResposta(d.resposta ?? d.erro ?? "Sem resposta.");
      setFontes(Array.isArray(d.fontes) ? d.fontes : []);
    } catch {
      setResposta("Falha na busca.");
    } finally {
      setBuscando(false);
    }
  }

  const pb = ctx?.playbook;
  const temItens = pb && pb.qualificacao.length + pb.objecao.length + pb.documento.length > 0;

  return (
    <details className="rounded-marca border border-line/10 bg-panel">
      <summary className="cursor-pointer list-none p-3 text-xs font-semibold uppercase tracking-wide text-fg-dim">
        Consulta
      </summary>
      <div className="space-y-3 px-3 pb-3">
        {/* Playbook da tese */}
        <section>
          {ctx?.tese_atual ? (
            <p className="mb-2 text-xs text-fg-faint">
              Tese: <span className="font-medium text-fg-dim">{ctx.tese_atual.nome}</span>
            </p>
          ) : (
            <div className="mb-2">
              <label className="mb-1 block text-xs text-fg-faint">Defina a tese deste lead:</label>
              <select
                disabled={salvando || !ctx?.teses?.length}
                defaultValue=""
                onChange={(e) => escolherTese(e.target.value)}
                className="w-full rounded-marca border border-line/20 bg-panel2 p-1.5 text-sm"
              >
                <option value="" disabled>
                  {ctx?.teses?.length ? "Escolha uma tese…" : "Sem teses cadastradas"}
                </option>
                {ctx?.teses?.map((t) => (
                  <option key={t.id} value={t.id}>{t.nome}</option>
                ))}
              </select>
            </div>
          )}

          {ctx?.tese_atual && temItens && pb && (
            <>
              <SecaoPlaybook titulo={ROTULO.qualificacao} itens={pb.qualificacao} />
              <SecaoPlaybook titulo={ROTULO.objecao} itens={pb.objecao} />
              <SecaoPlaybook titulo={ROTULO.documento} itens={pb.documento} />
            </>
          )}
          {ctx?.tese_atual && !temItens && (
            <p className="text-sm text-fg-dim">Esta tese ainda não tem playbook cadastrado.</p>
          )}
        </section>

        {/* Busca na base de conhecimento */}
        <section className="border-t border-line/10 pt-2">
          <form onSubmit={buscar} className="flex gap-1">
            <input
              value={pergunta}
              onChange={(e) => setPergunta(e.target.value)}
              placeholder="Buscar na base (B31, NTEP, prescrição…)"
              className="min-w-0 flex-1 rounded-marca border border-line/20 bg-panel2 p-1.5 text-sm"
            />
            <button type="submit" disabled={buscando} className="text-xs text-accent hover:underline">
              {buscando ? "…" : "buscar"}
            </button>
          </form>
          {resposta && (
            <div className="mt-2 text-sm">
              <p className="whitespace-pre-wrap">{resposta}</p>
              {fontes.length > 0 && (
                <p className="mt-1 text-[11px] text-fg-faint">
                  Fontes: {fontes.map((f) => f.titulo).join(" · ")}
                </p>
              )}
            </div>
          )}
        </section>
      </div>
    </details>
  );
}
```

- [ ] **Step 2: Renderizar a gaveta no painel**

Em `app/embed/kit/page.tsx`, adicionar o import junto aos outros imports do topo:

```tsx
import Consulta from "./Consulta";
```

Depois, dentro do `return` de `EmbedLeadPage`, logo ANTES do bloco de gavetas "Notas" (o primeiro `{(dados.notas?.length ?? 0) > 0 && (`), inserir a gaveta de consulta — ela aparece para qualquer lead com token e telefone:

```tsx
      {/* Consulta rápida — playbook da tese + base de conhecimento */}
      {token && telefone && <Consulta token={token} telefone={telefone} />}
```

> Nota: `token` e `telefone` já existem como estado em `page.tsx` (definidos no `useEffect` de inicialização). Use-os diretamente.

- [ ] **Step 3: Verificar tipos e build**

Run: `npx tsc --noEmit`
Expected: sem erros.

Run: `npm run build`
Expected: build conclui sem erro.

- [ ] **Step 4: Conferência por leitura (manual visual fica pro Eduardo)**

Confirmar por leitura do código:
- Lead SEM tese → aparece o `<select>` de teses; escolher dispara POST e recarrega.
- Lead COM tese → mostra nome da tese + seções (qualificação/objeções/documentos) que existirem.
- Busca → digita pergunta, recebe resposta + fontes.
Anotar no relatório: "conferência por leitura; visual no Chatwoot fica pro Eduardo".

- [ ] **Step 5: Commit**

```bash
git add app/embed/kit/Consulta.tsx app/embed/kit/page.tsx
git commit -m "feat(painel-lead): gaveta Consulta (playbook da tese + busca de conhecimento)"
```

---

## Self-Review (feita)

- **Cobertura do spec (Fase 2):** playbook da tese do lead na lateral ✓ (Tasks 1,2,4,5); seções qualificação/objeções/documentos só ✓ (`SECOES_CONSULTA`); busca na base de conhecimento dentro do painel ✓ (Tasks 3,4,5); endpoint embed único HMAC ✓ (Task 4); proxy da busca reusando o orquestrador (DRY) ✓ (Task 3); vínculo tese↔lead em `leads.tese_id` + seletor que grava ✓ (decisão do Eduardo: Tasks 1,4,5).
- **Placeholders:** nenhum — todo passo tem código/comando e saída esperada. (Task 1 é migração SQL: verificação manual explícita, sem teste automatizado — declarado.)
- **Consistência de tipos:** `PlaybookConsulta`/`ItemConsulta`/`SECOES_CONSULTA`/`agruparConsulta` (Task 2) consumidos na rota (Task 4) e refletidos no componente (Task 5, tipos locais espelhados). `FonteBusca`/`buscarConhecimento`/`fontesUnicas` (Task 3) usados nas rotas de sessão e embed. `validarTokenEmbed`/`normalizarTelefone`/`criarClienteAdmin` batem com as assinaturas reais lidas no código.

## Deploy (após todas as tasks, com aprovação do Eduardo)

1. **Migração primeiro:** rodar `supabase/14_tese_lead.sql` no SQL Editor do Supabase (a rota GET de contexto lê `leads.tese_id`; sem a coluna, quebra em runtime).
2. `git push` (após `git fetch` — frente paralela na main).
3. Na VPS: `cd /opt/intranet-ramon && git pull && docker compose up -d --build intranet`.
4. Smoke: `/api/embed/consulta` sem token → 403; com token e `?telefone=` → JSON com `teses`.

## Nota de aprovação

Pela constituição, **quem commita/push/deploya é o Eduardo** (ou Claude com autorização explícita por ocasião, como nas fases anteriores). Os passos de commit ficam à disposição; merge/push/deploy idem.

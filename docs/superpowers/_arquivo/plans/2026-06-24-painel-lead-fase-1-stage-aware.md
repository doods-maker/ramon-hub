# Painel do Lead — Fase 1: Layout stage-aware + enxugar

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o Painel do Lead (`/embed/kit`) mostrar o conteúdo certo conforme a etapa do lead (modo SDR / Closer / encerrado) e recolher histórico/notas/etiquetas em gavetas, em vez de despejar tudo de uma vez.

**Architecture:** A decisão "que blocos aparecem por etapa" vira uma função **pura e testável** (`lib/painel-lead.ts`). A página (`app/embed/kit/page.tsx`) passa a consumir essa função para ordenar/filtrar os blocos do Kit do Closer e move histórico/notas/etiquetas para `<details>` recolhíveis. Nenhuma mudança de dados ou de API.

**Tech Stack:** Next.js 15 (App Router, client component), TypeScript, Tailwind, Vitest (node env, `lib/**/*.test.ts`).

## Global Constraints

- **Idioma de trabalho:** PT-BR em código, comentários e UI (constituição da sede).
- **O painel é só-leitura nesta fase.** Nenhuma ação de escrita, nenhum envio. (Write-back é Fase 3.)
- **Reuso, não reescrita.** Mantém os componentes existentes (`Bloco`, `BotaoCopiar`) e os campos do `KitCloser` (`resumo_leigo`, `roteiro_perguntas`, `documentos`, `venda_objecoes`, `proximo_passo`).
- **Testes puros em `lib/`** (Vitest roda `lib/**/*.test.ts` em ambiente node; nada de import de `@/` com I/O nos testes).
- **Etapas canônicas do funil:** `novo`, `qualificando`, `agendado`, `fechado`, `perdido`.

---

## File Structure

- `lib/painel-lead.ts` — **novo.** Lógica pura: `modoDaEtapa(etapa)` e `blocosKit(modo)`. Sem I/O, sem React.
- `lib/painel-lead.test.ts` — **novo.** Testes Vitest da lógica pura.
- `app/embed/kit/page.tsx` — **modificar.** Consome a lógica; reordena/filtra blocos do Kit; move histórico/notas/etiquetas para gavetas `<details>`.

---

## Task 1: Lógica pura de modo + blocos visíveis

**Files:**
- Create: `lib/painel-lead.ts`
- Test: `lib/painel-lead.test.ts`

**Interfaces:**
- Consumes: nada (módulo folha).
- Produces:
  - `type ModoPainel = "sdr" | "closer" | "encerrado"`
  - `type BlocoKit = "resumo" | "roteiro" | "documentos" | "venda_objecoes" | "proximo_passo"`
  - `modoDaEtapa(etapa: string | null | undefined): ModoPainel`
  - `blocosKit(modo: ModoPainel): BlocoKit[]` — retorna os blocos na **ordem de exibição** do modo.

- [ ] **Step 1: Escrever o teste que falha**

Create `lib/painel-lead.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { modoDaEtapa, blocosKit } from "./painel-lead";

describe("modoDaEtapa", () => {
  it("novo e qualificando (e nulo) => modo sdr", () => {
    expect(modoDaEtapa("novo")).toBe("sdr");
    expect(modoDaEtapa("qualificando")).toBe("sdr");
    expect(modoDaEtapa(null)).toBe("sdr");
    expect(modoDaEtapa(undefined)).toBe("sdr");
  });
  it("agendado => modo closer", () => {
    expect(modoDaEtapa("agendado")).toBe("closer");
  });
  it("fechado e perdido => modo encerrado", () => {
    expect(modoDaEtapa("fechado")).toBe("encerrado");
    expect(modoDaEtapa("perdido")).toBe("encerrado");
  });
});

describe("blocosKit", () => {
  it("sdr mostra só roteiro e próximo passo, nessa ordem", () => {
    expect(blocosKit("sdr")).toEqual(["roteiro", "proximo_passo"]);
  });
  it("closer mostra resumo, venda/objeções, documentos, próximo passo, nessa ordem", () => {
    expect(blocosKit("closer")).toEqual([
      "resumo",
      "venda_objecoes",
      "documentos",
      "proximo_passo",
    ]);
  });
  it("encerrado não mostra blocos do kit", () => {
    expect(blocosKit("encerrado")).toEqual([]);
  });
});
```

- [ ] **Step 2: Rodar o teste e confirmar que falha**

Run: `npx vitest run lib/painel-lead.test.ts`
Expected: FAIL — `Failed to resolve import "./painel-lead"` (o módulo ainda não existe).

- [ ] **Step 3: Implementar o módulo puro**

Create `lib/painel-lead.ts`:

```ts
// Painel do Lead (Dashboard App do Chatwoot): decide o que aparece conforme a
// etapa do lead. Lógica PURA (sem React, sem I/O) para ser testável — a página
// app/embed/kit/page.tsx consome isto para priorizar o conteúdo por momento da
// venda. SDR (qualificando) ≠ Closer (fechando): cada um vê o que importa.

export type ModoPainel = "sdr" | "closer" | "encerrado";
export type BlocoKit = "resumo" | "roteiro" | "documentos" | "venda_objecoes" | "proximo_passo";

// Mapeia a etapa do funil para o modo do painel. Default = sdr (novo/qualificando/sem etapa).
export function modoDaEtapa(etapa: string | null | undefined): ModoPainel {
  switch (etapa) {
    case "agendado":
      return "closer";
    case "fechado":
    case "perdido":
      return "encerrado";
    default:
      return "sdr";
  }
}

// Quais blocos do Kit do Closer aparecem — e em que ordem — para cada modo.
export function blocosKit(modo: ModoPainel): BlocoKit[] {
  switch (modo) {
    case "sdr":
      return ["roteiro", "proximo_passo"];
    case "closer":
      return ["resumo", "venda_objecoes", "documentos", "proximo_passo"];
    case "encerrado":
      return [];
  }
}
```

- [ ] **Step 4: Rodar o teste e confirmar que passa**

Run: `npx vitest run lib/painel-lead.test.ts`
Expected: PASS — 6 testes verdes.

- [ ] **Step 5: Commit**

```bash
git add lib/painel-lead.ts lib/painel-lead.test.ts
git commit -m "feat(painel-lead): lógica pura de modo stage-aware (sdr/closer/encerrado)"
```

---

## Task 2: Página consome o modo e recolhe gavetas

**Files:**
- Modify: `app/embed/kit/page.tsx` (imports no topo; novo componente `Gaveta`; substituir o `return (...)` principal, hoje ~linhas 174–293)
- Verify: `npx tsc --noEmit` + `npm run build`

**Interfaces:**
- Consumes (da Task 1): `modoDaEtapa`, `blocosKit`, tipos `ModoPainel`/`BlocoKit`.
- Produces: nenhuma API nova (refactor de apresentação).

- [ ] **Step 1: Adicionar o import da Task 1**

Em `app/embed/kit/page.tsx`, logo após o import do tipo `KitCloser` (linha ~9), adicionar:

```tsx
import type { KitCloser } from "@/lib/kit-closer";
import { modoDaEtapa, blocosKit, type BlocoKit } from "@/lib/painel-lead";
```

- [ ] **Step 2: Adicionar o componente `Gaveta` (bloco recolhível)**

Logo após o componente `Bloco` (hoje termina na linha ~100), adicionar:

```tsx
// Bloco recolhível (histórico/notas/etiquetas ficam fora da primeira dobra).
function Gaveta({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <details className="rounded-marca border border-line/10 bg-panel">
      <summary className="cursor-pointer list-none p-3 text-xs font-semibold uppercase tracking-wide text-fg-dim">
        {titulo}
      </summary>
      <div className="px-3 pb-3">{children}</div>
    </details>
  );
}
```

- [ ] **Step 3: Adicionar o renderizador de bloco do Kit por chave**

Logo após o componente `Gaveta`, adicionar a função que devolve o JSX de cada bloco do Kit pela chave (reusa o componente `Bloco`):

```tsx
// Renderiza um bloco do Kit pela chave canônica (ver lib/painel-lead). Devolve
// null se o kit não tiver o conteúdo. A ORDEM e QUAIS blocos vêm de blocosKit(modo).
function renderBlocoKit(chave: BlocoKit, kit: KitCloser): React.ReactNode {
  switch (chave) {
    case "resumo":
      return (
        <Bloco key="resumo" titulo="Resumo + veredito" copiar={kit.resumo_leigo}>
          <p className="whitespace-pre-wrap text-sm">{kit.resumo_leigo}</p>
        </Bloco>
      );
    case "roteiro":
      return (
        <Bloco key="roteiro" titulo="Roteiro de perguntas" copiar={kit.roteiro_perguntas.join("\n")}>
          <ol className="list-decimal space-y-1 pl-5 text-sm">
            {kit.roteiro_perguntas.map((p, i) => (
              <li key={i}>{p}</li>
            ))}
          </ol>
        </Bloco>
      );
    case "documentos":
      return (
        <Bloco
          key="documentos"
          titulo="Documentos a pedir"
          copiar={kit.documentos.map((d) => `• ${d.documento} — ${d.porque}`).join("\n")}
        >
          <ul className="space-y-1 text-sm">
            {kit.documentos.map((d, i) => (
              <li key={i}>
                <span className="font-medium">{d.documento}</span>
                <span className="text-fg-dim"> — {d.porque}</span>
              </li>
            ))}
          </ul>
        </Bloco>
      );
    case "venda_objecoes":
      return (
        <Bloco key="venda_objecoes" titulo="Como vender + objeções" copiar={kit.venda_objecoes.pitch}>
          <p className="mb-2 whitespace-pre-wrap text-sm">{kit.venda_objecoes.pitch}</p>
          <div className="space-y-2">
            {kit.venda_objecoes.objecoes.map((o, i) => (
              <div key={i} className="rounded-marca bg-panel2 p-2 text-sm">
                <p className="font-medium">&quot;{o.objecao}&quot;</p>
                <p className="text-fg-dim">{o.resposta}</p>
              </div>
            ))}
          </div>
        </Bloco>
      );
    case "proximo_passo":
      return (
        <Bloco key="proximo_passo" titulo="Próximo passo" copiar={kit.proximo_passo}>
          <p className="whitespace-pre-wrap text-sm">{kit.proximo_passo}</p>
        </Bloco>
      );
  }
}
```

- [ ] **Step 4: Substituir o `return (...)` principal pelo layout stage-aware**

No componente `EmbedLeadPage`, logo após a linha `const linkCaso = ...` (hoje ~linha 172), inserir o cálculo do modo:

```tsx
  const lead = dados.lead;
  const kit = dados.kit;
  const linkCaso = dados.caso_id ? `${APP_BASE}/pra-fechar/${dados.caso_id}` : `${APP_BASE}/funil`;
  const modo = modoDaEtapa(lead?.etapa);
  const blocos = blocosKit(modo);
```

Em seguida, substituir TODO o `return ( ... )` atual (do `<div className="space-y-3">` até o fechamento, hoje ~linhas 174–293) por:

```tsx
  return (
    <div className="space-y-3">
      {/* Cabeçalho do lead — sempre visível */}
      <header className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-fg">{dados.cliente_nome ?? lead?.nome ?? "Lead"}</p>
          <p className="text-xs text-fg-dim">
            {cap(lead?.etapa)}
            {dados.viabilidade ? ` · viab. ${dados.viabilidade}` : ""}
            {moeda(lead?.valor_estimado) ? ` · ${moeda(lead?.valor_estimado)}` : ""}
          </p>
          <p className="text-[11px] text-fg-faint">
            {lead?.origem ?? "origem ?"}
            {lead?.campanha ? ` · ${lead.campanha}` : ""}
            {lead?.criado_em ? ` · desde ${dataCurta(lead.criado_em)}` : ""}
          </p>
        </div>
        <a href={linkCaso} target="_blank" rel="noreferrer" className="shrink-0 text-xs text-accent hover:underline">
          abrir ↗
        </a>
      </header>

      {/* Blocos do Kit — quais e em que ordem dependem do modo (sdr/closer/encerrado) */}
      {kit
        ? blocos.map((chave) => renderBlocoKit(chave, kit))
        : modo !== "encerrado" && (
            <p className="text-sm text-fg-dim">
              {dados.kit_status === "erro"
                ? "A geração do kit falhou. Reprocesse em 'Pra fechar' na intranet."
                : "Kit ainda não gerado para este lead (rode a triagem)."}
            </p>
          )}

      {/* Gavetas — fora da primeira dobra */}
      {(dados.notas?.length ?? 0) > 0 && (
        <Gaveta titulo="Notas">
          <ul className="space-y-2">
            {dados.notas!.map((n, i) => (
              <li key={i} className="text-sm">
                <p className="whitespace-pre-wrap">{n.conteudo}</p>
                <p className="text-[11px] text-fg-faint">
                  {n.autor ?? "—"} · {dataCurta(n.criado_em)}
                </p>
              </li>
            ))}
          </ul>
        </Gaveta>
      )}

      {(dados.etiquetas?.length ?? 0) > 0 && (
        <Gaveta titulo="Etiquetas">
          <div className="flex flex-wrap gap-1">
            {dados.etiquetas!.map((e) => (
              <span
                key={e.id}
                className="rounded-full px-2 py-0.5 text-[11px] font-medium"
                style={{ backgroundColor: `${e.cor}22`, color: e.cor }}
              >
                {e.nome}
              </span>
            ))}
          </div>
        </Gaveta>
      )}

      {(dados.historico?.length ?? 0) > 0 && (
        <Gaveta titulo="Histórico de etapas">
          <ol className="space-y-1 text-sm">
            {dados.historico!.map((h, i) => (
              <li key={i} className="flex items-center justify-between gap-2">
                <span>
                  {h.de_etapa ? `${cap(h.de_etapa)} → ` : ""}
                  <span className="font-medium">{cap(h.para_etapa)}</span>
                </span>
                <span className="shrink-0 text-[11px] text-fg-faint">{dataCurta(h.mudou_em)}</span>
              </li>
            ))}
          </ol>
        </Gaveta>
      )}
    </div>
  );
```

- [ ] **Step 5: Verificar tipos e build**

Run: `npx tsc --noEmit`
Expected: sem erros.

Run: `npm run build`
Expected: build conclui sem erro (a rota `/embed/kit` compila).

- [ ] **Step 6: Conferência visual rápida (manual)**

Rodar `npm run dev` e abrir as três variações via querystring `?telefone=` (o painel aceita telefone na URL p/ teste fora do Chatwoot — ver `page.tsx` linha ~113), com um token válido:
- Lead em `qualificando` → vê **roteiro** + **próximo passo**; **não** vê pitch/objeções/documentos; notas/etiquetas/histórico recolhidos.
- Lead em `agendado` → vê **resumo**, **pitch+objeções**, **documentos**, **próximo passo**.
- Lead em `fechado`/`perdido` → vê só cabeçalho + gavetas (sem blocos do kit).

Expected: cada etapa mostra o conjunto certo. (Conferência humana; sem assert automatizado porque o JSX do iframe não tem teste de componente neste projeto.)

- [ ] **Step 7: Commit**

```bash
git add app/embed/kit/page.tsx
git commit -m "feat(painel-lead): layout stage-aware + gavetas recolhíveis"
```

---

## Self-Review (feita)

- **Cobertura do spec (Fase 1):** modo por etapa (Task 1) ✓; SDR esconde material de fechamento e Closer mostra tudo (Task 1 `blocosKit` + Task 2 render) ✓; `fechado`/`perdido` = modo enxuto só com cabeçalho+gavetas (Task 1 `encerrado` + Task 2) ✓; histórico/notas/etiquetas em gavetas recolhidas (Task 2 `Gaveta`) ✓; sem mudança de dados/API ✓.
- **Placeholders:** nenhum — todo passo tem código/comando concreto e saída esperada.
- **Consistência de tipos:** `ModoPainel`/`BlocoKit`/`modoDaEtapa`/`blocosKit` definidos na Task 1 e consumidos com os mesmos nomes na Task 2; campos do `KitCloser` batem com `lib/kit-closer.ts` (`resumo_leigo`, `roteiro_perguntas`, `documentos`, `venda_objecoes.{pitch,objecoes}`, `proximo_passo`).

## Nota de aprovação

Pela constituição (`comercial/CLAUDE.md` §3), **quem commita é o Eduardo**. Os passos de commit acima ficam à disposição dele; o executor (humano ou agente) deve parar e pedir o "pode commitar" se não for o próprio Eduardo rodando.

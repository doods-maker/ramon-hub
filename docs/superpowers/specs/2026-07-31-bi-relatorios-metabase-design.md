# BI "Relatórios" — Metabase dentro do hub (design)

**Data:** 2026-07-31 · **Aprovado por:** Eduardo (na conversa, 31/07)
**Decisão de caminho:** hub = operação do dia (Cockpit/TV/Esteira intocados); Metabase = análise e tendência, embutido no hub. Migração das telas do hub pro Metabase foi **descartada** (telas são interativas; Metabase só faz gráfico; queries soltas quebram em silêncio — visto no Placar do Dono em 20/07).

## Contexto

- Metabase OSS no ar desde 14/07 em `bi.ramonantonio.adv.br` (container na VPS, user `metabase_ro` com `pg_read_all_data` no PG do hub). Creds: `conhecimento\metabase-credenciais.txt` (API key admin incluída).
- Conteúdo atual: dashboard **Placar do Dono** (id 2, 8 cartões) + coleção sample **Examples** (46 cartões). Último acesso: 14/07 — ninguém usa.
- **Defeito ativo:** nenhuma query filtra `source <> 'calculo-advbox'` → desde 20/07 os casos de cálculo ocultos poluem leads/valor/funil.

## Escopo

### 1. Faxina e correção (só Metabase, via API, sem código)

- Apagar (archive) a coleção Examples e o dashboard "E-commerce Insights".
- Corrigir as 8 queries do Placar do Dono: `AND l.source IS DISTINCT FROM 'calculo-advbox'` (mesma semântica do scope `Lead.funil`).
- Placar do Dono continua como visão rápida; não é substituído.

### 2. Dashboard novo "Análise Comercial" (Metabase, via API)

4 blocos, ~13 cartões, todos com o filtro de casos de cálculo. **Sem filtro global de período** (ajuste pós-exploração 31/07: cada cartão tem semântica de data própria — criação × fechamento × perda — então cada um usa janela fixa declarada no título, 12 meses nas tendências; filtro global fica como evolução se fizer falta):

| Bloco | Cartões |
|---|---|
| Tendência | Leads novos/mês · contratos fechados/mês · valor fechado/mês · taxa de conversão/mês · tempo médio lead→contrato |
| Funil profundo | Tempo médio por etapa · conversão etapa→etapa · ranking de motivos de perda |
| Origem e tese | Conversão e valor por canal (source) · por tese · por campanha (UTM) |
| Atendimento e agenda | SLA 1ª resposta histórico · reuniões marcadas × realizadas · follow-ups × contratos |

**NPS caiu do escopo** (ajuste pós-exploração 31/07): o banco só grava *quando o NPS foi pedido* (`custom_attributes.nps.pedido_em`) — o score respondido não é persistido em lugar nenhum. Cartão de NPS só quando existir dado estruturado.

**Ressalva declarada:** "tempo por etapa" e "conversão etapa→etapa" dependem do histórico de mudança de etapa na timeline do lead (atividades). Validar granularidade na implementação; se não bastar, entregar a melhor aproximação e avisar o Eduardo qual foi.

Fontes de dado já existentes no banco: `leads` (etapa/valor/tese/source/won_at), `lead_stages`, atividades do lead, `conversations` (SLA/first reply), contatos com UTM (PR #34), `lost_reason` obrigatório (PR #94/#96), contador de follow-up (PR #94), NPS em `custom_attributes` (PR #94). ROI de ads está **fora** (custo vive no Gerenciador da Meta; segue na skill comercial-analise-ads).

### 3. Página "Relatórios" no hub (código no fork)

- Item **Relatórios** no menu da Intranet, **admin-only** (padrão `useAdmin` existente; sidebar já filtra admin-only).
- Página Vue = iframe do dashboard via **static embedding** do Metabase OSS (gratuito): endpoint Rails admin-only gera JWT (HS256, secret compartilhado, exp curto) e devolve a URL embed; iframe carrega sem login no Metabase.
- Envs novos na VPS (`chatwoot.env`, com backup e OK do Eduardo na hora): `RAMON_METABASE_EMBED_SECRET` + `RAMON_METABASE_URL`. Env ausente → página mostra aviso amigável, nada quebra.
- No Metabase: ligar embedding, habilitar o dashboard pra embed (via API), gerar o secret.

### 4. Validação

- Specs: endpoint nega não-admin; JWT assinado com payload certo; env ausente → resposta de "não configurado". Vitest da página (estados configurado/não configurado).
- Smoke técnico: menu como admin → dashboard carrega dentro do hub; "Leads abertos" do Placar == total do Kanban.
- Roteiro de smoke do Eduardo em `comercial\docs\` (doc de smokes de sempre).

## Fora de escopo

- Migrar Cockpit/TV/Esteira pro Metabase (descartado).
- ROI de ads no Metabase (custo não está no banco).
- Acesso da equipe (menu é admin-only; abrir depois é 1 linha).
- Tema bronze no iframe (embed aceita só light/night; usar o que menos briga com o dark do hub).

## Manutenção (regra nova)

Queries do Metabase leem o banco cru: mudança de regra de negócio em `Lead` (novo source oculto, mudança de semântica de etapa) exige revisar as queries. Registrar essa regra no doc de smokes/decisões e na memória da sessão.

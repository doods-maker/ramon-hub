# Área Marketing no hub — tráfego, custos e metas

Desenho fechado com o Eduardo em 07/11/2026 (grill Q1–Q17). Objetivo: bater o
gasto em tráfego e os custos de marketing com os números do hub (leads, reuniões,
contratos, honorário), com a infra pronta agora e a Meta ligada **só no fim, com o
Tech Provider**.

## Decisões

| # | Decisão |
|---|---|
| Lugar | Grupo "Conteúdo" do menu (GESTÃO) vira **Marketing**, só admin, abas **Conteúdo · Tráfego · Custos e metas**. |
| Números | No **Metabase** (já é o painel de tudo). Aba Tráfego embute o painel por iframe, igual Relatórios. O hub só faz o que o Metabase não faz: **escrever**. |
| Fontes de custo | Meta automático (`ramon_meta_gastos`, cron já existe) + **lançamento manual** (data, valor, categoria, tese opcional, observação). Sem recorrência. Google Ads fora. |
| Ponte | **CSV do Gerenciador** grava na mesma tabela do gasto (`origem = 'csv'`); a API depois sobrescreve o mesmo anúncio/dia. |
| Conferências | (1) Meta × hub em leads; (2) custo descendo o funil por tese e campanha; (3) retorno = gasto × honorário. |
| CAC | **Mídia** (só anúncio) e **completo** (mídia + todos os lançamentos, inclusive "equipe"). |
| Rateio | Custo sem tese é rateado entre as teses pela proporção de leads do mês. |
| Atribuição | Último clique (já é assim). LP: parâmetros de URL dinâmicos na Meta, `utm_source=meta&utm_campaign={{campaign.id}}&utm_content={{ad.id}}`; `bi_leads` lê `utm_content` como ad_id só se `utm_source='meta'` e numérico. Sem fbclid. |
| Peças | Alcance, salvamentos, compartilhamentos, curtidas e comentários por peça publicada; puxador desligado. |
| Metas | Fonte única = `modelo.mjs`. O `mensal.json` do `exportar-painel.mjs` é subido na aba e **substitui todas** as metas. Métricas: contratos, agendadas, realizadas, anúncio, custo da área, CAC. Mensal, total, sem tese. |
| Ligar | `RAMON_META_GASTO` e `RAMON_IG_INSIGHTS` ficam `off` até o Tech Provider. |

## Dados (PR 1)

- `ramon_meta_gastos` += `adset_id`, `adset_name`, `objetivo`, `conversas`
  (ação `onsite_conversion.messaging_conversation_started_7d`), `leads_meta`
  (ação `lead`), `origem` (`api` | `csv`).
- `ramon_marketing_custos`: `account_id`, `data`, `valor`, `categoria`
  (impulsionamento, criativo, ferramenta, agencia, equipe, outro), `thesis_id`
  (opcional), `observacao`, `user_id`.
- `ramon_marketing_metas`: `account_id`, `mes` (dia 1), `metrica`, `valor`;
  único por conta+mês+métrica.
- `ramon_pecas` += `alcance`, `salvamentos`, `compartilhamentos`, `curtidas`,
  `comentarios`, `metricas_em`.
- Serviços: `Ramon::MetaGastoCsv` (CSV pt-BR ou inglês, `,` ou `;`, decimal com
  vírgula ou ponto; exige Dia, ID do anúncio e Valor usado; soma linhas repetidas do
  mesmo anúncio+dia; nunca sobrescreve o que veio da API) e `Ramon::MetasDoModelo`
  (lê o `mensal.json`).
- Jobs: `Ramon::MetaGastoJob` passa a gravar conjunto, objetivo e resultados;
  `Ramon::PecaMetricasJob` (diário, `RAMON_IG_INSIGHTS`, peças publicadas nos
  últimos 60 dias).
- Views: `bi_leads` v03 (ad_id pelo utm), `bi_meta_gastos` v02, novas
  `bi_marketing_custos`, `bi_marketing_metas`, `bi_pecas`.

## Tela (PR 2)

- `navIntranet.js`: grupo `conteudo` vira `marketing` com 3 abas admin-only.
- Tráfego: iframe do Metabase (dashboard próprio, `RAMON_METABASE_MARKETING_ID`).
- Custos e metas: lista + formulário de lançamento, importar CSV, subir
  `mensal.json`, quadro de status (chaves ligadas/desligadas, conta de anúncios
  configurada, último gasto gravado e de onde veio, última métrica de peça).

## Metabase e doc (PR 3)

- Script de cartões: Meta × hub por campanha/dia; custo por lead → qualificado →
  reunião → contrato por tese e por campanha (contratos = fechados no mês, igual em
  todos os cartões); retorno (gasto × honorário); CAC mídia
  e completo; realizado × meta mês a mês e acumulado; peças × alcance × leads do
  Instagram na semana.
- Doc do padrão de parâmetros de URL e de como exportar o CSV (nível anúncio,
  detalhamento por Dia, colunas de ID).

## Fora

Google Ads automático; CAPI de site (fbclid/_fbc); meta por tese; recorrência de
custo; tela nativa de números.

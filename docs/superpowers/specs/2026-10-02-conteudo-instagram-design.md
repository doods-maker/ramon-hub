# Conteúdo do Instagram dentro do hub — pauta → aprovação → montagem → agenda → publicação

**Data:** 02/10/2026 · **Status:** APROVADA pelo Eduardo em 02/10/2026
**Repos:** `ramon-hub` (tela, API, publicação) + `motor-marketing` (worker de montagem)

## 1. Objetivo

O Eduardo hoje aprova pauta e peça no kanban "Peças" do Notion, a montagem roda no PC dele e a
publicação é um comando local (`publicar-ig.mjs`). O objetivo é fazer **o ciclo inteiro dentro do
hub**: a pauta pesquisada pela rotina cloud cai no hub, ele aprova, vê a peça montada, agenda (ou
publica na hora) e ela sai sozinha no Instagram — de qualquer aparelho, sem PC ligado.

**Sucesso =** uma peça da rodada cloud percorre rascunho → publicado sem nenhum comando local, e o
post sai no horário agendado com legenda e slides corretos.

## 2. Decisões tomadas (02/10, com o Eduardo)

| Tema | Decisão | Por quê |
|---|---|---|
| App Review | **NÃO** pedir `instagram_business_content_publish` na submissão do Tech Provider | Publicar na conta da própria banca funciona com acesso padrão (provado 22/09 em modo dev). Pedir a mais só aumenta o risco de rejeição da submissão que importa (coexistência). Roteiro Bloco G mantido. |
| Onde monta | **Worker na VPS, sem Claude** | `build.mjs` é determinístico (Gemini por API + Playwright + sharp). VPS: 6 vCPU, 11 GB, ~5 GB livres, carga ~0 (medido 02/10). Claude da VPS fica só no papel de 17/08 (`@claude`). |
| Notion | **Espelhar durante a transição** | Hub é a fonte da verdade; Notion recebe só status, desligável por env. |
| Formatos v1 | **Carrossel + estático** | Reels dependem de gravação/edição — fatia futura. |
| Agenda | **Sugestão da grade + data/hora editável** | |
| Grade | **ter, qua, qui às 12h00 (BRT)** | O time inteiro reposta na hora do almoço (pedido Eduardo). Estudos 2025–26 (Sprout, Buffer, Hootsuite) também apontam qua 12–13h e, no recorte saúde, ter–qui 11–13h. Dados próprios (54 posts/2026) não mostram efeito de horário, só de formato. |
| Prévia | **No próprio hub, como post do IG** | Aprovar sem abrir o Drive (§4.4.1). |
| Drive | **Mantém cópia como acervo** | Pasta `Posts Instagram\<Carrossel|Estático>\<data — título>` como hoje — só arquivo, não etapa de revisão. |
| "Pode postar" | **Clicar "Aprovar e agendar" ou "Publicar agora" É o pode postar** | Princípio de aprovação preservado: nada publica sem ação explícita do Eduardo. |

Dado lateral (pra decisão de pauta, não desta spec): alcance mediano 2026 — estático 89 ·
carrossel 611 · reel 972.

## 3. Fluxo

```
rotina cloud (seg/qua/sex) ──POST /pecas──────────────► hub  [rascunho]
                                                        Eduardo: Aprovar / Reprovar
                                                              ▼
conteudo-worker (VPS) ◄──POST /pecas/proxima─────────── [aprovado] → [montando]
  build.mjs / build-static.mjs → PNG → JPEG
  grava em ./ig-media/<slug>/
  ──PATCH /pecas/:id/montada──────────────────────────► [montado]  (prévia + Drive)
                                                        Eduardo: Aprovar e agendar / Publicar agora
                                                              ▼
Ramon::PublicarPecasJob (cron 1 min) ◄──────────────── [agendado]
  contêineres Graph → espera FINISHED → media_publish ─► [publicado] + permalink
Ramon::NotionEspelho ── a cada transição ──► Notion "Peças" (até desligar)
```

**Status:** `rascunho → aprovado → montando → montado → agendado → publicando → publicado`;
laterais: `reprovado` (fim), `falhou` (publicação; botão "Tentar de novo" volta a `agendado` pra
agora). Falha de **montagem** volta a peça para `rascunho` com `erro` preenchido (Eduardo
re-aprova = nova tentativa).

## 4. Hub (`ramon-hub`)

### 4.1 Dados — tabela `ramon_pecas`

| coluna | tipo | nota |
|---|---|---|
| account_id | bigint | conta 2 |
| slug | string, **único** por conta | chave vinda da rodada (`NN-slug`) |
| rodada | date | data da rodada cloud |
| tipo | string | `carrossel` \| `estatico` |
| estilo, tese, gancho | string | exibição/filtro |
| conteudo | jsonb | `carousel.json`/`static.json` inteiro (fonte do build) |
| legenda | text | inicia com `conteudo.legenda` + hashtags; **editável** em `montado` |
| status | string (enum Rails) | ver §3 |
| imagens | jsonb (array de URLs) | `https://chat.ramonantonio.adv.br/ig-media/<slug>/slide-NN.jpg` |
| refazer_cards | integer[] | cards cuja imagem o worker deve regenerar |
| agendado_para | datetime | |
| montagem_iniciada_em | datetime | aviso "travou" se > 15 min em `montando` |
| ig_media_id, permalink | string | gravados no instante do publish |
| erro | text | última falha (montagem ou Meta) |
| nota_reprovacao | text | |
| notion_page_id | string | vem da rotina; espelho |
| drive_pasta_id | string | idempotência do acervo |

Migração exige `db:migrate` à mão no deploy (lição do hub).

### 4.2 API pública (rotina + worker) — `Public::Api::V1::ConteudoController`

Mesmo padrão do `AgenteController`: token em `RAMON_CONTEUDO_TOKEN` (query/header, mascarado em
`filter_parameters`), conta fixa.

- `POST pecas` — cria `rascunho`. Slug repetido → 200 com a existente (idempotente, a rotina pode
  re-rodar).
- `POST pecas/proxima` — devolve **uma** peça `aprovado` (ou `montado` com `refazer_cards`
  não vazio), trocando atomicamente pra `montando` (`UPDATE … WHERE status=… RETURNING` /
  `lock`). Sem peça → 204.
- `PATCH pecas/:id/montada` — `{imagens: [...]}` → `montado`, zera `refazer_cards`, enfileira
  acervo no Drive.
- `PATCH pecas/:id/falha` — `{erro}` → volta pra `rascunho` (ou `montado`, se era refação).

### 4.3 API interna (tela) — `Api::V1::Accounts::RamonConteudoController`

`index` (por status) · `show` · `aprovar` · `reprovar(nota)` · `atualizar_legenda` ·
`refazer(cards[])` · `agendar(agendado_para)` · `publicar_agora` · `cancelar_agendamento` ·
`tentar_de_novo`. Só administradores. Cada ação valida a transição de origem (409 se o status
mudou por baixo).

### 4.4 Tela "Conteúdo" (`routes/dashboard/ramon/pages/Conteudo.vue`)

Kanban com 5 colunas: **Pauta · Montando · Prontas · Agendadas · Publicadas** (+ `falhou` aparece
em Agendadas com selo vermelho). Card: gancho, tipo, tese, estilo, capa (quando houver), selo de
erro. Painel lateral por etapa:

| Etapa | Mostra | Botões |
|---|---|---|
| Pauta | texto dos cards (renderizado de `conteudo`), legenda, hashtags, erro anterior | Aprovar · Reprovar (nota) |
| Montando | início, aviso se > 15 min | — |
| Pronta | **prévia como post do IG** (§4.4.1), legenda editável ao lado | Refazer imagem do card N · Aprovar e agendar (data/hora pré-preenchida pela grade) · Publicar agora |
| Agendada | data/hora | Cancelar agendamento · Publicar agora |
| Falhou | mensagem da Meta | Tentar de novo |
| Publicada | permalink | — |

Fora da v1: editar o texto da arte pelo hub (reprova com nota → nova rodada).

#### 4.4.1 Prévia como post do Instagram (pedido Eduardo 02/10)

A aprovação acontece **olhando a prévia no hub** — o Drive vira só acervo, ninguém precisa
abri-lo. A prévia imita o post no feed: cabeçalho com monograma + `ramonantonioadvogados`,
imagem 4:5 com setas e bolinhas de posição (carrossel) ou imagem única (estático), e a legenda
embaixo truncada com "mais" (mesmo corte do app), atualizando ao vivo enquanto a legenda é
editada. Clicar na imagem abre em tamanho cheio. As imagens vêm direto de `imagens` (ig-media),
sem passar pelo Drive. Só Tailwind, sem lib de carrossel.

### 4.5 Grade — `Ramon::GradeConteudo`

```ruby
SLOTS = [[2, 12, 0], [3, 12, 0], [4, 12, 0]] # ponytail: ter/qua/qui 12h BRT; trocar aqui
```
`proximo_horario(agora)` = primeiro slot futuro sem peça `agendado`/`publicando`/`publicado`
naquela data-hora.

### 4.6 Publicação — `Ramon::PublicarPecasJob` + `Ramon::InstagramPublisher`

- Cron `* * * * *` em `config/schedule.yml`. Busca `agendado` com `agendado_para <= now`; por
  peça, `with_lock` troca pra `publicando` (só um processo avança).
- Carrossel: 1 contêiner `is_carousel_item` por JPEG → contêiner `CAROUSEL` com `caption` →
  espera `status_code=FINISHED` (poll até ~5 min) → `media_publish` → grava `ig_media_id` e
  busca `permalink` → `publicado` → Notion + push ntfy "publicado".
  Estático: contêiner único `image_url`.
- **Só feed, sem Stories** (decisão Eduardo 02/10: a arte 4:5 fica errada no formato do story).
- **Colaborador (regra 22/09):** mesmo casamento do `colaboradores(caption)` do `publicar-ig.mjs`
  — nome do crédito na legenda → @ da pessoa (mapa de `brand.json identidades`, copiado como
  constante no hub) → `collaborators` (até 3) na criação do contêiner.
- Host `graph.instagram.com/v26.0`, ig user da conta `@ramonantonioadvogados`.
- **Sem retry automático.** Qualquer erro → `falhou` + `erro` + push ntfy. Se `ig_media_id` já
  estiver gravado, o job nunca publica de novo. Peça presa em `publicando` > 15 min (processo
  morreu entre `media_publish` e o save) vira `falhou` com "conferir no Instagram antes de tentar
  de novo".
- Token: `RAMON_IG_PUBLISH_TOKEN` em `InstallationConfig` (super admin). `Ramon::IgTokenRefreshJob`
  semanal chama `refresh_access_token` e regrava; falha → push ntfy.

### 4.7 Espelho Notion — `Ramon::NotionEspelho`

`PATCH /v1/pages/:notion_page_id` com `Status` mapeado: rascunho→rascunho, aprovado/montando→
aprovado, montado/agendado→montado, publicado→publicado; demais = não mexe. No-op se
`RAMON_NOTION_TOKEN` ausente ou `notion_page_id` vazio; erro só loga (nunca bloqueia o fluxo).

### 4.8 Acervo Drive — `Ramon::ConteudoDriveJob`

Em `montado`: `Ramon::DriveClient.ensure_folder` de `<tipo>` e `<rodada — capa_titulo>` sob
`RAMON_DRIVE_POSTS_ID`, sobe os JPEGs + `legenda.txt`; guarda `drive_pasta_id` (re-upload só em
refação). ⚠️ O hub usa **service account** — sem cota em "Meu Drive". Se a pasta atual
`Posts Instagram` (no Meu Drive do Eduardo) recusar upload, o acervo passa a viver numa pasta
dentro do drive compartilhado que o hub já usa. Validar no PR 2.

## 5. Worker (`motor-marketing`)

- `lib/worker-hub.mjs`: loop a cada 30 s → `POST /pecas/proxima` → escreve `conteudo` em
  `/data/pecas/<slug>/carousel.json|static.json` (diretório persistente: reaproveita `img/` entre
  refações; para `refazer_cards` apaga só `img/slide-NN.png`) → `buildCarousel`/`buildStatic` →
  PNG→JPEG (mesma conversão do `publicar-ig.mjs`, extraída pra função compartilhada) →
  `/ig-media/<slug>/slide-NN.jpg` → `PATCH montada`. Exceção → `PATCH falha`. Uma peça por vez.
- Deploy no padrão do motor de cálculos: `git archive` do `main` → `/opt/conteudo-worker`,
  `Dockerfile` `FROM mcr.microsoft.com/playwright:<versão do package.json>` + `npm ci`.
  Serviço no `docker-compose.override.yml` da VPS: `build: /opt/conteudo-worker`,
  `mem_limit: 1536m`, `cpus: 1`, volumes `./ig-media:/ig-media` (rw) + `conteudo_data:/data`,
  env `GOOGLE_API_KEY`, `HUB_URL=http://chatwoot-web:3000`, `RAMON_CONTEUDO_TOKEN`.
- O worker **não** fala com Notion nem com o Instagram.

## 6. Rotina cloud (`trig_01Ls2UxuVTv2aQQXDCXLhrYQ`)

Passo 4: além do card no Notion, `POST pecas` no hub com `{slug, rodada, tipo, estilo, tese,
gancho, conteudo, notion_page_id}`. Token nas **variáveis do ambiente cloud**, nunca no texto do
prompt. Ajuste só depois do PR 1 no ar.

## 7. Testes

- **RSpec:** transições válidas/inválidas do model; `ConteudoController` (token, idempotência do
  POST, `proxima` entrega a mesma peça uma vez só); `GradeConteudo` (pula slot ocupado, vira a
  semana); `InstagramPublisher` com WebMock (carrossel feliz, erro da Meta → `falhou`,
  `ig_media_id` presente → não publica; crédito na legenda → `collaborators`); `NotionEspelho` no-op sem token.
- **node --test** (motor): `worker-hub` com hub falso em `node:http` — pega peça, builda em mock,
  manda `montada`; build lançando erro → manda `falha`.
- **Smoke real** (roteiro em bloco por seção, pro Eduardo): uma peça da rodada → aprovar → ver
  prévia → agendar pra +5 min → post no IG + Notion `publicado` + pasta no Drive.

## 8. Entrega — 3 PRs, cada um útil sozinho

1. **Pauta no hub:** migração, model, API pública (`POST pecas`), tela com Pauta/Aprovar/Reprovar,
   espelho Notion. → depois ajustar a rotina cloud.
2. **Montagem:** `proxima`/`montada`/`falha`, worker + Dockerfile + serviço na VPS, prévia,
   legenda editável, refazer card, acervo Drive.
3. **Publicação:** grade, agendar/publicar agora/cancelar, job de publicação, refresh do token.

## 9. Gates do Eduardo

- `db:migrate` + deploy de cada PR (via `!`, push barrado pro Claude).
- Gerar `RAMON_CONTEUDO_TOKEN` e pôr no `chatwoot.env` + env do worker + ambiente da rotina cloud.
- `GOOGLE_API_KEY` no env do worker.
- Token do Instagram (painel Meta → produto Instagram → Gerar token) no super admin.
- Compartilhar a pasta de acervo com a service account (ou aceitar pasta no drive compartilhado).
- Deploy key/acesso do `motor-marketing` na VPS (ou `git archive` feito do PC, como o motor de cálculos).
- Smoke final + primeiro "Aprovar e agendar" real.

## 10. Fora de escopo

Reels/vídeo · editar texto da arte · métricas de alcance no hub · `content_publish` no App Review ·
aposentar o Notion (decisão posterior do Eduardo).

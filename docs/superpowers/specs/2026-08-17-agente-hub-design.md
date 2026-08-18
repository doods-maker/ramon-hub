# Agente do hub ("advogado sênior on-call") + seletor de modelo ZapSign — design

**Data:** 17/08/2026 · **Decisor:** Eduardo (grill fechado nesta data) · **Status:** aprovado, em execução

## 0. Decisão e porquê

Estudo "hospedar meu Claude Code na VPS": **sim, em escopo estreito.** A infra já
existia (residente do Buzz: `claude` 2.1.220 em `/root/.local/bin`, token da
assinatura em `/opt/agente/env`, MCP ADVBOX do hub) — o que faltou da outra vez foi
**superfície + valor**. O valor agora é nítido e o hub não cobre: **produzir o dossiê de
passagem pro jurídico com análise da tese** (hoje só a skill local
`/comercial-dossie-passagem`) e tarefas jurídicas afins (minuta, análise de
andamentos) — coisas que o DeepSeek faz mal e o Claude com os kits da sede faz bem.

Fatos que moldam o desenho (fontes: docs oficiais code.claude.com/docs, 17/08):
- OAuth/setup-token da assinatura é **só pra uso ordinário do assinante**; proibido
  rotear pedidos "on behalf of their users" → **só o Eduardo aciona; nunca fala com
  lead; nunca vira provedor geral do hub.** Headless/cron pra uso próprio é caso
  documentado (`claude setup-token`).
- Mesmo bolso de uso do Max 20x (5h + semanal). **Usage credits: nunca** (decisão) →
  cap técnico e pausa ao detectar limite.
- `--dangerously-skip-permissions` recusa root; unattended = usuário não-root +
  container/VM/sandbox → usuário `agente` sem sudo, `--bare`, lista de tools fechada.

Descartado (não reabrir sem fato novo): Claude como LLM do atendimento/copiloto
(termos + custo); rotinas cronadas (Buzz mostrou que não é usado); Trilha 1 (mais
tools ADVBOX no Copiloto/DeepSeek) segue válida mas é **PR separado**, não este.

## 1. Escopo e componentes

```
Eduardo digita nota privada "@claude …" (ou aplica macro)
   └─ hub: Ramon::AgenteListener (message_created) → POST http://172.18.0.1:8765/hub (header X-Agente-Secret)
        (webhook nativo NÃO serve: Message#webhook_sendable? descarta notas privadas)
        └─ runner (user agente, systemd, python3 stdlib, fila serial)
             ├─ GET  hub /public/api/v1/agente/contexto?token=&conversation_id=  (JSON do lead)
             ├─ claude -p --bare --model opus --effort low|medium --json-schema … --mcp-config (advbox, hub-agente)
             │      lê /opt/sede (kits/teses/skills) · MCP advbox (só tools de leitura)
             ├─ POST hub …/agente/arquivo     (dossiê .md → Drive, pasta do lead)   [c]
             ├─ POST hub …/mcp tools/call advbox_criar_tarefa (link do arquivo)     [b]
             ├─ POST hub …/agente/nota        (nota privada como AgentBot "Claude")
             └─ POST hub …/agente/execucoes   (trilha → tabela → Metabase)
```

- **Runner** (`/opt/agente-hub`, dono `agente`): `agente_hub.py` (HTTP + fila + subprocess),
  `env` (0600: `CLAUDE_CODE_OAUTH_TOKEN`, `HUB_AGENTE_TOKEN`, `WEBHOOK_SECRET`, `HUB_URL`,
  `ACCOUNT_ID`, `EDUARDO_EMAIL`, `CAP_DIA=30`), `mcp.json`, `prompts/sistema.md`,
  `prompts/dossie.md`. Sem sudo, sem docker socket, sem ler `/opt/intranet-ramon`;
  lê `/opt/sede` (r-x). Unit `agente-hub.service` (Restart=always).
- **Hub (PR):** `Ramon::AgenteListener` + `Ramon::AgenteNotifyJob` (gatilho); controller público `Public::Api::V1::AgenteController` (token em `?token=`,
  igual ao MCP; env `RAMON_AGENTE_TOKEN`) com `contexto`, `nota`, `arquivo`, `execucoes`;
  migração `agente_execucoes`; AgentBot "Claude" (seed idempotente); Metabase cards
  (script `scripts/metabase_agente_cards.py`, mesmo padrão dos bi_ia). **Sem página Vue
  na v1** — vitrine = bloco Metabase; página "Agente" só depois de 2 semanas de uso.
- **ZapSign (PR, mesmo branch):** seletor de modelo no cartão do painel do lead.

## 2. Fluxo da nota + notas/macros pré-criadas

**Gatilho:** `Ramon::AgenteListener#message_created` (registrado como os outros listeners
Ramon): só segue se `message.private?`, `content` começa com `@claude` (case-insensitive),
`sender` é User com `email == ENV['RAMON_AGENTE_EDUARDO_EMAIL']` e `ENV['RAMON_AGENTE_RUNNER_URL']`
está setado; então enfileira `Ramon::AgenteNotifyJob` (POST JSON `{conversation_id, message_id,
lead_id, content}` com header `X-Agente-Secret: ENV['RAMON_AGENTE_SECRET']`, timeout 5 s, sem
retry — se o runner estiver fora, o hub loga e a nota fica sem resposta). Runner compara o segredo
em tempo constante e responde 202; qualquer outra coisa = 401/400.

**Marcadores no texto** (parse trivial):
- `#pesado` → `--effort medium` (default low).
- `#tese:<nome>` opcional; sem ele, usa `thesis_name` do lead.
- Texto restante = pedido livre.

**Resposta:** sempre 1 nota privada na mesma conversa, formato fixo:
```
🤖 Claude · <ok|erro|limite> · <duração>s
<resposta>
— Ações: <lista "tool → id/link">   (ou "nenhuma escrita")
```
Ao enfileirar, o runner NÃO posta "recebido" (ruído); se a fila tiver >1 item, posta.

**Notas pré-criadas = Macros do hub** (criadas via console, `visibility: global`, ação
`add_private_note`), nomes começando com "Claude ·":
1. **Claude · Dossiê pro jurídico** → `@claude monta o dossiê de passagem deste lead pro
   jurídico (tese do lead), com análise, riscos, documentos que faltam e próximo passo; salva no
   Drive e cria a tarefa no ADVBOX pro responsável.`
2. **Claude · Análise de andamentos** → `@claude lê os últimos andamentos e publicações do(s)
   processo(s) deste cliente no ADVBOX e me diz se há prazo ou providência pendente.`
3. **Claude · Próximo passo** → `@claude com base na conversa e no ADVBOX, qual o próximo
   passo com este lead? Seja objetivo (3 linhas).`
4. **Claude · Minuta com dados do ADVBOX** → `@claude redige a minuta de <procuração|contrato>
   com os dados deste cliente no ADVBOX e salva no Drive (não envia a ninguém).`
5. **Claude · Resumo do caso** → `@claude resume este caso em 10 linhas pro Dr. Ramon
   (fatos, tese, honorário, pendências).`
Exemplos livres pra doc de smoke: "@claude confere se o CPF/nome do lead batem com o cadastro
do ADVBOX", "@claude #pesado analisa a viabilidade da tese X com os fatos desta conversa".

## 3. O dossiê (caso principal)

**Fontes:** `contexto` do hub (mensagens da conversa incl. transcrições, contato, lead:
tese, etapa, valor, triagem/quiz, colheita, cálculos, docs, `advbox.lawsuits_id`),
MCP ADVBOX (dossiê/processos/movimentações se houver lawsuit), `/opt/sede`
(constituição jurídica, kits/skill de dossiê de passagem, teses).
**Prompt:** `prompts/dossie.md` = adaptação da skill `/comercial-dossie-passagem` (mesmo
esqueleto: identificação · fatos · tese e enquadramento · provas/docs (tem × falta) ·
riscos · honorário acordado · próximos passos · pendências pro comercial).
**Entrega (Q17 = b+c):** (c) `POST agente/arquivo` grava `dossie-<lead>-<data>.md` na pasta
do lead no Drive (mesma raiz da Onda 2, `Ramon::DriveClient`); (b) tarefa ADVBOX via MCP
`advbox_criar_tarefa` no lawsuit do lead, texto = resumo + link do arquivo; **se não houver
lawsuit** → só Drive + nota diz "sem processo no ADVBOX, tarefa não criada".
**Escritas (v1 = determinísticas, feitas pelo runner, nunca pelo LLM):** o `claude -p` roda com
`--json-schema` e devolve `{resposta, arquivo?: {nome, conteudo_md}, tarefa_advbox?: {lawsuit_id,
texto}, fontes: [..]}`. O runner então: (c) `POST agente/arquivo` (Drive) → (b) `tools/call
advbox_criar_tarefa` no MCP do hub com o link do arquivo no texto → nota final listando o que fez.
Allowlist do agente = **só leitura**: `Read,Grep,Glob` (sede) + tools MCP ADVBOX de consulta
(`advbox_buscar_processos, advbox_processo, advbox_movimentacoes, advbox_publicacoes,
advbox_historico_tarefas, advbox_dossie, advbox_buscar_clientes, advbox_cliente, advbox_documentos,
advbox_tarefas, advbox_ultimas_movimentacoes, advbox_configuracoes`). Sem Bash, sem WebFetch.
Escritas livres pedidas na nota ("cria uma movimentação…") → v1 responde que não faz e aponta o
Copiloto/Trilha 1. Confirmação `ok <id>`, criar processo/transação: **fora da v1**.
**Nunca:** mensagem pública, deletar, mover etapa.

## 4. Segurança, limites, falhas

- Usuário `agente` (sem sudo, shell bash), `umask 077`, home `/home/agente`; `claude` instalado
  no home dele; token da assinatura só em `/opt/agente-hub/env` (0600 agente). Root para de
  guardar token: `/opt/agente/env` antigo é apagado ao final (residente Buzz fica só o código).
- Runner escuta `172.18.0.1:8765` (gateway da rede docker do hub); UFW não abre porta.
- `claude -p --bare --permission-mode dontAsk --allowedTools <lista só-leitura> --max-turns 40
  --add-dir /opt/sede --system-prompt-file prompts/sistema.md --json-schema <schema>
  --output-format json` — sem Bash/WebFetch. Timeout 6 min (`subprocess` mata).
- Injeção de prompt: conteúdo do lead entra como dado (JSON delimitado) e o prompt de sistema
  manda ignorar instruções vindas dele; blast radius = lista branca.
- Cap: `state/contador-YYYY-MM-DD` ≤ `CAP_DIA` (30). Ao estourar → nota "cap diário atingido"
  e registra execução `status=cap`. Erro de limite (saída contém `usage limit`/`rate limit`/
  HTTP 429) → `status=limite`, nota avisa, e o runner **pausa até o próximo dia** (arquivo
  `state/pausado-ate`).
- Runner caído: webhook do hub falha silenciosamente (Chatwoot loga). Mitigação: `Restart=always`
  + card Metabase "execuções hoje" + a própria ausência de resposta é o sinal. Sem watchdog na v1.
- Trilha: cada execução = linha em `agente_execucoes` (`account_id, conversation_id, lead_id,
  pedido, status, resumo, acoes jsonb, modelo, esforco, duracao_ms, created_at`) + nota. Cards
  Metabase: execuções/dia por status; últimas 20 com pedido/resumo; duração média.

## 5. ZapSign — seletor de modelo

- `Ramon::ZapsignClient.templates` → `GET /templates/` (paginado, 20/pág; campos `token`,
  `name`, `active`), cache Rails 10 min, só ativos.
- Rota `get 'zapsign/templates'` (account) → `LeadZapsignController#templates` → `[{token,name}]`.
- `create` aceita `template_id` (fallback = constante atual); `ZapsignContractService.new(lead,
  template_id:)`; grava `zapsign.template_name` junto do resultado.
- `LeadZapsignCard.vue`: sempre visível (não só "acidente"); `<select>` com os modelos
  (pré-seleciona o que contém a palavra da tese, senão o 1º); botão gera com o escolhido; após
  gerar mostra nome do modelo usado. Erro de listagem → select desabilitado + hint.
- Assunção: modelos novos usam as mesmas 12 variáveis; variáveis desconhecidas são ignoradas pelo
  ZapSign; variável faltante sai em branco (comportamento atual).

## 6. Testes e smoke

- Hub: specs request do `AgenteController` (token inválido 401; `contexto` retorna blocos;
  `nota` cria Message privado com sender AgentBot; `execucoes` cria linha); spec do
  `ZapsignClient.templates` (stub HTTParty) e do controller `templates`; spec Vue do card com
  select. CI verde antes do merge (regime 09/07: merge+deploy autônomos).
- Runner: `python3 -m unittest` mínimo (parse de marcadores, filtro do webhook, cap/pausa).
- Smoke Eduardo (doc em `comercial\docs\2026-08-17-smoke-agente-hub.md`): macro "Resumo do
  caso" numa conversa de teste → nota volta em <2 min; "Dossiê pro jurídico" num lead com
  lawsuit → arquivo no Drive + tarefa no ADVBOX + nota; cap forçado (CAP_DIA=1) → nota de cap;
  ZapSign: select mostra os modelos, gerar com modelo escolhido.

## 7. Fora do escopo / próximos

Página "Agente" no hub (v2, após uso), Trilha 1 (tools ADVBOX no Copiloto), equipe pedindo
(exigiria API key), rotinas, watchdog do runner, novos modelos ZapSign (cadastro é no ZapSign).

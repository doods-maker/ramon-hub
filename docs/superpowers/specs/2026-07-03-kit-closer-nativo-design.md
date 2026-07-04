# F2.1 — Kit do Closer, Triagem IA e Playbooks NATIVOS no ramon-hub (design)
**03/07/2026 · rascunho para aprovação do Eduardo · insumo: mapeamento completo da intranet em `scratchpad/kit-closer-intranet.md` (sessão 02-03/07)**

## Objetivo

Portar o coração do fechamento (triagem por IA → viabilidade → Kit do Closer → playbook por tese) da intranet legada (Next.js/Supabase) para dentro do fork, nativo Rails/Vue. Ao final, o Dashboard App `/embed/kit` e o webhook legado podem ser desligados (conclui o F1).

## O que o port SIMPLIFICA (ganhos de nascer dentro do hub)

1. **Transcrição da conversa vira leitura local** — nada de chamada HTTP ao próprio Chatwoot com token de super admin; a triagem lê `conversation.messages` direto (sem env, sem proxy, sem o bug do header com underscore).
2. **Auth nativa** — morre o token HMAC do iframe; o painel já roda logado.
3. **Triagem vira job Sidekiq** — assíncrona, com resultado chegando via realtime (infra de `lead.updated` já existe); na intranet era request síncrono.
4. **Webhook → lógica interna** — origem/campanha já entram pelo endpoint público nativo.

## Modelo de dados (tabelas novas, todas account-scoped, nomes em inglês como o resto do fork)

- **`triage_agents`** ← `agentes`: name, description, area, system_prompt, provider (deepseek|anthropic|openai), model, sensitive (bool), active. Seed: 1 agente previdenciário padrão (portar prompt do banco da intranet — pegar em produção no Supabase antes do F3).
- **`lead_triages`** ← `casos` (simplificado): lead_id, triage_agent_id, status (pending|running|done|error), result (text), viability (high|medium|low), source_text, kit (jsonb), kit_status, timestamps. *Não portamos:* cliente_nome/parte_contraria (o lead+contact já têm), documentos/upload (fluxo raro; se voltar a doer, fatia própria), fila "Pra fechar" (o Kanban com etapas + filtros do A3 já cumpre o papel).
- **`theses`** + **`thesis_items`** ← `teses`/`tese_itens`: mesmas 5 seções (abertura, apresentacao, qualificacao, objecao, documento), title/content/position. Seed versionado com as 5 teses / ~65 itens do `12_playbook_seed_incapacidade.sql`.
- **`leads.thesis_id`** (nullable) ← `leads.tese_id`.

## Camada de IA

- Usar **RubyLLM** (gem que o Chatwoot 4.15 já embarca) como camada agnóstica: suporta Anthropic, OpenAI e DeepSeek. Zero dependência nova.
- **Regra LGPD preservada e testada em spec:** `sensitive: true` → DeepSeek bloqueado ANTES de qualquer envio; só anthropic/openai.
- ENVs novos no `chatwoot.env`: `DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY` (e `OPENAI_API_KEY` se usado).
- Prompts: system = `triage_agents.system_prompt` (dado, não código); instrução fixa da linha `VIABILIDADE:` e o prompt do kit (JSON estrito + parse tolerante) portados de `lib/triagem.ts`/`lib/kit-closer.ts`.

## UI (Vue, mundo certo pra cada coisa)

1. **Painel do lead na conversa** (estende o `LeadConversationPanel` existente):
   - Seletor de **tese** (grava `leads.thesis_id`).
   - **Playbook de consulta** (3 seções ao vivo: qualificação, objeções, documentos) da tese do lead — gaveta.
   - Botão **"Rodar triagem"** → job → resultado (viabilidade + análise) no painel via realtime.
   - **Kit do Closer por etapa** (porta `modoDaEtapa`/`blocosKit`): sdr = roteiro+próximo passo · closer = resumo+objeções+documentos+próximo passo · encerrado = nada. Botão copiar por bloco.
2. **Mundo Intranet — tela "Playbooks"** (CRUD de teses/itens): a lacuna real da intranet (hoje só SQL manual) vira UI de gestão. Segue o padrão da tela de config do funil (A2/2D).

## Fatias de execução (cada uma = plano próprio + PR + CI)

- **F2.1a — Dados + Playbooks:** migrações + seeds + API REST (theses CRUD, thesis do lead) + tela Playbooks no mundo Intranet + seletor de tese e consulta no painel. *(Sem IA ainda — já entrega valor: playbook na conversa.)*
- **F2.1b — Triagem nativa:** RubyLLM service + job + LGPD + botão/resultado no painel.
- **F2.1c — Kit do Closer:** 2ª passada + blocos por etapa + copiar.
- **F2.1d — F1 final:** desligar webhook legado + Dashboard App + rotação/limpeza de ENVs legadas (`CHATWOOT_API_TOKEN` etc.). Migrar dados vivos (teses reais do Supabase de produção, se divergirem do seed; casos históricos ficam pro F3).

Invariantes de sempre: fork-safe (namespace `ramon/`, core mínimo registrado), migração → schema regen via scratch DB na VPS, PR/CI valida (rollup completo!), deploy só com OK.

## Decisões (Eduardo, 03/07/2026)

1. **Trava LGPD = escolha do Eduardo, não bloqueio fixo.** O flag `sensitive` continua existindo por agente, mas é um **toggle que ele controla na UI** (default: desligado). Com o flag desligado, DeepSeek processa tudo — decisão consciente dele ("pretendo enviar todos os dados mesmo, sem problemas"). O mecanismo fica disponível caso mude de ideia. Provider padrão: DeepSeek.
2. **Triagem só manual, por botão.** Sem gatilho automático por etapa.
3. **Playbooks: popular junto.** Além das 5 teses de incapacidade do seed, o Claude redige RASCUNHOS de playbook (via skills comercial-* + business-context + conteúdo das LPs) para toda tese que a banca trabalha e tem material — candidatas: salário-maternidade, trabalhista geral, aposentadorias (verificar material). Rascunhos entram no seed marcados como rascunho e o Eduardo revisa/edita na tela nova de Playbooks. 

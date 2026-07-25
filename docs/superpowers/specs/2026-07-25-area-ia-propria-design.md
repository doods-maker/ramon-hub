# Área de IA própria no hub — design

**Data:** 2026-07-25
**Origem:** Eduardo trouxe prints de um CRM concorrente (Bravy / "Chat BullQ", `chat.bravy.com.br`)
e pediu a área "Jarvis" deles no nosso hub, com motor DeepSeek.
**Estado:** aprovado pelo Eduardo em conversa (25/07).

---

## 1. Contexto

O produto de referência é **o mesmo Chatwoot v4 que o hub roda** (mesmo
`components-next/sidebar`, mesmos grupos colapsáveis). A área "Jarvis" deles é o
módulo **Captain** do Chatwoot, renomeado e populado. Não há redesign envolvido.

O que o Eduardo aprovou:

- construir a **área de IA própria** (Captain ligado, renomeado, apontado pro DeepSeek);
- **descartado:** tema claro (não era o que chamou atenção dele);
- **Skills ≠ playbooks ≠ macros** — distinção levantada por ele e adotada aqui;
- **dois modos desde já:** copiloto interno + atendimento ao lead com humano no meio;
- **"IA sozinha" fora de escopo** — se um dia for, provavelmente pela IA da Meta;
- **DeepSeek único, sem fallback anthropic/openai** (decisão explícita dele).

## 2. Vocabulário (fixado)

| Termo | O que é | Quem dispara |
|---|---|---|
| **Macro** | Texto pronto | Humano |
| **Playbook** | Roteiro que o humano lê | Humano |
| **Tool** | Uma ação num sistema real | A IA |
| **Skill** | Instrução + conjunto de tools, para uma situação | A IA |
| **Agente** | Persona + skills + guardrails | — |

Macros e playbooks continuam existindo e **não são tocados** por este trabalho.

## 3. O que já existe no fork (não construir)

Levantado no código antes do desenho:

- `Captain::Assistant` — o agente.
- `Captain::Scenario` — título + descrição + **instrução** + tools referenciadas no
  texto por `[Nome](tool://slug)`; `resolve_tool_references` materializa em `tools`
  (jsonb) no save; `validate_instruction_tools` rejeita tool inexistente. **É a "skill".**
- `Captain::CustomTool` — tool HTTP (endpoint, método, `param_schema`, auth
  `none|bearer|basic|api_key`, templates). Teto de **15 por conta**.
- Catálogo de tools nativas: `config/agents/tools.yml` + convenção
  `Captain::Tools::{PascalCase(id)}Tool` (`captain_tools_helpers.rb#load_agent_tools`).
  Nativas prontas: `add_contact_note`, `add_private_note`, `update_priority`,
  `add_label_to_conversation`, `faq_lookup`, `resolve_conversation`, `handoff`.
- UI pronta: Agentes, Skills (cenários), Tools, Documentos, Playground.
- Instrumentação: `enterprise/app/services/captain/tools/instrumentation.rb`.

**Consequência de desenho:** as nossas tools **não** serão `CustomTool` HTTP. Os
sistemas que elas tocam (AdvBox, ZapSign, motor, Cal.com) já têm client Ruby dentro
do hub. Cada tool nossa = **1 entrada em `config/agents/tools.yml` + 1 classe Ruby**.
Sem HTTP, sem token em trânsito, sem o teto de 15. O `CustomTool` fica disponível
para algum sistema externo futuro.

## 4. Motor: DeepSeek

Ambos os caminhos de LLM do Captain leem os mesmos três `InstallationConfig`:

- `CAPTAIN_OPEN_AI_API_KEY`
- `CAPTAIN_OPEN_AI_ENDPOINT` → `https://api.deepseek.com`
- `CAPTAIN_OPEN_AI_MODEL` → `deepseek-chat`

Caminhos: `lib/llm/config.rb` (RubyLLM, moderno) e
`enterprise/app/services/llm/legacy_base_open_ai_service.rb` (legado, PDF/files).

**Sem fallback.** Se o DeepSeek não atender, o projeto muda de forma — não troca de
provedor. Decisão do Eduardo, 25/07.

Nota: a camada LLM própria do hub (`Ramon::LlmClient`, usada por triagem, colheita,
copiloto, follow-up) **permanece separada e intocada**. Não há unificação neste
trabalho.

## 5. Os dois agentes

### 5.1 Agente interno (copiloto da equipe)

Trabalha para a equipe. Nunca escreve em conversa de cliente. Skills de leitura +
skills de escrita em modo preparar.

### 5.2 Agente de atendimento (humano no meio)

Atua na conversa do lead. **Toda mensagem que sairia vira rascunho no editor** — o
agente humano revisa e envia. Usa `handoff` quando trava ou quando a confiança cai.

É o padrão já em produção no hub: o Copilot da conversa (#50) rascunha e nunca envia;
a triagem (#48) já faz handoff bot→humano por confiança com status `awaiting_human`.

## 6. Régua de autonomia (o núcleo do desenho)

Cada tool declara seu nível. É o princípio de aprovação do estatuto virando arquitetura.

### Nível LEITURA — a IA executa sozinha

| Tool | Encosta em |
|---|---|
| `consultar_dossie_advbox` | `Ramon::AdvboxMcpService` / client AdvBox |
| `calcular_beneficio` | `Ramon::MotorClient` |
| `checar_prescricao` | endpoint de prescrição já existente |
| `linha_da_vida` | Linha da Vida já existente |
| `documentos_faltantes` | `custom_attributes.colheita` (lacunas) |

Mais as nativas do Chatwoot (nota privada, etiqueta, prioridade, FAQ, handoff).

### Nível ESCRITA — a IA prepara, o humano aplica

| Tool | Encosta em |
|---|---|
| `preparar_contrato_zapsign` | `Ramon::ZapsignContractService` (já devolve `sign_url` sem enviar) |
| `preparar_caso_advbox` | `Ramon::AdvboxClosingService` |
| `agendar_reuniao` | webhook/integração Cal.com |
| `mover_etapa` | Lead stage |

**Nenhuma tool de escrita executa direto.** Todas produzem **nota rascunho + botão
aplicar**, reusando o mecanismo do copiloto noturno (`NightCopilotJob`: sugestão vira
nota rascunho, `apply!` idempotente, `apply_all` sem `move_stage`).

**Guardrail herdado e mantido:** a IA nunca resolve etapa `won`/`lost` — em `won` isso
dispararia `AdvboxClosingJob` real (decisão do PR #96).

## 7. Skills do primeiro lote

Cada skill = instrução + tools. Sugestão inicial, ajustável depois sem código:

- **Qualificar lead novo** — leitura + nota privada + etiqueta (espelha a skill
  `comercial-qualificar-lead`, agora executável).
- **Preparar reunião** — dossiê + cálculo + documentos faltantes.
- **Fechar contrato** — preparar ZapSign + preparar caso AdvBox, ambos em rascunho.

## 8. Menu

Grupo próprio (**nome a definir pelo Eduardo depois** — hoje "Captain"):

| Item | Estado |
|---|---|
| Visão geral | existe |
| Agentes | existe |
| Skills | existe (cenários) |
| Tools | existe |
| **Execuções** | **novo** — log auditável, sobre `instrumentation.rb` |
| **Watchdog** | **novo** — tela do vigia que já roda |

O **Watchdog** não é motor novo: `Ramon::DailyFollowUpJob` (cron 11:00 BRT) e o badge
`↻N` no LeadCard já rodam desde 23/07. Falta a tela — thresholds visíveis, contadores
24h, lista "em alerta" — que é o print 2 da referência.

## 9. Riscos, com o que fazer

| # | Risco | Verificação | Se der ruim |
|---|---|---|---|
| 1 | `config/llm_models.json` (registry RubyLLM) pode não conhecer `deepseek-chat` | Fatia 0 | registrar o modelo no arquivo |
| 2 | Captain V2 roda sobre o gem `ai-agents` com function calling encadeado; DeepSeek suporta, mas encadeamento é onde modelo barato escorrega | Fatia 0 | **sem fallback** — o projeto muda de forma (ex.: skills de passo único) |
| 3 | **`captain_integration` está em `enterprise/config/premium_features.yml`**; `Internal::ReconcilePlanConfigService#reconcile_premium_features` roda diário e chama `disable_features!` → **liga hoje, desliga amanhã** | — | remover a linha do YAML (mesmo fix do branding, PR #82; Eduardo já dispensou a regra "não tocar em enterprise/" para uso interno) |
| 4 | **LGPD:** o Captain envia a conversa **crua** ao LLM, sem o `Pseudonymizer` que a camada `Ramon::LlmClient` aplica | — | coberto pela decisão de 20/07 que autorizou o deepseek a receber PII (`RAMON_LLM_SENSITIVE_OK_PROVIDERS`); registrado aqui para ficar explícito |
| 5 | `CustomTool` tem teto de 15/conta | — | não nos afeta: nossas tools são nativas |

## 10. Fatiamento

**Fatia 0 — spike (barata, primeiro).**
Ligar o Captain na conta + remover a linha do `premium_features.yml` + apontar as três
configs pro DeepSeek + **uma** tool de leitura (`consultar_dossie_advbox`) + **uma**
skill que a usa. Objetivo único: matar os riscos 1 e 2 antes de investir.

**Fatia 1.** Restante das tools de leitura + agente interno + renomear a área.

**Fatia 2.** Tools de escrita com aprovação + agente de atendimento em modo rascunho.

**Fatia 3.** Telas Execuções e Watchdog.

## 11. Fora de escopo

- Tema claro (descartado pelo Eduardo).
- IA atendendo o lead sozinha (provavelmente Meta, no futuro).
- Unificar `Ramon::LlmClient` com a camada LLM do Captain.
- Mexer em macros ou playbooks.
- Fallback de provedor.

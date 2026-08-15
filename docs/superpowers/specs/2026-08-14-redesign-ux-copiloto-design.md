# Redesign UX + Copiloto — design aprovado (14/08/2026)

> **Status: DESIGN APROVADO pelo Eduardo em 14/08 — aguarda planos de implementação por onda.**
> Mockups aprovados em `comercial\docs\mockups\2026-08-14-redesign-material\`
> (ficha-cliente.html · conversa.html · conversa-v2-copiloto.html).

## O problema (nas palavras dele)

1. "Ver o andamento do lead" não tem resposta de bater o olho.
2. O painel de lead na conversa está entulhado — abre despejando tudo, sem hierarquia.
3. Não existe um lugar separado por cliente que consolide andamento, documentos,
   cálculos e reuniões.
4. Visual do hub datado; ele quer estética "estilo Material": claro, cartões,
   sombras suaves, marca bronze adaptada.

## Decisões de design (todas confirmadas pelo Eduardo)

- **D1 — Direção visual nova "Material claro"** substitui a direção do handoff.
  A rodada de teste mock-por-mock das ondas 1–5 do handoff está **cancelada**;
  o que valia (chip por etapa, seções recolhidas) é absorvido aqui.
- **D2 — Ficha do Cliente**: página dedicada por lead (não painel), com esteira
  de etapas no topo (assinatura visual: "selos" bronze com datas), cartão
  Próximo passo com ações, cartões Documentos X/Y, Cálculos, Reuniões,
  Linha do tempo, Dados do caso.
- **D3 — O painel de lead na conversa FICA** (pedido explícito): reorganizado —
  botão "Abrir ficha completa" no topo, mini-esteira, próximo passo, docs X/Y,
  resumo do caso; o resto recolhido.
- **D4 — IA e automações aparecem NA conversa**, sem abrir painel:
  chips de status no topo (SLA, cadência), eventos de automação inline no fluxo
  ("cadência cobrou docs", "IA reconheceu CNIS — Desfazer"), rascunho da IA
  acima do composer (Enviar/Editar/Descartar + o porquê), atalhos rápidos,
  coach de objeção em tempo real, áudio transcrito inline, termômetro,
  alerta de risco de esfriar, qualificação da tese ao vivo (N/M critérios).
- **D5 — Copiloto com 4 modos POR CONVERSA**:
  1. **Manual** — IA quieta.
  2. **Rascunho (padrão)** — nada sai sem Enviar do humano (comportamento atual
     do assistente "Atendimento (rascunho)").
  3. **Piloto com limites** — envia sozinho SÓ logística: cobrança de documento,
     confirmação de horário, mensagem de cadência. Nunca valores, análise de
     caso, promessa.
  4. **Piloto total** — responde tudo sozinho.
  Em ambos os pilotos: toda mensagem automática fica **carimbada** na conversa
  (evento visível "enviada pelo piloto · ver regra") e há **pausa de 1 clique**.
  Decisão do Eduardo 14/08: os dois níveis de piloto existem; ele assume o
  ajuste da fronteira do princípio de aprovação — a automação de envio é
  opt-in por conversa, escolhida por ele.

## Ancoragem no código existente (fatos, não suposição)

- Assistente em modo rascunho já existe: `Captain::Assistant#modo_rascunho?`
  (store_accessor no config jsonb) → `ResponseBuilderJob` grava nota privada.
  Os modos viram um enum por CONVERSA (custom_attributes da conversa) que o
  ResponseBuilderJob consulta: manual (não roda), rascunho (nota privada),
  piloto_limitado / piloto_total (mensagem outgoing + carimbo em
  content_attributes). Auto-resolver do Captain segue DESLIGADO.
- DeepSeek: sem json_schema (só json_object) — classificador de "é logística?"
  do piloto limitado precisa respeitar isso (lição PR #110).
- Transcrição: `Messages::AudioTranscriptionService` (whisper local) já
  transcreve áudio de WhatsApp — falta exibir inline com selo "transcrito".
- Rascunho na reply box: bus `INSERT_INTO_NORMAL_EDITOR` já usado pelo
  LeadCopilot e pela cobrança de docs (Onda 2) — o "Usar →" do coach reusa.
- Sugestões pendentes: `CopilotSuggestion` (kinds draft/alert/acao) — coach de
  objeção pode ser kind novo, aplicado no contexto da conversa.
- Cadência/SLA: `Ramon::Cadencia` é o dono único — termômetro e risco de
  esfriar derivam daí (ritmo de resposta + "vou pensar" é heurística nova).
- Qualificação viva: critérios por tese via `thesis_items` + quiz estruturado
  (`custom_attributes['quiz']`, Onda 1).
- Docs X/Y: escalares `docs_received/docs_total` + `LeadDocs` (Onda 2).
- Valor estimado + probability (Onda 3) alimentam cabeçalho da Ficha.

## Ondas propostas (cada uma = brainstorm de detalhe → plano → PR → smoke)

- **Onda A — Fundação visual + Ficha do Cliente.** Tokens do tema Material
  claro (papel #F7F5F2, cartão branco, bronze #8C6A3F, Fraunces+Manrope),
  rota/página da Ficha, esteira, cartões (dados que já existem). Botão
  "Abrir ficha" onde o lead aparece.
- **Onda B — Painel reorganizado + automações visíveis.** Painel enxuto (D3),
  eventos de automação inline no fluxo, chips SLA/cadência, áudio transcrito
  inline.
- **Onda C — Modos do copiloto.** Seletor por conversa (4 modos), carimbo,
  pausa de 1 clique, classificador de logística do piloto limitado.
- **Onda D — Copiloto proativo.** Coach de objeção (playbooks), termômetro,
  risco de esfriar (+atalho follow-up W4), qualificação viva com "perguntar →".
- **Onda E — Espalhar o visual.** Funil, Pós-venda, Reuniões, Relatórios,
  Cálculos no mesmo tema.

Sequência A→E; C e D dependem de B. Smokes consolidados das 3 ondas do funil
estratégico (gate Eduardo) seguem pendentes e independentes disto.

## Fora do escopo (v1)

- Novo framework de UI (MUI/Vuetify descartados — tema próprio sobre os
  componentes Vue existentes).
- IA falando valores/análise jurídica sozinha em QUALQUER modo.
- Ficha pública/portal do cliente.

## Guardrails

- OAB-safe em toda mensagem automática; piloto nunca promete resultado/prazo.
- Modo padrão de toda conversa nova: **Rascunho**.
- Toda mensagem de piloto é auditável (carimbo + registro).

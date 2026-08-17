# Inteligência completa — design (16/08/2026)

> Resultado da sessão de grill-with-docs com o Eduardo (16/08). Vocabulário no
> `CONTEXT.md` (§ Inteligência). Este doc é o mapa das 5 ondas; cada par de
> ondas ganha um plano próprio em `docs/superpowers/plans/`.
> Regime: merge + deploy autorizados, ondas de 2 em 2 (decisão Eduardo 16/08).

## O que já existe (fatos, 16/08)

- 2 Assistentes na conta 2: **Copiloto do Escritório** (equipe; skills Situação
  do processo / Preparar reunião / Histórico da pessoa) e **Atendimento
  (rascunho)** (lead; skills Qualificar lead novo / Fechar contrato / Agendar
  reunião e mover etapa), conectado só à inbox "Teste" (Channel::Api).
- 9 tools do fork (6 leitura, 3+1 escrita → Sugestão pendente) + 7 nativas.
- FAQ = 0, Documentos = 0: mortos porque `AssistantResponse.search` é vetorial
  (`vector(1536)`, `text-embedding-3-small` OpenAI) e só há DeepSeek. DeepSeek
  **não tem endpoint de embeddings** (doc oficial conferida 16/08).
- Modo do Copiloto por conversa (Onda C) + coach de objeção, termômetro,
  qualificação viva, retomada W4 (Onda D) no ar.
- Tela "Triagem de Iniciais" (`TriageAgent`, 1 agente ativo, 4 triagens na
  vida) — sistema paralelo de 03/07, fora do Captain.
- 5 teses no Playbooks: auxílio-doença B31 · aposentadoria por invalidez B32 ·
  auxílio-acidente B36 (a única com playbook rico: 27 colheita, 11 objeções,
  8 qualificação, 10 roteiro) · BPC/LOAS deficiência · acréscimo 25%.
- Honorário 30% + 3 mensalidades em todas as teses (decisão 14/08, provisória).

## Decisões (todas confirmadas pelo Eduardo em 16/08)

| # | Decisão | Alternativas descartadas |
|---|---|---|
| D1 | Escopo = área nativa populada e funcionando **e** utilidades novas do funil, em 5 ondas | só uma das duas |
| D2 | **FAQ sem embeddings**: busca textual do Postgres em português (`to_tsvector('portuguese')`), 100% DeepSeek/local | chave OpenAI só p/ embeddings (degrau seguinte se a busca textual falhar); embeddings locais |
| D3 | **2 Assistentes**, um por público (lead × equipe); crescem por Skills por situação | assistente por fase/tese |
| D4 | **FAQ** = pergunta do *lead* + resposta aprovada, por tese, voz "médico de confiança", OAB-safe. **Documento** (Captain) = fonte para GERAR FAQ (colar texto/URL → FAQ pendente pra aprovar) — descoberto que o Assistente não lê Documents direto; a referência de comportamento (voz, regras OAB, honorário) vive em `response_guidelines`/guardrails/skills. Eu redijo, Eduardo aprova (aprovação em bloco dada 16/08) | Documents como RAG |
| D5 | Atendimento conectado a **todas as caixas de lead** quando o WhatsApp oficial entrar; modo padrão *rascunho* por conversa; chat da LP segue roteirizado (sem IA) | IA no widget da LP |
| D6 | Tools novas escolhidas por mim (lista abaixo) | — |
| D7 | Autonomia-alvo 60 dias: **piloto_limitado por padrão** em conversa nova de lead, **após ~20 conversas em rascunho revisadas** com baixa correção; piloto_total fora do horizonte | ficar em rascunho; piloto_total |
| D8 | Qualidade = **caderno de provas** (conversas-modelo por tese rodadas no Playground a cada mudança) **+ métrica no Metabase** (rascunho enviado sem edição × editado × descartado; tempo até 1ª resposta com/sem IA; handoffs/objeções) | só uso real |
| D9 | Ordem: Fundação → Tools de leitura → Tools de escrita + qualificação → Piloto por padrão + métrica → Captação. Executar em pares | — |
| D10 | **Triagem de Iniciais**: fundir — o prompt vira Skill "Triagem" do Atendimento (rubrica de viabilidade) e a tela/menu/botão saem; modelos/controllers ficam até confirmação | manter as duas |
| D11 | `resolve_conversation` sai do catálogo dos Assistentes; `add_private_note`/`add_label`/`update_priority` ficam (internas) | bloquear todas |
| D12 | "Quanto custa?" nas FAQs: **30% + 3 mensalidades em todas as teses** (Eduardo, sobrepondo a regra da constituição do comercial "só auxílio-acidente") | modelo genérico sem número |
| D13 | Logística do piloto limitado (lista fechada): saudação/acolhida; dados cadastrais; horários e confirmação de reunião; lista de documentos e cobrança de pendentes; lembrete de cadência. Fora: direito, valor, prazo do INSS, chance | — |
| D14 | Agenda: reuniões vivem no ADVBOX e no Google Calendar; **Cal.com** = link de auto-agendamento pro lead (disponibilidade definida pelo Eduardo lá). O Assistente **manda o link**; não escolhe horário | Assistente propondo slots |
| D15 | Copiloto do Escritório soma: funil hoje, agenda do dia, publicações ADVBOX, revisão de documentos do caso (o que falta / o que pedir) | — |

## Ondas

### Onda 1 — Fundação (código pequeno + conteúdo)
1. FAQ textual (D2): `AssistantResponse.search` via FTS português; job de
   embedding vira no-op sem chave OpenAI real; `faq_lookup` sempre oferecida
   quando há FAQ.
2. Documento com conteúdo direto: API/modelo aceitam `content` (colar texto →
   FAQ gerada pendente), sem crawl.
3. Conteúdo: FAQ por tese (5 + geral) em `db/seeds/ramon/inteligencia/faq/`,
   guidelines/guardrails/skills em `assistentes.yml`; rake
   `ramon:inteligencia:seed[account_id]` idempotente (FAQ editada na UI não é
   sobrescrita; skill fora do yml é desabilitada, não apagada).
4. Skills: revisar as 6 e criar Triagem (D10), Objeções e honorário, Cobrar
   documentos (pós-venda), Enviar link de agendamento (D14); no Copiloto:
   Revisão de documentos do caso, Funil hoje, Agenda do dia, Publicações.
   Seed idempotente por título.
5. `resolve_conversation` fora (D11). Triagem de Iniciais sem pontos de
   entrada (D10).
6. Caderno de provas (D8) em `comercial\docs\`.

### Onda 2 — Tools de leitura
`playbook_da_tese` · `simular_honorario` (fórmula extraída do Simulador pra um
serviço único) · `historico_do_contato` · `link_agendamento` (Cal.com via env)
· `agenda_do_escritorio` (antes `agenda_do_dia`; tarefas/reuniões do hub + tarefas ADVBOX) · `funil_hoje`
(Cockpit em texto) · `publicacoes_advbox`. Google Calendar via SA fica pra
depois (gem nova = bundle lock na VPS) — dito ao Eduardo.

### Onda 3 — Tools de escrita + qualificação
`registrar_qualificacao` (escreve `qualificacao_status`, interno) ·
`criar_tarefa_esteira` · `marcar_perdido` (Sugestão) · `solicitar_documento`
e `enviar_link_portal` (rascunho na conversa). Carimbo "veio de rascunho da IA"
na mensagem enviada (base da métrica).

### Onda 4 — Piloto por padrão + métrica
Chave `RAMON_COPILOTO_MODO_DEFAULT` (liga piloto_limitado após D7); view
`bi_ia` + bloco "Inteligência" no dashboard Metabase (D8).

### Onda 5 — Captação
Quiz da LP ↔ Assistente (contexto estruturado já viaja); Instagram DM (gate
Meta); link Cal.com nas LPs; revisão do que sobrou.

## Fora de escopo (dito)
Piloto_total; IA no widget da LP; Google Calendar de saída; PDF em Documentos
(usa Files API da OpenAI); FAQ auto-gerada de conversas (fica ligada se
funcionar com DeepSeek, mas não é entrega).

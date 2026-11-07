# 0015. Várias etapas de ganho

Data: 07/11/2026. Pedido do Eduardo: Documentos e Jurídico como colunas reais do funil, depois de Fechado, com o agente
de IA escolhido pela etapa (spec `docs/superpowers/specs/2026-11-07-etapa-documentos-design.md`, seção 1). Revoga em
parte o [ADR 0001](0001-pos-venda-como-estado-derivado.md): o pós-venda passa a ter etapas; o checklist continua sendo
a medida de "o que falta".

## Decisão

- **Várias etapas `is_won` por conta.** `LeadStage` só mantém exclusiva a etapa de perda; Perdido continua único.
- **A entrada do ganho tem um ponto só: `Ramon::EtapaDeGanho`.** `principal(account)` é Fechado (`fase-fechado`; sem
  ela, a primeira `is_won` por posição). `entrada(lead)` diz onde um lead que acabou de ganhar cai: neste PR, sempre a
  principal; o PR 2 desvia para Documentos. ZapSign assinado, contrato fechado no ADVBOX, importação CSV e o fluxo dos
  eventos ADVBOX perguntam aqui, nunca `find_by(is_won: true)`.
- **"Está ganho" é qualquer etapa `is_won`.** Andar entre etapas de ganho não é um ganho novo: `won_at` fica
  (`Lead#apply_stage_timestamps` já preservava), então não há cascata do ganho (dossiê, ADVBOX, NPS), Drive nem
  `Purchase` na Meta de novo.
- **Documentos e Jurídico nascem por rake** (`ramon:funil:etapas_pos_venda[account_id]`), idempotente, logo depois de
  Fechado. Não rodam no deploy deste PR: entram junto do PR 2, que liga o agente de documentos.

## Consequências

- O gatilho de fluxo `lead_ganho` só dispara quando a etapa de origem não era de ganho (`RamonFluxoListener`).
- A janela de 90 dias do Kanban não esconde Documentos: é trabalho em andamento, não fechado (`Ramon::LeadRadar`).
- Telas: arrastar, trocar no painel, mover em lote ou pelo Ctrl K de ganho para ganho não pede valor
  (`entraNoGanho` em `helpers/stage.js`). Marcar uma etapa como ganho não pede confirmação nem desmarca as outras;
  marcar perda continua pedindo e substituindo.
- Métricas de ganho somam as etapas: o "Funil · conversão" do Centro mostra uma linha de ganhos com a soma; o resto
  (BI, dashboard, cockpit, radar de prescrição) já tratava "ganho" como qualquer `is_won`.
- Conta nova não ganha Documentos e Jurídico pelo seed (o fork tem uma conta só); levar ao seed se surgir outra.

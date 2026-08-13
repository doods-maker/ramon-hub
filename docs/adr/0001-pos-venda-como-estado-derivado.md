# Pós-venda é estado derivado do lead ganho, não etapas do funil

O funil precisa acompanhar o pós-venda (coleta de documentos até o caso estar
completo), mas a mecânica de ganho amarra `won_at` à permanência na etapa
`is_won`: sair dela apaga a data de ganho, e sair-e-voltar re-dispara a cascata
de fechamento (handoff, ADVBOX, NPS — o handoff pode até duplicar). Decidimos
que o lead ganho **fica na etapa "Fechado" para sempre**; o pós-venda é o
Checklist de Documentos por tese + uma visão "Pós-venda" (ganhos com docs
pendentes), e "Concluído" é o estado derivado "checklist completo + pacote no
Drive". Não criar colunas pós-ganho evita mexer no coração de won/lost e mantém
as métricas de conversão do funil limpas da logística de documentos.

## Considered Options

- Colunas pós-ganho preservando `won_at` — rejeitada: mexe na mecânica de
  won/lost com risco de regressão em cascata/BI, para informar menos que o
  checklist ("Coleta" diz menos que "faltam 2 de 7").
- Segundo kanban com campo próprio de status — rejeitada: estrutura paralela
  para o que o checklist já representa.

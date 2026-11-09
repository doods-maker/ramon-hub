# Plano — Extrato com duas grades + validação do apto pelo jurídico

**Spec:** `comercial\docs\2026-11-09-briefing-hub-extrato-duas-grades.md` na sede (decisões do Eduardo em 09/11/2026;
registro no `comercial\decision-log.md`, entrada 2026-11-09).
**Skills (regra do Eduardo):** `mattpocock-skills:codebase-design` (costuras abaixo), `mattpocock-skills:tdd` (spec
antes do código, uma fatia vertical por vez), `mattpocock-skills:code-review` antes do merge, `mattpocock-skills:pr`
no corpo do PR. Sem Ruby local: o vermelho/verde do RSpec é o CI; vitest roda local.

## Costuras (codebase-design)

1. **`Ramon::ContratoApto`**: módulo fundo. Interface: `validadores(lead)`, `pode_validar?(lead, user)`,
   `prazo(lead)`, `validar!(lead, user)`, `devolver!(lead, user, motivo)`, `reenviar!(lead, user)`,
   `designar!(lead, validador)` e `rodar!(agora)` (entra na fila + apto por prazo; chamado pelo job). Esconde a
   regra de quem valida (designado no lead → validadores da tese → administradores), o relógio de 5 dias úteis
   (seg–sex, sem `Ramon::Agenda::Feriados`), as notificações e os carimbos.
2. **`Ramon::ExtratoVariavel`**: continua sendo a única porta do extrato (`pessoas`). Por dentro, uma grade por
   papel (`sdr`, `closer`, `hibrido`) com a mesma forma: unidades do mês → linha. DSR e Programa ficam internos.
   `Ramon::ExtratoDescontos` sai: depois de apto a comissão é devida (regulamento §4), então não há mais desconto.

## PR 1 — Apto + botão de validação (`feat/extrato-duas-grades`, parte 1)

Migração `leads`: `validacao_desde`, `apto_em`, `apto_por_id` (nil = apto por prazo), `devolvido_em`,
`devolvido_por_id`, `devolvido_motivo`, `validador_id`. Migração `theses`: `validador_ids bigint[] default {}`,
`comissao_apto decimal(8,2)` (usada no PR 2).

Fatias TDD (spec primeiro, cada uma):
1. `rodar!`: contrato limpo sem `validacao_desde` entra na fila (carimbo = `contrato_limpo_em`) e notifica os
   validadores (sino, `ramon_fluxo_aviso`).
2. `prazo`: 5 dias úteis; sexta + feriado; `rodar!` dá apto por prazo (`apto_por_id` nil) e avisa o Closer.
3. `validadores`: designado > tese > admins; `pode_validar?` = admin ou validador.
4. `validar!` / `devolver!` (motivo obrigatório) / `reenviar!` (relógio novo) + aviso ao Closer.
5. Cancelamento: sair de Fechado antes do apto tira da fila (já some com `contrato_limpo_em`); depois do apto,
   `apto_em` fica (só `contrato_cancelado_em` é gravado).
6. Endpoint `POST leads/:id/apto` (`acao` = validar | devolver | reenviar | designar), 403 para quem não pode;
   JSON do lead com os campos + `apto_prazo` + `pode_validar`.
7. Tese: `validador_ids` e `comissao_apto` nos parâmetros e na tela Playbooks.
8. Painel do lead: `LeadApto.vue` (situação + botões + designar), vitest.
9. Job horário `Ramon::ContratoAptoJob` (schedule.yml).

Fica para depois (anotado): lista "Aguardando validação" em lote; responsável do ADVBOX como validador
(hoje o processo nasce com usuário fixo); feriados de Tubarão em `Feriados::MUNICIPAIS` (Eduardo informa).

## PR 2 — Extrato nas duas grades

1. `MetaComercial`: papel aceita `hibrido`; `fator` (padrão 1,0); `rampa` sai da tela (coluna ignorada).
   Papel da pessoa no mês = meta do mês → última meta lançada → time.
2. Grade SDR (A): reuniões qualificadas do mês, em ordem; até a meta (padrão 50) R$ 8, acima R$ 12; × fator.
3. Grade Closer (A): aptos do mês (`closer_id`, `apto_em`); até a meta (padrão 20) R$ 30, acima R$ 45; × fator.
4. Grade Híbrido (B): aptos × `thesis.comissao_apto` (sem valor → R$ 0 + marca); Programa do mês (faixa, gás).
5. DSR = variável × (domingos e feriados ÷ dias de seg a sáb); bônus do Programa sem DSR por cima.
6. Programa trimestral (`ramon_programas_metas`: início, fim, regras) + constância no mês seguinte ao trimestre.
7. Tela Extrato: papel com Híbrido, fator, linhas novas, formulário do Programa; nomes "comparecimento" e
   "fechamento" no Painel do time.
8. Apaga `ExtratoDescontos` e as specs da grade antiga.

Fica para depois: cálculo automático do fator do trimestre (o 1º trimestre é 1,0; antes de 01/02/2027).

## PR 3 — Sobras (decisões do Eduardo em 09/11/2026, noite)

- Lista "Aguardando validação" (`ValidacaoApto.vue`, `GET lead_aptos` + `POST lead_aptos/validar_lote`).
- Tese sem advogado fixo: o responsável do processo no ADVBOX vira o designado ao entrar na fila (`Ramon::ResponsavelAdvbox`).
- Quem agendou: `leads.reuniao_pela_ia` (tarefa da reunião sem criador); só a marcada pela IA deixa de pagar o SDR.
- Fator automático (`Ramon::FatorTrimestre` + `FatorQualidade`): calculado no 1º dia do trimestre com o que se sabe e
  guardado; o gestor corrige digitando o fator (vazio = o calculado); 1º trimestre da pessoa = 1,0.
- Quanto falta no cartão do Extrato: meta do mês, conta do fator, reuniões da IA, próxima faixa e constância até aqui.
- Feriados municipais: não entram (decisão do Eduardo).

# Sala de Fechamento — Design (parcial, decisões de 07/07)

**Contexto:** Onda 2 do "Organismo" (`comercial\docs\specs\2026-07-05-plano-sem-freios.md`).
Esta spec registra as decisões destravadas em 07/07 e separa o que já dá pra codar do
que espera gates do Eduardo. O detalhamento fino de cada componente fica pro writing-plans.

## Decisão do Eduardo (07/07) — honorário

**Estrutura ÚNICA para todas as teses:** `honorário = percentual × atrasados + N × mensalidade_do_benefício`.
Varia só o **percentual** e o **N** por tese. Não há tese com estrutura diferente (valor
fixo, % sobre benefício anual, etc.).

- Semente obrigatória: **auxílio-acidente = 30% + 3 mensalidades** (padrão fixo da casa,
  do `comercial\CLAUDE.md`).
- As demais teses: o Eduardo cadastra `%` e `N` **por config na UI**, sem código.

## Componentes e fatiamento

### PRONTO PRA CODAR (hub, sem gate)
- **Tabela de honorário por tese** — nova config: cada `thesis` (ou `benefit_type`) ganha
  `honorario_percentual` e `honorario_n_mensalidades`. CRUD na tela de teses/config. Seed do
  auxílio-acidente (30% / 3). É o insumo do simulador.

### DEPENDE DO MOTOR (Onda 2 core)
- **Simulador ao vivo:** dado o caso, o motor calcula **atrasados estimados** e **valor
  mensal** do benefício; o hub aplica a fórmula de honorário e mostra "atrasados ~R$ X ·
  esperando você perde R$ Y/mês · honorário ~R$ Z", com disclaimer (estimativa ≠ promessa).
  Depende de: integração hub↔motor + **F2 Incapacidade** (calcula o valor dos benefícios de
  incapacidade — é a família da tese-foco auxílio-acidente).

### DEPENDE DA ONDA 3a
- **Dossiê de 30 segundos:** tela única com tudo da pessoa (indicação, o que perguntou,
  triagem, objeções da tese + respostas do playbook). Reusa a Linha da Vida (Onda 3a) +
  teses/playbooks (já no ar) + triagem (já no ar).

### GATE DEMORADO DO EDUARDO (fim)
- **Fecho em um clique:** procuração + contrato + termo LGPD pré-preenchidos → assinatura
  numa remessa (ZapSign) → dossiê pro jurídico. Gate: **conta ZapSign + modelos de
  procuração/contrato**.
- **Caixa-preta da reunião:** gravação consentida → transcrição (reusa o **Whisper**, já no
  ar) → mineração de argumentos/objeções por tese → playbook se reescreve (proposta, humano
  aprova). Gate: **texto de consentimento de gravação** (rascunho do Claude, aprovação do
  Eduardo).

## Ordem sugerida
1. Tabela de honorário por tese (pronto) — pequeno, habilita o simulador.
2. Simulador (após F2 Incapacidade + integração motor).
3. Dossiê (após Onda 3a).
4. Fecho-em-1-clique e Caixa-preta (após os gates do Eduardo).

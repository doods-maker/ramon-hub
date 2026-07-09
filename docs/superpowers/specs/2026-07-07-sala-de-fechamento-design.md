# Sala de Fechamento — Design (parcial, decisões de 07/07; colheita estruturada 09/07)

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

## Colheita estruturada da reunião (aprovado pelo Eduardo 09/07)

**Princípio (engenharia reversa):** a petição inicial define o que a reunião precisa colher.
Do acervo real de petições do jurídico (03/07), extrair por tese — começando por
auxílio-acidente — **4 artefatos**:

1. **Checklist de colheita** — o que a reunião PRECISA cobrir, em qualquer ordem; aparece ao
   vivo no **Kit do Closer** (já no ar) com "o que ainda falta perguntar".
2. **Schema de extração** — campos canônicos de fatos/direito que a IA preenche a partir da
   transcrição (a extração por LLM não exige conversa ordenada; exige schema).
3. **Lista de documentos por tese** — cada fato do schema aponta o documento que o prova;
   lacuna no schema vira pedido de documento (rascunho, Eduardo aprova).
4. **Roteiro sugerido** — ordem de perguntas recomendada como apoio humano ao closer/advogado
   (guia, não trilho: a extração funciona mesmo se a conversa fugir da ordem).

**Fluxo completo:** reunião gravada (gate consentimento) → Whisper → extração contra o schema
da tese → preenche o caso + aponta lacunas → alimenta dossiê W3, notas do caso no AdvBox
(item 21 do plano mestre) e, adiante, fatos/direito da inicial. Isso **upgrada a Caixa-preta**:
de "minerar objeções pro playbook" para extração estruturada de fatos também.

**Primeiro passo (sem código, sem gate):** sessão de engenharia reversa sobre o acervo de
petições → produzir os 4 artefatos de auxílio-acidente como rascunho pra aprovação do Eduardo.

## Ordem sugerida
1. Tabela de honorário por tese (pronto) — pequeno, habilita o simulador.
2. Simulador (após F2 Incapacidade + integração motor).
3. Dossiê (após Onda 3a).
4. Fecho-em-1-clique e Caixa-preta (após os gates do Eduardo).

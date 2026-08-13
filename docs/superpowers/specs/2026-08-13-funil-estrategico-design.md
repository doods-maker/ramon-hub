# Funil estratégico do comercial — design

> ⚠️ **NÃO EXECUTAR.** Este é o registro do entendimento fechado na sessão de
> grilling de 2026-08-13 (Eduardo + Claude). Execução depende de plano de
> implementação aprovado à parte.

Visão: o ramon-hub como hub estratégico da área comercial — o funil de TODO o
comercial digital, do canal de aquisição ao caso completo entregue ao jurídico.
Vocabulário canônico em `CONTEXT.md`; decisões estruturais em `docs/adr/0001` e
`docs/adr/0002`.

## O que já existe e permanece intocado

- Funil de 8 etapas no banco (Novo → … → Fechado/Perdido), editável na UI.
- Ganho dispara cascata (handoff jurídico + cadastro ADVBOX + NPS); Perdido
  exige motivo de catálogo. Nada disso muda.
- Canal/Origem/UTM como dimensões do lead; SLA de 1ª resposta; parado por
  etapa; cadência de tarefas; triagem por IA; checklist de documentos por
  tese; portal do cliente com upload.

## Decisões (por região do funil)

### Topo — aquisição

1. **Canal é dimensão, nunca coluna do kanban.** Indicação entra no funil como
   lead normal (canal `indicacao`); fica fora apenas das métricas de aquisição
   paga (CPL/ROI). Orgânico presencial fica fora do hub.
2. **Derivação automática de canal completa** (hoje só `meta_ads` via referral
   e `landing_page` via endpoint das LPs; o resto cai em `outro`):
   - WhatsApp sem referral e sem assinatura → `indicacao` (regra do negócio:
     nos números da banca, quem chega sem anúncio é indicado).
   - Botões de WhatsApp do site institucional, das LPs e da bio do Instagram
     passam a abrir conversa com texto pré-preenchido identificável; o hub
     deriva `google_seo` / `landing_page` / `instagram` pela 1ª mensagem.
   - Ninguém pergunta origem ao lead; nada depende de digitação manual.

### Meio — qualificação

3. **Respostas do quiz das LPs viajam junto** com o lead (hoje se perdem — só
   nome/telefone/campanha chegam) e ficam estruturadas, visíveis ao SDR e
   consumíveis pela triagem por IA.
4. **Lead qualificado pela LP nasce em "Qualificação"**, não em "Novo" — o SDR
   confirma com documento, não recomeça a qualificação. Nunca pula direto pra
   reunião (quiz é auto-declaração).
5. Operação: Eduardo + triagem automática (quiz + agente IA) como primeira
   linha; estrutura pronta pra SDR humano entrar depois (sdr_id/closer_id já
   existem).

### Fundo e pós-venda

6. **Pós-venda é do comercial** (Eduardo; controller como apoio — o hub pode
   criar tarefa no ADVBOX pra ela via API, que isso a API faz).
7. **Sem colunas pós-ganho** (ADR-0001): lead ganho fica em "Fechado"; o
   pós-venda é o Checklist de Documentos + visão "Pós-venda" (ganhos com docs
   pendentes, ordenados por dias desde o ganho, com ação de cobrança).
   **"Concluído"** = checklist completo + pacote no Drive = fim real do funil.
8. **Checklist de documentos redesenhado** (os 4 sintomas confirmados):
   - aba "Documentos" própria no painel do lead (hoje enterrado);
   - "Cobrar pendentes" vira rascunho dentro da caixa de resposta da conversa
     (Eduardo revisa e envia — princípio de aprovação preservado; hoje é
     clipboard);
   - anexo recebido (conversa ou portal) → IA sugere o item correspondente
     ("parece o RG — marcar recebido?") com confirmação de um clique;
   - badge "docs X/Y" no card do kanban.
9. **Portal do cliente segue como apoio, WhatsApp em primeiro.** Sem
   investimento novo no portal além do casamento anexo↔checklist (que serve
   aos dois caminhos, pois o upload do portal já vira mensagem na conversa).

### Ponte ADVBOX (ADR-0002)

10. A API do ADVBOX não sobe documentos. Hub → **Drive automático e
    incremental**: cada doc conferido vira PDF renomeado em
    `Clientes\<Nome — CPF>\`; atalho do dia em `A enviar ao ADVBOX\<data>\`;
    checklist completo → pasta renomeada com sufixo `— COMPLETO`.
    Eduardo → ADVBOX: manual, diário; apagar a pasta do dia é o "feito".

### Estratégia visível

11. **Valor estimado automático por tese** (honorário da tese × valor do
    benefício, assim que conhecidos; ajustável à mão) desde a qualificação.
    Previsão = Σ (valor estimado × probability da etapa). No ganho, vira o
    valor do contrato.
12. **Cabeça das colunas do kanban** mostra contagem + valor somado +
    conversão pra próxima etapa. Metabase segue como análise profunda.
13. **Fim do drift do BI**: views SQL versionadas no repo (migrations) —
    `bi_leads` etc. — encapsulam as regras (o que é lead de funil, ganho,
    perdido, UTM); os cards do Metabase viram `SELECT` simples sobre as views.
    Regra muda no código → view muda na mesma PR.

## Métricas-alvo (o hub estratégico responde)

1. Leads novos por origem na semana + custo por lead (com dados de ads).
2. Vazamento do funil (conversão etapa a etapa).
3. Parados além do SLA que precisam de follow-up hoje.
4. Receita potencial por etapa/tese (valor estimado).
5. Previsão de contratos/receita do mês (valor × probabilidade).

## Fora de escopo desta rodada

- Automação de navegador na UI do ADVBOX (rejeitada — frágil).
- Perguntar origem ao lead na triagem (desnecessário — derivação cobre tudo).
- Portal como protagonista do pós-venda.

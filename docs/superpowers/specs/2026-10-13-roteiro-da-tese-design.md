# Roteiro da tese — atendimento por IA que cresce com as teses

**Data:** 13/10/2026 · **Status:** desenho aprovado em conversa (blocos 1–4) — aguarda revisão desta spec
**Origem:** levantamento dos agentes da LiderHub (`comercial\docs\2026-10-13-relatorio-agentes-liderhub.md`)

## 1. Problema e objetivo

A LiderHub atende no WhatsApp com 18 agentes em 4 grupos (auxílio-acidente ×2, BPC, maternidade). Tirando os
nomes, cada grupo é **um roteiro de qualificação por tese**: perguntas em ordem, e cada resposta leva a *segue*,
*pula etapa*, *desqualifica* ou *chama humano*, com troca de status/etiqueta como efeito. O custo do modelo deles:
prompts acima do limite do modelo (110–170%), as mesmas regras copiadas em todo prompt, contas feitas pela IA com
números divergentes, e **cada tese nova = clonar 3–8 agentes**.

O hub quer muitas teses. Objetivo: trazer a ideia central (roteiro + consequências automáticas) **sem** multiplicar
agentes. Critérios de sucesso (Eduardo, 13/10 — os três):

1. **Lead chega sozinho ao limite escolhido** (qualificação, reunião marcada ou contrato enviado).
2. **Equipe ganha velocidade:** SDR/Closer recebem a conversa com o roteiro respondido e o motivo de cada desfecho.
3. **Configurar sem programar:** tese nova = preencher o Playbook (roteiro + FAQs + honorário + contrato).

## 2. O que já existe e é reaproveitado

| Peça | Onde | Papel no roteiro |
|---|---|---|
| Tese como cadastro (`theses`, `thesis_items` por seção, honorário) | `app/models/thesis*.rb`, tela Playbooks | O roteiro vira mais uma parte do Playbook |
| Assistente **Atendimento** + skills (Captain scenarios) | `db/seeds/ramon/inteligencia/assistentes.yml` | Continua um só; a skill de triagem passa a seguir o roteiro |
| Modos por conversa (`manual/rascunho/piloto_limitado/piloto_total`) | `enterprise/lib/ramon/copiloto_modo.rb`, `response_builder_job.rb` | Ganha 3 modos "sozinho até…" |
| Lead nasce da conversa | `app/services/ramon/lead_da_conversa.rb` | Ganha a definição automática da tese |
| Qualificação viva (`qualificacao_status`) | `QualificacaoViva.vue`, `registrar_qualificacao_tool.rb` | Fica para teses **sem** roteiro; com roteiro, o painel mostra o roteiro |
| Honorário, Cal.com, ZapSign, triagem da LP, FAQ por tese | tools `simular_honorario`, `link_agendamento`, `preparar_contrato_zapsign`, `triagem_da_lp`, `faq_lookup` | Seguem (honorário passa a seguir o JUR-02 — 3.11; ZapSign ganha aplicação automática só no modo "até contrato") |
| Sino + push (`Ramon::NtfyPushJob`), etapa Perdido, etiquetas | — | Efeitos das saídas |
| Cadência (fluxo #36) | Automações | Faz o papel do follow-up por status da LiderHub — fora do escopo |

## 3. Desenho

### 3.1 O roteiro (dados)

Tabela nova **`roteiro_passos`**:

| Coluna | Tipo | Nota |
|---|---|---|
| `account_id` | bigint | |
| `thesis_id` | bigint, **nulo = passo comum da conta** | passos comuns rodam antes do roteiro de qualquer tese |
| `position` | int | ordem |
| `chave` | string | identificador estável (`recebeu_auxilio_doenca`); único por tese (ou por conta, nos comuns) |
| `titulo` | string | o que descobrir, em linguagem de gente |
| `orientacao` | text | como perguntar / sinais a observar (vai para a IA) |
| `tipo_resposta` | string | `sim_nao` · `escolha` · `numero` · `data` · `texto` |
| `opcoes` | jsonb | valores possíveis quando `escolha` |
| `calculadora` | string nulo | nome de uma calculadora (3.3) |
| `calculadora_campos` | jsonb | qual chave de resposta alimenta cada campo da calculadora |
| `saidas` | jsonb | lista ordenada de `{id, quando, acao, alvo, motivo, mensagem, efeitos:{etiqueta, etapa}}` |
| `edited` | bool | editado na tela → o seed não sobrescreve (mesmo padrão das skills) |

- `quando`: valor (`sim`, opção), faixa (`< 64`, `>= 65`), resultado da calculadora (`dentro`/`fora`/`depende`) ou
  `*` (qualquer outro). Avaliado na ordem; a primeira que casa vale.
- `acao`: `seguir` (próximo passo) · `ir_para` (`alvo` = chave) · `desqualificar` (`motivo` obrigatório) ·
  `humano` (`motivo` obrigatório) · `concluir` (roteiro terminou = **qualificado**).
- `mensagem`: texto-base opcional que a IA usa para a resposta daquela saída (ex.: encerramento de desqualificação).
- Último passo sem saída `concluir` explícita: `seguir` no último passo = `concluir`.

Teses **sem** passos continuam no comportamento de hoje (checklist de critérios).

### 3.2 Estado no lead

`lead.custom_attributes['roteiro']`:

```json
{ "tese_id": 3, "passo": "sequela", "desfecho": null, "motivo": null,
  "respostas": { "tem_advogado": {"valor": "nao", "em": "…"}, "graca": {"valor": "dentro", "calc": {…}, "em": "…"} } }
```

`desfecho` ∈ `qualificado · desqualificado · humano`. Trocar a tese do lead reinicia o roteiro (respostas dos
passos comuns ficam).

### 3.3 Calculadoras (Ruby, exatas, testadas)

`Ramon::Roteiro::Calculadoras` — cada uma recebe campos e devolve `{resultado, detalhe}`:

| Nome | Entrada | Resultado |
|---|---|---|
| `periodo_de_graca` | data do último vínculo, data do evento, +10 anos de contribuição?, desemprego comprovado? | `dentro` · `fora` · `depende` (regras 12/24/36 meses do relatório §2.2 #02) |
| `renda_per_capita` | renda total, nº de moradores | `abaixo` · `acima` do ¼ do salário mínimo (+ valor) |
| `prescricao_5_anos` | data | `dentro` · `prescrito` |
| `meses_ate_65` | data de nascimento | `ja_tem_65` · `faltam_N` (N em `detalhe`) |
| `data_prevista_parto` | semanas de gestação | data |
| `prazo_inss` | data do requerimento, data da perícia | `aguardar` · `forcar_julgamento` (45 dias da perícia / 90 do requerimento) |
| `honorario` | já existe (`Ramon::Honorario`) | — |

**Salário mínimo num lugar só:** `Ramon::SalarioMinimo.vigente(data)` com tabela por ano no código (valor oficial
conferido antes do seed; atualizar todo janeiro — entra no checklist de jan/2027 junto com as LPs).

### 3.4 Motor (regra fixa — a IA não decide consequência)

`Ramon::Roteiro`:

- `atual(lead)` → passo corrente (comuns primeiro, depois os da tese) com título, orientação, tipo, opções e o que
  já foi respondido.
- `registrar(lead, chave:, valor: nil, saida_id: nil)` → grava a resposta, roda a calculadora se houver, escolhe a
  saída (por `valor` casando `quando`; em `tipo_resposta: texto` a IA informa `saida_id` entre as listadas), aplica
  os efeitos e devolve o próximo passo ou o desfecho.

Efeitos, todos por código já existente:

| Ação | Efeitos |
|---|---|
| qualquer saída com `efeitos` | etiqueta na conversa; etapa do lead movida direto (configurada pelo admin = regra fixa, não sugestão) |
| `desqualificar` | lead → etapa Perdido com `lost_reason` = motivo + etiqueta `desqualificado-ia`; conversa → modo `manual` depois da mensagem de encerramento |
| `humano` | handoff da conversa + sino + push ao responsável/Eduardo com o motivo; modo → `rascunho` |
| `concluir` | `desfecho=qualificado`; move para a etapa escolhida na saída `concluir` (vazio = não move) |

Todas as aplicações gravam `LeadActivity` (histórico do lead já existente).

### 3.5 O agente

- Continua **um** assistente Atendimento. A skill "Triagem e qualificação" passa a: chamar
  **`roteiro_passo_atual`**, perguntar (uma pergunta, 1–2 frases), entender a resposta e chamar
  **`roteiro_registrar`**; repetir até desfecho. Sem roteiro na tese → instrução atual.
- **Regras globais** em `response_guidelines` (uma vez, valem para todas as teses): uma pergunta por vez, 1–2
  frases; nunca dizer que está transferindo; não repetir o que o lead já disse; quer contratar / pede humano →
  `humano`; 2ª pergunta sobre valor → `humano`; não sabe ler → `humano` com motivo; dúvida → FAQ antes.
- **Passos comuns da conta** (seed): nome · assunto (só quando o lead está sem tese — 3.6) · já tem advogado no
  caso (sim → desqualificar, motivo "tem advogado", etiqueta `TemAdvogado`). "Já recebe benefício" fica no roteiro
  de cada tese, porque a consequência muda por tese (BPC desqualifica; auxílio-acidente depende da aposentadoria).

### 3.6 De onde vem a tese

- `theses.palavras_chave` (array de texto) e `inboxes` ganha **tese padrão** (`ramon_thesis_id`).
- Em `Ramon::LeadDaConversa.origem` (1ª mensagem): se o lead está **sem tese** → 1º palavra-chave na 1ª
  mensagem (texto ou `referral.headline` da Meta), 2º tese da caixa. Lead da LP já nasce com a tese do quiz.
- Sem tese ao fim disso → o passo comum "assunto" pergunta e a resposta casa com nome/palavras-chave das teses
  (sem casar → `humano`).

### 3.7 Modo "sozinho até…"

- Novos modos em `Ramon::CopilotoModo::MODOS`: `piloto_ate_qualificacao`, `piloto_ate_reuniao`,
  `piloto_ate_contrato`. Até o limite, **envia direto** (como `piloto_total`).
- Limite atingido quando: qualificação → `roteiro.desfecho` presente; reunião → lead em `fase-reuniao-agendada`
  ou adiante (webhook Cal.com já move); contrato → `custom_attributes.zapsign.sign_url` presente.
- Ao atingir: conversa vira `rascunho` (carimbo no `copiloto_modo`) + sino "IA chegou ao limite" ao responsável.
  Desfecho `desqualificado`/`humano` antes do limite também encerra o envio direto (3.4).
- **Padrão por caixa:** `inboxes.ramon_copiloto_modo` (vazio = env `RAMON_COPILOTO_MODO_DEFAULT`, como hoje).
  `CopilotoModo.default` passa a receber a conversa e olhar a caixa primeiro. Troca por conversa segue no
  `CopilotoModoSelector`.
- `piloto_ate_contrato`: `preparar_contrato_zapsign` **aplica a sugestão na hora** (gera o documento e devolve o
  link para a IA enviar) — só nesse modo e só com nome completo, CPF e endereço confirmados no lead. Nos outros
  modos segue pendente no Cockpit. A diretriz "nunca afirme que contrato já existe" fica condicionada ao modo.
- Desqualificação em modo piloto sai direto; a etiqueta `desqualificado-ia` + o funil (3.9) servem de revisão.

### 3.8 Telas (padrão branco/preto do hub; mockup → prints aprovados antes do PR)

1. **Playbook da tese → aba "Roteiro":** lista vertical de passos (cartões); cada cartão abre gaveta com título,
   orientação, tipo, opções, calculadora + campos, e as **saídas** (uma linha por saída: *quando* → *ação* →
   alvo/motivo/mensagem/efeitos). Reordenar arrastando. Campo **palavras-chave** no cabeçalho da tese.
2. **Passos comuns:** mesma lista, no topo da tela de Playbooks ("Valem para todas as teses").
3. **Caixa (configurações da inbox, onde já fica "Criar lead"):** tese padrão + modo padrão.
4. **Painel do lead:** com roteiro, a Qualificação viva mostra passo a passo (respondido / atual / pendente),
   resultado das calculadoras e o desfecho com motivo.
5. **Inteligência → Testar:** escolher a tese e conversar; o roteiro roda em memória (não grava lead).

### 3.9 Métricas

View `bi_roteiro` (scenic, sobre `leads.custom_attributes->'roteiro'`): lead, tese, passo atual, desfecho, motivo,
modo da conversa, limite atingido, datas. Cards no Metabase (bloco Inteligência, script idempotente como
`scripts/metabase_bi_ia_cards.py`): funil por tese (entrou → qualificado/desqualificado/humano), **passo onde
param**, motivos de desqualificação, quantos chegaram a cada limite.

### 3.10 Conteúdo inicial

- Seed `db/seeds/ramon/roteiros/{comuns,auxilio-acidente,bpc-loas,salario-maternidade}.yml` + rake
  `ramon:roteiros:seed[conta]` idempotente (respeita `edited`). Cria a tese se não existir.
- Fonte: relatório LiderHub — auxílio-acidente parte do grupo "Teste Agosto" (o que roda hoje) completado com o
  "FER MAR26" (aposentado, regime RPPS, prazos do INSS, nexo da doença); BPC (Andreia/Carol/Bianca); maternidade
  (Juliana/Mariana).
- **Eduardo revisa** uma versão legível (md) dos 3 roteiros antes de o seed rodar em produção. Regra do hub: texto
  que fala com cliente (orientações, mensagens das saídas, regras globais novas) só é **ativado** com o aprovado
  dele — o código sobe antes; os modos "sozinho até…" só são ligados numa caixa a pedido dele.
- **Decidido 13/10** (análise em `comercial\docs\2026-10-13-roteiros-decisoes-pendentes.md`, citações
  verificadas):
  - Maternidade: R$ 6.848 era erro; R$ 6.484 = 4 × salário mínimo é o **mínimo**, não o máximo ("até" proibido);
    valor sai da calculadora. Roteiro de 7 passos do documento; **mãe rural/pescadora → humano**; carteira ativa
    no parto → humano (trabalhista).
  - Honorário: **fonte da verdade = POP JUR-02** (3.11). Maternidade está fora da tabela → IA não cita valor.
  - Auxílio-acidente: **meio-termo** — espinha do Teste Agosto + regime próprio, aposentado (atrasados até a
    véspera da aposentadoria), nexo da doença e sequela mínima comprovada do FER; situação no INSS e laudo viram
    dado para a reunião.
  - Os itens `[CONFERIR]` do documento são lidos na fonte oficial antes de o texto do roteiro ser ativado.

### 3.11 Honorário pela tabela do POP JUR-02 (decisão 13/10)

Hoje: `theses.honorario_percentual` + `honorario_n_mensalidades` só expressam "X% + N", e todas as FAQs + a
diretriz global + o guardrail do Atendimento dizem "30% + 3" (D12, 16/08). O POP JUR-02 (aprovado 06/10) diverge:
auxílio-doença adm. = 30% com mínimo 1 SB; invalidez adm. = 30% com mínimo 3 SB; BPC online, acréscimo de 25% e
salário-maternidade **fora da tabela**.

- `theses` ganha: `honorario_formula` (`soma` = "% + N" · `ou` = "% ou N" · `percentual`), `honorario_minimo_qtd`
  + `honorario_minimo_base` (`sm`/`sb`) e `honorario_na_tabela` (bool). Os valores de cada tese = a linha
  **online/tráfego** do JUR-02 (é quem fala com a IA); balcão/via judicial ficam com o advogado no JUR-02.
- `simular_honorario` e `playbook_da_tese` passam a ler esses campos. Tese com `honorario_na_tabela = false` →
  a IA **não cita valor** e passa para humano ("o advogado explica o honorário na conversa").
- Diretriz global e guardrail do Atendimento deixam de cravar "30% + 3" e passam a mandar consultar a tese.
  FAQs por tese reescritas conforme o JUR-02 (texto = gate do Eduardo).

## 4. Fora do escopo

Voz/áudio gerado · follow-up por status (cadência cobre) · limite de crédito por conversa (teto diário de IA já
existe) · vários agentes por tese · reunião pelo Google Calendar (Cal.com segue) · agente de andamento do processo
(Copiloto/Painel do Cliente cobrem).

## 5. Erros e segurança

- Ferramenta do roteiro falha → a IA segue sem ela e a resposta vira rascunho (fail-safe, igual ao
  `piloto_limitado` sem classificação).
- Saída inválida (`ir_para` para chave inexistente, passo sem saída casando) → `humano` com motivo "roteiro sem
  saída" + aviso ao admin; validação também no salvar da tela.
- Calculadora com campo faltando → devolve `depende` → a saída configurada (normalmente `humano`).
- Dados pessoais: respostas ficam no lead (já é dado do caso); `bi_roteiro` não expõe texto livre das respostas.
- Envio direto só nos modos piloto escolhidos por caixa/conversa — rascunho segue padrão onde nada for escolhido.

## 6. Entrega em fatias (cada uma com PR, CI, smoke)

0. **F0 — Honorário pelo JUR-02 (antes de tudo; corrige o que está no ar):** campos de honorário da tese (3.11),
   `simular_honorario`/`playbook_da_tese`, diretriz + guardrail + FAQs reescritos (rascunho → aprovado do Eduardo
   → seed), rake que preenche as teses pela tabela.
1. **F1 — Motor:** migração (`roteiro_passos`, `theses.palavras_chave`, `inboxes.ramon_thesis_id`,
   `inboxes.ramon_copiloto_modo`), `Ramon::Roteiro`, calculadoras, `SalarioMinimo`, tools `roteiro_passo_atual` /
   `roteiro_registrar`, skill de triagem + regras globais no seed. Specs unitários das calculadoras e do motor;
   prova e2e no console (Playground runner).
2. **F2 — Telas:** aba Roteiro, passos comuns, palavras-chave, painel do lead, Testar com tese.
3. **F3 — Tese automática + modos "sozinho até…":** `LeadDaConversa`, `CopilotoModo` (3 modos + padrão por
   caixa + limite), ZapSign automático no modo contrato, configurações da caixa.
4. **F4 — Conteúdo + métricas:** 3 roteiros + comuns (após revisão do Eduardo), `bi_roteiro`, cards Metabase.

Efeito real em produção depende dos números por tese no WhatsApp oficial (hoje o assistente só está na caixa
Teste) — até lá, prova na caixa Teste.

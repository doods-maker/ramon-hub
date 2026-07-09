# Linha da Vida (pessoa ≠ caso) — Design

**Data:** 2026-07-07
**Contexto:** Onda 3 do plano "Organismo" (`comercial\docs\specs\2026-07-05-plano-sem-freios.md`).
A decisão de modelagem pessoa≠caso era o gate mais importante do organismo. Fechada
com o Eduardo em 07/07. Esta spec é o design de implementação; o plano (writing-plans)
e o código vêm depois.

## Problema

Hoje o hub trata "lead" como entidade central, misturando **pessoa** e **caso**.
Isso impede a visão que o organismo quer: uma pessoa que o escritório acompanha ao
longo de 20 anos, com vários casos/benefícios ao longo da vida, e um calendário de
direitos futuros que gera demanda sem gastar anúncio.

## Decisões do Eduardo (07/07)

1. **Três níveis, não dois:** pessoa → interesse (lead no funil) → **caso** (contrato
   fechado sobre um benefício). Cada contrato = um benefício = um caso. Uma pessoa
   acumula vários leads *e* vários casos ao longo do tempo.
2. **Hub só registra o caso (leve); AdvBox gerencia** o processual (andamentos, prazos,
   peças). O hub guarda o caso pra Linha da Vida, LTV e Placar — não reinventa o AdvBox.
3. **CPF estruturado** vira a chave de identidade da pessoa (pra importar a base do
   AdvBox e cruzar com o processual; mais estável que telefone).
4. **Calendário de direitos por data de nascimento, NÃO por CNIS.** Exigir CNIS de cada
   pessoa é inviável (obtenção, armazenamento, LGPD). O calendário v1 usa **marcos
   etários** (data de nascimento, que já vem do AdvBox) + DCB/prescrição que o hub já
   tem. CNIS = refinamento **pontual por caso ativo**, opt-in, nunca pré-requisito.

## Descoberta técnica (a fundação já existe)

Varredura do código (07/07) confirmou:
- **`Contact` já é a pessoa** — identidade estável, unicidade por telefone/email/identifier
  (`app/models/contact.rb`). Falta só `has_many :leads` e os campos CPF/nascimento.
- **`Lead` já é o caso/episódio** — todos os atributos de negócio (tese, benefício, funil,
  `value`, `won_at`/`lost_at`, prescrição, triagens) são do Lead, não do Contact
  (`app/models/lead.rb`, `db/schema.rb:1069`). O único acoplamento pessoa→caso é
  `leads.name` (label snapshot do card).
- **O banco já permite N leads por pessoa** — índice `contact_id` não-único
  (`schema.rb:1097`). O que força ~1 lead vivo por pessoa é só a **lógica de dedup** nos
  caminhos de criação (`ramon_lead_listener.rb:11`, `leads_controller.rb:37-49`,
  `ramon_leads_controller.rb:58-63`), que re-aponta em vez de criar novo.

Conclusão: **não se cria entidade "Caso" nova.** O Lead `won` já é o registro leve do
caso. A modelagem é: reusar Contact como pessoa, manter Lead como episódio, permitir N.

## Modelagem

- **Pessoa = `Contact`** + colunas novas `cpf` (string, indexada, única por conta quando
  presente) e `data_nascimento` (date). `has_many :leads`.
- **Lead = episódio**, ciclo de vida atravessando comercial→jurídico:
  - no funil (stage não-won/não-lost) = **interesse**;
  - `won` = **caso** (contrato fechado sobre o `benefit_type`/`thesis`);
  - `lost` = interesse perdido (fica no histórico da pessoa).
- **N casos por pessoa:** relaxar a dedup. Critério **novo caso vs reengajamento**:
  - mesmo benefício/tese com lead ainda **aberto** → reengaja o existente (comportamento
    atual);
  - benefício/tese **diferente**, ou todos os leads da pessoa **fechados** (won/lost) →
    cria **novo** lead/caso vinculado ao mesmo Contact.

## Calendário de direitos (o "futuro")

Radar de **oportunidade** (não parecer jurídico — sem tempo de contribuição não se crava
o direito; o marco etário sinaliza "vale reabordar").

- **Marcos etários** — calculados no próprio hub a partir de `data_nascimento` + sexo, com
  uma tabela versionada das idades-alvo das regras (aposentadoria por idade pós-EC103:
  65 H / 62 M; transições etárias). Gera itens tipo "atinge a idade da regra X em
  <ano-mês>". **Não chama o motor** (idade é aritmética de data + tabela fixa).
- **DCB/cessação e prescrição** — o hub já calcula (`dcb_em`, `benefit_monthly_value`,
  `Lead#prescription`). Entram no mesmo calendário.
- **CNIS = refinamento pontual por caso ativo** (3b): quando um caso tem CNIS carregado, o
  motor calcula elegibilidade/valor finos (aposentadoria por tempo/pontos, RMI). Opt-in.

## Fatiamento

### 3a — Linha da Vida + calendário etário (100% hub, zero dependência externa)
Pronta pra codar já. Componentes:
- **Migração:** `contacts.cpf` (string, índice único parcial por conta) + `contacts.data_nascimento` (date). `Contact has_many :leads`.
- **Relaxar dedup** nos 3 caminhos de criação de lead, aplicando o critério novo-caso vs
  reengajamento acima. Preservar retrocompat (não quebrar a captação das LPs).
- **CPF/nascimento na UI:** campos editáveis na ficha da pessoa (gaveta do lead / painel do
  contato). Validação de CPF (formato + dígito).
- **Serviço `Ramon::MarcosEtarios`** (novo, hub): dado nascimento+sexo, retorna a lista de
  marcos etários futuros (tabela de idades-alvo versionada em YAML/constante).
- **Tela "Linha da Vida"** por pessoa: passado (leads/casos anteriores + benefícios) ·
  presente (lead ativo) · futuro (marcos etários + DCB + prescrição, ordenados por data).
  Acessível do painel do contato / gaveta do lead.

### 3b — Refinamento pelo motor (depois; depende da integração hub↔motor + F2 Incapacidade)
- Integração hub → motor-calculos (serviço) para, num caso com CNIS, calcular elegibilidade
  por tempo/pontos e o valor (RMI). Requer o motor exposto como serviço acessível ao hub
  (infra nova) e o F2 Incapacidade/paridade-média maduros.

## Fora de escopo (YAGNI)

- Entidade "Caso" separada (o Lead `won` já é o caso).
- Gestão processual no hub (é do AdvBox).
- CNIS em massa / por pessoa (só pontual, por caso, na 3b).
- Migração da base histórica dos 10.000 (é trabalho do Eduardo exportar o CSV; o **código**
  de importação é fatia própria, reusa CPF+nascimento — pode ser desenhado à parte).

## Dependências / gates

- **3a:** nenhuma — código puro do hub.
- **3b:** motor exposto como serviço + F2 Incapacidade rodando.
- **Importação da base:** CSV do AdvBox (trabalho do Eduardo; o código de import é fatia A à parte).

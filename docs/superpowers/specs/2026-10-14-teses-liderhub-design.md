# Teses novas da LiderHub — trabalhista, isenção de IR e consulta de andamento

**Data:** 14/10/2026 · **Status:** desenho fechado em conversa (grilling 14/10) com o Eduardo
**Origem:** `Downloads\relatorio-agentes-liderhub-trabalhista-andamentos-ir.md` (pastas TRABALHISTA COMPLETO,
Trabalhista + Acidente, Isenção de IR, Andamentilson)
**Base:** o Roteiro da tese já no ar (`2026-10-13-roteiro-da-tese-design.md`, F0–F4). Nada de agente novo.

## 1. Princípio

**Cada tese = 1 número (caixa com tese padrão) + 1 LP com mensagem pronta.** A tese não muda dentro do roteiro;
caso que pertence a outra tese → `humano` com o motivo. (Avaliamos uma saída "trocar de tese"; descartada por
simplicidade — o humano resolve o caso raro.)

Da LiderHub vem só a **estrutura** (perguntas e saídas). Persona, "empresa como inimigo comum", insistência
("não aceite adiamento"), comparação com outros advogados e "nunca diga que é IA" **não** vêm. Objeções viram
FAQ/objeções da tese, reescritas dentro do Provimento 205/2021.

## 2. Teses e roteiros

### 2.1 Trabalhista — 4 teses, 4 números

| Tese | Entrada esperada | Roteiro (base LiderHub) |
|---|---|---|
| Acidente/doença do trabalho | sofreu acidente ou adoeceu pelo trabalho | AG.2: sequela (lista #LIMITAÇÃO; fora da lista → humano), saída da empresa, data do acidente/início dos sintomas, CAT/afastamento |
| Rescisão indireta | ainda trabalha na empresa | AG.4: função + queixas; a IA enquadra numa **lista fechada** de hipóteses (enquadrou → qualifica; nenhuma → desqualifica; dúvida → humano) |
| Reconhecimento de vínculo | trabalhou sem carteira, saiu há ≤ 2 anos | AG.3: as perguntas de vínculo; **a IA julga no fim** (qualifica / desqualifica / humano) |
| Direito suprimido | tinha carteira, saiu há ≤ 2 anos | AG.5: perguntas + **lista fechada** de hipóteses, igual à rescisão indireta |

- Cada roteiro confere as próprias condições de entrada (ainda trabalha? saiu quando? tinha CLT?). Não bateu →
  `humano` ("caso de outra tese").
- **Prazos** (calculadoras, nunca conta da IA):
  - saída da empresa: `prescricao_2_anos` (nova, §3) — `dentro` segue · `ultimos_meses` (21–24 meses) → humano
    URGENTE · `prescrito` → desqualifica.
  - acidente/doença: `prescricao_5_anos` (existente) — `dentro` segue · `ultimo_ano` (4–5 anos) → humano ·
    `prescrito` com sequela → humano, motivo "aux.-acidente (trabalhista prescrito)".
- Honorário: **30% do êxito** (decisão do Eduardo 15/10; o JUR-02 dizia 25%) — `honorario_formula: percentual`, a IA pode citar.
- Limite do modo "sozinha até…": **até reunião** (não há modelo ZapSign trabalhista ainda).
- Humano → responsável do lead (comercial); a Dra. Rafaela entra na reunião.

### 2.2 Isenção de IR — 1 tese, 1 número

Base: Rafaela (IR). Passos: aposentado/pensionista? → renda → doença (lista legal) → qualificado.

- Não é aposentado nem pensionista → desqualifica. **Servidor inativo (regime próprio) → desqualifica.**
- Renda abaixo do corte → **humano** (pode haver restituição dos últimos 5 anos). O valor do corte é conferido na
  lei vigente antes de ativar (a Lei 15.270/2025 não foi confirmada na fonte em 14/10).
- Sem doença da lista → desqualifica (sem etiqueta).
- Lista de doenças: art. 6º, XIV, Lei 7.713/88 — conferida pelo revisor de citações.
- Honorário: JUR-02 traz faixa (R$ 3.500 a 5.000 + 25% da restituição) definida no caso →
  `honorario_na_tabela = false` (a IA não cita valor).
- **A IA nunca pede senha gov.br.** Limite: até reunião.

### 2.3 Consulta de andamento (ADR 0008)

- Qualquer caixa, quando quem escreve diz que **já é cliente** (sai do roteiro de lead; passo comum ganha a saída).
- A IA pede **CPF + data de nascimento**; confere os dois no cadastro do ADVBOX. Não confere → humano.
- Responde a **fase em linguagem simples** (mesma lógica da fase do Painel do Cliente) + link do Painel.
  Pergunta específica (valor, data de pagamento, prazo) → humano. CPF/nascimento não ficam gravados no lead.

### 2.4 Regras globais novas (texto — gate do Eduardo)

- "Assunto fora da tese → humano com o motivo."
- "Perguntou se é robô → admite com leveza: assistente virtual do escritório; um advogado acompanha o caso."

## 3. Código

Só o que o motor não tem:

- **L1:** calculadora `prescricao_2_anos` (campo `saida`; resultados `dentro · ultimos_meses · prescrito · depende`).
  Art. 7º, XXIX, CF: ação até 2 anos depois do fim do contrato.
- **L4:** tool de consulta de andamento (ADVBOX por CPF, confere nascimento, devolve a fase) + saída "já sou
  cliente" no passo comum.

## 4. Entrega

| Fatia | O quê | Gate |
|---|---|---|
| L1 | calculadora `prescricao_2_anos` | CI |
| L2 | 4 teses trabalhistas: seed das teses + roteiros + FAQs/objeções + regras globais (2.4) | rascunho `.md` → revisor de citações → **aprovado do Eduardo** → seed |
| L3 | Isenção de IR: tese + roteiro + FAQ | idem |
| L4 | consulta de andamento | idem (texto) + CI |

**Fora do hub (Eduardo):** 5 números na Meta (4 trabalhistas + IR) e 5 LPs no `landing-pages` com a mensagem de
cada tese. Até lá, prova na caixa Teste escolhendo a tese.

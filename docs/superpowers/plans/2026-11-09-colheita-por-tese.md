# Colheita por tese (11 teses) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Skills do Matt (regra do Eduardo):** `mattpocock-skills:tdd` em toda task; `mattpocock-skills:codebase-design` na Task 1 (a costura é o `Esquema`); `mattpocock-skills:code-review` antes do merge; `mattpocock-skills:pr` no corpo.

**Goal:** a colheita (ficha de fatos que a IA extrai da conversa) passa a valer para as 11 teses do hub, com os blocos aprovados, e aparece no painel do lead para qualquer tese.

**Architecture:** um módulo novo `Ramon::Colheita::Esquema` guarda os blocos (Hash Ruby com o modelo JSON de cada um) e o mapa tese → blocos; o `ColheitaExtractionService` monta o prompt e valida a resposta a partir dele, em vez do `SYSTEM_PROMPT` fixo do auxílio-acidente. No painel, o `colheitaCampos` deixa de ter seções fixas e formata objeto/lista genericamente; o `ColheitaChecklist` mostra "O que a IA colheu" e o botão de extrair mesmo sem itens de checklist.

**Tech Stack:** Rails 7.1 / RSpec (CI), Vue 3 `<script setup>` / Vitest, i18n `en.json` + `pt_BR.json`.

**Spec:** `docs/superpowers/specs/2026-11-09-colheita-por-tese.md` (aprovada 09/11; desenho-mãe em `esteira-agentes/docs/2026-11-08-atendimento-na-esteira-design.md`).

## Global Constraints

- Sem Ruby local: testes rodam no CI; Ruby passa no `rubocop-vps` antes do commit; JS/Vue no eslint do checkout principal (`cat <f> | ../ramon-hub/node_modules/.bin/eslint --stdin --stdin-filename <f>`), depois `HUSKY=0`.
- Regras invioláveis do prompt continuam: nunca inventar dado (null + `lacunas`); incerto → `confirmar`; datas `YYYY-MM-DD` (só mês/ano = dia 15); máscara LGPD vira lacuna; a IA não calcula nada.
- `cliente` = pessoa do benefício (autor); quem conversa vai em `cliente.representante` `{nome, parentesco, motivo}`.
- Trabalhista guarda nome das testemunhas: `contrato.testemunhas[]` `{nome, relacao}` (decisão do Eduardo).
- `outras_teses_sinal[]` `{tese, motivo}` no núcleo: só aviso; nada muda a tese do lead.
- Auxílio-acidente: esquema aprovado fica; só ganha `acidente.lesao` `{descricao, cid}`, `sequela.tratamentos[]` no formato `{tipo, onde, quando}` e `beneficios[].der`/`prorrogacao_pedida` (núcleo).
- Labels i18n em `en.json` **e** `pt_BR.json` (o fork mantém os dois para `ramon.json`).
- Nenhum texto que fala com cliente muda (roteiro intocado).

## Review Focus

1. **Tese com nome fora do mapa** (conta nova, tese criada à mão): extrai só o núcleo, sem erro → teste na Task 1 (`blocos_para('Tese inventada')`) e na Task 2.
2. **"Acréscimo de 25% (grande invalidez)" contém "invalidez"** e não pode cair no B32 → teste na Task 1.
3. **Lead não-B36 com B91 cessado**: `dcb_em` (relógio do auxílio-acidente) não pode ser preenchido → teste na Task 2.
4. **Colheita antiga gravada no formato do B36** (`sequela.tratamentos` como lista de strings) continua aparecendo no painel → teste na Task 3 (`colheitaCampos` com array de strings).
5. **Campo novo sem label** mostra a chave crua (`RAMON.COLHEITA.CAMPO.x.y`) → teste na Task 3 que confere todo campo do `Esquema` contra o `en.json` e o `pt_BR.json`.

---

### Task 1: `Ramon::Colheita::Esquema` — blocos e mapa tese → blocos

**Files:**
- Create: `app/services/ramon/colheita/esquema.rb`
- Test: `spec/services/ramon/colheita/esquema_spec.rb`

**Interfaces:**
- Produces:
  - `Ramon::Colheita::Esquema::NUCLEO = %w[cliente beneficios fechamento outras_teses_sinal]`
  - `Ramon::Colheita::Esquema::BLOCOS` — `Hash{String => Hash|Array}`: modelo JSON de cada bloco (chave de topo = nome do bloco). Folha = `nil` (texto livre), `[]` (lista de texto), `"a|b|c"` (escolha uma), ou Hash/`[Hash]` aninhado.
  - `Ramon::Colheita::Esquema.blocos_para(thesis_name) -> Array<String>` (núcleo + blocos da tese, nessa ordem)
  - `Ramon::Colheita::Esquema.modelo_json(thesis_name) -> String` (`JSON.pretty_generate` do recorte de `BLOCOS` + `confirmar`, `lacunas`, `checklist_ok` como no prompt de hoje)
  - `Ramon::Colheita::Esquema.tese(thesis_name) -> Symbol | nil` (`:b31 :b32 :b36 :bpc :acrescimo25 :maternidade :ir :trab_acidente :trab_rescisao :trab_vinculo :trab_suprimido`)
  - `Ramon::Colheita::Esquema.campos(bloco) -> Array<String>` (caminhos `bloco.campo` de 1º nível; para bloco que é lista de objetos, só `bloco`) — usado no teste de labels da Task 3

- [ ] **Step 1: Write the failing tests**

```ruby
RSpec.describe Ramon::Colheita::Esquema do
  it 'B31 = núcleo + segurado, saude, incapacidade' do
    expect(described_class.blocos_para('Auxílio por incapacidade temporária (auxílio-doença / B31)'))
      .to eq(%w[cliente beneficios fechamento outras_teses_sinal segurado saude incapacidade])
  end

  it 'acréscimo de 25% não cai no B32 por conter "invalidez"' do
    expect(described_class.tese('Acréscimo de 25% (grande invalidez)')).to eq(:acrescimo25)
    expect(described_class.blocos_para('Acréscimo de 25% (grande invalidez)')).to include('dependencia').and exclude('incapacidade')
  end

  it 'mapeia as 11 teses do hub' do
    {
      'Aposentadoria por incapacidade permanente (invalidez / B32)' => :b32, 'Auxílio-acidente (B36)' => :b36,
      'BPC/LOAS (idoso ou pessoa com deficiência)' => :bpc, 'Salário-maternidade' => :maternidade,
      'Isenção de IR por doença grave' => :ir, 'Trabalhista — acidente ou doença do trabalho' => :trab_acidente,
      'Trabalhista — rescisão indireta' => :trab_rescisao, 'Trabalhista — reconhecimento de vínculo' => :trab_vinculo,
      'Trabalhista — direito suprimido' => :trab_suprimido
    }.each { |nome, chave| expect(described_class.tese(nome)).to eq(chave), nome }
  end

  it 'trabalhista de acidente reaproveita acidente e sequela do B36' do
    expect(described_class.blocos_para('Trabalhista — acidente ou doença do trabalho'))
      .to eq(%w[cliente beneficios fechamento outras_teses_sinal contrato acidente sequela responsabilidade])
  end

  it 'tese fora do mapa extrai só o núcleo' do
    expect(described_class.blocos_para('Tese inventada')).to eq(described_class::NUCLEO)
  end

  it 'o modelo do prompt traz só os blocos da tese, com representante e testemunhas' do
    b31 = JSON.parse(described_class.modelo_json('Auxílio por incapacidade temporária (auxílio-doença / B31)'))
    expect(b31.keys).to include('incapacidade', 'confirmar', 'lacunas', 'checklist_ok').and exclude('acidente')
    expect(b31.dig('cliente', 'representante').keys).to eq(%w[nome parentesco motivo])
    vinculo = JSON.parse(described_class.modelo_json('Trabalhista — reconhecimento de vínculo'))
    expect(vinculo.dig('contrato', 'testemunhas', 0).keys).to eq(%w[nome relacao])
  end
end
```

- [ ] **Step 2: Run** `bundle exec rspec spec/services/ramon/colheita/esquema_spec.rb` no CI (push na branch) → FAIL (`uninitialized constant Ramon::Colheita::Esquema`).

- [ ] **Step 3: Implement `Ramon::Colheita::Esquema`**

`BLOCOS` copia os campos da spec, seções 1–5, com os nomes exatos dela: núcleo (§1: `cliente` de hoje + `nacionalidade` + `representante`; `beneficios` de hoje + `der`, `prorrogacao_pedida: "sim|nao|nao_sabe"` e `especie` com o enum ampliado; `fechamento` de hoje; `outras_teses_sinal: [{tese, motivo}]`), P1–P7 (§3), `qualificacao`/`acidente`/`sequela` do B36 (§4, com `acidente.lesao` e `acidente.tipo` ganhando `doenca_trabalho`, `sequela.tratamentos: [{tipo, onde, quando}]`), T1–T4 (§5, com `contrato.testemunhas: [{nome, relacao}]`). Mapa por regex no nome, **em ordem** (25% antes de B32; "Trabalhista — acidente" antes de qualquer regex de acidente):

| tese | regex (i) | blocos além do núcleo |
|---|---|---|
| `:acrescimo25` | `/25\s*%\|grande invalidez/` | saude, dependencia |
| `:b31` | `/B31\|incapacidade tempor/` | segurado, saude, incapacidade |
| `:b32` | `/B32\|incapacidade permanente/` | segurado, saude, incapacidade, dependencia |
| `:trab_acidente` | `/trabalhista.*(acidente\|doen)/` | contrato, acidente, sequela, responsabilidade |
| `:trab_rescisao` | `/rescis[aã]o indireta/` | contrato, queixas |
| `:trab_vinculo` | `/v[ií]nculo/` | contrato, vinculo |
| `:trab_suprimido` | `/direito suprimido/` | contrato, queixas |
| `:b36` | `/aux[ií]lio-acidente/` | qualificacao, acidente, sequela |
| `:bpc` | `/BPC\|LOAS/` | saude, assistencial |
| `:maternidade` | `/sal[aá]rio-maternidade/` | segurado, maternidade |
| `:ir` | `/isen[cç][aã]o de IR\|imposto de renda/` | saude, ir |

- [ ] **Step 4:** `rubocop-vps`; push; CI da spec PASS.
- [ ] **Step 5: Commit** `feat(colheita): esquema por tese para as 11 teses do hub`

---

### Task 2: `ColheitaExtractionService` usa o `Esquema`

**Files:**
- Modify: `app/services/ramon/colheita_extraction_service.rb` (sai `THESIS_MATCH`, `SCHEMA_SECTIONS` e o JSON fixo do `SYSTEM_PROMPT`)
- Test: `spec/services/ramon/colheita_extraction_service_spec.rb`

**Interfaces:**
- Consumes: `Esquema.blocos_para`, `Esquema.modelo_json`, `Esquema.tese` (Task 1)
- Produces: `extractable?` = tese presente **e** conversa presente (qualquer tese); `system_prompt -> String` (privado)

- [ ] **Step 1: Write the failing tests** (no spec existente; o teste "não chama o LLM quando a tese do lead não é auxílio-acidente" sai)

```ruby
it 'extrai para B31 com o modelo de incapacidade no prompt' do
  b31 = account.theses.find_by!(name: 'Auxílio por incapacidade temporária (auxílio-doença / B31)')
  lead.update!(thesis: b31)
  allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result({ incapacidade: { parou_em: '2024-05-15' } }.to_json))
  described_class.new(lead).perform
  expect(Ramon::LlmClient).to have_received(:complete).with(hash_including(system: include('"incapacidade"')))
  expect(lead.reload.custom_attributes.dig('colheita', 'dados', 'incapacidade', 'parou_em')).to eq('2024-05-15')
end

it 'não preenche dcb_em (relógio do auxílio-acidente) fora do B36' do
  b31 = account.theses.find_by!(name: 'Auxílio por incapacidade temporária (auxílio-doença / B31)')
  lead.update!(thesis: b31)
  allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result(colheita_json))
  described_class.new(lead).perform
  expect(lead.reload.dcb_em).to be_nil
end

it 'rejeita JSON só com bloco de outra tese' do
  b31 = account.theses.find_by!(name: 'Auxílio por incapacidade temporária (auxílio-doença / B31)')
  lead.update!(thesis: b31, custom_attributes: { 'colheita' => { 'dados' => { 'cliente' => { 'profissao' => 'pedreiro' } } } })
  allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result({ contrato: { funcao: 'x' } }.to_json))
  described_class.new(lead).perform
  expect(lead.reload.custom_attributes.dig('colheita', 'dados', 'cliente', 'profissao')).to eq('pedreiro')
end
```

(Se a seed da conta de teste não tiver a tese B31, crie-a no `let` com `create(:thesis, account:, name: …)`; conferir `db/seeds`/`seed_lead_config` antes.)

- [ ] **Step 2:** CI → FAIL nos três.
- [ ] **Step 3: Implement.** `system_prompt` = parágrafo de abertura genérico ("…um cliente com possível caso de <tese>"), `Esquema.modelo_json(@lead.thesis.name)`, as regras invioláveis de hoje (mantidas palavra por palavra, menos as linhas de enum, que viram a regra "valor com `|` no modelo = escolha UMA opção") + 3 linhas novas: `cliente` é a pessoa do benefício e quem conversa vai em `cliente.representante`; `outras_teses_sinal` só quando a conversa der motivo concreto; testemunhas só com o que o lead disse. `parse` valida `obj.keys.intersect?(Esquema.blocos_para(nome) - %w[fechamento])`. `extracted_dcb` só roda quando `Esquema.tese(nome) == :b36`.
- [ ] **Step 4:** `rubocop-vps`; CI PASS (spec inteira do service, inclusive os testes antigos do B36).
- [ ] **Step 5: Commit** `feat(colheita): extração por tese a partir do esquema`

---

### Task 3: painel mostra a colheita de qualquer tese

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/helpers/colheitaCampos.js`
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/components/lead/ColheitaChecklist.vue` (wrapper com `v-if="lead?.thesis_id"`; título/contagem/lista do checklist com `v-if="colheitaItems.length"`)
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json` e `pt_BR/ramon.json` (`RAMON.COLHEITA.CAMPO.<bloco>.<campo>` para todo campo novo; bloco-lista = string única, como `beneficios`)
- Test: `helpers/specs/colheitaCampos.spec.js`, `components/lead/specs/ColheitaChecklist.spec.js`, `spec/services/ramon/colheita/labels_spec.rb`

**Interfaces:**
- Consumes: `Esquema::BLOCOS`, `Esquema.campos(bloco)` (Task 1)
- Produces: `colheitaCampos(dados, confirmar) -> [{chave, valor, confirmar}]` com ordem: `ORDEM` fixa (núcleo, depois P1–P7, A, T1–T4, na ordem da tabela da spec §2) e chaves desconhecidas no fim

- [ ] **Step 1: Write the failing tests**

```js
it('formata objeto aninhado e lista de objetos sem perder campos', () => {
  const dados = {
    cliente: { representante: { nome: 'Ana', parentesco: 'filha', motivo: null } },
    saude: { doencas: [{ nome: 'lombalgia', cid: 'M54.5', diagnostico_em: '2023-02-10' }] },
    outras_teses_sinal: [{ tese: 'B36', motivo: 'acidente no trajeto' }],
  };
  expect(colheitaCampos(dados, [])).toEqual([
    { chave: 'cliente.representante', valor: 'Ana · filha', confirmar: false },
    { chave: 'outras_teses_sinal', valor: 'B36 · acidente no trajeto', confirmar: false },
    { chave: 'saude.doencas', valor: 'lombalgia · M54.5 · 10/02/2023', confirmar: false },
  ]);
});

it('mantém colheita antiga do B36 com tratamentos em lista de texto', () => {
  expect(colheitaCampos({ sequela: { tratamentos: ['fisioterapia', 'cirurgia'] } }, []))
    .toEqual([{ chave: 'sequela.tratamentos', valor: 'fisioterapia, cirurgia', confirmar: false }]);
});
```

`ColheitaChecklist.spec.js`: lead de tese sem itens `colheita` e com `custom_attributes.colheita.dados.incapacidade.parou_em` → `[data-testid="colheita-dados"]` existe e `[data-testid="colheita-count"]` não; botão `[data-testid="colheita-extract"]` aparece com `conversation_id`.

`labels_spec.rb`: para cada bloco de `Esquema::BLOCOS` e cada caminho de `Esquema.campos(bloco)`, `en.json` e `pt_BR.json` têm `RAMON.COLHEITA.CAMPO.<caminho>` (lê os dois JSON com `JSON.parse(File.read(Rails.root.join(...)))` e `dig`).

- [ ] **Step 2:** CI (frontend-tests + backend) → FAIL.
- [ ] **Step 3: Implement.** Valor: objeto → valores não vazios formatados e juntados com `' · '`; lista de objetos → cada item assim, juntados com `'; '` (no campo) ou uma linha por item (no topo, como `beneficios` hoje); lista de texto → `', '`; datas ISO → `dd/mm/aaaa`; booleano → sim/não (como hoje). Labels pt_BR curtos, no padrão dos existentes ("Data do acidente", "Limitação no trabalho").
- [ ] **Step 4:** eslint do checkout principal nos `.js/.vue`; `rubocop-vps`; CI PASS.
- [ ] **Step 5: Commit** `feat(colheita): painel mostra a colheita de qualquer tese`

---

### Task 4: revisão e PR

- [ ] `mattpocock-skills:code-review` desde `origin/ramon` (spec = este plano + a spec).
- [ ] Registrar em `docs/FORK-PONTOS-DE-REGISTRO.md` só se algum arquivo do core upstream mudou (esperado: nenhum).
- [ ] PR com `mattpocock-skills:pr`; no Merge Danger: com a peça `colheita` do funil ligada, o observador passa a extrair para todas as teses (mais chamadas de LLM; custo em Uso e custo, função `colheita`).
- [ ] CI 100% verde → merge (regra de merge autônomo do hub) → deploy pelo Eduardo com `!` → smoke: lead de cada família (B31, BPC, trabalhista) → botão "Extrair da conversa" → ficha aparece com labels.

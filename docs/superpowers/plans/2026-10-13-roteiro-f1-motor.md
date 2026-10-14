# F1 — Motor do roteiro da tese · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a IA do Atendimento passa a qualificar o lead seguindo um roteiro de passos da tese (cadastro), e as consequências de cada resposta (segue, pula, desqualifica, chama a equipe, qualificado) são aplicadas por regra fixa no código — não pela IA.

**Architecture:** tabela `ramon_roteiro_passos` (passos por tese; `thesis_id` nulo = passo comum da conta). Quatro peças em `app/services/ramon/roteiro/`: `Calculadoras` (contas exatas), `Resposta` (normaliza a resposta e casa com o "quando" das saídas), `Efeitos` (etiqueta, etapa, Perdido, equipe + sino — etapa e Perdido viram sugestão no Cockpit fora do piloto total) e `Registro` (grava, calcula, escolhe a saída, avança). `Ramon::Roteiro` é a porta de entrada (`atual`, `registrar`, `reabrir`, textos para a IA). Recusar o Perdido sugerido pelo roteiro, ou tirar o lead do Perdido no Kanban, reabre o roteiro no passo que decidiu. Duas tools novas do Captain (`roteiro_passo_atual`, `roteiro_registrar`) chamam o motor. A skill de triagem e as regras globais mudam no seed, mas só são **ativadas** com o aprovado do Eduardo.

**Tech Stack:** Rails 7.1 (Chatwoot 4.15 fork), RSpec, Captain tools (`enterprise/lib/captain/tools/`).

**Spec:** `docs/superpowers/specs/2026-10-13-roteiro-da-tese-design.md` §3.1–3.5, §5 e §6 (F1).

## Global Constraints

- Branch `feat/roteiro-f1-motor` no worktree `ramon-hub-wt-roteiro`, criada de `origin/ramon` (063d72b). Base do PR: `ramon`.
- Tabela nova com prefixo `ramon_` (convenção do fork: `ramon_reunioes`, `ramon_fluxos`…): `ramon_roteiro_passos`, model `RoteiroPasso` com `self.table_name`.
- `db/schema.rb` editado à mão (não há Postgres local), versão do topo `2026_10_13_200001`.
- Sem Ruby local (Smart App Control): Ruby é validado pelo **CI**; lint antes do push com `rubocop-vps` (Git Bash, ~10 s). Limites: `Metrics/MethodLength` 19, `Metrics/AbcSize` 26, linha 150.
- **Specs em `spec/enterprise` não rodam no CI FOSS** (o CI apaga `enterprise/`). Por isso toda a lógica fica em `app/services/ramon/roteiro/` (testada no CI) e as tools são finas; a prova delas é o `rails runner` da Task 7. Pelo mesmo motivo o motor **não** usa `Ramon::CopilotoModo` (vive em `enterprise/lib`): lê `conversation.custom_attributes['copiloto_modo']` direto.
- **Toda conta nasce com o funil e os motivos de perda padrão** (`Account after_create` → `Leads::SeedDefaultConfigService`: etapas Novo, Qualificação, …, Fechado (ganho), Perdido; motivos Sem viabilidade, Outro, …; e as teses do `theses_seed.yml`). Specs usam as etapas semeadas (`account.lead_stages.find_by!(name: 'Novo')`) — criar outra "Novo"/"Perdido" quebra a unicidade. Teses dos specs com o nome padrão da factory.
- Definição compacta (`module Ramon::Roteiro::Resposta`) **não** põe `Ramon::Roteiro` na nesting: dentro de `Resposta`, `Efeitos` e `Registro`, referenciar outras peças pelo nome completo (`Ramon::Roteiro::Calculadoras`).
- Salário mínimo só por `Ramon::SalarioMinimo.vigente(data)` (já existe, F0).
- Texto que fala com cliente (skill de triagem, regras globais) só é **ativado** (`rake 'ramon:inteligencia:seed[2]'`) depois do aprovado do Eduardo. O código sobe antes.
- Efeitos por modo da conversa (grilling 13/10): **etiqueta** e **passar para a equipe** valem direto em qualquer modo; **mudar etapa** e **Perdido** só direto em `piloto_total` — em rascunho, piloto limitado, manual ou lead sem conversa viram `CopilotSuggestion` (`move_stage` / `acao: perdido`) com `payload['origem'] = 'roteiro'`. O desfecho do roteiro é gravado em qualquer modo. Sem passos cadastrados (até a F4), nada muda em produção.
- i18n: `en/ramon.json` **e** `pt_BR/ramon.json`.
- Commits: Conventional Commits + rodapé de atribuição da sessão.

**Desvios deliberados da spec (registrar no PR):**
1. `prescricao_5_anos` devolve três faixas — `dentro` (< 4 anos) · `ultimo_ano` (4 a 5) · `prescrito` — porque o roteiro da maternidade (decisões 13/10) manda "entre 4 e 5 anos → humano".
2. `meses_ate_65` devolve `ja_tem_65` · `menos_de_65` (meses no `detalhe`), em vez de `faltam_N`: o "quando" das saídas casa por texto exato.
3. `data_prevista_parto` devolve `ja_pode_pedir` · `aguardar` (a data prevista e a data a partir da qual pode pedir vão no `detalhe`): o benefício pode começar 28 dias antes do parto (Lei 8.213, art. 71).
4. Lead **sem tese** fica sem roteiro até a F3 (tese automática + passo comum "assunto"). As colunas `theses.palavras_chave`, `inboxes.ramon_thesis_id` e `inboxes.ramon_copiloto_modo` entram nesta migração (uma regeneração de schema só), mas são usadas na F3.
5. `LeadActivity` só quando a saída tem efeito ou encerra o roteiro (não em todo "seguir", para não poluir o histórico).
6. Validar `ir_para` com destino existente fica para o salvar da tela (F2); no motor, destino inexistente → equipe com motivo "roteiro sem saída".

**Decisões do grilling (Eduardo, 13/10) — valem sobre a spec onde divergirem:**
- Q1/Q9 — Perdido e mudança de etapa: direto só em `piloto_total` (e nos modos "sozinho até…" da F3); nos outros modos viram sugestão no Cockpit. Q5 — passar para a equipe: direto em qualquer modo. Q8 — etiquetas: direto.
- Q2 — desqualificado: a conversa **fica com o robô, calada** (modo manual, sem `bot_handoff!`).
- Q6 — com a sugestão de Perdido pendente a IA não faz mais perguntas do roteiro (o desfecho já está gravado, com `aguarda_equipe`). **Aprovar** → Perdido + etiqueta `desqualificado-ia` + IA calada. **Recusar** → o roteiro reabre.
- Q3/Q7/Q12 — `Ramon::Roteiro.reabrir`: apaga só a resposta do **passo que decidiu** (`decisivo`), volta a perguntar dali e devolve a conversa ao **modo de antes** (guardado em `conversation.custom_attributes['copiloto_modo_antes_roteiro']`) e tira a etiqueta. Também reabre quando o lead **sai do Perdido no Kanban** (só desfecho desqualificado). O botão no painel fica para a F2 (lá entra o "reiniciar", se fizer falta).
- Q10 — motivo de perda: a saída pode trazer `motivo_perda` (nome do catálogo `lost_reasons` da conta; padrão "Sem viabilidade"); o texto `motivo` vai para o histórico e o estado.
- Q11 — passos comuns rodam em **toda tese**. Tese sem passos próprios: ao fim dos comuns o roteiro **não conclui** — a IA recebe "passos comuns concluídos, siga a triagem de sempre".
- Q13 — correção: registrar de novo um passo já respondido vale a nova resposta e o roteiro volta a seguir **dali** (passos pulados antes passam a ser perguntados). Depois do desfecho, só reabrindo.
- Q4 — a prova da F1 é motor + tools no `rails runner`; a IA conversando de verdade fica para a caixa Teste (F4).

## Review Focus

1. **Lead adianta uma resposta** ("já tenho advogado, e o acidente foi em janeiro") → o passo respondido não é perguntado de novo e o passo atual não pula os que faltam; **corrigir** uma resposta volta a seguir dali (Task 4).
2. **A IA manda o valor num formato de gente** ("Sim!", "12/03/2025", "R$ 1.200,50") → normaliza; formato inválido (31/02, "talvez" num sim/não) → erro de volta para a IA e **nada é gravado** (Task 3 e Task 4).
3. **Saída sem casar ou `ir_para` para chave inexistente** → o lead vai para a equipe com motivo "roteiro sem saída" e o responsável recebe o sino, em vez de travar a conversa (Task 4).
4. **A IA insiste depois do desfecho** (registra outro passo ou corrige um, num roteiro encerrado) → recusa, nada muda; **lead já ganho** desqualificado → não volta para Perdido nem vira sugestão (Task 4).
5. **Trocar a tese do lead no meio** → o roteiro recomeça na tese nova e as respostas dos passos comuns ficam (Task 4).

---

### Task 1: Calculadoras

**Files:**
- Create: `app/services/ramon/roteiro/calculadoras.rb`
- Create: `spec/services/ramon/roteiro/calculadoras_spec.rb`

**Interfaces:**
- Consumes: `Ramon::SalarioMinimo.vigente(data) -> BigDecimal`
- Produces:
  - `Ramon::Roteiro::Calculadoras::NOMES` (Array de String)
  - `Ramon::Roteiro::Calculadoras.calcular(nome, campos, hoje: Date.current) -> { resultado: String, detalhe: String }` — `campos` com chaves String ou Symbol; nome desconhecido ou campo faltando → `resultado: 'depende'`
  - `Ramon::Roteiro::Calculadoras.numero(valor) -> BigDecimal | nil`
  - `Ramon::Roteiro::Calculadoras.data(valor) -> Date | nil` (aceita `AAAA-MM-DD` e `DD/MM/AAAA`)
  - `Ramon::Roteiro::Calculadoras.sim_nao(valor) -> 'sim' | 'nao' | nil`

- [ ] **Step 1: Escrever o spec (falha)**

`spec/services/ramon/roteiro/calculadoras_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Roteiro::Calculadoras do
  let(:hoje) { Date.new(2026, 10, 13) }

  def calc(nome, **campos)
    described_class.calcular(nome, campos, hoje: hoje)
  end

  describe 'periodo_de_graca' do
    # último vínculo 10/03/2025: 12 meses → mantém até 15/05/2026; 24 → 15/05/2027; 36 → 15/05/2028
    let(:base) { { ultimo_vinculo: '2025-03-10' } }

    it 'dentro quando tinha vínculo na data do evento' do
      expect(calc('periodo_de_graca', **base, evento: '2025-01-05')[:resultado]).to eq('dentro')
    end

    it 'dentro até o dia 15 do 2º mês depois dos 12 meses (art. 15 §4º)' do
      expect(calc('periodo_de_graca', **base, evento: '2026-05-15')[:resultado]).to eq('dentro')
      expect(calc('periodo_de_graca', **base, evento: '2026-05-16', mais_de_120: 'nao', desemprego: 'nao')[:resultado])
        .to eq('fora')
    end

    it 'faixa de 24 meses: uma extensão basta; sem saber = depende' do
      evento = '2027-01-10'
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'sim')[:resultado]).to eq('dentro')
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'nao', desemprego: 'sim')[:resultado]).to eq('dentro')
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'nao')[:resultado]).to eq('depende')
    end

    it 'faixa de 36 meses: precisa das duas extensões' do
      evento = '2028-01-10'
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'sim', desemprego: 'sim')[:resultado]).to eq('dentro')
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'sim', desemprego: 'nao')[:resultado]).to eq('fora')
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'sim')[:resultado]).to eq('depende')
    end

    it 'fora depois de 36 meses; facultativa só tem 6 meses' do
      expect(calc('periodo_de_graca', **base, evento: '2028-05-16', mais_de_120: 'sim', desemprego: 'sim')[:resultado]).to eq('fora')
      expect(calc('periodo_de_graca', **base, evento: '2025-11-15', facultativa: 'sim')[:resultado]).to eq('dentro')
      expect(calc('periodo_de_graca', **base, evento: '2025-11-16', facultativa: 'sim')[:resultado]).to eq('fora')
    end

    it 'depende quando falta data' do
      expect(calc('periodo_de_graca', evento: '2026-01-01')[:resultado]).to eq('depende')
    end
  end

  it 'renda_per_capita: até ¼ do salário mínimo (R$ 405,25 em 2026) é abaixo' do
    expect(calc('renda_per_capita', renda_total: '1621', moradores: '4')[:resultado]).to eq('abaixo')
    expect(calc('renda_per_capita', renda_total: '1621,04', moradores: '4')[:resultado]).to eq('acima')
    expect(calc('renda_per_capita', renda_total: '1621', moradores: '4')[:detalhe]).to include('405.25')
    expect(calc('renda_per_capita', renda_total: '1621', moradores: '0')[:resultado]).to eq('depende')
  end

  it 'prescricao_5_anos em três faixas' do
    expect(calc('prescricao_5_anos', data: '2023-01-01')[:resultado]).to eq('dentro')
    expect(calc('prescricao_5_anos', data: '2022-01-01')[:resultado]).to eq('ultimo_ano')
    expect(calc('prescricao_5_anos', data: '2021-10-13')[:resultado]).to eq('ultimo_ano')
    expect(calc('prescricao_5_anos', data: '2021-10-12')[:resultado]).to eq('prescrito')
  end

  it 'meses_ate_65' do
    expect(calc('meses_ate_65', nascimento: '1961-10-13')[:resultado]).to eq('ja_tem_65')
    res = calc('meses_ate_65', nascimento: '1962-04-20')
    expect(res[:resultado]).to eq('menos_de_65')
    expect(res[:detalhe]).to include('6 meses')
  end

  it 'data_prevista_parto: 40 semanas; pode pedir 28 dias antes' do
    res = calc('data_prevista_parto', semanas: '30')
    expect(res[:resultado]).to eq('aguardar')
    expect(res[:detalhe]).to include('22/12/2026').and include('24/11/2026')
    expect(calc('data_prevista_parto', semanas: '37')[:resultado]).to eq('ja_pode_pedir')
    expect(calc('data_prevista_parto', semanas: '50')[:resultado]).to eq('depende')
  end

  it 'prazo_inss: 45 dias da perícia ou 90 do requerimento' do
    expect(calc('prazo_inss', requerimento: '2026-09-01')[:resultado]).to eq('aguardar')
    expect(calc('prazo_inss', requerimento: '2026-07-01')[:resultado]).to eq('forcar_julgamento')
    expect(calc('prazo_inss', requerimento: '2026-08-01', pericia: '2026-08-25')[:resultado]).to eq('forcar_julgamento')
    expect(calc('prazo_inss')[:resultado]).to eq('depende')
  end

  it 'nome desconhecido = depende' do
    expect(calc('xablau')[:resultado]).to eq('depende')
  end

  describe 'leitura de valores' do
    it 'numero entende o jeito brasileiro' do
      expect(described_class.numero('R$ 1.200,50')).to eq(BigDecimal('1200.50'))
      expect(described_class.numero('R$ 1.200')).to eq(BigDecimal('1200'))
      expect(described_class.numero('1200.5')).to eq(BigDecimal('1200.5'))
      expect(described_class.numero('abc')).to be_nil
      expect(described_class.numero('-')).to be_nil
    end

    it 'data aceita ISO e dd/mm/aaaa; data impossível = nil' do
      expect(described_class.data('12/03/2025')).to eq(Date.new(2025, 3, 12))
      expect(described_class.data('2025-03-12')).to eq(Date.new(2025, 3, 12))
      expect(described_class.data('31/02/2026')).to be_nil
      expect(described_class.data('ontem')).to be_nil
    end

    it 'sim_nao' do
      expect(described_class.sim_nao('Sim!')).to eq('sim')
      expect(described_class.sim_nao('não')).to eq('nao')
      expect(described_class.sim_nao('talvez')).to be_nil
    end
  end
end
```

- [ ] **Step 2: Implementar**

`app/services/ramon/roteiro/calculadoras.rb`:

```ruby
# Contas exatas do roteiro da tese (spec 2026-10-13 §3.3). Cada uma recebe os campos já respondidos — como o motor
# grava: 'sim'/'nao', datas ISO, números em texto — e devolve { resultado:, detalhe: }. Campo faltando = 'depende'
# (a saída configurada no passo decide; normalmente equipe).
module Ramon::Roteiro::Calculadoras
  NOMES = %w[periodo_de_graca renda_per_capita prescricao_5_anos meses_ate_65 data_prevista_parto prazo_inss].freeze
  DEPENDE = { resultado: 'depende', detalhe: 'falta dado para a conta' }.freeze

  module_function

  def calcular(nome, campos, hoje: Date.current)
    return DEPENDE unless NOMES.include?(nome.to_s)

    send(nome, (campos || {}).to_h.transform_keys(&:to_s), hoje)
  end

  # Lei 8.213 art. 15: 12 meses depois do último vínculo (II); +12 com mais de 120 contribuições (§1º); +12 com
  # desemprego comprovado (§2º); facultativo, 6 meses (VI). §4º + Decreto 3.048 art. 14: a qualidade vai até o
  # dia 15 do 2º mês seguinte ao fim do prazo.
  # Campos: ultimo_vinculo, evento (datas); mais_de_120, desemprego, facultativa (sim/nao; vazio = não sabe).
  def periodo_de_graca(campos, _hoje)
    fim = data(campos['ultimo_vinculo'])
    evento = data(campos['evento'])
    return DEPENDE unless fim && evento
    return res('dentro', 'tinha vínculo na data do evento') if evento <= fim
    return graca_facultativa(fim, evento) if sim_nao(campos['facultativa']) == 'sim'

    meses = [12, 24, 36].find { |m| evento <= mantem_ate(fim, m) }
    return res('fora', 'mais de 36 meses sem contribuir') if meses.nil?

    graca_estendida(meses, campos['mais_de_120'], campos['desemprego'])
  end

  def mantem_ate(fim, meses)
    limite = fim >> (meses + 2)
    Date.new(limite.year, limite.month, 15)
  end

  def graca_facultativa(fim, evento)
    return res('dentro', 'facultativa: dentro dos 6 meses') if evento <= mantem_ate(fim, 6)

    res('fora', 'facultativa: mais de 6 meses sem contribuir')
  end

  # Quantas extensões o prazo precisa (24 meses = 1, 36 = 2) e quantas a pessoa tem ('sim'); vazio = talvez.
  def graca_estendida(meses, mais_de_120, desemprego)
    precisa = (meses - 12) / 12
    respostas = [mais_de_120, desemprego].map { |v| sim_nao(v) }
    tem = respostas.count('sim')
    return res('dentro', "dentro dos #{meses} meses de graça") if tem >= precisa
    return res('fora', "precisaria de #{meses} meses de graça") if tem + respostas.count(nil) < precisa

    res('depende', 'depende das 120 contribuições ou do desemprego comprovado')
  end

  # Lei 8.742 art. 20 §3º: renda por pessoa igual ou inferior a ¼ do salário mínimo.
  def renda_per_capita(campos, hoje)
    renda = numero(campos['renda_total'])
    moradores = numero(campos['moradores'])
    return DEPENDE unless renda && moradores&.positive?

    por_pessoa = (renda / moradores).round(2)
    limite = (Ramon::SalarioMinimo.vigente(hoje) / 4).round(2)
    detalhe = "R$ #{por_pessoa.to_s('F')} por pessoa; limite R$ #{limite.to_s('F')} (1/4 do salário mínimo)"
    res(por_pessoa <= limite ? 'abaixo' : 'acima', detalhe)
  end

  # Parcelas prescrevem em 5 anos (art. 103 parágrafo único); entre 4 e 5 anos = risco, a saída decide.
  def prescricao_5_anos(campos, hoje)
    quando = data(campos['data'])
    return DEPENDE if quando.nil?
    return res('dentro', 'menos de 4 anos') if quando > hoje.prev_year(4)
    return res('ultimo_ano', 'entre 4 e 5 anos') if quando >= hoje.prev_year(5)

    res('prescrito', 'mais de 5 anos')
  end

  def meses_ate_65(campos, hoje)
    nascimento = data(campos['nascimento'])
    return DEPENDE if nascimento.nil?

    faz65 = nascimento.next_year(65)
    return res('ja_tem_65', "fez 65 em #{faz65.strftime('%d/%m/%Y')}") if hoje >= faz65

    meses = ((faz65.year * 12) + faz65.month) - ((hoje.year * 12) + hoje.month)
    meses -= 1 if faz65.day < hoje.day
    res('menos_de_65', "faltam #{meses} meses para os 65 (#{faz65.strftime('%d/%m/%Y')})")
  end

  # Parto previsto com 40 semanas; o salário-maternidade pode começar 28 dias antes (Lei 8.213, art. 71).
  def data_prevista_parto(campos, hoje)
    semanas = numero(campos['semanas'])
    return DEPENDE unless semanas&.between?(1, 42)

    parto = hoje + ((40 - semanas) * 7).round
    pode_pedir = parto - 28
    detalhe = "parto previsto por volta de #{parto.strftime('%d/%m/%Y')}; pode pedir a partir de #{pode_pedir.strftime('%d/%m/%Y')}"
    res(hoje >= pode_pedir ? 'ja_pode_pedir' : 'aguardar', detalhe)
  end

  # Pedido parado: mais de 45 dias da perícia ou mais de 90 do requerimento → ação para forçar o julgamento.
  def prazo_inss(campos, hoje)
    requerimento = data(campos['requerimento'])
    pericia = data(campos['pericia'])
    return DEPENDE unless requerimento || pericia

    parado = (pericia && (hoje - pericia) > 45) || (requerimento && (hoje - requerimento) > 90)
    res(parado ? 'forcar_julgamento' : 'aguardar', parado ? 'passou do prazo de análise' : 'ainda no prazo de análise')
  end

  # "R$ 1.200,50", "R$ 1.200", "1200.5" → BigDecimal; vazio ou lixo → nil.
  def numero(valor)
    texto = valor.to_s.gsub(/[^\d,.-]/, '')
    texto = texto.delete('.').tr(',', '.') if texto.include?(',') || texto.match?(/\A-?\d{1,3}(\.\d{3})+\z/)
    texto.empty? ? nil : BigDecimal(texto)
  rescue ArgumentError
    nil
  end

  def data(valor)
    texto = valor.to_s.strip
    return Date.iso8601(texto) if texto.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.strptime(texto, '%d/%m/%Y') if texto.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})
  rescue ArgumentError
    nil
  end

  def sim_nao(valor)
    texto = I18n.transliterate(valor.to_s).downcase.gsub(/[^a-z]/, '')
    return 'sim' if %w[sim s].include?(texto)

    'nao' if %w[nao n].include?(texto)
  end

  def res(resultado, detalhe)
    { resultado: resultado, detalhe: detalhe }
  end
end
```

Nota: `app/services/ramon/roteiro.rb` (Task 4) é quem define o módulo `Ramon::Roteiro`; até lá o Zeitwerk cria o namespace pela pasta `roteiro/` (módulo implícito). Nada a fazer.

- [ ] **Step 3: Lint + commit**

```bash
rubocop-vps app/services/ramon/roteiro/calculadoras.rb spec/services/ramon/roteiro/calculadoras_spec.rb
git add app/services/ramon/roteiro/calculadoras.rb spec/services/ramon/roteiro/calculadoras_spec.rb
git commit -m "feat(roteiro): calculadoras exatas do roteiro da tese (graça, renda, prescrição, 65 anos, parto, prazo INSS)"
```

(O spec roda no CI — Task 7. Se o `rubocop-vps -a` corrigir algo, re-adicionar.)

---

### Task 2: Dados — passos do roteiro

**Files:**
- Create: `db/migrate/20261013200001_create_ramon_roteiro_passos.rb`
- Modify: `db/schema.rb` (versão do topo; bloco novo `ramon_roteiro_passos` entre `ramon_reunioes` e `related_categories`; `theses`; `inboxes`)
- Create: `app/models/roteiro_passo.rb`
- Modify: `app/models/thesis.rb` (associação)
- Create: `spec/factories/roteiro_passos.rb`
- Create: `spec/models/roteiro_passo_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Roteiro::Calculadoras::NOMES` (Task 1)
- Produces:
  - `RoteiroPasso` (`account`, `thesis` opcional, `position`, `chave`, `titulo`, `orientacao`, `tipo_resposta`, `opcoes` (Array), `calculadora`, `calculadora_campos` (Hash campo → chave), `saidas` (Array de Hash com chaves String: `id`, `quando`, `acao`, `alvo`, `motivo`, `motivo_perda` (nome do catálogo `lost_reasons`), `mensagem`, `efeitos` → `{ 'etiqueta', 'etapa' }`), `edited`)
  - `RoteiroPasso::TIPOS`, `RoteiroPasso::ACOES`, scope `RoteiroPasso.comuns`, default order `position, id`
  - `Thesis#roteiro_passos`
  - factory `:roteiro_passo`
  - colunas `theses.palavras_chave` (string[], default `[]`), `inboxes.ramon_thesis_id` (bigint), `inboxes.ramon_copiloto_modo` (string) — usadas na F3

- [ ] **Step 1: Spec do model (falha)**

`spec/factories/roteiro_passos.rb`:

```ruby
FactoryBot.define do
  factory :roteiro_passo do
    account
    thesis { association :thesis, account: account }
    sequence(:chave) { |n| "passo_#{n}" }
    titulo { 'Passo' }
    tipo_resposta { 'sim_nao' }
    saidas { [] }
  end
end
```

`spec/models/roteiro_passo_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe RoteiroPasso do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }

  it 'recusa tipo, calculadora e saídas inválidos' do
    passo = build(:roteiro_passo, account: account, thesis: thesis, tipo_resposta: 'x', calculadora: 'nada',
                                  saidas: [{ 'id' => 'a', 'acao' => 'desqualificar' }, { 'acao' => 'pular' },
                                           { 'id' => 'b', 'acao' => 'ir_para' }])
    expect(passo).not_to be_valid
    expect(passo.errors[:tipo_resposta]).to be_present
    expect(passo.errors[:calculadora]).to be_present
    expect(passo.errors[:saidas].join(' ')).to include('motivo obrigatório').and include('ação inválida')
      .and include('falta o id').and include('falta o passo de destino')
  end

  it 'aceita passo válido e calculadora vazia vira nil' do
    passo = build(:roteiro_passo, account: account, thesis: thesis, calculadora: '',
                                  saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'humano', 'motivo' => 'x' }])
    expect(passo).to be_valid
    expect(passo.calculadora).to be_nil
  end

  it 'chave única por tese e, nos comuns, por conta' do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'sequela')
    expect(build(:roteiro_passo, account: account, thesis: thesis, chave: 'sequela')).not_to be_valid
    expect(build(:roteiro_passo, account: account, thesis: create(:thesis, account: account), chave: 'sequela')).to be_valid

    create(:roteiro_passo, account: account, thesis: nil, chave: 'nome')
    expect(build(:roteiro_passo, account: account, thesis: nil, chave: 'nome')).not_to be_valid
    expect(described_class.comuns.pluck(:chave)).to eq(['nome'])
  end

  it 'chave só com minúsculas, números e _' do
    expect(build(:roteiro_passo, account: account, thesis: thesis, chave: 'Tem Advogado')).not_to be_valid
  end

  it 'motivo de perda só do catálogo da conta (Sem viabilidade nasce com a conta)' do
    ok = { 'id' => 'a', 'acao' => 'desqualificar', 'motivo' => 'x', 'motivo_perda' => 'Sem viabilidade' }
    expect(build(:roteiro_passo, account: account, thesis: thesis, saidas: [ok])).to be_valid

    passo = build(:roteiro_passo, account: account, thesis: thesis, saidas: [ok.merge('motivo_perda' => 'Inventado')])
    expect(passo).not_to be_valid
    expect(passo.errors[:saidas].join).to include('fora do catálogo')
  end
end
```

- [ ] **Step 2: Migração**

`db/migrate/20261013200001_create_ramon_roteiro_passos.rb`:

```ruby
# Roteiro da tese (spec 2026-10-13 §3.1): passos de qualificação por tese; thesis_id nulo = passo comum da conta.
# palavras_chave e os padrões por caixa entram aqui (uma regeneração de schema só) e são usados na F3.
class CreateRamonRoteiroPassos < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_roteiro_passos do |t|
      t.bigint :account_id, null: false
      t.bigint :thesis_id
      t.integer :position, null: false, default: 0
      t.string :chave, null: false
      t.string :titulo, null: false
      t.text :orientacao
      t.string :tipo_resposta, null: false, default: 'texto'
      t.jsonb :opcoes, null: false, default: []
      t.string :calculadora
      t.jsonb :calculadora_campos, null: false, default: {}
      t.jsonb :saidas, null: false, default: []
      t.boolean :edited, null: false, default: false
      t.timestamps
    end
    add_index :ramon_roteiro_passos, :account_id
    add_index :ramon_roteiro_passos, %i[thesis_id chave], unique: true, where: 'thesis_id IS NOT NULL',
                                                         name: 'index_ramon_roteiro_passos_on_thesis_and_chave'
    add_index :ramon_roteiro_passos, %i[account_id chave], unique: true, where: 'thesis_id IS NULL',
                                                          name: 'index_ramon_roteiro_passos_comuns_on_chave'

    add_column :theses, :palavras_chave, :string, array: true, null: false, default: []
    add_column :inboxes, :ramon_thesis_id, :bigint
    add_column :inboxes, :ramon_copiloto_modo, :string
  end
end
```

- [ ] **Step 3: `db/schema.rb` à mão**

Topo: `ActiveRecord::Schema[7.1].define(version: 2026_10_13_200001) do`.

No bloco `create_table "inboxes"`, depois de `t.boolean "portaria_enabled", default: false, null: false`:

```ruby
    t.bigint "ramon_thesis_id"
    t.string "ramon_copiloto_modo"
```

No bloco `create_table "theses"`, depois de `t.boolean "honorario_na_tabela", default: false, null: false`:

```ruby
    t.string "palavras_chave", default: [], null: false, array: true
```

Bloco novo, logo depois do `end` de `create_table "ramon_reunioes"` (antes de `create_table "related_categories"`):

```ruby
  create_table "ramon_roteiro_passos", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "thesis_id"
    t.integer "position", default: 0, null: false
    t.string "chave", null: false
    t.string "titulo", null: false
    t.text "orientacao"
    t.string "tipo_resposta", default: "texto", null: false
    t.jsonb "opcoes", default: [], null: false
    t.string "calculadora"
    t.jsonb "calculadora_campos", default: {}, null: false
    t.jsonb "saidas", default: [], null: false
    t.boolean "edited", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "chave"], name: "index_ramon_roteiro_passos_comuns_on_chave", unique: true, where: "(thesis_id IS NULL)"
    t.index ["account_id"], name: "index_ramon_roteiro_passos_on_account_id"
    t.index ["thesis_id", "chave"], name: "index_ramon_roteiro_passos_on_thesis_and_chave", unique: true, where: "(thesis_id IS NOT NULL)"
  end

```

- [ ] **Step 4: Model e associação**

`app/models/roteiro_passo.rb`:

```ruby
# Um passo do roteiro de qualificação da tese (spec 2026-10-13 §3.1). thesis nil = passo comum da conta, roda antes
# do roteiro de qualquer tese. saidas (avaliadas em ordem, a 1ª que casa vale):
#   [{ 'id', 'quando' (valor, faixa '< 64', resultado da calculadora ou '*'), 'acao', 'alvo' (ir_para),
#      'motivo' (desqualificar/humano), 'motivo_perda' (catálogo lost_reasons; padrão Sem viabilidade),
#      'mensagem' (base da resposta), 'efeitos' => { 'etiqueta', 'etapa' } }]
class RoteiroPasso < ApplicationRecord
  self.table_name = 'ramon_roteiro_passos'

  TIPOS = %w[sim_nao escolha numero data texto].freeze
  ACOES = %w[seguir ir_para desqualificar humano concluir].freeze

  belongs_to :account
  belongs_to :thesis, optional: true

  normalizes :calculadora, with: ->(v) { v.presence }

  validates :titulo, presence: true
  validates :chave, presence: true, format: { with: /\A[a-z0-9_]+\z/ }, uniqueness: { scope: %i[account_id thesis_id] }
  validates :tipo_resposta, inclusion: { in: TIPOS }
  validates :calculadora, inclusion: { in: Ramon::Roteiro::Calculadoras::NOMES }, allow_nil: true
  validate :saidas_validas

  scope :comuns, -> { where(thesis_id: nil) }
  default_scope { order(:position, :id) }

  private

  def saidas_validas
    return errors.add(:saidas, 'deve ser uma lista') unless saidas.is_a?(Array)

    saidas.each.with_index(1) { |saida, n| erros_da_saida(saida).each { |erro| errors.add(:saidas, "#{n}: #{erro}") } }
  end

  def erros_da_saida(saida)
    acao = saida['acao']
    [('falta o id' if saida['id'].blank?),
     ("ação inválida (#{acao})" unless ACOES.include?(acao)),
     ('motivo obrigatório' if %w[desqualificar humano].include?(acao) && saida['motivo'].blank?),
     ('falta o passo de destino' if acao == 'ir_para' && saida['alvo'].blank?),
     ("motivo de perda fora do catálogo (#{saida['motivo_perda']})" if motivo_perda_invalido?(saida['motivo_perda']))].compact
  end

  def motivo_perda_invalido?(motivo)
    motivo.present? && !account&.lost_reasons&.exists?(name: motivo)
  end
end
```

`app/models/thesis.rb` — depois de `has_many :leads, dependent: :nullify`:

```ruby
  has_many :roteiro_passos, dependent: :destroy
```

- [ ] **Step 5: Lint + commit**

```bash
rubocop-vps db/migrate/20261013200001_create_ramon_roteiro_passos.rb app/models/roteiro_passo.rb app/models/thesis.rb \
  spec/models/roteiro_passo_spec.rb spec/factories/roteiro_passos.rb
git add db/migrate/20261013200001_create_ramon_roteiro_passos.rb db/schema.rb app/models/roteiro_passo.rb \
  app/models/thesis.rb spec/models/roteiro_passo_spec.rb spec/factories/roteiro_passos.rb
git commit -m "feat(roteiro): tabela de passos do roteiro da tese (comuns e por tese) e campos da F3"
```

---

### Task 3: Resposta e efeitos

**Files:**
- Create: `app/services/ramon/roteiro/resposta.rb`
- Create: `app/services/ramon/roteiro/efeitos.rb`
- Create: `spec/services/ramon/roteiro/resposta_spec.rb`
- Modify: `app/javascript/dashboard/i18n/locale/en/ramon.json`, `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json` (tipo de atividade `ROTEIRO`)

**Interfaces:**
- Consumes: `Ramon::Roteiro::Calculadoras.numero/data/sim_nao` (Task 1), `RoteiroPasso` (Task 2), `Ramon::LeadNotificationBuilder`, `Ramon::NtfyPushJob`, `Ramon::Papeis.gestor_ids`, `Conversation#add_labels`, `Conversation#bot_handoff!`
- Produces:
  - `Ramon::Roteiro::Resposta.normalizar(passo, valor) -> [valor_normalizado (String|nil), erro (String|nil)]` — vazio → `[nil, nil]`
  - `Ramon::Roteiro::Resposta.casa?(quando, valor) -> Boolean`
  - `Ramon::Roteiro::Efeitos.aplicar(lead, passo, saida) -> void` (saida = Hash com chaves String)
  - `Ramon::Roteiro::Efeitos.direto?(lead) -> Boolean` (conversa em `piloto_total`)
  - `Ramon::Roteiro::Efeitos.calar(lead) -> void` (etiqueta `desqualificado-ia` + modo manual guardando o de antes; usada também ao aprovar a sugestão — Task 5)
  - `Ramon::Roteiro::Efeitos.reabrir(lead) -> void` (devolve o modo de antes, tira a etiqueta, anota "roteiro reaberto")
  - `Ramon::Roteiro::Efeitos::ETIQUETA_DESQUALIFICADO = 'desqualificado-ia'`, `MOTIVO_PERDA_PADRAO = 'Sem viabilidade'`, `MODO_ANTES = 'copiloto_modo_antes_roteiro'`
  - Sugestões criadas: `kind: 'move_stage'` (`payload`: `etapa_sugerida`, `justificativa`) e `kind: 'acao'` (`payload`: `acao: 'perdido'`, `lost_reason`, `texto`), ambas com `origem: 'roteiro'`, `lead_name`, `stage_name`
  - `LeadActivity` `kind: 'roteiro'`, `to_value: "<título do passo> → <resumo>"`

Os efeitos são testados pelo motor na Task 4 (cenário completo com conversa, etapas, sugestões e sino) e na Task 5 (reabrir).

- [ ] **Step 1: Spec da resposta (falha)**

`spec/services/ramon/roteiro/resposta_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Roteiro::Resposta do
  def passo(tipo, opcoes: [])
    build(:roteiro_passo, tipo_resposta: tipo, opcoes: opcoes)
  end

  describe '.normalizar' do
    it 'sim_nao, escolha, numero, data e texto' do
      expect(described_class.normalizar(passo('sim_nao'), 'Sim!')).to eq(['sim', nil])
      expect(described_class.normalizar(passo('escolha', opcoes: ['Carteira assinada', 'Autônomo']), 'autonomo'))
        .to eq(['Autônomo', nil])
      expect(described_class.normalizar(passo('numero'), 'R$ 1.200,50')).to eq(['1200.5', nil])
      expect(described_class.normalizar(passo('data'), '12/03/2025')).to eq(['2025-03-12', nil])
      expect(described_class.normalizar(passo('texto'), '  ficou com dor  ')).to eq(['ficou com dor', nil])
    end

    it 'devolve erro sem valor quando o formato não serve' do
      expect(described_class.normalizar(passo('sim_nao'), 'talvez')).to eq([nil, 'Responda sim ou nao.'])
      expect(described_class.normalizar(passo('data'), '31/02/2026').last).to include('AAAA-MM-DD')
      expect(described_class.normalizar(passo('escolha', opcoes: %w[A B]), 'C').last).to include('A | B')
      expect(described_class.normalizar(passo('numero'), 'muito').last).to include('numero')
    end

    it 'vazio = nada' do
      expect(described_class.normalizar(passo('sim_nao'), ' ')).to eq([nil, nil])
    end
  end

  describe '.casa?' do
    it 'valor exato sem acento e caixa, faixa numérica e curinga' do
      expect(described_class.casa?('Não', 'nao')).to be(true)
      expect(described_class.casa?('< 64', '63')).to be(true)
      expect(described_class.casa?('>= 65', '64.9')).to be(false)
      expect(described_class.casa?('> 1,5', '2')).to be(true)
      expect(described_class.casa?('< 64', 'abc')).to be(false)
      expect(described_class.casa?('*', nil)).to be(true)
      expect(described_class.casa?('sim', 'nao')).to be(false)
    end
  end
end
```

- [ ] **Step 2: Implementar a resposta**

`app/services/ramon/roteiro/resposta.rb`:

```ruby
# Resposta de um passo do roteiro: normaliza o que a IA informa para o tipo do passo e casa com o "quando" das
# saídas (spec 2026-10-13 §3.1). Formato que não serve volta como erro para a IA — nada é gravado.
module Ramon::Roteiro::Resposta
  FAIXA = /\A(<=|>=|<|>)\s*(-?\d+(?:[.,]\d+)?)\z/

  module_function

  # @return [valor_normalizado, erro]
  def normalizar(passo, valor)
    texto = valor.to_s.strip
    return [nil, nil] if texto.empty?

    case passo.tipo_resposta
    when 'sim_nao' then exigir(Ramon::Roteiro::Calculadoras.sim_nao(texto), 'Responda sim ou nao.')
    when 'escolha' then exigir(opcao(passo, texto), "Use uma das opcoes: #{Array(passo.opcoes).join(' | ')}.")
    when 'numero' then exigir(Ramon::Roteiro::Calculadoras.numero(texto)&.to_s('F'), 'Informe um numero.')
    when 'data' then exigir(Ramon::Roteiro::Calculadoras.data(texto)&.iso8601, 'Informe a data como AAAA-MM-DD.')
    else [texto, nil]
    end
  end

  def casa?(quando, valor)
    regra = quando.to_s.strip
    return true if regra == '*'

    faixa = FAIXA.match(regra)
    return normal(regra) == normal(valor) if faixa.nil?

    numero = Ramon::Roteiro::Calculadoras.numero(valor)
    !numero.nil? && numero.public_send(faixa[1], BigDecimal(faixa[2].tr(',', '.')))
  end

  def opcao(passo, texto)
    Array(passo.opcoes).find { |o| normal(o) == normal(texto) }
  end

  def exigir(valor, erro)
    valor.nil? ? [nil, erro] : [valor, nil]
  end

  def normal(texto)
    I18n.transliterate(texto.to_s).downcase.strip
  end
end
```

Atenção: `BigDecimal('1200.50').to_s('F')` = `"1200.5"` — o spec espera `'1200.5'`.

- [ ] **Step 3: Implementar os efeitos**

`app/services/ramon/roteiro/efeitos.rb`:

```ruby
# Consequências fixas de uma saída do roteiro (spec 2026-10-13 §3.4) — configuradas pelo admin no passo; a IA não
# decide. Por modo da conversa (decisões 13/10): etiqueta e "passar para a equipe" valem direto em qualquer modo;
# etapa (só aberta) e Perdido só direto em piloto total — nos outros modos, e sem conversa, viram sugestão no Cockpit.
# Perdido de verdade = etiqueta desqualificado-ia + IA calada (a conversa fica com o robô). Histórico: LeadActivity 'roteiro'.
module Ramon::Roteiro::Efeitos
  ETIQUETA_DESQUALIFICADO = 'desqualificado-ia'.freeze
  MOTIVO_PERDA_PADRAO = 'Sem viabilidade'.freeze
  MODO_ANTES = 'copiloto_modo_antes_roteiro'.freeze
  ENCERRA = %w[desqualificar humano concluir].freeze

  module_function

  def aplicar(lead, passo, saida)
    efeitos = saida['efeitos'] || {}
    etiquetar(lead, efeitos['etiqueta'])
    mover(lead, efeitos['etapa'], passo)
    desqualificar(lead, passo, saida) if saida['acao'] == 'desqualificar'
    humano(lead, saida['motivo']) if saida['acao'] == 'humano'
    anotar(lead, "#{passo.titulo} → #{resumo(saida)}") if ENCERRA.include?(saida['acao']) || efeitos.values.any?(&:present?)
  end

  # ponytail: lê só o atributo da conversa (Ramon::CopilotoModo vive em enterprise/, fora do CI); se o
  # RAMON_COPILOTO_MODO_DEFAULT um dia virar piloto_total, considerar o default aqui também.
  def direto?(lead)
    lead.conversation&.custom_attributes&.[]('copiloto_modo') == 'piloto_total'
  end

  # Label do Chatwoot é minúscula (Label#title.downcase).
  def etiquetar(lead, etiqueta)
    return if etiqueta.blank? || lead.conversation.nil?

    lead.conversation.add_labels([etiqueta.to_s.downcase])
  end

  # Só etapa aberta: ganho nunca; perdido só pela saída desqualificar.
  def mover(lead, nome, passo)
    return if nome.blank?

    etapa = lead.account.lead_stages.find_by(name: nome, is_won: false, is_lost: false)
    return anotar(lead, "etapa '#{nome}' nao existe no funil") if etapa.nil?
    return if lead.lead_stage_id == etapa.id
    return lead.update!(lead_stage: etapa) if direto?(lead)

    sugerir(lead, 'move_stage', 'etapa_sugerida' => etapa.name, 'justificativa' => "roteiro da IA: #{passo.titulo}")
  end

  def desqualificar(lead, passo, saida)
    return if lead.won_at || lead.lost_at

    motivo_perda = saida['motivo_perda'].presence || MOTIVO_PERDA_PADRAO
    return perder(lead, motivo_perda) if direto?(lead)

    sugerir(lead, 'acao', 'acao' => 'perdido', 'lost_reason' => motivo_perda,
                          'texto' => "Marcar como perdido (#{motivo_perda}) - roteiro: #{passo.titulo}, #{saida['motivo']}")
  end

  def perder(lead, motivo_perda)
    perdido = lead.account.lead_stages.find_by(is_lost: true)
    lead.update!(lead_stage: perdido, lost_reason: motivo_perda) if perdido
    calar(lead)
  end

  # A mensagem de encerramento desta resposta ainda sai: o ResponseBuilderJob guarda o modo do início da resposta.
  # Também chamada ao aprovar o Perdido sugerido pelo roteiro (CopilotSuggestion#marcar_perdido).
  def calar(lead)
    etiquetar(lead, ETIQUETA_DESQUALIFICADO)
    modo(lead, 'manual')
  end

  # Roteiro reaberto (Ramon::Roteiro.reabrir): devolve o modo de antes e tira a etiqueta de desqualificado.
  def reabrir(lead)
    restaurar(lead.conversation) if lead.conversation
    anotar(lead, 'roteiro reaberto')
  end

  def restaurar(conversa)
    attrs = conversa.custom_attributes || {}
    conversa.update!(custom_attributes: attrs.except(MODO_ANTES).merge('copiloto_modo' => attrs[MODO_ANTES])) if attrs.key?(MODO_ANTES)
    return unless conversa.label_list.include?(ETIQUETA_DESQUALIFICADO)

    conversa.update_labels(conversa.label_list - [ETIQUETA_DESQUALIFICADO])
  end

  # Como as tools de escrita: pendente igual (mesmo caso, mesmo tipo/ação) não vira duas.
  def sugerir(lead, kind, payload)
    pendentes = lead.account.copilot_suggestions.pending.where(lead_id: lead.id, kind: kind)
    return if pendentes.any? { |s| s.payload['acao'] == payload['acao'] }

    lead.account.copilot_suggestions.create!(
      lead: lead, kind: kind, status: 'pending', run_at: Time.current,
      payload: payload.merge('origem' => 'roteiro', 'lead_name' => lead.name, 'stage_name' => lead.lead_stage&.name)
    )
  end

  # Mesmo caminho da tool handoff (bot_handoff!); sino ao closer/SDR do lead, sem eles aos gestores.
  def humano(lead, motivo)
    conversa = lead.conversation
    conversa.bot_handoff! if conversa&.pending?
    modo(lead, 'rascunho')
    ids = [lead.closer_id || lead.sdr_id].compact.presence || Ramon::Papeis.gestor_ids(lead.account)
    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso', user_ids: ids,
                                       meta: { 'label' => "IA passou #{lead.name} para a equipe: #{motivo}".truncate(200) }).perform
    Ramon::NtfyPushJob.perform_later(lead.id, title: "IA passou para a equipe: #{lead.name}", body: motivo.to_s.truncate(200))
  end

  # Guarda o modo de antes para o reabrir devolver (decisão 13/10).
  def modo(lead, valor)
    conversa = lead.conversation
    return if conversa.nil?

    attrs = conversa.custom_attributes || {}
    conversa.update!(custom_attributes: attrs.merge(MODO_ANTES => attrs['copiloto_modo'], 'copiloto_modo' => valor))
  end

  def resumo(saida)
    case saida['acao']
    when 'desqualificar' then "desqualificado: #{saida['motivo']}"
    when 'humano' then "passou para a equipe: #{saida['motivo']}"
    when 'concluir' then 'qualificado'
    else saida['acao']
    end
  end

  def anotar(lead, texto)
    lead.lead_activities.create!(account: lead.account, kind: 'roteiro', to_value: texto.truncate(250))
  end
end
```

- [ ] **Step 4: i18n do histórico**

Em `app/javascript/dashboard/i18n/locale/pt_BR/ramon.json`, no bloco `RAMON.LEAD_PANEL.HISTORY.KIND`, depois de `"DOSSIE_ENTREGUE": "marcou o dossiê como entregue ao jurídico"` (pôr vírgula nessa linha):

```json
          "ROTEIRO": "roteiro da IA"
```

Em `en/ramon.json`, no mesmo lugar, depois de `"DOSSIE_ENTREGUE": "marked the dossier as delivered to the legal team"`:

```json
          "ROTEIRO": "AI script"
```

(`ListaAtividades.vue` já mostra `to_value` como detalhe e cai no grupo visual "outro" — nada a mudar no Vue.)

- [ ] **Step 5: Lint + commit**

```bash
rubocop-vps app/services/ramon/roteiro/resposta.rb app/services/ramon/roteiro/efeitos.rb spec/services/ramon/roteiro/resposta_spec.rb
git add app/services/ramon/roteiro/resposta.rb app/services/ramon/roteiro/efeitos.rb spec/services/ramon/roteiro/resposta_spec.rb \
  app/javascript/dashboard/i18n/locale/en/ramon.json app/javascript/dashboard/i18n/locale/pt_BR/ramon.json
git commit -m "feat(roteiro): leitura da resposta e efeitos fixos das saídas (etapa e Perdido por modo, equipe)"
```

---

### Task 4: Motor

**Files:**
- Create: `app/services/ramon/roteiro.rb`
- Create: `app/services/ramon/roteiro/registro.rb`
- Create: `spec/services/ramon/roteiro_spec.rb`

**Interfaces:**
- Consumes: `RoteiroPasso` (Task 2), `Ramon::Roteiro::Resposta`, `Ramon::Roteiro::Efeitos` (Task 3), `Ramon::Roteiro::Calculadoras.calcular` (Task 1)
- Produces:
  - `Ramon::Roteiro.passos(lead) -> Array<RoteiroPasso>` (comuns da conta + os da tese, em **toda** tese; lead sem tese ou nenhum passo = `[]` = sem roteiro)
  - `Ramon::Roteiro.estado(lead) -> Hash` (cópia; `'respostas'` sempre presente)
  - `Ramon::Roteiro.proximo(lista, estado) -> RoteiroPasso | nil`
  - `Ramon::Roteiro.atual(lead) -> nil | { passo: RoteiroPasso|nil, estado: Hash }` (passo nil = encerrado, ou comuns concluídos numa tese sem passos próprios)
  - `Ramon::Roteiro.registrar(lead, chave:, valor: nil, saida_id: nil) -> { erro: String } | { estado: Hash, proximo: RoteiroPasso|nil, calc: Hash|nil, mensagem: String|nil }`
  - `Ramon::Roteiro.reabrir(lead, se: nil) -> Boolean` (`se: 'desqualificado'` = só reabre esse desfecho; false = nada a reabrir)
  - `Ramon::Roteiro.descrever(passo, estado) -> String` e `Ramon::Roteiro.resumo(resultado) -> String` (textos que as tools devolvem à IA)
  - estado gravado em `lead.custom_attributes['roteiro']`: `{ 'tese_id', 'cursor', 'desfecho', 'motivo', 'decisivo' (chave do passo que encerrou), 'aguarda_equipe' (Perdido virou sugestão), 'respostas' => { chave => { 'valor', 'calc', 'saida', 'em' } } }`

- [ ] **Step 1: Spec do motor (falha)**

`spec/services/ramon/roteiro_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Roteiro do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  # Toda conta nasce com o funil e os motivos de perda padrão (Leads::SeedDefaultConfigService).
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:qualificacao) { account.lead_stages.find_by!(name: 'Qualificação') }
  let(:perdido) { account.lead_stages.find_by!(is_lost: true) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: novo, conversation: conversation) }

  def passo(chave, position, **attrs)
    create(:roteiro_passo, account: account, thesis: thesis, chave: chave, position: position, titulo: chave.humanize, **attrs)
  end

  def registrar(chave, valor = nil, saida_id: nil)
    described_class.registrar(lead.reload, chave: chave, valor: valor, saida_id: saida_id)
  end

  def piloto_total!
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_total' })
  end

  before do
    create(:roteiro_passo, account: account, thesis: nil, chave: 'tem_advogado', position: 0, titulo: 'Tem advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado',
                                      'motivo_perda' => 'Outro', 'mensagem' => 'Que bom que ja tem quem cuide.',
                                      'efeitos' => { 'etiqueta' => 'TemAdvogado' } },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    passo('recebeu_auxilio', 1, saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'ir_para', 'alvo' => 'sequela' },
                                         { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    passo('data_acidente', 2, tipo_resposta: 'data')
    passo('graca', 3, tipo_resposta: 'data', calculadora: 'periodo_de_graca',
                      calculadora_campos: { 'ultimo_vinculo' => 'graca', 'evento' => 'data_acidente' },
                      saidas: [{ 'id' => 'dentro', 'quando' => 'dentro', 'acao' => 'seguir' },
                               { 'id' => 'fora', 'quando' => 'fora', 'acao' => 'desqualificar', 'motivo' => 'fora do periodo de graca' },
                               { 'id' => 'outro', 'quando' => '*', 'acao' => 'humano', 'motivo' => 'graca depende' }])
    passo('sequela', 4, tipo_resposta: 'texto',
                        saidas: [{ 'id' => 'ficou', 'quando' => 'ficou alguma limitacao', 'acao' => 'concluir',
                                   'efeitos' => { 'etapa' => 'Qualificação' } },
                                 { 'id' => 'voltou_100', 'quando' => 'voltou 100%', 'acao' => 'desqualificar', 'motivo' => 'sem sequela' }])
  end

  it 'lead sem tese fica sem roteiro (tese automática = F3)' do
    sem_tese = create(:lead, account: account, lead_stage: novo)
    expect(described_class.atual(sem_tese)).to be_nil
    expect(described_class.registrar(sem_tese, chave: 'tem_advogado', valor: 'nao')).to eq(erro: 'Este caso nao tem roteiro.')
  end

  it 'tese sem passos próprios roda os comuns e devolve para a triagem de sempre' do
    outro = create(:lead, account: account, thesis: create(:thesis, account: account), lead_stage: novo)
    expect(described_class.atual(outro)[:passo].chave).to eq('tem_advogado')

    res = described_class.registrar(outro, chave: 'tem_advogado', valor: 'nao')
    expect(res[:proximo]).to be_nil
    expect(res[:estado]['desfecho']).to be_nil
    expect(described_class.resumo(res)).to include('siga a triagem de sempre')
  end

  it 'começa pelos comuns e segue a ordem' do
    expect(described_class.atual(lead)[:passo].chave).to eq('tem_advogado')
    expect(registrar('tem_advogado', 'Não')[:proximo].chave).to eq('recebeu_auxilio')
    expect(lead.reload.custom_attributes.dig('roteiro', 'respostas', 'tem_advogado', 'valor')).to eq('nao')
  end

  it 'ir_para pula etapas; concluir qualifica e, fora do piloto total, sugere a etapa no Cockpit' do
    registrar('tem_advogado', 'nao')
    expect(registrar('recebeu_auxilio', 'sim')[:proximo].chave).to eq('sequela')

    res = registrar('sequela', 'ficou com dor no punho', saida_id: 'ficou')
    expect(res[:estado]).to include('desfecho' => 'qualificado', 'decisivo' => 'sequela')
    expect(res[:proximo]).to be_nil
    expect(lead.reload.lead_stage).to eq(novo)
    sugestao = account.copilot_suggestions.pending.find_by!(lead: lead, kind: 'move_stage')
    expect(sugestao.payload).to include('etapa_sugerida' => 'Qualificação', 'origem' => 'roteiro')
    expect(lead.lead_activities.where(kind: 'roteiro').last.to_value).to eq('Sequela → qualificado')
  end

  it 'em piloto total a etapa muda direto' do
    piloto_total!
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim')
    registrar('sequela', 'ficou com dor no punho', saida_id: 'ficou')
    expect(lead.reload.lead_stage).to eq(qualificacao)
    expect(account.copilot_suggestions.count).to eq(0)
  end

  it 'a calculadora decide; fora do piloto total o Perdido vira sugestão e a IA não é calada' do
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'nao')
    registrar('data_acidente', '10/01/2026')
    res = registrar('graca', '2022-01-01') # 36 meses mantêm só até 15/03/2025

    expect(res[:calc][:resultado]).to eq('fora')
    expect(res[:estado]).to include('desfecho' => 'desqualificado', 'motivo' => 'fora do periodo de graca',
                                    'decisivo' => 'graca', 'aguarda_equipe' => true)
    expect(lead.reload.lead_stage).to eq(novo)
    sugestao = account.copilot_suggestions.pending.find_by!(lead: lead, kind: 'acao')
    expect(sugestao.payload).to include('acao' => 'perdido', 'lost_reason' => 'Sem viabilidade', 'origem' => 'roteiro')
    expect(conversation.reload.label_list).not_to include('desqualificado-ia')
    expect(conversation.custom_attributes['copiloto_modo']).to be_nil
    expect(described_class.descrever(nil, res[:estado])).to include('aguardando a equipe')
  end

  it 'em piloto total desqualifica direto: motivo do catálogo, etiquetas e IA calada com o robô, guardando o modo' do
    piloto_total!
    res = registrar('tem_advogado', 'sim')

    expect(res[:mensagem]).to eq('Que bom que ja tem quem cuide.')
    expect(res[:estado]).not_to have_key('aguarda_equipe')
    expect(lead.reload).to have_attributes(lead_stage: perdido, lost_reason: 'Outro')
    expect(conversation.reload.label_list).to include('temadvogado', 'desqualificado-ia')
    expect(conversation.custom_attributes).to include('copiloto_modo' => 'manual', 'copiloto_modo_antes_roteiro' => 'piloto_total')
    expect(conversation.status).to eq('pending')
  end

  it 'a etiqueta da saída vale em qualquer modo' do
    registrar('tem_advogado', 'sim')
    expect(conversation.reload.label_list).to include('temadvogado')
    expect(conversation.label_list).not_to include('desqualificado-ia')
  end

  it 'resposta adiantada não é perguntada de novo nem pula o passo atual' do
    registrar('data_acidente', '10/01/2026')
    expect(described_class.atual(lead.reload)[:passo].chave).to eq('tem_advogado')

    registrar('tem_advogado', 'nao')
    expect(registrar('recebeu_auxilio', 'nao')[:proximo].chave).to eq('graca')
  end

  it 'corrigir um passo já respondido vale a nova resposta e volta a seguir dali' do
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim') # pulou para sequela
    res = registrar('recebeu_auxilio', 'nao')

    expect(res[:proximo].chave).to eq('data_acidente')
    expect(res[:estado].dig('respostas', 'recebeu_auxilio', 'valor')).to eq('nao')
  end

  it 'nada casando vai para a equipe com sino ao gestor' do
    admin = create(:user, account: account, role: :administrator)
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim')
    res = registrar('sequela', 'nao sei dizer')

    expect(res[:estado]['desfecho']).to eq('humano')
    expect(res[:estado]['motivo']).to include('roteiro sem saida no passo sequela')
    expect(conversation.reload.status).to eq('open')
    expect(conversation.custom_attributes['copiloto_modo']).to eq('rascunho')
    expect(Notification.where(user: admin, primary_actor: lead, notification_type: 'ramon_fluxo_aviso').count).to eq(1)
  end

  it 'ir_para para passo inexistente vai para a equipe' do
    RoteiroPasso.find_by(chave: 'recebeu_auxilio').update!(saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'ir_para', 'alvo' => 'sumiu' }])
    registrar('tem_advogado', 'nao')
    expect(registrar('recebeu_auxilio', 'sim')[:estado]['motivo']).to include('destino sumiu nao existe')
  end

  it 'valor inválido não grava nada' do
    expect(registrar('tem_advogado', 'talvez')).to eq(erro: 'Responda sim ou nao.')
    expect(registrar('data_acidente', '31/02/2026')[:erro]).to include('AAAA-MM-DD')
    expect(registrar('sequela')[:erro]).to include('saida_id')
    expect(registrar('sequela', 'x', saida_id: 'nao_tem')[:erro]).to include('nao existe')
    expect(registrar('xablau', 'sim')[:erro]).to include('tem_advogado, recebeu_auxilio')
    expect(lead.reload.custom_attributes['roteiro']).to be_nil
  end

  it 'depois do desfecho recusa (inclusive correção) e não mexe em nada' do
    registrar('tem_advogado', 'sim')
    expect(registrar('recebeu_auxilio', 'nao')[:erro]).to include('ja terminou')
    expect(registrar('tem_advogado', 'nao')[:erro]).to include('ja terminou')
    expect(lead.reload.custom_attributes.dig('roteiro', 'respostas')).to eq('tem_advogado' => a_hash_including('valor' => 'sim'))
  end

  it 'lead ganho não volta para Perdido nem vira sugestão' do
    ganho = account.lead_stages.find_by!(is_won: true)
    lead.update_columns(lead_stage_id: ganho.id, won_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- sem disparar o fluxo "Lead ganho"
    registrar('tem_advogado', 'sim')
    expect(lead.reload.lead_stage).to eq(ganho)
    expect(account.copilot_suggestions.count).to eq(0)
  end

  it 'trocar a tese recomeça o roteiro e mantém os comuns' do
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'nao')
    bpc = create(:thesis, account: account)
    create(:roteiro_passo, account: account, thesis: bpc, chave: 'renda', position: 1)
    lead.update!(thesis: bpc)

    atual = described_class.atual(lead.reload)
    expect(atual[:passo].chave).to eq('renda')
    expect(atual[:estado]['respostas'].keys).to eq(['tem_advogado'])
  end

  it 'descrever mostra o passo, as saídas do texto e o que já foi respondido' do
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim')
    texto = described_class.descrever(*described_class.atual(lead.reload).values_at(:passo, :estado))
    expect(texto).to include('Passo atual: Sequela (chave: sequela')
      .and include('ficou = ficou alguma limitacao').and include('tem_advogado=nao')
    expect(described_class.descrever(nil, { 'desfecho' => 'humano', 'motivo' => 'x', 'respostas' => {} }))
      .to include('Roteiro encerrado: humano (x)')
  end
end
```

- [ ] **Step 2: Implementar a porta de entrada**

`app/services/ramon/roteiro.rb`:

```ruby
# Motor do roteiro da tese (spec docs/superpowers/specs/2026-10-13-roteiro-da-tese-design.md §3.2–3.4).
# Regra fixa: a IA pergunta e informa a resposta; aqui se grava, se faz a conta e se escolhe a saída.
# Estado em lead.custom_attributes['roteiro']:
#   tese_id · cursor (chave; muda no ir_para e na correção) · desfecho (qualificado|desqualificado|humano) · motivo ·
#   decisivo (passo que encerrou) · aguarda_equipe (Perdido virou sugestão) · respostas { chave => { valor, calc, saida, em } }
# Passo atual = o 1º sem resposta a partir do cursor: resposta adiantada pelo lead não é perguntada de novo.
# ponytail: last-write-wins no custom_attributes (duas respostas no mesmo instante); with_lock se aparecer corrida.
module Ramon::Roteiro
  TIPOS = { 'sim_nao' => 'sim ou nao', 'escolha' => 'uma das opcoes', 'numero' => 'numero',
            'data' => 'data AAAA-MM-DD', 'texto' => 'texto livre + saida_id' }.freeze
  COMUNS_OK = 'Passos comuns concluidos e esta tese nao tem roteiro proprio: siga a triagem de sempre ' \
              '(playbook da tese e registrar qualificacao).'.freeze

  module_function

  # Comuns da conta (em toda tese) e depois os da tese. Nenhum passo = sem roteiro (triagem de sempre).
  # ponytail: lead sem tese fica sem roteiro até a F3 (tese automática + passo comum "assunto").
  def passos(lead)
    return [] if lead.thesis_id.nil?

    RoteiroPasso.comuns.where(account_id: lead.account_id).to_a + RoteiroPasso.where(thesis_id: lead.thesis_id).to_a
  end

  # Trocar a tese reinicia o roteiro; as respostas dos passos comuns ficam.
  def estado(lead)
    salvo = (lead.custom_attributes || {})['roteiro'].deep_dup || {}
    return salvo.reverse_merge('respostas' => {}) if salvo['tese_id'] == lead.thesis_id

    comuns = RoteiroPasso.comuns.where(account_id: lead.account_id).pluck(:chave)
    { 'tese_id' => lead.thesis_id, 'respostas' => (salvo['respostas'] || {}).slice(*comuns) }
  end

  def proximo(lista, est)
    inicio = lista.index { |p| p.chave == est['cursor'] } || 0
    lista[inicio..].find { |p| !est['respostas'].key?(p.chave) }
  end

  def atual(lead)
    lista = passos(lead)
    return if lista.empty?

    est = estado(lead)
    { passo: est['desfecho'] ? nil : proximo(lista, est), estado: est }
  end

  def registrar(lead, chave:, valor: nil, saida_id: nil)
    Registro.new(lead).call(chave: chave, valor: valor, saida_id: saida_id)
  end

  # Reabre no passo que decidiu (as outras respostas ficam) e devolve a conversa ao modo de antes (decisões 13/10).
  # Chamado ao recusar o Perdido sugerido pelo roteiro, ao tirar o lead do Perdido no Kanban e, na F2, pelo painel.
  def reabrir(lead, se: nil)
    est = estado(lead)
    return false if est['desfecho'].nil? || (se && est['desfecho'] != se)

    est['respostas'].delete(est['decisivo'])
    est['cursor'] = est['decisivo']
    novo = est.except('desfecho', 'motivo', 'decisivo', 'aguarda_equipe')
    lead.update!(custom_attributes: (lead.custom_attributes || {}).merge('roteiro' => novo))
    Efeitos.reabrir(lead)
    true
  end

  # Texto para a IA: o passo a perguntar (ou o desfecho) e o que já foi respondido.
  def descrever(passo, est)
    return encerrado(est) if passo.nil?

    linhas = ["Passo atual: #{passo.titulo} (chave: #{passo.chave}; resposta: #{TIPOS[passo.tipo_resposta]})"]
    linhas << "Como perguntar: #{passo.orientacao}" if passo.orientacao.present?
    linhas << "Opcoes: #{passo.opcoes.join(' | ')}" if passo.tipo_resposta == 'escolha'
    linhas << "Saidas (informe saida_id): #{passo.saidas.map { |s| "#{s['id']} = #{s['quando']}" }.join('; ')}" if passo.tipo_resposta == 'texto'
    respondidas = est['respostas'].map { |chave, r| "#{chave}=#{r['valor'] || r['saida']}" }
    linhas << "Ja respondido: #{respondidas.join('; ')}" if respondidas.any?
    linhas.join("\n")
  end

  def encerrado(est)
    return COMUNS_OK if est['desfecho'].nil?

    motivo = " (#{est['motivo']})" if est['motivo']
    espera = ' - aguardando a equipe confirmar' if est['aguarda_equipe']
    "Roteiro encerrado: #{est['desfecho']}#{motivo}#{espera}. Nao faca mais perguntas do roteiro."
  end

  # Texto para a IA depois de registrar.
  def resumo(res)
    partes = ['Registrado.']
    partes << "Conta: #{res[:calc][:resultado]} (#{res[:calc][:detalhe]})." if res[:calc]
    partes << "Base para a resposta: #{res[:mensagem]}" if res[:mensagem].present?
    partes << descrever(res[:proximo], res[:estado])
    partes.join("\n")
  end
end
```

- [ ] **Step 3: Implementar o registro**

`app/services/ramon/roteiro/registro.rb`:

```ruby
# Registra a resposta da IA num passo do roteiro: normaliza, faz a conta, escolhe a saída, avança o estado e aplica
# os efeitos (spec 2026-10-13 §3.4 e §5). Porta de entrada: Ramon::Roteiro.registrar.
class Ramon::Roteiro::Registro
  SEGUIR = { 'id' => 'seguir', 'acao' => 'seguir' }.freeze
  DESFECHOS = { 'concluir' => 'qualificado', 'desqualificar' => 'desqualificado', 'humano' => 'humano' }.freeze

  def initialize(lead)
    @lead = lead
    @lista = Ramon::Roteiro.passos(lead)
    @est = Ramon::Roteiro.estado(lead)
  end

  # @return { erro: } | { estado:, proximo:, calc:, mensagem: }
  def call(chave:, valor: nil, saida_id: nil)
    @passo = @lista.find { |p| p.chave == chave.to_s }
    erro = recusa(chave)
    return { erro: erro } if erro

    normal, erro = Ramon::Roteiro::Resposta.normalizar(@passo, valor)
    erro ||= 'Informe o valor da resposta ou o saida_id.' if normal.nil? && saida_id.blank?
    return { erro: erro } if erro

    calc = calcular(normal)
    saida = escolher(saida_id, calc ? calc[:resultado] : normal)
    return { erro: "A saida #{saida_id} nao existe neste passo." } if saida.nil?

    gravar(normal, calc, saida)
  end

  private

  def recusa(chave)
    return 'Este caso nao tem roteiro.' if @lista.empty?
    return "O roteiro ja terminou (#{@est['desfecho']}). Nao registre mais passos." if @est['desfecho']

    "Passo #{chave} nao existe. Passos: #{@lista.map(&:chave).join(', ')}." if @passo.nil?
  end

  # Campos da calculadora vêm das respostas; o do próprio passo, da resposta de agora.
  def calcular(valor)
    return if @passo.calculadora.blank?

    campos = @passo.calculadora_campos.transform_values do |chave|
      chave == @passo.chave ? valor : @est.dig('respostas', chave, 'valor')
    end
    Ramon::Roteiro::Calculadoras.calcular(@passo.calculadora, campos)
  end

  # Sem saídas = só coleta (segue). Com saídas e nada casando = roteiro sem saída (equipe).
  def escolher(saida_id, comparado)
    return SEGUIR if @passo.saidas.blank?
    return @passo.saidas.find { |s| s['id'].to_s == saida_id.to_s } if saida_id.present?

    @passo.saidas.find { |s| Ramon::Roteiro::Resposta.casa?(s['quando'], comparado) } || sem_saida('nenhuma saida casou')
  end

  def gravar(valor, calc, saida)
    # Correção de um passo já respondido: vale a nova resposta e o roteiro volta a seguir dali (decisão 13/10).
    @est['cursor'] = @passo.chave if @est['respostas'].key?(@passo.chave)
    @est['respostas'][@passo.chave] = { 'valor' => valor, 'calc' => calc&.stringify_keys, 'saida' => saida['id'],
                                        'em' => Time.zone.now.iso8601 }.compact
    saida = avancar(saida)
    @est['aguarda_equipe'] = true if saida['acao'] == 'desqualificar' && !Ramon::Roteiro::Efeitos.direto?(@lead)
    @lead.update!(custom_attributes: (@lead.custom_attributes || {}).merge('roteiro' => @est))
    Ramon::Roteiro::Efeitos.aplicar(@lead, @passo, saida)
    { estado: @est, proximo: @est['desfecho'] ? nil : Ramon::Roteiro.proximo(@lista, @est), calc: calc,
      mensagem: saida['mensagem'] }
  end

  # ir_para move o cursor; seguir/ir_para sem passo pela frente = concluir (qualificado) — menos numa tese sem
  # passos próprios: ao fim dos comuns a IA volta para a triagem de sempre, sem desfecho (decisão 13/10).
  def avancar(saida)
    if saida['acao'] == 'ir_para'
      return avancar(sem_saida("destino #{saida['alvo']} nao existe")) if @lista.none? { |p| p.chave == saida['alvo'] }

      @est['cursor'] = saida['alvo']
    end
    fim = %w[seguir ir_para].include?(saida['acao']) && Ramon::Roteiro.proximo(@lista, @est).nil?
    saida = saida.merge('acao' => 'concluir') if fim && @lista.any?(&:thesis_id)
    encerrar(saida)
    saida
  end

  def encerrar(saida)
    desfecho = DESFECHOS[saida['acao']]
    return if desfecho.nil?

    @est.merge!('desfecho' => desfecho, 'motivo' => saida['motivo'], 'decisivo' => @passo.chave)
  end

  def sem_saida(detalhe)
    { 'id' => 'sem_saida', 'acao' => 'humano', 'motivo' => "roteiro sem saida no passo #{@passo.chave} (#{detalhe})" }
  end
end
```

- [ ] **Step 4: Lint + commit**

```bash
rubocop-vps app/services/ramon/roteiro.rb app/services/ramon/roteiro/registro.rb spec/services/ramon/roteiro_spec.rb
git add app/services/ramon/roteiro.rb app/services/ramon/roteiro/registro.rb spec/services/ramon/roteiro_spec.rb
git commit -m "feat(roteiro): motor do roteiro da tese (passo atual, registrar, desfecho por regra fixa)"
```

Se o `rubocop-vps` acusar `Metrics/*` em `descrever`, `call` ou `gravar`, extrair um método privado/auxiliar (ex.: `linhas_de_saida(passo)`, `gravar_resposta(valor, calc, saida)`) — não desligar o cop.

---

### Task 5: Aprovar, recusar e tirar do Perdido (Cockpit e Kanban)

**Files:**
- Modify: `app/models/copilot_suggestion.rb` (`marcar_perdido` cala a IA quando a origem é o roteiro; `dismiss!` novo)
- Modify: `app/controllers/api/v1/accounts/copilot_suggestions_controller.rb` (`dismiss` chama `dismiss!`)
- Modify: `app/models/lead.rb` (callback: saiu do Perdido → reabre o roteiro desqualificado)
- Create: `spec/services/ramon/roteiro_reabrir_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Roteiro.reabrir(lead, se:)`, `Ramon::Roteiro.registrar`, `Ramon::Roteiro.atual` (Task 4), `Ramon::Roteiro::Efeitos.calar` (Task 3)
- Produces: `CopilotSuggestion#dismiss! -> void` (o controller passa a usar; o request spec `dismisses a suggestion` continua valendo)

- [ ] **Step 1: Spec (falha)**

`spec/services/ramon/roteiro_reabrir_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Ramon::Roteiro, '.reabrir' do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: novo, conversation: conversation) }

  before do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'tem_advogado', position: 0, titulo: 'Tem advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'sequela', position: 1, titulo: 'Sequela', tipo_resposta: 'texto',
                           saidas: [{ 'id' => 'ficou', 'quando' => 'ficou', 'acao' => 'concluir' }])
  end

  # Fora do piloto total o Perdido do roteiro vira sugestão no Cockpit.
  def desqualificar!
    described_class.registrar(lead, chave: 'tem_advogado', valor: 'sim')
    account.copilot_suggestions.pending.find_by!(lead: lead, kind: 'acao')
  end

  it 'recusar o Perdido sugerido reabre no passo que decidiu' do
    desqualificar!.dismiss!

    atual = described_class.atual(lead.reload)
    expect(atual[:passo].chave).to eq('tem_advogado')
    expect(atual[:estado].keys).not_to include('desfecho', 'decisivo', 'aguarda_equipe')
    expect(lead.lead_activities.where(kind: 'roteiro').last.to_value).to eq('roteiro reaberto')
  end

  it 'aprovar marca Perdido e cala a IA; tirar do Perdido no Kanban reabre e devolve o modo de antes' do
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_limitado' })
    expect(desqualificar!.apply!).to be(true)
    expect(lead.reload.lost_reason).to eq('Sem viabilidade')
    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('manual')
    expect(conversation.label_list).to include('desqualificado-ia')

    lead.update!(lead_stage: novo)

    expect(conversation.reload.custom_attributes['copiloto_modo']).to eq('piloto_limitado')
    expect(conversation.label_list).not_to include('desqualificado-ia')
    expect(described_class.atual(lead.reload)[:passo].chave).to eq('tem_advogado')
  end

  it 'Kanban e recusa só reabrem desqualificado; reabrir sem filtro volta no passo que decidiu' do
    described_class.registrar(lead, chave: 'tem_advogado', valor: 'nao')
    described_class.registrar(lead, chave: 'sequela', saida_id: 'ficou')
    expect(described_class.reabrir(lead.reload, se: 'desqualificado')).to be(false)

    lead.update!(lead_stage: account.lead_stages.find_by!(is_lost: true))
    lead.update!(lead_stage: novo)
    expect(described_class.atual(lead.reload)[:estado]['desfecho']).to eq('qualificado')

    expect(described_class.reabrir(lead)).to be(true)
    expect(described_class.atual(lead.reload)[:passo].chave).to eq('sequela')
  end

  it 'recusar sugestão que não é do roteiro não mexe no roteiro' do
    described_class.registrar(lead, chave: 'tem_advogado', valor: 'sim')
    outra = account.copilot_suggestions.create!(lead: lead, kind: 'acao', status: 'pending',
                                                payload: { 'acao' => 'perdido', 'texto' => 'sumiu' })
    outra.dismiss!
    expect(described_class.atual(lead.reload)[:estado]['desfecho']).to eq('desqualificado')
  end
end
```

- [ ] **Step 2: `CopilotSuggestion`**

Em `app/models/copilot_suggestion.rb`:

a) Logo depois de `apply!` (método público):

```ruby
  # Recusar o Perdido sugerido pelo roteiro da tese reabre o roteiro no passo que decidiu (decisão 13/10).
  def dismiss!
    update!(status: 'dismissed')
    Ramon::Roteiro.reabrir(lead, se: 'desqualificado') if perdido_do_roteiro?
  end
```

b) Em `marcar_perdido`, trocar a última linha
`lead.update!(lead_stage: etapa, lost_reason: payload['lost_reason'].presence || 'Sugerido pelo agente')`
por:

```ruby
    lead.update!(lead_stage: etapa, lost_reason: payload['lost_reason'].presence || 'Sugerido pelo agente')
    # Perdido do roteiro aprovado: etiqueta e IA calada; a conversa fica com o robô (decisão 13/10).
    Ramon::Roteiro::Efeitos.calar(lead) if perdido_do_roteiro?
    true
```

c) Na seção `private`, antes de `criar_nota`:

```ruby
  def perdido_do_roteiro?
    kind == 'acao' && payload['acao'] == 'perdido' && payload['origem'] == 'roteiro'
  end
```

- [ ] **Step 3: Controller**

Em `app/controllers/api/v1/accounts/copilot_suggestions_controller.rb`, no `dismiss`, trocar `@copilot_suggestion.update!(status: 'dismissed')` por:

```ruby
    @copilot_suggestion.dismiss!
```

- [ ] **Step 4: `Lead`**

Em `app/models/lead.rb`, depois de `after_update_commit :ganhou, if: :saved_change_to_won_at?`:

```ruby
  after_update_commit :reabrir_roteiro, if: -> { saved_change_to_lost_at? && lost_at.nil? }
```

E na seção privada, depois do método `ganhou`:

```ruby
  # Tirar do Perdido no Kanban reabre o roteiro da tese desqualificado (decisão 13/10).
  def reabrir_roteiro
    Ramon::Roteiro.reabrir(self, se: 'desqualificado')
  end
```

(`track_stage_cycle` zera `lost_at` quando o lead sai da etapa de perdido; o `update!` do `reabrir` só mexe em `custom_attributes`, então o callback não se repete.)

- [ ] **Step 5: Lint + commit**

```bash
rubocop-vps app/models/copilot_suggestion.rb app/controllers/api/v1/accounts/copilot_suggestions_controller.rb app/models/lead.rb \
  spec/services/ramon/roteiro_reabrir_spec.rb
git add app/models/copilot_suggestion.rb app/controllers/api/v1/accounts/copilot_suggestions_controller.rb app/models/lead.rb \
  spec/services/ramon/roteiro_reabrir_spec.rb
git commit -m "feat(roteiro): aprovar o Perdido do roteiro cala a IA; recusar ou tirar do Perdido reabre o roteiro"
```

---

### Task 6: Tools do agente + skill de triagem e regras globais (seed)

**Files:**
- Create: `enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb`
- Create: `enterprise/lib/captain/tools/roteiro_registrar_tool.rb`
- Modify: `config/agents/tools.yml` (2 entradas, depois de `registrar_qualificacao`)
- Modify: `enterprise/app/services/captain/assistant/agent_runner_service.rb` (saída humano do roteiro conta como handoff — Step 1b)
- Modify: `db/seeds/ramon/inteligencia/assistentes.yml` (Atendimento: `response_guidelines` + skill "Triagem e qualificação do lead novo")
- Create: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-13-roteiro-f1-textos.md` (gate do Eduardo)

**Interfaces:**
- Consumes: `Ramon::Roteiro.atual/registrar/descrever/resumo` (Task 4), `Captain::Tools::RamonBaseTool#resolver_lead`, `SEM_LEAD`
- Produces: tools `roteiro_passo_atual` (nivel `consulta`) e `roteiro_registrar` (nivel `interna` → no modo teste dos Casos de IA só simula)

- [ ] **Step 1: Tools**

`enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb`:

```ruby
# Leitura: o passo do roteiro da tese que a IA pergunta agora (spec roteiro da tese §3.5). Toda a regra fica em
# Ramon::Roteiro (testada no CI); aqui só resolve o caso e devolve o texto.
class Captain::Tools::RoteiroPassoAtualTool < Captain::Tools::RamonBaseTool
  SEM_ROTEIRO = 'Esta tese nao tem roteiro. Siga a triagem de sempre (playbook da tese e registrar qualificacao).'.freeze

  description 'Diz o passo atual do roteiro de qualificacao da tese do caso: o que descobrir, como perguntar, as ' \
              'opcoes e o que ja foi respondido. Chame antes de cada pergunta de qualificacao.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false

  def perform(tool_context, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    atual = ::Ramon::Roteiro.atual(lead)
    return SEM_ROTEIRO if atual.nil?

    log_tool_usage('roteiro_passo_atual', { lead_id: lead.id })
    ::Ramon::Roteiro.descrever(atual[:passo], atual[:estado])
  end
end
```

`enterprise/lib/captain/tools/roteiro_registrar_tool.rb`:

```ruby
# Escrita interna (nada sai para o cliente): grava a resposta do lead num passo do roteiro. O motor faz a conta,
# escolhe a saida e aplica as consequencias fixas (etiqueta, etapa, Perdido, passar para a equipe).
class Captain::Tools::RoteiroRegistrarTool < Captain::Tools::RamonBaseTool
  description 'Registra a resposta do lead a um passo do roteiro da tese. Informe a chave do passo e o valor ' \
              '(sim/nao, uma das opcoes, numero, data AAAA-MM-DD ou texto). Em passo de texto livre, informe tambem ' \
              'o saida_id que melhor descreve a resposta. Devolve o proximo passo ou o desfecho.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false
  param :chave, type: 'string', desc: 'Chave do passo (vem do Passo atual do roteiro)', required: true
  param :valor, type: 'string', desc: 'Resposta do lead, no formato do passo', required: false
  param :saida_id, type: 'string', desc: 'Id da saida escolhida (passo de texto livre)', required: false

  def perform(tool_context, chave:, valor: nil, saida_id: nil, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    log_tool_usage('roteiro_registrar', { lead_id: lead.id, chave: chave })
    res = ::Ramon::Roteiro.registrar(lead, chave: chave, valor: valor, saida_id: saida_id)
    res[:erro] || ::Ramon::Roteiro.resumo(res)
  end
end
```

`config/agents/tools.yml` — logo depois do bloco `- id: registrar_qualificacao` (linha em branco antes e depois, como os vizinhos):

```yaml
- id: roteiro_passo_atual
  title: 'Passo atual do roteiro'
  description: 'O que perguntar agora no roteiro de qualificação da tese do lead'
  icon: 'checkmark-circle'
  nivel: consulta
  sistema: funil

- id: roteiro_registrar
  title: 'Registrar no roteiro'
  description: 'Grava a resposta do lead no roteiro; o motor aplica a consequência (segue, desqualifica, equipe)'
  icon: 'checkmark-circle'
  nivel: interna
  sistema: funil
```

- [ ] **Step 1b: Handoff do roteiro no meio do turno (ruling 13/10, achado na execução)**

Quando `roteiro_registrar` encerra como `humano`, `Efeitos.humano` chama `bot_handoff!` no meio do turno da IA. O `ResponseBuilderJob#process_response` só publica a resposta se a conversa ainda está `pending`, e o sinal `handoff_tool_called` só é ligado pela `HandoffTool` — então a resposta do turno some e o lead fica sem nada. Correção: o runner trata a saída humano do roteiro como handoff, e o job manda a mensagem de handoff do assistente (rascunho fora do piloto, como no handoff nativo).

Em `enterprise/lib/captain/tools/roteiro_registrar_tool.rb`, dentro da classe, antes de `description`:

```ruby
  # Texto que Ramon::Roteiro.descrever devolve quando o roteiro acaba de passar o caso para a equipe; o
  # AgentRunnerService trata isso como handoff (a conversa já saiu do bot e a resposta do turno não publicaria).
  HANDOFF = 'Roteiro encerrado: humano'.freeze
```

Em `enterprise/app/services/captain/assistant/agent_runner_service.rb`:

a) em `add_usage_metadata_callback`, trocar o bloco `runner.on_tool_complete do |tool_name, _tool_result, context_wrapper|` por:

```ruby
    runner.on_tool_complete do |tool_name, tool_result, context_wrapper|
      track_handoff_usage(tool_name, handoff_tool_name, context_wrapper, tool_result)
    end
```

b) em `track_handoff_usage`, mudar a assinatura e a guarda:

```ruby
  def track_handoff_usage(tool_name, handoff_tool_name, context_wrapper, tool_result = nil)
    return unless context_wrapper&.context
    return unless tool_name.to_s == handoff_tool_name || roteiro_handoff?(tool_name, tool_result)
```

(o resto do método igual) e, logo depois dele:

```ruby
  # Saída "humano" do roteiro da tese já fez bot_handoff! (Ramon::Roteiro::Efeitos.humano): mesmo caminho do handoff nativo.
  def roteiro_handoff?(tool_name, tool_result)
    tool_name.to_s == 'roteiro_registrar' && tool_result.to_s.include?(Captain::Tools::RoteiroRegistrarTool::HANDOFF)
  end
```

Antes de editar, confira no código real o nome que o runner usa para a tool (`Captain::Tools::RoteiroRegistrarTool.new(assistant).name` — se não for `'roteiro_registrar'`, compare com esse nome como o método já faz com a HandoffTool). Um registro que bate num roteiro já encerrado devolve "O roteiro ja terminou (humano)…" — não contém `HANDOFF`, então não dispara de novo.

- [ ] **Step 2: Seed — regras globais e skill de triagem**

Em `db/seeds/ramon/inteligencia/assistentes.yml`, assistente **Atendimento**:

a) Substituir a linha de `response_guidelines`
`- "Sempre que uma dúvida exigir decisão jurídica sobre o caso concreto, ou o lead pedir para falar com uma pessoa/advogado, passe para humano — e diga ao lead que alguém da equipe vai chamá-lo."`
por:

```yaml
      - "Sempre que uma dúvida exigir decisão jurídica sobre o caso concreto, ou o lead disser que quer contratar ou pedir para falar com uma pessoa/advogado, passe para humano. Nunca diga que está \"transferindo\": diga só que alguém da equipe continua a conversa por aqui."
```

b) Acrescentar ao fim de `response_guidelines`:

```yaml
      - "Uma pergunta por vez, em 1 ou 2 frases. Não repita o que o lead já contou nem pergunte de novo o que ele já respondeu."
      - "Se o lead perguntar o valor do honorário pela segunda vez depois da sua resposta, passe para humano."
      - "Se o lead disser que não sabe ler ou tiver dificuldade com mensagem escrita, passe para humano informando esse motivo."
```

c) Na skill `Triagem e qualificação do lead novo`, **antes** do parágrafo "Antes de perguntar qualquer coisa, consulte [Triagem da LP]…", inserir (mesma indentação do bloco `instruction: |`):

```yaml
          Primeiro veja se a tese do caso tem roteiro: chame [Passo atual do roteiro](tool://roteiro_passo_atual).
          Com roteiro, ele manda na qualificação: pergunte só o passo atual, do jeito da orientação; entenda a
          resposta e grave com [Registrar no roteiro](tool://roteiro_registrar) — a chave do passo e o valor (sim ou
          nao, uma das opções, número, data AAAA-MM-DD ou texto; em texto livre, informe também o saida_id que melhor
          descreve a resposta). Se o lead já respondeu um passo antes de você perguntar, registre sem perguntar de
          novo. Repita até o roteiro encerrar. Quando vier "Base para a resposta", use esse texto como base, com as
          suas palavras. Encerrado como qualificado → siga para a reunião (skill de agendamento); desqualificado →
          explique com gentileza e honestidade, sem prometer nada — mas, se vier "aguardando a equipe confirmar",
          não diga que o caso não tem viabilidade: diga só que a equipe vai analisar e retorna por aqui; humano →
          diga que alguém da equipe continua a conversa por aqui. As consequências (etapa, etiqueta, equipe) quem
          aplica é o roteiro — não use Mover de etapa nem Marcar como perdido para isso.
          Sem roteiro ("Esta tese nao tem roteiro") ou com os passos comuns concluídos ("siga a triagem de sempre"),
          siga o restante desta instrução.

```

- [ ] **Step 3: Doc dos textos para o Eduardo (gate)**

`C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-13-roteiro-f1-textos.md` — rascunho para aprovação, com: (1) as 3 regras globais novas e a regra reescrita (texto exato do Step 2), (2) o parágrafo novo da skill de triagem, (3) o aviso: "nada disso muda o atendimento enquanto nenhuma tese tiver passos de roteiro (F4); ativar = rodar o seed depois do aprovado", (4) o destaque da frase do desqualificado **aguardando a equipe** (em rascunho e piloto limitado o Perdido vira sugestão; a IA não diz ao lead que não tem viabilidade antes de você aprovar — confirmar se é isso), (5) uma pergunta: *"quer contratar → passar para humano" (spec §3.5) vale também nas conversas em rascunho, onde hoje a skill Fechar contrato prepara o ZapSign para você aprovar? A F3 refina isso no modo 'sozinho até contrato'.*

- [ ] **Step 4: Lint + commit** (o arquivo `.md` do comercial fica fora do repo do hub)

```bash
rubocop-vps enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb enterprise/lib/captain/tools/roteiro_registrar_tool.rb \
  enterprise/app/services/captain/assistant/agent_runner_service.rb
git add enterprise/lib/captain/tools/roteiro_passo_atual_tool.rb enterprise/lib/captain/tools/roteiro_registrar_tool.rb \
  enterprise/app/services/captain/assistant/agent_runner_service.rb config/agents/tools.yml db/seeds/ramon/inteligencia/assistentes.yml
git commit -m "feat(inteligencia): tools do roteiro da tese e triagem guiada pelo roteiro (texto aguarda aprovação)"
```

---

### Task 7: PR, CI, merge, deploy, prova e registro

**Files:**
- Modify: `C:\Users\dudsl\.claude\projects\C--Users-dudsl-RAdvogados\memory\roteiro-da-tese.md`

- [ ] **Step 1: Push e PR** (push = Eduardo via `!` se o classificador barrar)

```bash
git push -u origin feat/roteiro-f1-motor
gh pr create --base ramon --title "feat(roteiro): motor do roteiro da tese (F1)" --body-file <corpo>
```

Corpo: parágrafo de produto ("a IA passa a qualificar seguindo os passos cadastrados da tese; as consequências são regra fixa; sem passos cadastrados nada muda"); os 6 desvios deliberados e as decisões do grilling (etapa/Perdido por modo, reabrir, comuns em toda tese, correção); "Como testar" = a prova do Step 4; o aviso de que a skill/regras novas só são ativadas com o seed após o aprovado; rodapé de atribuição.

- [ ] **Step 2: CI 100% verde** — spec/lint vermelho → corrigir, `rubocop-vps`, novo commit (sem amend). 429/503 baixando actions = re-rodar o job.

- [ ] **Step 3: Merge (squash) e deploy** — regime autônomo com CI verde (CLAUDE.md do ramon-hub). Migração só de estrutura (sem dados). Na VPS: `docker pull ghcr.io/doods-maker/ramon-hub:sha-<7>` + `docker tag … :v4.15.1-ramon` + `docker compose run --rm --no-deps chatwoot-web bundle exec rails db:migrate` + `docker compose up -d chatwoot-web chatwoot-worker`. Conferir a label da imagem e login 200 em https://chat.ramonantonio.adv.br.

- [ ] **Step 4: Prova em produção sem deixar rastro** (tudo numa transação desfeita; o push do ntfy enfileirado acha o lead apagado e não sai). Rodar via `cat prova.rb | ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails runner "eval(STDIN.read)"'`:

```ruby
ActiveRecord::Base.transaction do
  a = Account.find(2)
  t = a.theses.create!(name: "Prova roteiro #{Time.now.to_i}")
  RoteiroPasso.create!(account: a, thesis: t, position: 1, chave: 'recebeu_auxilio', titulo: 'Recebeu auxilio-doenca',
                       orientacao: 'Pergunte se recebeu auxilio-doenca por causa do acidente.',
                       saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'ir_para', 'alvo' => 'sequela' },
                                { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
  RoteiroPasso.create!(account: a, thesis: t, position: 2, chave: 'renda', titulo: 'Renda', tipo_resposta: 'numero')
  RoteiroPasso.create!(account: a, thesis: t, position: 3, chave: 'sequela', titulo: 'Sequela', tipo_resposta: 'texto',
                       saidas: [{ 'id' => 'ficou', 'quando' => 'ficou limitacao', 'acao' => 'concluir' },
                                { 'id' => 'voltou', 'quando' => 'voltou 100%', 'acao' => 'desqualificar', 'motivo' => 'sem sequela' }])
  etapa = a.lead_stages.where(is_won: false, is_lost: false).first
  lead = a.leads.create!(name: 'Prova roteiro', thesis: t, lead_stage: etapa)
  asst = Captain::Assistant.find_by(account: a, name: 'Atendimento')
  ctx = Struct.new(:state).new({})
  atual = Captain::Tools::RoteiroPassoAtualTool.new(asst)
  reg = Captain::Tools::RoteiroRegistrarTool.new(asst)
  puts atual.perform(ctx, lead_id: lead.id.to_s)                                    # Passo atual: Recebeu auxilio-doenca
  puts reg.perform(ctx, lead_id: lead.id.to_s, chave: 'recebeu_auxilio', valor: 'Sim!') # Proximo: Sequela (pulou renda)
  puts reg.perform(ctx, lead_id: lead.id.to_s, chave: 'sequela', valor: 'dor no punho', saida_id: 'ficou')
  # => Roteiro encerrado: qualificado
  puts reg.perform(ctx, lead_id: lead.id.to_s, chave: 'renda', valor: '1000')       # recusa: ja terminou
  p lead.reload.custom_attributes['roteiro']
  p lead.lead_activities.where(kind: 'roteiro').pluck(:to_value)                   # ["Sequela → qualificado"]
  puts atual.perform(ctx, lead_id: a.leads.where.not(thesis_id: t.id).where.not(thesis_id: nil).first.id.to_s)
  # => Esta tese nao tem roteiro (tese real sem passos: produção segue igual)

  # Lead sem conversa = fora do piloto total: o Perdido vira sugestão; recusar reabre no passo que decidiu.
  l2 = a.leads.create!(name: 'Prova roteiro 2', thesis: t, lead_stage: etapa)
  puts reg.perform(ctx, lead_id: l2.id.to_s, chave: 'sequela', valor: 'voltou 100%', saida_id: 'voltou')
  # => Roteiro encerrado: desqualificado (sem sequela) - aguardando a equipe confirmar
  s = a.copilot_suggestions.pending.find_by!(lead: l2, kind: 'acao')
  p s.payload                                    # acao perdido, lost_reason Sem viabilidade, origem roteiro
  s.dismiss!
  puts atual.perform(ctx, lead_id: l2.id.to_s)   # => Passo atual: Sequela
  raise ActiveRecord::Rollback
end
puts RoteiroPasso.count # => 0
```

- [ ] **Step 5: Registro** — atualizar `memory\roteiro-da-tese.md`: PR, squash, VPS sha, migração aplicada, prova OK, textos aguardando aprovado (doc `2026-10-13-roteiro-f1-textos.md`) → depois `rake 'ramon:inteligencia:seed[2]'`; próximo = plano F2 (telas). Smoke visual não há nesta fatia (sem tela); o smoke do Eduardo é a leitura do doc de textos.

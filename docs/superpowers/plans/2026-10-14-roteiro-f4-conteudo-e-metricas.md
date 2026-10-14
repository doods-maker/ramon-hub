# F4 — Conteúdo dos roteiros + métricas · Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** os três roteiros aprovados (auxílio-acidente, BPC/LOAS, salário-maternidade) e os passos comuns entram no hub por um seed idempotente que respeita o que o admin editou na tela, e o Metabase passa a mostrar o funil do roteiro por tese, onde os leads param, os motivos de desqualificação/equipe e os limites dos modos "sozinha até…".

**Architecture:** `Ramon::Roteiro::Seed` (em `app/`, testado no CI) lê `db/seeds/ramon/roteiros/*.yml` (comuns primeiro), cria/renomeia a tese quando preciso, faz upsert dos passos por (tese, chave) pulando os `edited`, cria as etiquetas usadas e, no fim, roda a `Ramon::Roteiro::Conferencia` da F2 em tudo — erro desfaz a transação inteira. Rake `ramon:roteiros:seed[conta]`. Para a métrica "onde param", o `Registro` da F1 passa a gravar `passo` (o próximo a perguntar) no estado. View scenic `bi_roteiro` sobre `leads.custom_attributes->'roteiro'` + o carimbo `copiloto_limite` da conversa (F3), sem expor o texto das respostas. Quatro cards no bloco Inteligência do Metabase pelo script idempotente que já existe (`scripts/metabase_bi_ia_cards.py`, que passa a ter uma lista de blocos).

**Tech Stack:** Rails 7.1 (fork Chatwoot 4.15.1), RSpec, scenic (views), Python 3 + API do Metabase.

**Spec:** `docs/superpowers/specs/2026-10-13-roteiro-da-tese-design.md` §3.1–3.2, §3.9, §3.10, §5 e §6 (F4). Conteúdo: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-13-roteiros-f4-rascunho.md` §3 (APROVADO pelo Eduardo em 14/10, "pode continuar" = D1–D35 com os padrões propostos), corrigido por `…\2026-10-13-roteiros-f4-citacoes.md` (vale a conferência onde as duas divergem). Planos anteriores cujas interfaces esta fatia consome: F1 `docs/superpowers/plans/2026-10-13-roteiro-f1-motor.md` (mergeado, #240), F2 `…-roteiro-f2-telas.md`, F3 `…-roteiro-f3-tese-e-modos.md`.

## Decisões que tomei sem perguntar (revisar)

1. **Passo comum `assunto` entra no `comuns.yml`** (posição 2, entre nome e tem advogado — ordem da spec §3.5). O D3 do rascunho o deixou de fora "porque só faz sentido na F3"; esta fatia roda depois da F3. **A orientação dele é a única fala nova fora do rascunho aprovado** → o seed em produção espera o aprovado dela (Task 5, Step 6). Efeito: lead sem tese passa a ter roteiro (nome → assunto); sem palavras-chave nas teses, o assunto cai em "equipe" (regra da F3).
2. **D19 aplicado (renomear a tese do BPC):** `bpc-loas.yml` usa `tese: "BPC/LOAS (idoso ou pessoa com deficiência)"` + `antes: ["BPC/LOAS por deficiência"]` (o mesmo idioma `antes:` do `assistentes.yml`): o seed acha a tese pelo nome antigo e renomeia, sem trocar o id (leads, FAQs e honorário seguem ligados). `theses_seed.yml` **não muda** (conta nova nasce com o nome antigo e o seed renomeia; specs da F3 usam o nome antigo). Descrição e itens do Playbook do BPC continuam falando só de deficiência — fora desta fatia.
3. **Única mudança no texto aprovado:** D24 (orientação de `moradores`) — "pais (ou padrasto e madrasta)" vira "pai e mãe (padrasto ou madrasta só quando falta um dos dois)", porque a conferência de citações diz "padrasto/madrasta só na ausência de um dos pais" (Lei 8.742, art. 20 §1º). Os marcadores `[CONFERIR]` dos comentários do YAML viraram o resultado da conferência (comentário não vai para a IA).
4. **D8 (etiquetas):** o seed cria na conta as etiquetas das saídas (`temadvogado`, `acidente`, `doenca`, `idoso`, `falta-laudo`) e a `desqualificado-ia` da F1, com a cor padrão do hub (`#1f93ff`) e visíveis na barra lateral, pelo `Ramon::StageLabelSync.ensure_label` que já existe.
5. **Demais pontos abertos do rascunho ficam como escritos:** D5 (qualificado → etapa "Qualificação", sugestão fora do piloto), D9 ("quer trocar de advogado" também cai fora), D12 (invalidez do próprio acidente → equipe), D27 (64 anos sem deficiência: desqualifica, **sem** etiqueta de retomada — o rascunho não propôs padrão), D30 ("30 dias" pela fala da lead).
6. **Mecânica do seed:** passo achado por (tese, chave); `edited = true` (salvo na tela da F2) → pulado; posição = ordem no YAML (1, 2, 3…); campo ausente no YAML volta ao vazio (`opcoes []`, `saidas []`, `calculadora nil`, `calculadora_campos {}`, `orientacao nil`) para não sobrar configuração velha; passo que sair do YAML **não** é apagado (apaga-se pela tela). Tudo numa transação; a `Conferencia` da F2 roda no fim em todos os passos do seed (inclusive os editados) e qualquer erro desfaz tudo.
7. **Tese criada pelo seed** (só "Salário-maternidade", D32): área `previdenciario`, posição no fim, `honorario_na_tabela = false` (a IA não cita valor — fora da tabela do JUR-02), sem descrição, itens de Playbook ou palavras-chave (tela da F2 / checklist da F3).
8. **Seed em `app/services/ramon/roteiro/seed.rb`**, não em `lib/ramon/` como o `InteligenciaSeed`: o CI testa `app/` e o seed tem regra (edited, renomear, conferência).
9. **"Onde param" = o próximo passo a perguntar**, gravado pelo motor no estado (`roteiro.passo`) a cada registro — a spec §3.2 já previa a chave `passo`. Fica nulo com desfecho. Depois de "Reabrir roteiro" fica nulo até o próximo registro (ponytail: reabrir é raro e a IA registra logo em seguida).
10. **`bi_roteiro` = lead com roteiro OU conversa com o carimbo `copiloto_limite`** (o limite também vale em tese sem roteiro); a coluna `em_roteiro` separa. Sem os valores das respostas (spec §5): só quantas, quando, desfecho, motivo (texto da saída configurada pelo admin, não fala do lead) e o passo que decidiu.
11. **"Parado" = sem resposta há 2 dias ou mais** — o mesmo prazo de "parado" da etapa Novo no funil (`stalled_after_days` 2).
12. **Cards no mesmo script do bloco Inteligência** (spec §3.9), com subtítulo próprio "Inteligência — roteiro da tese" na linha 97, logo abaixo do bloco do agente (linhas 80–96, `metabase_agente_cards.py`). O script passa a percorrer uma lista de blocos; o bloco antigo não muda.

**Perguntas abertas:** nenhuma bloqueante. Gate em produção: aprovado da orientação do `assunto` (decisão 1) antes do `rake ramon:roteiros:seed[2]`.

## Global Constraints

- **Começar só com a F3 mergeada** em `origin/ramon` (a F2 antes dela). Branch `feat/roteiro-f4-conteudo` criada de `origin/ramon` (`git fetch origin && git switch -c feat/roteiro-f4-conteudo origin/ramon`) no worktree `ramon-hub-wt-roteiro`. PR com base `ramon`.
- **Interfaces das fatias anteriores que esta consome** — conferir no código mergeado antes da Task 1; se algo mudou, adaptar só a chamada e anotar no PR:
  - F1: `RoteiroPasso` (`ramon_roteiro_passos`; colunas `account_id, thesis_id, position, chave, titulo, orientacao, tipo_resposta, opcoes, calculadora, calculadora_campos, saidas, edited`; scope `comuns`; default order `position, id`; valida `motivo_perda` no catálogo da conta), `Ramon::Roteiro.atual/registrar/proximo/estado`, `Ramon::Roteiro::Registro#gravar`, `Ramon::Roteiro::Efeitos::ETIQUETA_DESQUALIFICADO`, `Ramon::Roteiro::Calculadoras` (resultados: `periodo_de_graca` dentro/fora/depende · `renda_per_capita` abaixo/acima/depende · `prescricao_5_anos` dentro/ultimo_ano/prescrito/depende · `meses_ate_65` ja_tem_65/menos_de_65/depende · `data_prevista_parto` ja_pode_pedir/aguardar/depende).
  - F2: `Ramon::Roteiro::Conferencia.erros(passo) -> Array<String>` (vazio = ok); o controller da tela grava `edited: true`.
  - F3: `Ramon::Roteiro::ASSUNTO = 'assunto'` (comum só para lead sem tese; com tese, `passos` o tira); `Ramon::CopilotoModo.direto?`; carimbo `conversation.custom_attributes['copiloto_limite'] = { 'limite', 'modo', 'motivo'?, 'em' }`.
  - Existentes: `Ramon::StageLabelSync.ensure_label(account, title, color = nil)`; `Leads::SeedDefaultConfigService` (toda conta nasce com etapas Novo/Qualificação/…/Perdido, motivos "Sem viabilidade"/"Outro"/… e as teses do `theses_seed.yml`, entre elas "Auxílio-acidente (B36)" e "BPC/LOAS por deficiência").
- Sem Ruby local (Smart App Control): Ruby é validado pelo **CI**. Lint antes do push com `rubocop-vps <arquivos>` (Git Bash, ~10 s). Limites: `Metrics/MethodLength` 19, `Metrics/AbcSize` 26, `Metrics/ClassLength` 175, linha 150, `RSpec/MultipleExpectations` 7, `RSpec/ExampleLength` 50. Se um `Metrics/*` acusar, extrair método privado (não desligar o cop). `rubocop-vps` **não** pega cops que leem o schema (ex.: `Rails/UniqueValidationWithoutIndex`) — o CI pega.
- **Specs em `spec/enterprise` não rodam no CI** (o CI apaga `enterprise/`). Toda regra fica em `app/`; nada desta fatia toca `enterprise/`.
- Migração nova: `db/schema.rb` editado à mão (sem Postgres local; o CI faz `db:schema:load`). Versão do topo = `2026_10_14_100001`; se o `schema.rb` já tiver versão maior (F2/F3), renomear a migração para um timestamp posterior e usar esse.
- **Texto que fala com cliente:** o conteúdo do rascunho está aprovado, mas **ativar = rodar o seed em produção depois do deploy** (`rake 'ramon:roteiros:seed[2]'`), e só depois do aprovado da orientação do `assunto` (decisão 1). O código sobe antes.
- Deploy = `docker pull` da imagem + `docker tag` + `db:migrate` (há migração: a view) + `up -d chatwoot-web chatwoot-worker`. Prova em produção = `rails runner` com `raise ActiveRecord::Rollback`.
- Python: `python` (3.13) roda local; `PYTHONUTF8=1` no console do Windows (nomes com "—"/"…"). Credencial do Metabase nunca no repo.
- Commits: Conventional Commits, assunto sem citar Claude, terminando com o rodapé de atribuição da sessão que executar. Nunca `git add -A`: só os caminhos de cada task.

## Review Focus

1. **Seed rodado de novo depois que o admin editou um passo na tela (ou mexeram num passo pelo console)** → o editado fica como está, o não editado volta ao texto do YAML, nada duplica (Task 1).
2. **YAML com "vai para" ou campo de calculadora apontando para chave que não existe (erro de digitação numa revisão futura)** → o seed para com a mensagem do passo e não grava nada, nem a tese criada/renomeada (Task 1).
3. **Lead que pula ramos** (grávida não passa por "já recebeu"; idoso de 65+ não passa por deficiência; auxílio-doença pula o vínculo) → o motor pergunta exatamente o passo seguinte certo, sem repetir nem pular (Task 2: o helper confere o passo atual antes de cada resposta).
4. **Desempregado que responde "não" ao seguro-desemprego/SINE** → vai para a equipe, não para o Perdido (D17); autônomo sem carteira anterior → Perdido sugerido com "Sem viabilidade" (D10) (Task 2).
5. **Respostas com dado pessoal (nome, doença, renda) no estado do lead** → nada disso aparece na `bi_roteiro` nem nos cards (Task 3).

---

### Task 1: Seed dos roteiros (`Ramon::Roteiro::Seed`) + rake

**Files:**
- Create: `app/services/ramon/roteiro/seed.rb`
- Create: `lib/tasks/ramon_roteiros.rake`
- Create: `spec/services/ramon/roteiro/seed_spec.rb`

**Interfaces:**
- Consumes: `RoteiroPasso` (F1), `Ramon::Roteiro::Conferencia.erros` (F2), `Ramon::Roteiro::Efeitos::ETIQUETA_DESQUALIFICADO` (F1), `Ramon::StageLabelSync.ensure_label`
- Produces:
  - `Ramon::Roteiro::Seed::DIR` = `Rails.root.join('db/seeds/ramon/roteiros')`
  - `Ramon::Roteiro::Seed.new(account, dir: DIR).run -> Hash` com contagens `:teses_criadas`, `:passos_criados`, `:passos_atualizados`, `:passos_pulados_editados`, `:etiquetas_conferidas` (chave ausente = 0); levanta `ArgumentError` ("Roteiro com erro (nada foi gravado): …") e desfaz tudo se a conferência acusar
  - Formato do arquivo: `tese:` (nome; `null` = passos comuns), `antes:` (lista de nomes antigos, opcional), `passos:` (lista com `chave`, `titulo`, `orientacao`, `tipo_resposta`, `opcoes`, `calculadora`, `calculadora_campos`, `saidas`)
  - `rake 'ramon:roteiros:seed[account_id]'` (imprime as contagens)

- [ ] **Step 1: Spec (falha)**

`spec/services/ramon/roteiro/seed_spec.rb`:

```ruby
require 'rails_helper'
require 'tmpdir'

RSpec.describe Ramon::Roteiro::Seed do
  let(:account) { create(:account) }
  let(:dir) { Dir.mktmpdir }
  let(:passos) { RoteiroPasso.where(account: account) }

  def arquivo(nome, conteudo) = File.write(File.join(dir, nome), conteudo)
  def semear = described_class.new(account, dir: dir).run

  before do
    arquivo('comuns.yml', <<~YAML)
      tese: null
      passos:
        - chave: tem_advogado
          titulo: "Tem advogado"
          tipo_resposta: sim_nao
          saidas:
            - { id: sim, quando: "sim", acao: desqualificar, motivo: "tem advogado", efeitos: { etiqueta: "TemAdvogado" } }
            - { id: nao, quando: "nao", acao: seguir }
    YAML
    arquivo('bpc.yml', <<~YAML)
      tese: "BPC/LOAS (idoso ou pessoa com deficiência)"
      antes: ["BPC/LOAS por deficiência"]
      passos:
        - chave: recebe_beneficio
          titulo: "Já recebe benefício"
          tipo_resposta: sim_nao
          saidas:
            - { id: sim, quando: "sim", acao: ir_para, alvo: renda }
            - { id: nao, quando: "nao", acao: seguir }
        - { chave: renda, titulo: "Renda", tipo_resposta: numero }
    YAML
    arquivo('nova.yml', <<~YAML)
      tese: "Tese nova do seed"
      passos:
        - { chave: situacao, titulo: "Situação", tipo_resposta: texto }
    YAML
  end

  after { FileUtils.remove_entry(dir) }

  it 'cria os passos na ordem do arquivo, renomeia a tese pelo nome antigo (mesmo id) e cria a que falta' do
    bpc_id = account.theses.find_by!(name: 'BPC/LOAS por deficiência').id

    expect(semear).to include(passos_criados: 4, teses_criadas: 1)
    expect(account.theses.find(bpc_id).name).to eq('BPC/LOAS (idoso ou pessoa com deficiência)')
    expect(passos.where(thesis_id: bpc_id).pluck(:chave, :position)).to eq([['recebe_beneficio', 1], ['renda', 2]])
    expect(passos.comuns.pluck(:chave)).to eq(['tem_advogado'])
    expect(account.theses.find_by!(name: 'Tese nova do seed')).to have_attributes(honorario_na_tabela: false, area: 'previdenciario')
    expect(account.labels.pluck(:title)).to include('temadvogado', 'desqualificado-ia')
  end

  # Review Focus 1.
  it 'rodar de novo não duplica, devolve o texto do arquivo ao passo não editado e pula o editado na tela' do
    semear
    passos.find_by!(chave: 'renda').update!(titulo: 'Mexido no console', opcoes: ['x'])
    passos.find_by!(chave: 'tem_advogado').update!(titulo: 'Editado na tela', edited: true)

    expect(semear).to include(passos_atualizados: 3, passos_pulados_editados: 1)
    expect(passos.count).to eq(4)
    expect(passos.find_by!(chave: 'renda')).to have_attributes(titulo: 'Renda', opcoes: [])
    expect(passos.find_by!(chave: 'tem_advogado').titulo).to eq('Editado na tela')
    expect(account.theses.where(name: 'Tese nova do seed').count).to eq(1)
  end

  # Review Focus 2.
  it 'roteiro com "vai para" sem destino não grava nada, nem tese criada ou renomeada' do
    arquivo('quebrado.yml', <<~YAML)
      tese: "Tese quebrada"
      passos:
        - chave: primeiro
          titulo: "Primeiro"
          tipo_resposta: sim_nao
          saidas: [{ id: sim, quando: "sim", acao: ir_para, alvo: nao_existe }]
    YAML

    expect { semear }.to raise_error(ArgumentError, /primeiro: .*nao_existe/)
    expect(passos.count).to eq(0)
    expect(account.theses.where(name: ['Tese quebrada', 'Tese nova do seed']).count).to eq(0)
    expect(account.theses.where(name: 'BPC/LOAS por deficiência').count).to eq(1)
  end
end
```

- [ ] **Step 2: Implementar o seed**

`app/services/ramon/roteiro/seed.rb`:

```ruby
# Seed dos roteiros da tese (spec 2026-10-13 §3.10, F4): db/seeds/ramon/roteiros/*.yml, comuns.yml primeiro.
# Idempotente: passo achado por (tese, chave); editado na tela (edited, F2) fica como está. Tese que falta é criada fora da
# tabela de honorário (a IA não cita valor); `antes:` acha a tese pelo nome antigo e renomeia (D19), sem trocar o id.
# Tudo numa transação: no fim a Conferencia da tela (F2) roda nos passos do seed e qualquer erro desfaz tudo.
# ponytail: passo que sai do YAML não é apagado — apaga-se pela tela.
class Ramon::Roteiro::Seed
  DIR = Rails.root.join('db/seeds/ramon/roteiros')
  CAMPOS = %w[titulo orientacao tipo_resposta opcoes calculadora calculadora_campos saidas].freeze
  VAZIO = { 'orientacao' => nil, 'opcoes' => [], 'calculadora' => nil, 'calculadora_campos' => {}, 'saidas' => [] }.freeze

  def initialize(account, dir: DIR)
    @account = account
    @dir = Pathname(dir)
    @contagem = Hash.new(0)
    @passos = []
  end

  # @return [Hash] contagens (teses_criadas, passos_criados/atualizados/pulados_editados, etiquetas_conferidas)
  def run
    ActiveRecord::Base.transaction do
      arquivos.each { |dados| semear(dados) }
      conferir!
      etiquetar
    end
    @contagem
  end

  private

  # comuns.yml primeiro, depois os outros em ordem alfabética.
  def arquivos
    Dir[@dir.join('*.yml').to_s].sort_by { |f| [File.basename(f) == 'comuns.yml' ? 0 : 1, f] }
                                .map { |f| YAML.safe_load_file(f) }
  end

  def semear(dados)
    tese = dados['tese'] && tese_de(dados)
    dados.fetch('passos').each.with_index(1) { |attrs, posicao| semear_passo(tese, attrs, posicao) }
  end

  def tese_de(dados)
    tese = @account.theses.find_by(name: [dados['tese'], *dados['antes']]) ||
           @account.theses.new(area: 'previdenciario', position: @account.theses.maximum(:position).to_i + 1)
    @contagem[:teses_criadas] += 1 if tese.new_record?
    tese.update!(name: dados['tese'])
    tese
  end

  def semear_passo(tese, attrs, posicao)
    passo = RoteiroPasso.find_or_initialize_by(account: @account, thesis: tese, chave: attrs.fetch('chave'))
    @passos << passo
    return @contagem[:passos_pulados_editados] += 1 if passo.edited?

    @contagem[passo.new_record? ? :passos_criados : :passos_atualizados] += 1
    passo.update!(VAZIO.merge(attrs.slice(*CAMPOS)).merge('position' => posicao))
  end

  # "Vai para", campos da calculadora e chaves repetidas: a mesma conferência do salvar da tela (F2).
  def conferir!
    erros = @passos.flat_map { |p| Ramon::Roteiro::Conferencia.erros(p).map { |erro| "#{p.chave}: #{erro}" } }
    raise ArgumentError, "Roteiro com erro (nada foi gravado): #{erros.join('; ')}" if erros.any?
  end

  # Etiquetas das saídas + a do desqualificado (D8): existem na conta para aparecer com cor no hub.
  def etiquetar
    titulos = @passos.flat_map { |p| p.saidas.filter_map { |s| s.dig('efeitos', 'etiqueta')&.downcase } }
    (titulos + [Ramon::Roteiro::Efeitos::ETIQUETA_DESQUALIFICADO]).uniq.each do |titulo|
      Ramon::StageLabelSync.ensure_label(@account, titulo)
      @contagem[:etiquetas_conferidas] += 1
    end
  end
end
```

(`@account.theses.maximum` ignora o `default_scope { order(:position) }` da tese — o Rails tira o ORDER BY das contas simples.)

`lib/tasks/ramon_roteiros.rake`:

```ruby
# frozen_string_literal: true

namespace :ramon do
  namespace :roteiros do
    desc 'Seed idempotente dos roteiros da tese (db/seeds/ramon/roteiros) numa conta; passo editado na tela fica. ' \
         'Uso: rake ramon:roteiros:seed[account_id]'
    task :seed, [:account_id] => :environment do |_task, args|
      raise ArgumentError, 'Uso: rake ramon:roteiros:seed[account_id]' if args[:account_id].blank?

      Ramon::Roteiro::Seed.new(Account.find(args[:account_id])).run.each { |chave, valor| puts "#{chave}: #{valor}" }
    end
  end
end
```

- [ ] **Step 3: Lint + commit** (o spec roda no CI, Task 5)

```bash
rubocop-vps app/services/ramon/roteiro/seed.rb lib/tasks/ramon_roteiros.rake spec/services/ramon/roteiro/seed_spec.rb
git add app/services/ramon/roteiro/seed.rb lib/tasks/ramon_roteiros.rake spec/services/ramon/roteiro/seed_spec.rb
git commit -m "feat(roteiro): seed idempotente dos roteiros da tese que respeita o editado na tela"
```

---

### Task 2: Conteúdo aprovado — passos comuns + 3 roteiros

**Files:**
- Create: `db/seeds/ramon/roteiros/comuns.yml`
- Create: `db/seeds/ramon/roteiros/auxilio-acidente.yml`
- Create: `db/seeds/ramon/roteiros/bpc-loas.yml`
- Create: `db/seeds/ramon/roteiros/salario-maternidade.yml`
- Create: `spec/services/ramon/roteiro/roteiros_semeados_spec.rb`

**Interfaces:**
- Consumes: `Ramon::Roteiro::Seed` (Task 1); `Ramon::Roteiro.atual(lead) -> { passo:, estado: } | nil` e `Ramon::Roteiro.registrar(lead, chave:, valor: nil, saida_id: nil) -> { estado:, proximo:, calc:, mensagem: } | { erro: }` (F1, com o `assunto` da F3)
- Produces: os 4 arquivos do seed (42 passos: 3 comuns + 17 + 10 + 12); teses "Auxílio-acidente (B36)", "BPC/LOAS (idoso ou pessoa com deficiência)" (renomeada) e "Salário-maternidade" (criada)

Os arquivos abaixo são o §3 do rascunho aprovado, **copiados sem mudar uma vírgula**, com só estas diferenças (decisões 1–3): cabeçalho de 2 linhas de comentário; passo `assunto` no `comuns.yml`; `tese`/`antes` do BPC; orientação de `moradores` (D24); comentários `[CONFERIR]` trocados pelo resultado da conferência. Se for copiar à mão do rascunho em vez daqui, aplicar essas cinco diferenças.

- [ ] **Step 1: `db/seeds/ramon/roteiros/comuns.yml`**

```yaml
# Conteúdo APROVADO pelo Eduardo em 14/10/2026 ("pode continuar") — fonte: comercial/docs/2026-10-13-roteiros-f4-rascunho.md §3,
# corrigido pela conferência de citações (…-roteiros-f4-citacoes.md). Mudar texto aqui = novo aprovado dele.
tese: null # passos comuns: rodam antes do roteiro de qualquer tese
passos:
  - chave: nome
    titulo: "Nome"
    orientacao: "Se o nome do WhatsApp ou do formulário já é um nome de gente, registre sem perguntar. Senão, pergunte com simpatia como a pessoa se chama. Não use a primeira mensagem como nome."
    tipo_resposta: texto

  - chave: assunto # F3: chave fixa; só roda para lead sem tese (o motor tira este passo quando a tese existe)
    titulo: "Assunto"
    orientacao: "Só aparece quando ainda não se sabe o assunto. Pergunte, com simpatia, sobre o que a pessoa quer conversar e registre a resposta com as palavras dela (ex.: 'sofri um acidente no trabalho', 'benefício para minha mãe idosa', 'salário-maternidade'). Não ofereça lista de benefícios nem diga se tem direito."
    tipo_resposta: texto

  - chave: tem_advogado
    titulo: "Já tem advogado neste caso"
    orientacao: "Pergunte se algum advogado já cuida deste caso hoje. Advogado de um caso antigo, já encerrado, é não."
    tipo_resposta: sim_nao
    saidas:
      - id: sim
        quando: "sim"
        acao: desqualificar
        motivo: "tem advogado no caso"
        motivo_perda: "Outro"
        mensagem: "Entendi! Como você já tem advogado cuidando deste caso, o certo é seguir com ele. Se precisar de nós em outro assunto, é só chamar."
        efeitos: { etiqueta: "temadvogado" }
      - id: nao
        quando: "nao"
        acao: seguir
```

- [ ] **Step 2: `db/seeds/ramon/roteiros/auxilio-acidente.yml`**

```yaml
# Conteúdo APROVADO pelo Eduardo em 14/10/2026 ("pode continuar") — fonte: comercial/docs/2026-10-13-roteiros-f4-rascunho.md §3,
# corrigido pela conferência de citações (…-roteiros-f4-citacoes.md). Mudar texto aqui = novo aprovado dele.
tese: "Auxílio-acidente (B36)"
passos:
  - chave: evento
    titulo: "Acidente ou doença"
    orientacao: "Pergunte o que aconteceu: um acidente (de qualquer tipo: trabalho, trânsito, em casa) ou uma doença. Se for doença, entenda se tem ligação com o trabalho antes de escolher; se não ficar claro, peça um pouco mais de contexto."
    tipo_resposta: escolha
    opcoes: ["Acidente", "Doença ligada ao trabalho", "Doença sem ligação com o trabalho", "Perda de audição", "Não ficou claro"]
    saidas:
      - id: acidente
        quando: "Acidente"
        acao: ir_para
        alvo: data_evento
        efeitos: { etiqueta: "acidente" }
      - id: doenca_trabalho
        quando: "Doença ligada ao trabalho"
        acao: seguir
        efeitos: { etiqueta: "doenca" }
      - id: doenca_comum
        quando: "Doença sem ligação com o trabalho"
        acao: desqualificar
        motivo: "doença comum, sem ligação com o trabalho" # D15: Lei 8.213, arts. 20 e 21 (conferido 13/10)
        mensagem: "Obrigado por explicar. O auxílio-acidente é para quem sofreu um acidente ou tem doença ligada ao trabalho; pelo que você contou, este caso não se encaixa."
      - id: perda_auditiva
        quando: "Perda de audição"
        acao: humano
        motivo: "perda auditiva: regra própria (art. 86 §4º)"
      - id: nao_claro
        quando: "*"
        acao: humano
        motivo: "não ficou claro se foi acidente ou doença do trabalho"

  - chave: nexo
    titulo: "Ligação da doença com o trabalho"
    orientacao: "Só para doença. Pergunte que trabalho fazia e como a doença começou ou piorou. Escolha pela história contada (ex.: dor por movimento repetitivo no serviço = causou)."
    tipo_resposta: escolha
    opcoes: ["O trabalho causou", "O trabalho piorou", "Não tem certeza", "Sem relação com o trabalho"]
    saidas:
      - id: causou
        quando: "O trabalho causou"
        acao: seguir
      - id: piorou
        quando: "O trabalho piorou"
        acao: seguir
      - id: sem_relacao
        quando: "Sem relação com o trabalho"
        acao: desqualificar
        motivo: "doença sem ligação com o trabalho"
        mensagem: "Obrigado por explicar. Pelo que você contou, a doença não tem ligação com o trabalho, e o auxílio-acidente depende disso."
      - id: duvidoso
        quando: "*"
        acao: humano
        motivo: "ligação da doença com o trabalho duvidosa"

  - chave: data_evento
    titulo: "Data do acidente ou da doença"
    orientacao: "Pergunte quando foi o acidente (ou, na doença, quando precisou parar de trabalhar por causa dela). Só mês e ano: registre o dia 15."
    tipo_resposta: data

  - chave: auxilio_doenca
    titulo: "Recebeu auxílio-doença"
    orientacao: "Pergunte se recebeu auxílio-doença do INSS por causa disso. Licença paga pela prefeitura ou pelo estado não conta."
    tipo_resposta: sim_nao
    saidas:
      - id: sim
        quando: "sim"
        acao: ir_para
        alvo: aposentado
      - id: nao
        quando: "nao"
        acao: seguir

  - chave: regime
    titulo: "Como trabalhava na época"
    orientacao: "Pergunte como trabalhava na data do acidente (ou quando a doença começou): carteira assinada, na roça ou na pesca, autônomo/MEI, servidor público ou desempregado. Doméstica com carteira e trabalhador avulso contam como carteira assinada."
    tipo_resposta: escolha
    opcoes: ["Carteira assinada", "Rural ou pescador", "Servidor público", "Autônomo ou MEI", "Desempregado", "Não sabe"]
    saidas:
      - id: carteira
        quando: "Carteira assinada"
        acao: ir_para
        alvo: aposentado
      - id: rural
        quando: "Rural ou pescador"
        acao: ir_para
        alvo: aposentado
      - id: servidor
        quando: "Servidor público"
        acao: seguir
      - id: autonomo
        quando: "Autônomo ou MEI"
        acao: ir_para
        alvo: autonomo_carteira_antes # D10: Lei 8.213, art. 18 §1º
      - id: desempregado
        quando: "Desempregado"
        acao: ir_para
        alvo: teve_carteira_antes
      - id: nao_sabe
        quando: "*"
        acao: humano
        motivo: "não soube dizer como trabalhava na época"

  - chave: servidor_regime
    titulo: "Servidor: CLT, INSS ou regime próprio"
    orientacao: "Pergunte se era contratado pela CLT (carteira) ou concursado, e, se concursado, se a previdência dele é um regime próprio do município ou do estado (no contracheque o desconto vai para um instituto ou fundo próprio, e não para o INSS). Na dúvida, escolha 'Não sabe'."
    tipo_resposta: escolha
    opcoes: ["CLT", "Concursado que paga o INSS", "Concursado com regime próprio de previdência", "Não sabe"]
    saidas:
      - id: clt
        quando: "CLT"
        acao: ir_para
        alvo: aposentado
      - id: concursado_inss
        quando: "Concursado que paga o INSS"
        acao: ir_para
        alvo: aposentado # D14: município sem regime próprio mantém o servidor no INSS
      - id: regime_proprio
        quando: "Concursado com regime próprio de previdência"
        acao: desqualificar
        motivo: "servidor com regime próprio: sem auxílio-acidente do INSS" # D14: Lei 8.213, art. 12
        mensagem: "Entendi. Quem é concursado com regime próprio de previdência fica fora do INSS, então o auxílio-acidente do INSS não se aplica ao seu caso."
      - id: nao_sabe
        quando: "*"
        acao: humano
        motivo: "servidor sem saber se tem regime próprio ou paga o INSS"

  - chave: autonomo_carteira_antes
    titulo: "Autônomo: tinha carteira assinada antes"
    orientacao: "Pergunte se, antes de trabalhar por conta própria, tinha trabalhado de carteira assinada."
    tipo_resposta: sim_nao
    saidas:
      - id: sim
        quando: "sim"
        acao: humano
        motivo: "autônomo/MEI na data do acidente, com carteira anterior: avaliar" # D10
      - id: nao
        quando: "nao"
        acao: desqualificar
        motivo: "autônomo/MEI sem carteira anterior: contribuinte individual não tem auxílio-acidente" # D10: Lei 8.213, art. 18 §1º
        motivo_perda: "Sem viabilidade"
        mensagem: "Entendi. Pela lei, o auxílio-acidente do INSS é para quem trabalha de carteira, na roça ou na pesca; quem trabalha por conta própria não tem esse benefício. Pelo que você contou, este caso não se encaixa."

  - chave: teve_carteira_antes
    titulo: "Desempregado: teve carteira assinada antes"
    orientacao: "Pergunte se antes do acidente já tinha trabalhado de carteira assinada."
    tipo_resposta: sim_nao
    saidas:
      - id: sim
        quando: "sim"
        acao: seguir
      - id: nao
        quando: "nao"
        acao: desqualificar
        motivo: "desempregado sem carteira antes: sem vínculo que dê direito"
        mensagem: "Entendi. O auxílio-acidente do INSS é para quem trabalha de carteira, na roça ou na pesca. Pelo que você contou, este caso não se encaixa."

  - chave: ultimo_vinculo
    titulo: "Saída do último emprego de carteira"
    orientacao: "Pergunte quando saiu do último emprego de carteira assinada. Só mês e ano: registre o dia 15."
    tipo_resposta: data
    calculadora: periodo_de_graca
    calculadora_campos: { ultimo_vinculo: ultimo_vinculo, evento: data_evento }
    saidas:
      - id: dentro
        quando: "dentro"
        acao: humano
        motivo: "desempregado no período de graça na data do acidente: avaliar se mantém o direito" # D10
      - id: fora
        quando: "fora"
        acao: desqualificar
        motivo: "fora do período de graça na data do acidente"
        mensagem: "Pelo que você contou, na data do acidente já fazia muito tempo que você estava sem contribuir para o INSS, e isso impede o auxílio-acidente."
      - id: depende
        quando: "depende"
        acao: seguir

  - chave: mais_de_120
    titulo: "Mais de 10 anos pagando o INSS"
    orientacao: "Pergunte se, somando todos os empregos de carteira, tem mais de 10 anos pagando o INSS, sem ficar muito tempo parado." # D16
    tipo_resposta: escolha
    opcoes: ["Sim", "Não", "Não sabe"]
    calculadora: periodo_de_graca
    calculadora_campos: { ultimo_vinculo: ultimo_vinculo, evento: data_evento, mais_de_120: mais_de_120 }
    saidas:
      - id: dentro
        quando: "dentro"
        acao: humano
        motivo: "desempregado no período de graça na data do acidente: avaliar se mantém o direito" # D10
      - id: fora
        quando: "fora"
        acao: desqualificar
        motivo: "fora do período de graça na data do acidente"
        mensagem: "Pelo que você contou, na data do acidente já fazia muito tempo que você estava sem contribuir para o INSS, e isso impede o auxílio-acidente."
      - id: depende
        quando: "depende"
        acao: seguir

  - chave: desemprego
    titulo: "Desemprego comprovado"
    orientacao: "Pergunte se, depois que saiu do emprego, recebeu seguro-desemprego ou se cadastrou no SINE." # D17
    tipo_resposta: escolha
    opcoes: ["Sim", "Não", "Não sabe"]
    calculadora: periodo_de_graca
    calculadora_campos: { ultimo_vinculo: ultimo_vinculo, evento: data_evento, mais_de_120: mais_de_120, desemprego: desemprego }
    saidas: # D10 e D17: desempregado que chega aqui sempre vai para a equipe; a conta fica registrada para ela
      - id: dentro
        quando: "dentro"
        acao: humano
        motivo: "desempregado no período de graça na data do acidente: avaliar se mantém o direito"
      - id: fora
        quando: "fora"
        acao: humano
        motivo: "sem seguro-desemprego/SINE: ver outra prova de desemprego (Súmula 27 TNU)"
      - id: depende
        quando: "*"
        acao: humano
        motivo: "período de graça depende dos 10 anos pagando o INSS ou da prova de desemprego"

  - chave: aposentado
    titulo: "Recebe aposentadoria"
    orientacao: "Pergunte se recebe alguma aposentadoria hoje."
    tipo_resposta: sim_nao
    saidas:
      - id: nao
        quando: "nao"
        acao: ir_para
        alvo: sequela
      - id: sim
        quando: "sim"
        acao: seguir

  - chave: aposentadoria_quando
    titulo: "Aposentou antes ou depois do acidente"
    orientacao: "Pergunte se se aposentou antes ou depois do acidente (ou da doença). Para escolher entre as opções de 'depois', use a resposta do auxílio-doença que ele já deu, sem perguntar de novo."
    tipo_resposta: escolha
    opcoes: ["Antes do acidente", "Depois, e tinha recebido auxílio-doença", "Aposentadoria por invalidez por causa deste acidente", "Depois, sem ter recebido auxílio-doença", "Não sabe"]
    saidas:
      - id: antes
        quando: "Antes do acidente"
        acao: desqualificar
        motivo: "aposentado antes do acidente"
        mensagem: "Entendi. O auxílio-acidente não pode ser pago junto com uma aposentadoria que já existia antes do acidente, então neste caso não há o que pedir."
      - id: invalidez_do_acidente
        quando: "Aposentadoria por invalidez por causa deste acidente"
        acao: humano
        motivo: "aposentadoria por invalidez decorrente do próprio acidente: avaliar se houve intervalo com auxílio-acidente" # D12: sem acórdão achado (STJ/TRF4), por isso equipe
      - id: depois_com_ad
        quando: "Depois, e tinha recebido auxílio-doença"
        acao: seguir
      - id: outro
        quando: "*"
        acao: humano
        motivo: "aposentado depois do acidente sem auxílio-doença, ou não sabe quando aposentou"

  - chave: aposentadoria_data
    titulo: "Data da aposentadoria"
    orientacao: "Pergunte quando se aposentou. Só mês e ano: registre o dia 15."
    tipo_resposta: data
    calculadora: prescricao_5_anos
    calculadora_campos: { data: aposentadoria_data }
    saidas:
      - id: dentro
        quando: "dentro"
        acao: seguir
      - id: ultimo_ano
        quando: "ultimo_ano"
        acao: humano
        motivo: "aposentou há 4 a 5 anos: atrasados perto de prescrever"
      - id: prescrito
        quando: "*"
        acao: humano
        motivo: "aposentou há mais de 5 anos: ver se houve pedido que suspenda a prescrição" # D11

  - chave: sequela
    titulo: "Sequela"
    orientacao: "Pergunte se ficou alguma limitação depois do acidente ou da doença, mesmo pequena: dor, perda de força ou de movimento, dificuldade para fazer o serviço como antes. Antes de escolher 'recuperado', confirme: 'Então hoje você faz tudo como antes, sem nenhuma limitação?'"
    tipo_resposta: texto
    saidas:
      - id: limitacao
        quando: "ficou alguma limitação, mesmo pequena"
        acao: seguir
      - id: recuperado
        quando: "confirmou que voltou 100% ao que era antes"
        acao: desqualificar
        motivo: "sem sequela: voltou 100%"
        mensagem: "Que bom que você se recuperou totalmente! O auxílio-acidente é para quem ficou com alguma sequela. Se algo mudar, pode me chamar."
      - id: incerto
        quando: "ainda em tratamento ou não sabe dizer"
        acao: humano
        motivo: "sequela incerta ou ainda em tratamento" # D13

  - chave: ja_pediu_inss
    titulo: "Já pediu no INSS"
    orientacao: "Pergunte se já pediu o auxílio-acidente no INSS e como está. É só para a reunião: não muda nada no roteiro."
    tipo_resposta: escolha
    opcoes: ["Não pediu", "Pediu e foi negado", "Pediu e está em análise", "Não sabe"]

  - chave: laudo
    titulo: "Laudo ou exame"
    orientacao: "Pergunte se tem laudo, exame ou relatório médico do acidente ou da doença. Diga que não precisa ter agora."
    tipo_resposta: escolha
    opcoes: ["Tem", "Não tem", "Não sabe"]
    saidas:
      - id: nao_tem
        quando: "Não tem"
        acao: seguir
        mensagem: "Pelo que você me contou, seu caso tem pontos que vale a pena um advogado olhar com calma."
        efeitos: { etiqueta: "falta-laudo", etapa: "Qualificação" }
      - id: outro
        quando: "*"
        acao: seguir
        mensagem: "Pelo que você me contou, seu caso tem pontos que vale a pena um advogado olhar com calma."
        efeitos: { etapa: "Qualificação" }
```

- [ ] **Step 3: `db/seeds/ramon/roteiros/bpc-loas.yml`**

```yaml
# Conteúdo APROVADO pelo Eduardo em 14/10/2026 ("pode continuar") — fonte: comercial/docs/2026-10-13-roteiros-f4-rascunho.md §3,
# corrigido pela conferência de citações (…-roteiros-f4-citacoes.md). Mudar texto aqui = novo aprovado dele.
tese: "BPC/LOAS (idoso ou pessoa com deficiência)" # D19: o roteiro cobre também o idoso 65+
antes: ["BPC/LOAS por deficiência"] # nome antigo (theses_seed.yml): o seed acha a tese por ele e renomeia
passos:
  - chave: para_quem
    titulo: "Para quem é o pedido"
    orientacao: "Pergunte se o benefício é para a própria pessoa ou para um familiar. Se for para outra pessoa, faça as próximas perguntas sobre ela."
    tipo_resposta: escolha
    opcoes: ["Para a própria pessoa", "Para um familiar"]

  - chave: recebe_beneficio
    titulo: "Já recebe benefício"
    orientacao: "Pergunte se a pessoa já recebe aposentadoria, pensão, BPC ou outro benefício do INSS. Bolsa Família não conta aqui." # D25 (conferido 13/10)
    tipo_resposta: sim_nao
    saidas:
      - id: sim
        quando: "sim"
        acao: desqualificar
        motivo: "já recebe benefício (não acumula com o BPC)"
        mensagem: "Entendi. O BPC não pode ser pago junto com outro benefício do INSS, então neste caso não há como pedir."
      - id: nao
        quando: "nao"
        acao: seguir

  - chave: cadunico
    titulo: "CadÚnico"
    orientacao: "Pergunte se a família está inscrita no CadÚnico (o cadastro do CRAS). Se não estiver, diga só que a equipe orienta esse passo; não mande ir ao CRAS sozinho."
    tipo_resposta: escolha
    opcoes: ["Sim, atualizado", "Sim, mas desatualizado", "Não", "Não sabe"]

  - chave: nascimento
    titulo: "Data de nascimento"
    orientacao: "Pergunte a data de nascimento da pessoa que vai receber o benefício."
    tipo_resposta: data
    calculadora: meses_ate_65
    calculadora_campos: { nascimento: nascimento }
    saidas:
      - id: idoso
        quando: "ja_tem_65"
        acao: ir_para
        alvo: moradores
        efeitos: { etiqueta: "idoso" }
      - id: menos_de_65
        quando: "*"
        acao: seguir

  - chave: deficiencia
    titulo: "Doença ou deficiência"
    orientacao: "Pergunte qual é a doença ou deficiência e o que ela atrapalha no dia a dia ou no trabalho. Para criança, pergunte o que a limita nas atividades da idade."
    tipo_resposta: texto
    saidas:
      - id: tem
        quando: "tem doença ou deficiência que atrapalha a vida ou o trabalho"
        acao: seguir
      - id: nao_tem
        quando: "não tem doença nem deficiência"
        acao: desqualificar
        motivo: "menos de 65 anos e sem doença ou deficiência" # D27
        mensagem: "Obrigado por explicar. O BPC é para quem tem 65 anos ou mais, ou tem uma deficiência ou doença de longa duração. Pelo que você contou, hoje o caso não se encaixa."
      - id: nao_sabe
        quando: "não soube dizer"
        acao: humano
        motivo: "não ficou clara a doença ou deficiência"

  - chave: duracao
    titulo: "Há quanto tempo atrapalha"
    orientacao: "Pergunte há quanto tempo a doença ou deficiência atrapalha a vida ou o trabalho."
    tipo_resposta: escolha
    opcoes: ["2 anos ou mais", "Criança ou nunca conseguiu trabalhar", "Menos de 2 anos"]
    saidas:
      - id: menos_de_2
        quando: "Menos de 2 anos"
        acao: humano
        motivo: "limitação há menos de 2 anos: avaliar se é de longo prazo" # D20: Lei 8.742, art. 20 §10 (conferido 13/10)
      - id: longo_prazo
        quando: "*"
        acao: seguir

  - chave: laudo
    titulo: "Laudo médico"
    orientacao: "Pergunte se tem laudo ou relatório médico. Diga que não precisa ter agora."
    tipo_resposta: escolha
    opcoes: ["Tem", "Não tem", "Não sabe"]
    saidas:
      - id: nao_tem
        quando: "Não tem"
        acao: seguir
        efeitos: { etiqueta: "falta-laudo" }
      - id: outro
        quando: "*"
        acao: seguir

  - chave: moradores
    titulo: "Moradores da casa"
    orientacao: "Pergunte quantas pessoas moram na casa, contando a pessoa do benefício. Conte só cônjuge ou companheiro, pai e mãe (padrasto ou madrasta só quando falta um dos dois), irmãos solteiros, filhos e enteados solteiros e menores tutelados que moram juntos." # D24: Lei 8.742, art. 20 §1º (conferido 13/10)
    tipo_resposta: numero

  - chave: renda_total
    titulo: "Renda total da casa"
    orientacao: "Pergunte quanto entra por mês na casa somando todos: salários, bicos, pensão alimentícia, benefícios do INSS e o Bolsa Família. Não some: BPC de outra pessoa da casa; benefício de até 1 salário mínimo de outro idoso de 65+ ou de pessoa com deficiência da casa. Antes de registrar, confirme o resumo com o lead (quantas pessoas e quanto entra)." # D22 (Decreto 12.534/2025: Bolsa Família entra) · D23 (conferido 13/10)
    tipo_resposta: numero
    calculadora: renda_per_capita
    calculadora_campos: { renda_total: renda_total, moradores: moradores }
    saidas:
      - id: abaixo
        quando: "abaixo"
        acao: concluir
        mensagem: "Pelo que você me contou, o caso tem pontos que vale a pena um advogado olhar com calma."
        efeitos: { etapa: "Qualificação" }
      - id: acima
        quando: "acima"
        acao: seguir
      - id: depende
        quando: "*"
        acao: humano
        motivo: "faltou dado para a conta da renda por pessoa"

  - chave: gastos_saude
    titulo: "Gastos com saúde"
    orientacao: "Pergunte se a família gasta todo mês com remédio, fralda, alimentação especial ou tratamento que o SUS não dá."
    tipo_resposta: sim_nao
    saidas:
      - id: sim
        quando: "sim"
        acao: humano
        motivo: "renda por pessoa acima de 1/4 do salário mínimo, mas com gastos de saúde: avaliar" # D21
      - id: nao
        quando: "nao"
        acao: desqualificar
        motivo: "renda por pessoa acima de 1/4 do salário mínimo"
        mensagem: "Obrigado por confirmar. Pelo que você contou, a renda da casa por pessoa fica acima do limite do BPC, então hoje o caso não se encaixa. Se a situação da casa mudar, pode me chamar."
```

- [ ] **Step 4: `db/seeds/ramon/roteiros/salario-maternidade.yml`**

```yaml
# Conteúdo APROVADO pelo Eduardo em 14/10/2026 ("pode continuar") — fonte: comercial/docs/2026-10-13-roteiros-f4-rascunho.md §3,
# corrigido pela conferência de citações (…-roteiros-f4-citacoes.md). Mudar texto aqui = novo aprovado dele.
tese: "Salário-maternidade" # D32: o seed cria a tese
passos:
  - chave: para_quem
    titulo: "É a mãe ou fala por ela"
    orientacao: "Pergunte se quem está falando é a mãe ou alguém da família. Se for outra pessoa, faça as próximas perguntas sobre a mãe."
    tipo_resposta: escolha
    opcoes: ["É a mãe", "Fala pela mãe"]

  - chave: situacao
    titulo: "Situação"
    orientacao: "Pergunte se está grávida, se o bebê já nasceu, ou se é adoção ou guarda. Na guarda, confirme se é para fins de adoção." # D34: sem limite de idade da criança
    tipo_resposta: escolha
    opcoes: ["Grávida", "Bebê já nasceu", "Bebê nasceu sem vida", "Adoção ou guarda para adoção", "Guarda que não é para adoção", "Perdeu o bebê (aborto)"]
    saidas:
      - id: gravida
        quando: "Grávida"
        acao: seguir
      - id: guarda_sem_adocao
        quando: "Guarda que não é para adoção"
        acao: desqualificar
        motivo: "guarda que não é para fins de adoção"
        mensagem: "Entendi. O salário-maternidade vale para parto, adoção ou guarda para fins de adoção. Guarda com outra finalidade não dá direito a ele."
      - id: aborto
        quando: "Perdeu o bebê (aborto)"
        acao: humano
        motivo: "aborto: benefício de 2 semanas, equipe avalia" # D29
      - id: nascido
        quando: "*"
        acao: ir_para
        alvo: ja_recebeu

  - chave: semanas
    titulo: "Semanas de gestação"
    orientacao: "Pergunte de quantas semanas está."
    tipo_resposta: numero
    calculadora: data_prevista_parto
    calculadora_campos: { semanas: semanas }
    saidas:
      - id: depende
        quando: "depende"
        acao: humano
        motivo: "semanas de gestação fora do normal"
      - id: ok
        quando: "*"
        acao: ir_para
        alvo: data_parto

  - chave: ja_recebeu
    titulo: "Já recebeu por este parto"
    orientacao: "Pergunte se já recebeu salário-maternidade por este parto (ou por esta criança, na adoção)."
    tipo_resposta: sim_nao
    saidas:
      - id: sim
        quando: "sim"
        acao: desqualificar
        motivo: "já recebeu salário-maternidade por este parto"
        mensagem: "Entendi. Como você já recebeu o salário-maternidade por esse parto, não há o que pedir de novo."
      - id: nao
        quando: "nao"
        acao: seguir

  - chave: data_parto
    titulo: "Data do parto"
    orientacao: "Grávida: NÃO pergunte — registre a data do 'parto previsto' que a conta das semanas devolveu (ou a data provável que o médico deu, se ela contou). Já nasceu: pergunte a data do parto. Adoção: a data da adoção ou da guarda." # D28
    tipo_resposta: data
    calculadora: prescricao_5_anos
    calculadora_campos: { data: data_parto }
    saidas:
      - id: dentro
        quando: "dentro"
        acao: ir_para
        alvo: trabalho
      - id: ultimo_ano
        quando: "ultimo_ano"
        acao: humano
        motivo: "parto há 4 a 5 anos: risco de prazo"
      - id: prescrito
        quando: "*"
        acao: seguir

  - chave: pediu_antes_5_anos
    titulo: "Pediu no INSS dentro dos 5 anos"
    orientacao: "Pergunte se ela já tinha pedido o salário-maternidade no INSS antes." # D35 (conferido 13/10)
    tipo_resposta: sim_nao
    saidas:
      - id: sim
        quando: "sim"
        acao: humano
        motivo: "parto há mais de 5 anos, com pedido anterior no INSS"
      - id: nao
        quando: "nao"
        acao: desqualificar
        motivo: "parto há mais de 5 anos, sem pedido anterior"
        mensagem: "Entendi. O prazo para pedir o salário-maternidade é de 5 anos depois do parto, e esse prazo já passou."

  - chave: trabalho
    titulo: "Como trabalhava na data do parto"
    orientacao: "Pergunte como ela trabalhava na data do parto (grávida: como trabalha hoje). Carteira assinada em empresa comum: quem paga é a empresa. Demitida antes do parto entra como 'saiu do emprego'." # D33
    tipo_resposta: escolha
    opcoes: ["Carteira assinada em empresa", "Doméstica, empregada de MEI ou intermitente", "Paga o INSS por conta e está em dia", "Saiu do emprego e ficou desempregada", "Parou de pagar o carnê ou o MEI", "Trabalhadora rural ou pescadora", "Nunca pagou o INSS", "Não sabe"]
    saidas:
      - id: carteira_empresa
        quando: "Carteira assinada em empresa"
        acao: humano
        motivo: "carteira ativa no parto: quem paga é a empresa, avaliar caso trabalhista"
      - id: inss_paga
        quando: "Doméstica, empregada de MEI ou intermitente"
        acao: ir_para
        alvo: ja_pediu_inss
      - id: em_dia
        quando: "Paga o INSS por conta e está em dia"
        acao: ir_para
        alvo: ja_pediu_inss
      - id: desempregada
        quando: "Saiu do emprego e ficou desempregada"
        acao: ir_para
        alvo: ultima_contribuicao
      - id: parou_carne
        quando: "Parou de pagar o carnê ou o MEI"
        acao: seguir
      - id: rural
        quando: "Trabalhadora rural ou pescadora"
        acao: humano
        motivo: "mãe rural ou pescadora: prova da atividade" # decisão 13/10
      - id: nunca_pagou
        quando: "Nunca pagou o INSS"
        acao: desqualificar
        motivo: "nunca contribuiu e não é rural"
        mensagem: "Entendi. Pelo INSS, o salário-maternidade é para quem contribui (ou contribuiu há pouco tempo) ou trabalha na roça ou na pesca. Pelo que você contou, hoje o caso não se encaixa."
      - id: nao_sabe
        quando: "*"
        acao: humano
        motivo: "não soube dizer como trabalhava na data do parto"

  - chave: facultativa
    titulo: "Pagava como dona de casa ou estudante"
    orientacao: "Pergunte se, quando pagava o carnê, ela pagava como dona de casa ou estudante (sem ter trabalho próprio)."
    tipo_resposta: sim_nao

  - chave: ultima_contribuicao
    titulo: "Última contribuição"
    orientacao: "Pergunte quando foi a última contribuição ao INSS (ou a saída do último emprego de carteira). Só mês e ano: registre o dia 15."
    tipo_resposta: data
    calculadora: periodo_de_graca
    calculadora_campos: { ultimo_vinculo: ultima_contribuicao, evento: data_parto, facultativa: facultativa }
    saidas:
      - id: dentro
        quando: "dentro"
        acao: ir_para
        alvo: ja_pediu_inss
      - id: fora
        quando: "fora"
        acao: desqualificar
        motivo: "fora do período de graça na data do parto"
        mensagem: "Pelo que você contou, na data do parto já tinha passado o prazo em que o INSS ainda protege quem parou de contribuir, então hoje o caso não se encaixa."
      - id: depende
        quando: "depende"
        acao: seguir

  - chave: mais_de_120
    titulo: "Mais de 10 anos pagando o INSS"
    orientacao: "Pergunte se, somando tudo, ela tem mais de 10 anos pagando o INSS, sem ficar muito tempo parada." # D16
    tipo_resposta: escolha
    opcoes: ["Sim", "Não", "Não sabe"]
    calculadora: periodo_de_graca
    calculadora_campos: { ultimo_vinculo: ultima_contribuicao, evento: data_parto, mais_de_120: mais_de_120 }
    saidas:
      - id: dentro
        quando: "dentro"
        acao: ir_para
        alvo: ja_pediu_inss
      - id: fora
        quando: "fora"
        acao: desqualificar
        motivo: "fora do período de graça na data do parto"
        mensagem: "Pelo que você contou, na data do parto já tinha passado o prazo em que o INSS ainda protege quem parou de contribuir, então hoje o caso não se encaixa."
      - id: depende
        quando: "depende"
        acao: seguir

  - chave: desemprego
    titulo: "Desemprego comprovado"
    orientacao: "Pergunte se, depois que saiu do emprego, ela recebeu seguro-desemprego ou se cadastrou no SINE." # D17
    tipo_resposta: escolha
    opcoes: ["Sim", "Não", "Não sabe"]
    calculadora: periodo_de_graca
    calculadora_campos: { ultimo_vinculo: ultima_contribuicao, evento: data_parto, mais_de_120: mais_de_120, desemprego: desemprego }
    saidas:
      - id: dentro
        quando: "dentro"
        acao: seguir
      - id: fora
        quando: "fora"
        acao: humano
        motivo: "sem seguro-desemprego/SINE: ver outra prova de desemprego (Súmula 27 TNU)" # D17: aqui "fora" só vem de resposta "não"
      - id: depende
        quando: "*"
        acao: humano
        motivo: "período de graça depende dos 10 anos pagando o INSS ou da prova de desemprego"

  - chave: ja_pediu_inss
    titulo: "Já pediu no INSS"
    orientacao: "Pergunte se ela já pediu o salário-maternidade no INSS e como está." # D30
    tipo_resposta: escolha
    opcoes: ["Não pediu", "Pediu há menos de 30 dias e está em análise", "Pediu há mais de 30 dias e não saiu", "Pediu e foi negado", "Não sabe"]
    saidas:
      - id: parado
        quando: "Pediu há mais de 30 dias e não saiu"
        acao: humano
        motivo: "pedido parado no INSS há mais de 30 dias"
      - id: negado
        quando: "Pediu e foi negado"
        acao: humano
        motivo: "pedido negado no INSS"
      - id: qualificada
        quando: "*"
        acao: concluir
        mensagem: "Pelo que você me contou, o seu caso tem pontos que vale a pena um advogado olhar com calma."
        efeitos: { etapa: "Qualificação" }
```

- [ ] **Step 5: Conferir os arquivos localmente (Python, sem Ruby)**

```bash
PYTHONUTF8=1 python -c "
import yaml, glob
for f in sorted(glob.glob('db/seeds/ramon/roteiros/*.yml')):
    d = yaml.safe_load(open(f, encoding='utf-8'))
    ch = [p['chave'] for p in d['passos']]
    pos = {c: i for i, c in enumerate(ch)}
    alvos = [(p['chave'], s['alvo']) for p in d['passos'] for s in p.get('saidas', []) if s['acao'] == 'ir_para']
    assert all(a in pos and pos[a] > pos[c] for c, a in alvos), (f, alvos)
    assert all(v in ch for p in d['passos'] for v in (p.get('calculadora_campos') or {}).values()), f
    print(f, d['tese'], len(ch))
"
```

Esperado: `comuns.yml None 3`, `auxilio-acidente.yml Auxílio-acidente (B36) 17`, `bpc-loas.yml BPC/LOAS (idoso ou pessoa com deficiência) 10`, `salario-maternidade.yml Salário-maternidade 12`, sem `AssertionError` (todo "vai para" aponta para frente — o motor só pula para frente, D2).

- [ ] **Step 6: Spec dos roteiros de verdade (caminhos do rascunho, de ponta a ponta no motor)**

`spec/services/ramon/roteiro/roteiros_semeados_spec.rb`:

```ruby
require 'rails_helper'

# Os roteiros aprovados (db/seeds/ramon/roteiros) rodando no motor de verdade: cada exemplo é um caminho do rascunho de
# 14/10 e confere, antes de cada resposta, que o motor pergunta exatamente aquele passo (os "vai para" levam ao lugar certo).
RSpec.describe Ramon::Roteiro, 'roteiros semeados' do
  let(:account) { create(:account) }
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:acidente) { 'Auxílio-acidente (B36)' }
  let(:bpc) { 'BPC/LOAS (idoso ou pessoa com deficiência)' }
  let(:maternidade) { 'Salário-maternidade' }

  before do
    travel_to Time.zone.local(2026, 10, 14, 12)
    Ramon::Roteiro::Seed.new(account).run
  end

  def lead_da(tese)
    create(:lead, account: account, thesis: account.theses.find_by!(name: tese), lead_stage: novo,
                  conversation: create(:conversation, account: account, status: :pending))
  end

  # Responde em ordem; cada par = [chave, valor, saida_id]. Devolve o resultado do último registro.
  def responder(lead, *pares)
    pares.map do |chave, valor, saida_id|
      expect(described_class.atual(lead.reload)[:passo]&.chave).to eq(chave)
      described_class.registrar(lead.reload, chave: chave, valor: valor, saida_id: saida_id)
    end.last
  end

  def comuns = [%w[nome Maria], %w[tem_advogado não]]

  it 'semeia 3 passos comuns e 17/10/12 nas teses; rodar de novo não cria nada' do
    contar = ->(nome) { RoteiroPasso.where(account: account, thesis: nome && account.theses.find_by!(name: nome)).count }

    expect([nil, acidente, bpc, maternidade].map(&contar)).to eq([3, 17, 10, 12])

    de_novo = Ramon::Roteiro::Seed.new(account).run
    expect(de_novo).to include(passos_atualizados: 42)
    expect(de_novo).not_to have_key(:passos_criados)
  end

  it 'auxílio-acidente: acidente de carteira, sem aposentadoria, com sequela e sem laudo → qualificado' do
    lead = lead_da(acidente)
    res = responder(lead, *comuns, %w[evento Acidente], %w[data_evento 15/03/2025], %w[auxilio_doenca não],
                    ['regime', 'Carteira assinada'], %w[aposentado não], ['sequela', 'dói o ombro e perdeu força', 'limitacao'],
                    ['ja_pediu_inss', 'Não pediu'], ['laudo', 'Não tem'])

    expect(res[:estado]).to include('desfecho' => 'qualificado')
    expect(res[:mensagem]).to include('vale a pena um advogado olhar')
    expect(lead.conversation.reload.label_list).to include('acidente', 'falta-laudo')
    expect(account.copilot_suggestions.pending.find_by!(lead: lead, kind: 'move_stage').payload)
      .to include('etapa_sugerida' => 'Qualificação')
  end

  # Review Focus 4 (D17).
  it 'auxílio-acidente: desempregado sem seguro-desemprego vai para a equipe, não para o Perdido' do
    lead = lead_da(acidente)
    res = responder(lead, *comuns, %w[evento Acidente], %w[data_evento 2025-03-15], %w[auxilio_doenca não],
                    %w[regime Desempregado], %w[teve_carteira_antes sim], %w[ultimo_vinculo 2023-10-15],
                    %w[mais_de_120 Não], %w[desemprego Não])

    expect(res[:estado]).to include('desfecho' => 'humano', 'motivo' => include('Súmula 27'))
    expect(account.copilot_suggestions.pending.where(lead: lead, kind: 'acao')).to be_empty
  end

  # Review Focus 4 (D10) e 3 (auxílio-doença pula o vínculo).
  it 'auxílio-acidente: autônomo sem carteira anterior → Perdido sugerido; com auxílio-doença pula o vínculo' do
    autonomo = responder(lead_da(acidente), *comuns, %w[evento Acidente], %w[data_evento 2025-03-15], %w[auxilio_doenca não],
                         ['regime', 'Autônomo ou MEI'], %w[autonomo_carteira_antes não])
    com_auxilio = responder(lead_da(acidente), *comuns, %w[evento Acidente], %w[data_evento 2025-03-15],
                            %w[auxilio_doenca sim], %w[aposentado sim], ['aposentadoria_quando', 'Antes do acidente'])

    expect(autonomo[:estado]).to include('desfecho' => 'desqualificado', 'aguarda_equipe' => true)
    expect(account.copilot_suggestions.pending.where(kind: 'acao').map { |s| s.payload['lost_reason'] }).to include('Sem viabilidade')
    expect(com_auxilio[:estado]).to include('desfecho' => 'desqualificado', 'motivo' => 'aposentado antes do acidente')
  end

  # Review Focus 3: idoso pula deficiência, duração e laudo.
  it 'BPC: idoso de 65+ vai direto aos moradores e qualifica com renda até 1/4 do salário mínimo' do
    lead = lead_da(bpc)
    res = responder(lead, *comuns, ['para_quem', 'Para a própria pessoa'], %w[recebe_beneficio não], %w[cadunico Não],
                    %w[nascimento 1955-05-10], %w[moradores 3], ['renda_total', 'R$ 1.200,00'])

    expect(res[:estado]).to include('desfecho' => 'qualificado')
    expect(res[:estado].dig('respostas', 'renda_total', 'calc')).to include('resultado' => 'abaixo')
    expect(lead.conversation.reload.label_list).to include('idoso')
  end

  it 'BPC: renda acima de 1/4 — com gasto de saúde vai para a equipe, sem gasto é desqualificado (D21)' do
    pares = [*comuns, ['para_quem', 'Para um familiar'], %w[recebe_beneficio não], ['cadunico', 'Sim, atualizado'],
             %w[nascimento 1955-05-10], %w[moradores 2], %w[renda_total 1621]]

    expect(responder(lead_da(bpc), *pares, %w[gastos_saude sim])[:estado]).to include('desfecho' => 'humano')
    expect(responder(lead_da(bpc), *pares, %w[gastos_saude não])[:estado]).to include('desfecho' => 'desqualificado')
  end

  # Review Focus 3: grávida não passa por "já recebeu"; a data do parto é a prevista pela conta (D28).
  it 'salário-maternidade: grávida que paga o INSS em dia e não pediu → qualificada' do
    res = responder(lead_da(maternidade), *comuns, ['para_quem', 'É a mãe'], %w[situacao Grávida], %w[semanas 30],
                    %w[data_parto 2026-12-23], ['trabalho', 'Paga o INSS por conta e está em dia'], ['ja_pediu_inss', 'Não pediu'])

    expect(res[:estado]).to include('desfecho' => 'qualificado')
    expect(res[:estado].dig('respostas', 'semanas', 'calc', 'detalhe')).to include('23/12/2026')
  end

  it 'salário-maternidade: desempregada fora do período de graça é desqualificada; rural vai para a equipe' do
    base = [*comuns, ['para_quem', 'É a mãe'], ['situacao', 'Bebê já nasceu'], %w[ja_recebeu não], %w[data_parto 15/06/2026]]
    fora = responder(lead_da(maternidade), *base, ['trabalho', 'Saiu do emprego e ficou desempregada'],
                     %w[ultima_contribuicao 2023-01-15])
    rural = responder(lead_da(maternidade), *base, ['trabalho', 'Trabalhadora rural ou pescadora'])

    expect(fora[:estado]).to include('desfecho' => 'desqualificado')
    expect(rural[:estado]).to include('desfecho' => 'humano', 'motivo' => include('rural'))
  end
end
```

(Contas de conferência, com hoje = 14/10/2026 e salário mínimo 2026 = R$ 1.621: ¼ = R$ 405,25; 1.200/3 = 400 → abaixo; 1.621/2 = 810,50 → acima. Período de graça: vínculo até 15/10/2023 e acidente em 15/03/2025 precisa de 24 meses — "Não" nos 10 anos e "Não" no SINE → fora → equipe. Vínculo até 15/01/2023 e parto em 15/06/2026 passa dos 36 meses → fora. 30 semanas → parto previsto 23/12/2026.)

- [ ] **Step 7: Lint + commit**

```bash
rubocop-vps spec/services/ramon/roteiro/roteiros_semeados_spec.rb
git add db/seeds/ramon/roteiros spec/services/ramon/roteiro/roteiros_semeados_spec.rb
git commit -m "feat(roteiro): roteiros aprovados de auxílio-acidente, BPC/LOAS e salário-maternidade + passos comuns"
```

---

### Task 3: Métrica — passo atual no estado + view `bi_roteiro`

**Files:**
- Modify: `app/services/ramon/roteiro/registro.rb` (`gravar`)
- Modify: `spec/services/ramon/roteiro_spec.rb` (1 exemplo)
- Create: `db/migrate/20261014100001_create_bi_roteiro.rb`
- Create: `db/views/bi_roteiro_v01.sql`
- Modify: `db/schema.rb` (versão do topo + `create_view "bi_roteiro"`)
- Create: `spec/db/bi_roteiro_view_spec.rb`

**Interfaces:**
- Consumes: estado do roteiro (F1: `tese_id, cursor, desfecho, motivo, decisivo, aguarda_equipe, respostas{chave => {valor, calc, saida, em}}`); carimbo `copiloto_limite` (F3)
- Produces:
  - `lead.custom_attributes['roteiro']['passo']` = chave do próximo passo a perguntar (nulo com desfecho ou sem passo pendente)
  - view `bi_roteiro`, uma linha por lead com roteiro ou com conversa carimbada: `lead_id, account_id, conversation_id, lead_criado_em, em_roteiro (bool), thesis_id, thesis_name, passo_atual, desfecho, motivo, passo_decisivo, aguarda_equipe (bool), respondidos (int), iniciado_em, ultima_resposta_em, modo, limite_atingido, limite_em`

- [ ] **Step 1: Spec do `passo` (falha)**

Em `spec/services/ramon/roteiro_spec.rb`, depois do exemplo `'tese sem passos próprios roda os comuns e devolve para a triagem de sempre'` (o `before` do arquivo cria `tem_advogado` comum + `recebeu_auxilio`, `data_acidente`, `graca`, `sequela` na tese):

```ruby
  it 'grava no estado o próximo passo a perguntar (bi_roteiro) e o limpa no desfecho' do
    expect(registrar('tem_advogado', 'nao')[:estado]['passo']).to eq('recebeu_auxilio')
    expect(registrar('recebeu_auxilio', 'sim')[:estado]['passo']).to eq('sequela')
    expect(lead.reload.custom_attributes.dig('roteiro', 'passo')).to eq('sequela')

    registrar('sequela', 'dor no punho', saida_id: 'ficou')
    expect(lead.reload.custom_attributes['roteiro']).to include('passo' => nil, 'desfecho' => 'qualificado')
  end
```

- [ ] **Step 2: Gravar o `passo` no `Registro`**

Em `app/services/ramon/roteiro/registro.rb`, no `gravar`, calcular o próximo **uma vez**, antes da transação, guardar a chave no estado e devolver o mesmo objeto. Código da F1 (conferir a âncora no código mergeado; a F3 mexeu em `call`, não aqui):

```ruby
  def gravar(valor, calc, saida)
    guardar_resposta(valor, calc, saida)
    saida = avancar(saida)
    @est['aguarda_equipe'] = true if vira_sugestao_de_perdido?(saida)
    ActiveRecord::Base.transaction do
      @lead.update!(custom_attributes: (@lead.custom_attributes || {}).merge('roteiro' => @est))
      Ramon::Roteiro::Efeitos.aplicar(@lead, @passo, saida)
    end
    { estado: @est, proximo: @est['desfecho'] ? nil : Ramon::Roteiro.proximo(@lista, @est), calc: calc,
      mensagem: saida['mensagem'] }
  end
```

vira:

```ruby
  def gravar(valor, calc, saida)
    guardar_resposta(valor, calc, saida)
    saida = avancar(saida)
    @est['aguarda_equipe'] = true if vira_sugestao_de_perdido?(saida)
    proximo = @est['desfecho'] ? nil : Ramon::Roteiro.proximo(@lista, @est)
    @est['passo'] = proximo&.chave # bi_roteiro (F4): onde o lead parou; ponytail: fica nulo depois do reabrir até o próximo registro
    ActiveRecord::Base.transaction do
      @lead.update!(custom_attributes: (@lead.custom_attributes || {}).merge('roteiro' => @est))
      Ramon::Roteiro::Efeitos.aplicar(@lead, @passo, saida)
    end
    { estado: @est, proximo: proximo, calc: calc, mensagem: saida['mensagem'] }
  end
```

(Se o `rubocop-vps` acusar `Metrics/AbcSize` aqui, extrair `def proximo_passo = @est['desfecho'] ? nil : Ramon::Roteiro.proximo(@lista, @est)`.)

- [ ] **Step 3: Spec da view (falha)**

`spec/db/bi_roteiro_view_spec.rb`:

```ruby
require 'rails_helper'

# View scenic do roteiro da tese (F4, spec 2026-10-13 §3.9) — consultada por SQL, como o Metabase.
RSpec.describe 'view bi_roteiro' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:thesis) { create(:thesis, account: account) }

  def linha(lead) = ActiveRecord::Base.connection.select_all("SELECT * FROM bi_roteiro WHERE lead_id = #{lead.id}").to_a.first

  def conversa(attrs) = create(:conversation, account: account, custom_attributes: attrs)

  # Review Focus 5.
  it 'mostra tese, passo, desfecho e datas do roteiro sem expor o texto das respostas' do
    roteiro = { 'tese_id' => thesis.id, 'passo' => nil, 'desfecho' => 'qualificado', 'decisivo' => 'sequela',
                'respostas' => { 'nome' => { 'valor' => 'Maria Souza', 'em' => '2026-10-14T10:00:00-03:00' },
                                 'sequela' => { 'valor' => 'dor no ombro', 'saida' => 'limitacao', 'em' => '2026-10-14T10:04:00-03:00' } } }
    limite = { 'limite' => 'qualificacao', 'modo' => 'piloto_ate_qualificacao', 'em' => '2026-10-14T10:05:00-03:00' }
    lead = create(:lead, account: account, thesis: thesis, lead_stage: novo, custom_attributes: { 'roteiro' => roteiro },
                         conversation: conversa('copiloto_modo' => 'rascunho', 'copiloto_limite' => limite))

    expect(linha(lead)).to include('thesis_name' => thesis.name, 'desfecho' => 'qualificado', 'passo_decisivo' => 'sequela',
                                   'respondidos' => 2, 'em_roteiro' => true, 'aguarda_equipe' => false,
                                   'modo' => 'rascunho', 'limite_atingido' => 'qualificacao')
    expect(linha(lead)['ultima_resposta_em']).to be_present
    expect(linha(lead).values.join(' ')).not_to include('Maria Souza', 'dor no ombro')
  end

  it 'lead sem roteiro só entra com o carimbo do limite; sem nenhum dos dois fica de fora' do
    sem_nada = create(:lead, account: account, thesis: thesis, lead_stage: novo)
    so_limite = create(:lead, account: account, thesis: thesis, lead_stage: novo,
                              conversation: conversa('copiloto_limite' => { 'limite' => 'reuniao', 'em' => '2026-10-14T11:00:00-03:00' }))

    expect(linha(sem_nada)).to be_nil
    expect(linha(so_limite)).to include('em_roteiro' => false, 'limite_atingido' => 'reuniao', 'respondidos' => 0, 'desfecho' => nil)
  end
end
```

- [ ] **Step 4: View, migração e schema**

`db/views/bi_roteiro_v01.sql`:

```sql
-- Roteiro da tese por lead (spec 2026-10-13 §3.9, F4). Fonte: leads.custom_attributes->'roteiro' (motor F1; 'passo' =
-- próximo a perguntar) e o carimbo copiloto_limite da conversa (F3). Sem o texto das respostas (spec §5): só quantas,
-- quando, o desfecho, o motivo (texto da saída configurada pelo admin) e o passo que decidiu.
SELECT l.id AS lead_id,
       l.account_id,
       l.conversation_id,
       l.created_at AS lead_criado_em,
       l.custom_attributes ? 'roteiro' AS em_roteiro,
       (l.custom_attributes #>> '{roteiro,tese_id}')::bigint AS thesis_id,
       t.name AS thesis_name,
       l.custom_attributes #>> '{roteiro,passo}' AS passo_atual,
       l.custom_attributes #>> '{roteiro,desfecho}' AS desfecho,
       l.custom_attributes #>> '{roteiro,motivo}' AS motivo,
       l.custom_attributes #>> '{roteiro,decisivo}' AS passo_decisivo,
       COALESCE((l.custom_attributes #>> '{roteiro,aguarda_equipe}')::boolean, false) AS aguarda_equipe,
       r.respondidos,
       r.iniciado_em,
       r.ultima_resposta_em,
       c.custom_attributes ->> 'copiloto_modo' AS modo,
       c.custom_attributes #>> '{copiloto_limite,limite}' AS limite_atingido,
       (c.custom_attributes #>> '{copiloto_limite,em}')::timestamptz AS limite_em
FROM leads l
LEFT JOIN theses t ON t.id = (l.custom_attributes #>> '{roteiro,tese_id}')::bigint
LEFT JOIN conversations c ON c.id = l.conversation_id
CROSS JOIN LATERAL (
  SELECT COUNT(*) AS respondidos,
         MIN((e.v ->> 'em')::timestamptz) AS iniciado_em,
         MAX((e.v ->> 'em')::timestamptz) AS ultima_resposta_em
  FROM jsonb_each(COALESCE(l.custom_attributes #> '{roteiro,respostas}', '{}'::jsonb)) AS e(chave, v)
) r
WHERE l.custom_attributes ? 'roteiro' OR c.custom_attributes ? 'copiloto_limite'
```

`db/migrate/20261014100001_create_bi_roteiro.rb`:

```ruby
class CreateBiRoteiro < ActiveRecord::Migration[7.1]
  def change
    create_view :bi_roteiro
  end
end
```

`db/schema.rb`:
- topo: `ActiveRecord::Schema[7.1].define(version: 2026_10_14_100001) do` (ver Global Constraints);
- logo depois do bloco `create_view "bi_ia_conversas", sql_definition: <<-SQL … SQL` (antes do primeiro `create_trigger`), acrescentar o mesmo SQL do `.sql` (sem as 3 linhas de comentário), indentado como os outros:

```ruby
  create_view "bi_roteiro", sql_definition: <<-SQL
      SELECT l.id AS lead_id,
      l.account_id,
      l.conversation_id,
      l.created_at AS lead_criado_em,
      (l.custom_attributes ? 'roteiro'::text) AS em_roteiro,
      ((l.custom_attributes #>> '{roteiro,tese_id}'::text[]))::bigint AS thesis_id,
      t.name AS thesis_name,
      (l.custom_attributes #>> '{roteiro,passo}'::text[]) AS passo_atual,
      (l.custom_attributes #>> '{roteiro,desfecho}'::text[]) AS desfecho,
      (l.custom_attributes #>> '{roteiro,motivo}'::text[]) AS motivo,
      (l.custom_attributes #>> '{roteiro,decisivo}'::text[]) AS passo_decisivo,
      COALESCE(((l.custom_attributes #>> '{roteiro,aguarda_equipe}'::text[]))::boolean, false) AS aguarda_equipe,
      r.respondidos,
      r.iniciado_em,
      r.ultima_resposta_em,
      (c.custom_attributes ->> 'copiloto_modo'::text) AS modo,
      (c.custom_attributes #>> '{copiloto_limite,limite}'::text[]) AS limite_atingido,
      ((c.custom_attributes #>> '{copiloto_limite,em}'::text[]))::timestamp with time zone AS limite_em
     FROM (((leads l
       LEFT JOIN theses t ON ((t.id = ((l.custom_attributes #>> '{roteiro,tese_id}'::text[]))::bigint)))
       LEFT JOIN conversations c ON ((c.id = l.conversation_id)))
       CROSS JOIN LATERAL ( SELECT count(*) AS respondidos,
              min(((e.v ->> 'em'::text))::timestamp with time zone) AS iniciado_em,
              max(((e.v ->> 'em'::text))::timestamp with time zone) AS ultima_resposta_em
             FROM jsonb_each(COALESCE((l.custom_attributes #> '{roteiro,respostas}'::text[]), '{}'::jsonb)) e(chave, v)) r)
    WHERE ((l.custom_attributes ? 'roteiro'::text) OR (c.custom_attributes ? 'copiloto_limite'::text));
  SQL
```

- [ ] **Step 5: Lint + commit**

```bash
rubocop-vps app/services/ramon/roteiro/registro.rb spec/services/ramon/roteiro_spec.rb \
  db/migrate/20261014100001_create_bi_roteiro.rb spec/db/bi_roteiro_view_spec.rb
git add app/services/ramon/roteiro/registro.rb spec/services/ramon/roteiro_spec.rb db/migrate/20261014100001_create_bi_roteiro.rb \
  db/views/bi_roteiro_v01.sql db/schema.rb spec/db/bi_roteiro_view_spec.rb
git commit -m "feat(roteiro): view bi_roteiro com o passo onde o lead parou, desfecho e limite do modo"
```

---

### Task 4: Cards do roteiro no Metabase (bloco Inteligência)

**Files:**
- Modify: `scripts/metabase_bi_ia_cards.py`

**Interfaces:**
- Consumes: view `bi_roteiro` (Task 3); funções `api`, `native`, `sql_atual` do próprio script
- Produces: `CARDS_ROTEIRO` (4 cards), `HEADING_ROTEIRO`, `ROW0_ROTEIRO = 97`, `BLOCOS = [(HEADING, ROW0, CARDS), (HEADING_ROTEIRO, ROW0_ROTEIRO, CARDS_ROTEIRO)]`; `ensure_cards(cards, apply_)` e `ensure_dashcards(ids, cards, heading, row0, apply_)` passam a receber o bloco

- [ ] **Step 1: Docstring e cards novos**

Na docstring, trocar a 1ª linha por:

```python
"""Cria/atualiza o bloco "Inteligência" (metrica D8 + roteiro da tese) no dashboard Análise Comercial do Metabase.
```

e a linha `Cards nativos sobre as views bi_ia_rascunhos / bi_ia_conversas (Onda 4). Idempotente: casa os` por:

```python
Cards nativos sobre as views bi_ia_rascunhos / bi_ia_conversas (Onda 4) e bi_roteiro (F4). Idempotente: casa os
```

Logo depois da linha `# ponytail: handoffs e 0/1 por conversa …`, acrescentar:

```python

HEADING_ROTEIRO = "Inteligência — roteiro da tese"
ROW0_ROTEIRO = 97      # abaixo do bloco do agente (metabase_agente_cards.py: ROW0=80, heading + 2 linhas de 8 = ate 96)

# "Parado" = 2 dias sem resposta: o mesmo prazo de parado da etapa Novo (stalled_after_days).
CARDS_ROTEIRO = {
    "Roteiro: funil por tese (leads dos últimos 30d)": dict(display="table", sql=f"""
SELECT COALESCE(thesis_name, '(sem tese)') AS tese, COUNT(*) AS entraram,
       COUNT(*) FILTER (WHERE desfecho = 'qualificado') AS qualificados,
       COUNT(*) FILTER (WHERE desfecho = 'desqualificado') AS desqualificados,
       COUNT(*) FILTER (WHERE desfecho = 'humano') AS para_equipe,
       COUNT(*) FILTER (WHERE desfecho IS NULL) AS em_andamento
FROM bi_roteiro
WHERE account_id = {ACCOUNT_ID} AND em_roteiro AND lead_criado_em > now() - interval '30 days'
GROUP BY 1 ORDER BY entraram DESC"""),
    "Roteiro: onde param (sem desfecho, parados há 2+ dias)": dict(display="table", sql=f"""
SELECT COALESCE(thesis_name, '(sem tese)') AS tese, COALESCE(passo_atual, '(sem passo pendente)') AS passo,
       COUNT(*) AS leads
FROM bi_roteiro
WHERE account_id = {ACCOUNT_ID} AND em_roteiro AND desfecho IS NULL
  AND ultima_resposta_em < now() - interval '2 days' AND lead_criado_em > now() - interval '60 days'
GROUP BY 1, 2 ORDER BY leads DESC"""),
    "Roteiro: motivos de desqualificação e de equipe (30d)": dict(display="table", sql=f"""
SELECT CASE desfecho WHEN 'humano' THEN 'equipe' ELSE desfecho END AS desfecho,
       COALESCE(thesis_name, '(sem tese)') AS tese, passo_decisivo, motivo, COUNT(*) AS leads
FROM bi_roteiro
WHERE account_id = {ACCOUNT_ID} AND desfecho IN ('desqualificado', 'humano')
  AND ultima_resposta_em > now() - interval '30 days'
GROUP BY 1, 2, 3, 4 ORDER BY leads DESC"""),
    "Roteiro: limites atingidos nos modos 'sozinha até…' (30d)": dict(display="bar", sql=f"""
SELECT limite_atingido AS limite, COUNT(*) AS conversas
FROM bi_roteiro
WHERE account_id = {ACCOUNT_ID} AND limite_atingido IS NOT NULL AND limite_em > now() - interval '30 days'
GROUP BY 1 ORDER BY 1"""),
}

BLOCOS = [(HEADING, ROW0, CARDS), (HEADING_ROTEIRO, ROW0_ROTEIRO, CARDS_ROTEIRO)]
```

- [ ] **Step 2: Funções recebem o bloco**

- `def ensure_cards(apply_):` → `def ensure_cards(cards, apply_):` e, dentro, `for name, spec in CARDS.items():` → `for name, spec in cards.items():`.
- `def ensure_dashcards(ids, apply_):` → `def ensure_dashcards(ids, cards, heading, row0, apply_):` e, dentro, trocar cada `HEADING` por `heading`, cada `ROW0` por `row0` e `for i, name in enumerate(CARDS):` por `for i, name in enumerate(cards):`.
- No `main`, trocar

```python
    ids = ensure_cards(apply_)
    ensure_dashcards(ids, apply_)
```

por:

```python
    for heading, row0, cards in BLOCOS:
        print(f"== {heading}")
        ids = ensure_cards(cards, apply_)
        ensure_dashcards(ids, cards, heading, row0, apply_)
```

(Cada bloco relê o dashboard antes de gravar; os ids negativos temporários dos dashcards novos só valem dentro de um PUT.)

- [ ] **Step 3: Conferir**

```bash
PYTHONUTF8=1 python -m py_compile scripts/metabase_bi_ia_cards.py && echo OK
PYTHONUTF8=1 python scripts/metabase_bi_ia_cards.py; echo "saida=$?"
PYTHONUTF8=1 python -c "import sys; sys.path.insert(0, 'scripts'); import metabase_bi_ia_cards as m; print([(h, r, len(c)) for h, r, c in m.BLOCOS])"
```

Esperado: `OK`; `faltam METABASE_URL e/ou METABASE_ADMIN_KEY no ambiente.` com `saida=1`; `[('Inteligência — rascunhos da IA e 1ª resposta', 56, 4), ('Inteligência — roteiro da tese', 97, 4)]`.

- [ ] **Step 4: Commit**

```bash
git add scripts/metabase_bi_ia_cards.py
git commit -m "feat(bi): cards do roteiro da tese no bloco Inteligência do Metabase"
```

---

### Task 5: PR, CI, merge, deploy, prova, seed (gate) e registro

**Files:**
- Create: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-14-roteiro-f4-entrega.md` (fora do repo do hub)
- Modify: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-13-roteiros-f4-rascunho.md` (só o aviso do topo)
- Modify: `C:\Users\dudsl\.claude\projects\C--Users-dudsl-RAdvogados\memory\roteiro-da-tese.md`

- [ ] **Step 1: Push e PR** (push/merge = Eduardo via `!` se o classificador barrar)

```bash
git push -u origin feat/roteiro-f4-conteudo
gh pr create --base ramon --title "feat(roteiro): roteiros aprovados das 3 teses + métricas do roteiro (F4)" --body-file <corpo>
```

Corpo: parágrafo de produto ("os roteiros aprovados de auxílio-acidente, BPC/LOAS e salário-maternidade e os passos comuns entram por um seed que respeita o que foi editado na tela; o Metabase ganha funil do roteiro por tese, onde os leads param, motivos e limites dos modos 'sozinha até…'"); as **Decisões que tomei sem perguntar** do topo; "Como testar" = a prova do Step 4 + o smoke do Step 8; o aviso: **o conteúdo só vale em produção depois do `rake 'ramon:roteiros:seed[2]'`**, que espera o aprovado da orientação do `assunto`; rodapé de atribuição.

- [ ] **Step 2: CI 100% verde** — spec/lint vermelho → corrigir, `rubocop-vps`, novo commit (sem amend). 429/503 baixando actions = re-rodar o job.

- [ ] **Step 3: Merge (squash) e deploy** — regime autônomo com CI verde (CLAUDE.md do ramon-hub). Na VPS (`ssh root@185.194.216.67`, `cd /opt/intranet-ramon`):

```bash
docker pull ghcr.io/doods-maker/ramon-hub:sha-<7>
docker tag ghcr.io/doods-maker/ramon-hub:sha-<7> ghcr.io/doods-maker/ramon-hub:v4.15.1-ramon
docker compose run --rm --no-deps chatwoot-web bundle exec rails db:migrate
docker compose up -d chatwoot-web chatwoot-worker
```

Conferir a label da imagem e login 200 em https://chat.ramonantonio.adv.br (~2 min depois do `up`). View criada: `docker compose exec -T chatwoot-web bundle exec rails runner 'p ActiveRecord::Base.connection.select_value("SELECT count(*) FROM bi_roteiro")'` → um número (0 ou mais), sem erro.

- [ ] **Step 4: Prova em produção sem deixar rastro** — `cat prova.rb | ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails runner "eval(STDIN.read)"'`:

```ruby
antes = RoteiroPasso.count
ActiveRecord::Base.transaction do
  a = Account.find(2)
  p Ramon::Roteiro::Seed.new(a).run   # passos_criados 42 (menos os que já existirem), teses_criadas 1, etiquetas_conferidas 6
  p Ramon::Roteiro::Seed.new(a).run   # nada criado; passos_atualizados + passos_pulados_editados = 42
  nomes = ['Auxílio-acidente (B36)', 'BPC/LOAS (idoso ou pessoa com deficiência)', 'Salário-maternidade']
  p a.theses.where(name: nomes).pluck(:name, :palavras_chave, :honorario_na_tabela)
  lead = a.leads.create!(name: 'Prova F4', thesis: a.theses.find_by!(name: nomes[0]), lead_stage: a.lead_stages.find_by!(name: 'Novo'))
  [['nome', 'Prova'], ['tem_advogado', 'não'], ['evento', 'Acidente'], ['data_evento', '15/03/2025'], ['auxilio_doenca', 'sim'],
   ['aposentado', 'não'], ['sequela', 'dor no ombro', 'limitacao'], ['ja_pediu_inss', 'Não pediu'], ['laudo', 'Tem']].each do |chave, valor, saida|
    res = Ramon::Roteiro.registrar(lead.reload, chave: chave, valor: valor, saida_id: saida)
    puts "#{chave} -> #{res[:erro] || res[:estado]['passo'] || res[:estado]['desfecho']}"
  end
  # nome -> tem_advogado ... auxilio_doenca -> aposentado (pulou o vínculo) ... laudo -> qualificado
  p ActiveRecord::Base.connection.select_all("SELECT passo_atual, desfecho, respondidos FROM bi_roteiro WHERE lead_id = #{lead.id}").to_a
  raise ActiveRecord::Rollback
end
p [antes, RoteiroPasso.count] # iguais; a tese do BPC segue com o nome antigo
```

E os 4 SQLs dos cards contra o banco de produção (só leitura), a partir do worktree:

```bash
PYTHONUTF8=1 python -c "import json, sys; sys.path.insert(0, 'scripts'); import metabase_bi_ia_cards as m; print('\n'.join('p ActiveRecord::Base.connection.select_all(%s).to_a.first(3)' % json.dumps(c['sql']) for c in m.CARDS_ROTEIRO.values()))" \
  | ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails runner "eval(STDIN.read)"'
```

Esperado: 4 linhas `[]` (ou poucas linhas), nenhum erro de SQL.

- [ ] **Step 5: Doc de entrega para o Eduardo** — `C:\Users\dudsl\RAdvogados\comercial\docs\2026-10-14-roteiro-f4-entrega.md`, com estas seções:

1. **No ar** — PR, squash, sha da VPS, migração aplicada, prova OK (o que a prova mostrou).
2. **Pedido de aprovado (única fala nova):** a orientação do passo comum `assunto`, exata como está em `db/seeds/ramon/roteiros/comuns.yml`, e o ajuste do D24 (texto antes → depois). "Aprovado" → eu rodo o seed.
3. **O que o seed liga:** os 42 passos; a tese do BPC passa a se chamar "BPC/LOAS (idoso ou pessoa com deficiência)"; nasce a tese "Salário-maternidade" (fora da tabela de honorário; sem palavras-chave nem itens de Playbook — preencher na tela); 6 etiquetas na conta. **Efeito visível na hora:** o painel dos leads dessas 3 teses mostra o cartão "Roteiro da IA" (F2) no lugar do checklist de qualificação. A IA só conversa pelo roteiro com a skill de triagem da F1 ativa (PR #241 + `seed[2]`, aprovado separado).
4. **Checklist antes de ligar um modo "sozinha até…" na caixa** (da F3): palavras-chave das 3 teses (sem elas, lead sem tese → "assunto" → equipe), incluindo a tese nova de maternidade.
5. **Smoke** (Step 8), em bloco por seção.
6. **Metabase:** o comando do Step 7 para ele rodar.

No rascunho `2026-10-13-roteiros-f4-rascunho.md`, trocar o aviso do topo `> **RASCUNHO — aguarda aprovado do Eduardo; nada é ativado antes.**` por `> **APROVADO pelo Eduardo em 14/10/2026 ("pode continuar") — seed em db/seeds/ramon/roteiros (F4). Mudanças: ver 2026-10-14-roteiro-f4-entrega.md.**`

- [ ] **Step 6: Gate → seed em produção** — só depois do "aprovado" do Eduardo ao item 2 do doc de entrega:

```bash
ssh root@185.194.216.67 'cd /opt/intranet-ramon && docker compose exec -T chatwoot-web bundle exec rails "ramon:roteiros:seed[2]"'
```

Esperado: `passos_criados: 42` (ou criados + pulados_editados = 42), `teses_criadas: 1`, `etiquetas_conferidas: 6`. Se ele reprovar a orientação do `assunto`: tirar o bloco do `comuns.yml` num PR de 1 linha e rodar o seed depois do deploy dele (o passo comum `assunto` ausente = lead sem tese continua sem roteiro, regra da F3).

- [ ] **Step 7: Cards no Metabase** — a chave fica em `C:\Users\dudsl\RAdvogados\conhecimento\metabase-credenciais.txt` (o classificador barra o Claude de ler); o Eduardo roda pelo `!` (Git Bash), primeiro sem `--apply` (mostra `[CRIAR]` 4 cards + `[DASHBOARD] acrescentar 5 bloco(s)` no bloco do roteiro e `[JA OK]` no bloco antigo), depois com:

```bash
cd /c/Users/dudsl/RAdvogados/comercial/projetos/ramon-hub-wt-roteiro && export PYTHONUTF8=1 \
  METABASE_URL=<URL do Metabase, no mesmo arquivo de credenciais> \
  METABASE_ADMIN_KEY=$(grep -oE 'mb_[^[:space:]]+' /c/Users/dudsl/RAdvogados/conhecimento/metabase-credenciais.txt) \
  && python scripts/metabase_bi_ia_cards.py --apply
```

Rodar de novo deve dar só `[JA OK]` e `[DASHBOARD JA OK]` (idempotente).

- [ ] **Step 8: Smoke do Eduardo** (vai no doc de entrega; em bloco por seção, não pergunta a pergunta)

  - **A. Playbooks (depois do seed):** Configurações → Playbooks → "Passos comuns" mostra Nome, Assunto, Já tem advogado; as 3 teses têm a aba "Roteiro da IA" com 17 / 10 / 12 passos; abrir um passo do BPC (`renda_total`) mostra a calculadora "renda por pessoa" com os campos ligados e as saídas abaixo/acima/equipe.
  - **B. Testar (Inteligência → Testar, com a skill de triagem da F1 ativa):** escolher cada tese e fazer um caminho: auxílio-acidente acidente de carteira com sequela → qualificado; BPC idoso de 65+ com renda baixa → qualificado; maternidade grávida de 30 semanas que paga o INSS → qualificada; e um desqualificado (ex.: "já tenho advogado"). Conferir que a IA faz uma pergunta por vez e usa as frases de encerramento aprovadas.
  - **C. Caixa Teste (WhatsApp):** um lead real de cada tese — o cartão "Roteiro da IA" no painel anda sozinho; etiquetas `acidente`/`idoso`/`falta-laudo` aparecem na conversa; o qualificado gera a sugestão "Qualificação" no Cockpit.
  - **D. Metabase:** bloco "Inteligência — roteiro da tese" com os 4 cards; depois do smoke C, o funil mostra os leads de teste.

- [ ] **Step 9: Registro** — atualizar `memory\roteiro-da-tese.md`: PR, squash, sha da VPS, migração `20261014100001` aplicada, prova OK, seed rodado (ou aguardando o aprovado do `assunto`), cards aplicados (ou aguardando o `!`), smoke em `comercial\docs\2026-10-14-roteiro-f4-entrega.md` AGUARDA Eduardo; decisões 1–12 do topo deste plano. Roteiro da tese = F0–F4 entregues.

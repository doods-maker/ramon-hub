# Peticionamento pela pasta — Parte 1 (hub) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a pessoa aponta uma pasta do Drive em Protocolos; o hub baixa os arquivos, lê a peça, monta o protocolo e abre uma conferência antes de virar rascunho protocolável.

**Architecture:** a `Peticao` ganha o status `conferencia` (tribunal e número ainda podem faltar) e o campo `leitura` (jsonb). Um job baixa a pasta, aplica regras puras (`RegrasDaPasta`, `MarcadoresRascunho`), chama o LLM (`LerPeca`) e preenche a petição. `confirmar` passa para `rascunho`, e daí em diante vale o fluxo da Fase 1. A lista de pastas prontas vem de um arquivo-marcador no Drive, lido por um job com cron.

**Tech Stack:** Rails + RSpec, Vue 3 + Vitest, `Ramon::DriveClient`, `Ramon::LlmClient` (Claude Haiku por chave de API), gem nova `pdf-reader`.

**Spec:** `docs/superpowers/specs/2026-11-02-peticionamento-pela-pasta-design.md`. Base: `docs/superpowers/specs/2026-10-30-peticionamento-design.md`.

**Fora deste plano:** cofre e robô (Parte 2) e Word timbrado na esteira (Parte 3), com planos próprios. Este plano sobe ao ar **sem a equipe usar** (decisão 7 da spec): **Apontar pasta** e a lista de pastas prontas só aparecem para admin, e o lançamento só acontece com as três partes prontas.

## Global Constraints

- Sem ambiente local de Ruby: quem valida Ruby é PR + CI. Lint Ruby com `rubocop-vps`; JS/Vue com eslint de `node_modules`. Linha de até 150 caracteres.
- Migração à mão na VPS no deploy, pelo Eduardo (`!`). `db/schema.rb` atualizado no mesmo PR: à mão, porque o ssh de escrita é barrado para o Claude; se o CI acusar diferença, o comando do scratch DB vai pronto para o Eduardo rodar.
- i18n: `ramon.json` em `en` e `pt_BR`, e erros do backend em `config/locales/en.yml`, como no PR #301; título de notificação em `en.yml` e `pt_BR.yml`, como `ramon_ia_gasto`. Sem string solta em template.
- Eventos Vue em camelCase; só classes Tailwind e as constantes de `helpers/ui`.
- Nunca chutar: dado com pouca certeza vem vazio ou marcado como incerto.
- Texto de push público (ntfy) nunca leva nome, CPF ou número de processo. A notificação desta entrega usa só o sino; **não** chamar `NtfyPushJob`.
- Marcadores e códigos de recusa com os valores exatos da spec.
- Quem pode: admin ou time `advogados` (`RamonPeticaoPolicy`).

## Review Focus

1. Pasta com arquivos de mesmo nome base (`01 Petição.docx` + `01 Petição.pdf`): o Word é ignorado, sem contar como número repetido.
2. Nome com numeração no padrão `01.2-Laudo.pdf`: ordena depois de `01.1` e antes de `02`, e o nome no pacote não fica com número duplicado (`01 01.2-Laudo.pdf`).
3. PDF escaneado (sem texto extraível): a recusa por marcador não pode passar em silêncio. Usa os marcadores devolvidos pelo LLM e, sem eles, avisa `sem_texto`.
4. Alguém troca a peça principal na conferência: os marcadores são reavaliados no `confirmar`, sobre a nova principal.
5. Clique duplo em Reler ou job morto: não pode duplicar arquivos nem deixar a tela presa em "lendo".

---

### Task 1: Petição em conferência

**Files:**
- Create: `db/migrate/20261102120000_peticao_pela_pasta.rb`
- Modify: `db/schema.rb`, `app/models/peticao.rb`, `config/locales/en.yml`, `config/locales/pt_BR.yml`
- Test: `spec/models/peticao_spec.rb`

**Interfaces:**
- Produces: `Peticao::STATUS` com `conferencia`; `Peticao#conferencia?`; colunas `pela_pasta` (boolean) e `leitura` (jsonb); `Peticao#confirmar!(confirmar_alertas: false)`, que levanta `ActiveRecord::RecordInvalid` com erro em `base`; `as_json_hub` inclui `pela_pasta` e `leitura`.

- [ ] **Step 1: Write the failing tests**

```ruby
def em_conferencia(**attrs)
  account.peticoes.create!({ criado_por: user, responsavel: user, status: 'conferencia', pela_pasta: true,
                             drive_pasta_id: "p#{SecureRandom.hex(2)}" }.merge(attrs))
end

it 'em conferência dispensa tribunal e número' do
  expect(em_conferencia).to be_persisted
end

it 'pasta não pode ser usada em duas petições' do
  em_conferencia(drive_pasta_id: 'x')
  expect { em_conferencia(drive_pasta_id: 'x') }.to raise_error(ActiveRecord::RecordInvalid)
end

it 'não registra protocolo em conferência' do
  p = em_conferencia(tribunal: 'trf4', numero_processo: numero_valido_trf4)
  arquivo = fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')
  expect { p.registrar_protocolo!(usuario: user, numero_evento: '1', comprovante: arquivo) }.to raise_error(ActiveRecord::RecordInvalid)
end

it 'confirmar! exige número e tribunal' do
  p = em_conferencia
  expect { p.confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
  expect(p.reload.status).to eq('conferencia')
end

it 'problemas não acusa limite enquanto não há tribunal' do
  p = em_conferencia
  p.arquivos.create!(nome: 'A.pdf', tipo: 'peticao', posicao: 1, principal: true, origem: 'drive', tamanho: 12 * 1024 * 1024)
  expect(p.reload.problemas).to eq([])
end
```

- [ ] **Step 2: Migration e schema**

`change_column_null :ramon_peticoes, :tribunal, true`; `add_column :pela_pasta, :boolean, default: false, null: false`; `add_column :leitura, :jsonb, default: {}, null: false`; índice único parcial `[:account_id, :drive_pasta_id] where: 'pela_pasta'`. Atualizar `db/schema.rb` e a `version`.

- [ ] **Step 3: Modelo**

`STATUS` ganha `conferencia`. `editavel?` segue `!protocolada?`. Validações de tribunal e número ficam com `unless: :conferencia?`; validar unicidade de `drive_pasta_id` com escopo em `account_id`, `if: :pela_pasta?`. `problemas`: só acusa limite com tribunal presente. `protocolo_bloqueado`: `return :em_conferencia if conferencia?` antes do resto, com mensagem em `en.yml`/`pt_BR.yml`. `confirmar!` só muda o status para `rascunho` nesta task; a Task 6 acrescenta as travas de recusa e alertas.

- [ ] **Step 4: CI do branch**

Run: `git push -u origin feat/peticionamento-pasta` e `gh run watch`
Expected: `spec/models/peticao_spec.rb` verde. (Sem Ruby local, esta é a forma de rodar Ruby. Nas tasks seguintes, agrupar pushes.)

- [ ] **Step 5: Commit**

`feat(peticionamento): petição em conferência, com pasta e leitura`

---

### Task 2: Regras da pasta

**Files:**
- Create: `lib/ramon/peticionamento/regras_da_pasta.rb`
- Modify: `lib/ramon/drive_client.rb`
- Test: `spec/lib/ramon/peticionamento/regras_da_pasta_spec.rb`

**Interfaces:**
- Produces:
  - `Ramon::DriveClient.conteudo_da_pasta(pasta_id) -> [{id:, name:, mime_type:, pasta:, size:}]` (sem o filtro de tipos; não lixeira).
  - `Ramon::DriveClient.nomes_acima(pasta_id, limite: 4) -> [String]`.
  - `Ramon::Peticionamento::RegrasDaPasta.call(itens) -> Resultado` (`Data` com `arquivos:`, `recusas:`, `avisos:`). `arquivos` em ordem, cada um `{id:, name:, mime_type:, nome_limpo:}`, e o primeiro é a peça principal.

- [ ] **Step 1: Write the failing tests**

```ruby
PDF = 'application/pdf'.freeze
DOCX = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'.freeze

def item(name, mime = PDF, pasta: false) = { id: name, name: name, mime_type: mime, pasta: pasta }

it 'ordena pelo número, inclusive NN.N, e limpa o nome' do
  r = described_class.call([item('10 Laudo.pdf'), item('02.1-RG.pdf'), item('01 Petição.pdf'), item('02.2-CPF.pdf')])
  expect(r.arquivos.pluck(:name)).to eq(['01 Petição.pdf', '02.1-RG.pdf', '02.2-CPF.pdf', '10 Laudo.pdf'])
  expect(r.arquivos.pluck(:nome_limpo)).to eq(['Petição.pdf', 'RG.pdf', 'CPF.pdf', 'Laudo.pdf'])
  expect(r.recusas).to eq([])
end

it 'Word com PDF de mesmo número é ignorado' do
  r = described_class.call([item('01 Petição.docx', DOCX), item('01 Petição.pdf')])
  expect(r.arquivos.pluck(:name)).to eq(['01 Petição.pdf'])
  expect(r.recusas).to eq([])
end

it 'recusa: só Word, sem PDF, sem número, número repetido e formato estranho' do
  expect(described_class.call([item('01 Petição.docx', DOCX)]).recusas).to eq(['sem_pdf', 'word_sem_pdf:01 Petição.docx'])
  expect(described_class.call([]).recusas).to eq(['sem_pdf'])
  expect(described_class.call([item('01 P.pdf'), item('Laudo.pdf')]).recusas).to eq(['sem_numero:Laudo.pdf'])
  expect(described_class.call([item('01 P.pdf'), item('01 Q.pdf')]).recusas).to eq(['numero_repetido:01 Q.pdf'])
  expect(described_class.call([item('01 P.pdf'), item('02 x.zip', 'application/zip')]).recusas).to eq(['formato:02 x.zip'])
end

it 'imagem entra; subpasta vira aviso; arquivo com _ é ignorado' do
  r = described_class.call([item('01 P.pdf'), item('02 RG.jpg', 'image/jpeg'), item('Extras', 'folder', pasta: true),
                            item('_pasta-pronta.json', 'application/json')])
  expect(r.arquivos.size).to eq(2)
  expect(r.avisos).to eq(['subpastas:Extras'])
  expect(r.recusas).to eq([])
end
```

- [ ] **Step 2: Implementar**

Número: `/\A(\d+)(?:\.(\d+))?[\s._-]*/`, ordenando por `[maior, menor.to_i]`. Peça principal não pode ser imagem: se o primeiro for imagem, recusa `sem_pdf`. `DriveClient.conteudo_da_pasta` reutiliza `listar` (limite 200); a pasta sai como `pasta: true`.

- [ ] **Step 3: Commit**

`feat(peticionamento): regras da pasta do protocolo`

---

### Task 3: Marcadores de rascunho

**Files:**
- Create: `lib/ramon/peticionamento/marcadores_rascunho.rb`
- Modify: `Gemfile`, `Gemfile.lock`
- Test: `spec/lib/ramon/peticionamento/marcadores_rascunho_spec.rb`

**Interfaces:**
- Produces: `Ramon::Peticionamento::MarcadoresRascunho::LISTA`; `.no_texto(texto) -> [String]`; `.texto_do_pdf(bytes) -> String` (`''` se criptografado, corrompido ou escaneado).

- [ ] **Step 1: Write the failing tests**

```ruby
LISTA = ['[CAMPO', '[CONFERIR]', '[NB]', '[DIB]', '[CPF]', '[VALOR]', '[DATA]', '[OAB]', '[NOME DA PARTE]', '[ADVOGADO(A) ASSOCIADO(A)]',
         'CONTROLE INTERNO', 'RASCUNHO', 'Notas ao advogado', 'Conferência humana', 'O que esta minuta NÃO faz'].freeze

it 'tem exatamente a lista da spec' do
  expect(described_class::LISTA).to match_array(LISTA)
end

it 'acha marcador mesmo com espaços quebrados, e não recusa [...] nem [sic]' do
  expect(described_class.no_texto("valor [CAMPO: a apurar]\nCONTROLE   INTERNO")).to match_array(['[CAMPO', 'CONTROLE INTERNO'])
  expect(described_class.no_texto('conforme [...] e [sic], órgão de controle interno')).to eq([])
end

it 'lê o texto de um PDF real e devolve vazio em lixo' do
  pdf = Prawn::Document.new.tap { |d| d.text 'Conferência humana' }.render
  expect(described_class.no_texto(described_class.texto_do_pdf(pdf))).to eq(['Conferência humana'])
  expect(described_class.texto_do_pdf('lixo')).to eq('')
end
```

- [ ] **Step 2: Implementar**

Gem `pdf-reader` (MIT, Ruby puro), em `Gemfile` e `Gemfile.lock`. Sem Ruby local: escrever o `Gemfile.lock` à mão com a gem e as dependências (`Ascii85`, `afm`, `hashery`, `ruby-rc4`; `ttfunk` já está), e o CI confere. A comparação é sensível a maiúsculas, com `gsub(/\s+/, ' ')` antes. Antes de fechar a task, conferir a lista com `grep` nos modelos e agentes (`minuta-inicial/modelos`, `esteira-peticao.md`, `esteira-replica.md`); marcador novo encontrado entra na lista e é relatado ao Eduardo.

- [ ] **Step 3: Commit**

`feat(peticionamento): detectar sobra de rascunho na peça`

---

### Task 4: Leitura da peça pelo LLM

**Files:**
- Create: `app/services/ramon/peticionamento/ler_peca.rb`
- Modify: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/ramonIaUso.json`
- Test: `spec/services/ramon/peticionamento/ler_peca_spec.rb`

**Interfaces:**
- Consumes: `Ramon::LlmClient.complete`, `Ramon::Peticionamento::Cnj`, `Tribunais::TODOS`.
- Produces: `Ramon::Peticionamento::LerPeca.call(arquivo, account:) -> Hash` com chaves string: `falhou`, `e_peticao`, `tipo` (`inicial`/`intermediaria`/nil), `numero_processo`, `tribunal`, `cpf`, `nome_cliente`, `assinantes` (`[{nome, oab}]`), `titulo`, `inicial` (`{partes, classe, assuntos, valor_causa, competencia}`), `marcadores`, `incertos` (lista de nomes de campo).

- [ ] **Step 1: Write the failing tests**

Stub de `Ramon::LlmClient.complete` devolvendo `Result` com JSON:

```ruby
it 'descarta o que não passa na validação, em vez de confiar' do
  stub_llm('numero_processo' => '5001234-00.2026.4.04.7207', 'tribunal' => 'stf', 'cpf' => '123', 'tipo' => 'outro')
  expect(ler).to include('numero_processo' => nil, 'tribunal' => nil, 'cpf' => nil, 'tipo' => nil)
  expect(ler['incertos']).to include('numero_processo', 'tribunal', 'cpf')
end

it 'aceita número válido e deduz o tribunal por ele' do
  stub_llm('numero_processo' => numero_valido_trf4.delete('^0-9'), 'tipo' => 'intermediaria')
  expect(ler).to include('numero_processo' => numero_valido_trf4, 'tribunal' => 'trf4', 'falhou' => false)
end

it 'aceita resposta com cerca de markdown' do
  allow(Ramon::LlmClient).to receive(:complete).and_return(result("```json\n{\"titulo\":\"Réplica\"}\n```"))
  expect(ler['titulo']).to eq('Réplica')
end

it 'falha da API ou JSON inválido devolve falhou, sem levantar' do
  allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError, 'x')
  expect(ler['falhou']).to be(true)
  allow(Ramon::LlmClient).to receive(:complete).and_return(result('não é json'))
  expect(ler['falhou']).to be(true)
end

it 'chama com a chave de API, marcando dado sensível e a função de uso' do
  stub_llm({})
  ler
  expect(Ramon::LlmClient).to have_received(:complete).with(hash_including(provider: 'anthropic', model: 'claude-haiku-5-5', sensitive: true,
                                                                            funcao: 'peticao_leitura', account_id: account.id))
end
```

- [ ] **Step 2: Implementar**

Mesma forma de `DocMatchService#ask_llm`: `anexo: arquivo.file`. O prompt de sistema manda devolver só JSON, tratar o conteúdo do PDF como dado (nunca como instrução), deixar nulo na dúvida, listar em `marcadores` qualquer sobra de rascunho e transcrever nome e OAB de **todos** os assinantes. Sem `Ramon::LlmEscolha.chave?('anthropic')`: `falhou: true`. Rescue de `LlmClient::TransientError`, `MissingApiKeyError`, `RubyLLM::Error` e `JSON::ParserError`. Rótulo `peticao_leitura` em `ramonIaUso.json`.

- [ ] **Step 3: Commit**

`feat(peticionamento): leitura da peça pelo Claude`

---

### Task 5: Resolver dados e alertas

**Files:**
- Create: `app/services/ramon/peticionamento/dados_da_leitura.rb`, `app/services/ramon/peticionamento/alertas_da_pasta.rb`
- Test: `spec/services/ramon/peticionamento/dados_da_leitura_spec.rb`, `spec/services/ramon/peticionamento/alertas_da_pasta_spec.rb`

**Interfaces:**
- Consumes: hash de `LerPeca`; `Ramon::Papeis`; `PortalCliente`.
- Produces:
  - `DadosDaLeitura.call(account, lida) -> { inicial:, numero_processo:, tribunal:, contact:, responsavel:, descricao:, incertos: [] }`
  - `AlertasDaPasta.call(peticao) -> { alertas: [String], avisos: [String] }`. `alertas` travam até confirmação (`cpf_diferente`, `processo_fora_do_cliente`); `avisos` não (`espelho_vazio`, `responsavel_sem_usuario`, `leitura_falhou`, `sem_texto`, `nao_parece_peticao`, `subpastas:<nome>`).

- [ ] **Step 1: Write the failing tests**

```ruby
# DadosDaLeitura
it 'responsável é o associado, não o Dr. Ramon' do
  lida = { 'assinantes' => [{ 'nome' => 'RAMON ANTONIO', 'oab' => 'SC 19.044' }, { 'nome' => 'Brenda Antunes', 'oab' => 'SC 54.338' }] }
  expect(dados(lida)[:responsavel]).to eq(brenda) # usuária "Brenda" no time advogados
end

it 'Dr. Ramon sozinho é o responsável' do
  expect(dados('assinantes' => [{ 'nome' => 'Ramon Antonio', 'oab' => 'SC 19.044' }])[:responsavel]).to eq(ramon)
end

it 'dois nomes que servem, ou nenhum: sem responsável, e marca incerto' do
  r = dados('assinantes' => [{ 'nome' => 'Ana Souza', 'oab' => 'SC 1' }])
  expect(r[:responsavel]).to be_nil
  expect(r[:incertos]).to include('responsavel')
end

it 'cliente só pelo CPF, nunca pelo nome' do
  contato = create(:contact, account: account, name: 'João', cpf: cpf_valido)
  expect(dados('cpf' => cpf_valido)[:contact]).to eq(contato)
  expect(dados('nome_cliente' => 'João')[:contact]).to be_nil
end

# AlertasDaPasta
it 'CPF da peça diferente do CPF da pasta trava' do
  p = peticao(leitura: { 'cpf_pasta' => '11111111111', 'campos' => { 'cpf' => '22222222222' } })
  expect(alertas(p)[:alertas]).to eq(['cpf_diferente'])
end

it 'processo fora da lista do cliente trava; lista vazia só avisa' do
  portal(processos: [{ 'numero' => outro_numero }])
  expect(alertas(peticao_do_contato)[:alertas]).to eq(['processo_fora_do_cliente'])
  portal(processos: [])
  expect(alertas(peticao_do_contato)).to include(alertas: [], avisos: ['espelho_vazio'])
end
```

- [ ] **Step 2: Implementar**

Constante `OAB_DR_RAMON = '19044'` (ponytail: titular fixo; virar configuração se houver segundo titular). Compare a OAB só por dígitos. Associado: primeiro assinante de OAB diferente; com vários, o primeiro e `incertos` recebe `responsavel`. Casar usuário: entre admins e time `advogados` (`Ramon::Papeis`), o usuário cujos tokens de nome (`I18n.transliterate`, minúsculas) estão **todos** contidos nos tokens do assinante; exatamente um, senão `nil`. Alertas de processo são recalculados a partir do número atual, então corrigir o número na conferência os resolve. Sem responsável: mantém quem apontou e avisa `responsavel_sem_usuario`.

- [ ] **Step 3: Commit**

`feat(peticionamento): dados e alertas da leitura da pasta`

---

### Task 6: Job de leitura e travas do confirmar

**Files:**
- Create: `app/services/ramon/peticionamento/importar_pasta.rb`, `app/jobs/ramon/peticao_ler_pasta_job.rb`
- Modify: `app/models/peticao.rb`, `config/locales/{en,pt_BR}.yml`
- Test: `spec/services/ramon/peticionamento/importar_pasta_spec.rb`, `spec/jobs/ramon/peticao_ler_pasta_job_spec.rb`, `spec/jobs/ramon/peticao_arquivar_job_spec.rb`, `spec/models/peticao_spec.rb`

**Interfaces:**
- Consumes: Tasks 2–5; `AdicionarArquivo.call`; `DriveClient.download`.
- Produces: `ImportarPasta.call(peticao)`, que grava em `peticao.leitura`: `estado` (`lendo`/`lida`/`erro`), `recusas`, `avisos`, `campos`, `incertos`, `cpf_pasta`. `Ramon::PeticaoLerPastaJob.perform_later(peticao_id)`. `Peticao#confirmar!(confirmar_alertas: false)` completo.

- [ ] **Step 1: Write the failing tests**

```ruby
# ImportarPasta (DriveClient e LerPeca com stub; PDF gerado por Prawn)
it 'monta o pacote, com o primeiro como principal e o drive_file_id da origem' do
  importar
  expect(peticao.arquivos.pluck(:nome, :principal, :drive_file_id, :drive_origem_id))
    .to eq([['Petição.pdf', true, 'a', 'a'], ['Procuração.pdf', false, 'b', 'b']])
  expect(peticao.reload).to have_attributes(numero_processo: numero_valido_trf4, tribunal: 'trf4', responsavel: brenda, descricao: 'Réplica')
  expect(peticao.leitura['estado']).to eq('lida')
end

it 'recusa de regra não baixa nada nem chama o LLM' do
  stub_pasta([item('01 P.docx', DOCX)])
  importar
  expect(Ramon::DriveClient).not_to have_received(:download)
  expect(peticao.leitura['recusas']).to include('sem_pdf')
end

it 'marcador no texto da principal vira recusa' do
  stub_download('a', pdf_com('[CONFERIR] tese'))
  importar
  expect(peticao.leitura['recusas']).to eq(['marcador:[CONFERIR]'])
end

it 'PDF sem texto: usa os marcadores do LLM e avisa' do
  stub_download('a', pdf_sem_texto)
  stub_ler('marcadores' => ['[CAMPO'])
  importar
  expect(peticao.leitura).to include('recusas' => ['marcador:[CAMPO'])
  expect(peticao.leitura['avisos']).to include('sem_texto')
end

it 'reler substitui o pacote em vez de acumular' do
  2.times { importar }
  expect(peticao.arquivos.count).to eq(2)
end

it 'falha do LLM não trava: abre a conferência com aviso' do
  stub_ler('falhou' => true)
  importar
  expect(peticao.leitura).to include('estado' => 'lida')
  expect(peticao.leitura['avisos']).to include('leitura_falhou')
end

it 'peça que não parece petição: sem principal e com aviso' do
  stub_ler('e_peticao' => false)
  importar
  expect(peticao.arquivos.where(principal: true)).to be_empty
  expect(peticao.leitura['avisos']).to include('nao_parece_peticao')
end

# Job
it 'esgotadas as tentativas, grava estado erro' do
  allow(Ramon::Peticionamento::ImportarPasta).to receive(:call).and_raise(Google::Apis::ServerError, 'x')
  perform_enqueued_jobs { described_class.perform_later(peticao.id) } rescue nil
  expect(peticao.reload.leitura['estado']).to eq('erro')
end

# confirmar!
it 'trava com recusa, com alerta não confirmado e com marcador na nova principal' do
  expect { com_recusa.confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
  expect { com_alerta.confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
  com_alerta.confirmar!(confirmar_alertas: true)
  expect(com_alerta.reload.status).to eq('rascunho')
  expect { trocou_principal_para_pdf_com_marcador.confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
end

# PeticaoArquivarJob
it 'pela pasta: não sobe cópia, só o comprovante, e apaga do disco' do
  expect(Ramon::DriveClient).to receive(:upload).once.with(hash_including(parent_id: 'pasta', name: /Comprovante/))
  described_class.perform_now(protocolada_pela_pasta.id)
  expect(protocolada_pela_pasta.reload.arquivos.first.file).not_to be_attached
end
```

- [ ] **Step 2: Implementar**

`ImportarPasta`, nesta ordem: apagar arquivos atuais; `conteudo_da_pasta`; `RegrasDaPasta`; se houver recusa, gravar `lida` e parar; baixar em ordem com `AdicionarArquivo.call(..., nome: nome_limpo, origem: 'drive', drive_origem_id: id, principal: primeiro)`, e depois `update_columns(drive_file_id: id)`; verificar marcadores na principal (`marcador:<texto>`); `LerPeca`; `DadosDaLeitura`; gravar campos sem sobrescrever `prazo`. `responsavel` só muda se resolvido; `tipo` da peça principal = `peticao`. `cpf_pasta`: primeiro CPF em `nomes_acima`. O arquivamento dispensa mudança: `pasta_do_pacote` já devolve `drive_pasta_id` e o `where(drive_file_id: nil)` já pula.

Job: `queue_as :default`; `retry_on StandardError, wait: 30.seconds, attempts: 3` com bloco final que grava `estado: 'erro'`.

`confirmar!`: dentro de `with_lock`, recusa se `leitura['recusas']` não vazio, se `problemas.any?`, se a principal tem marcador (baixar o arquivo do `file` e rodar `MarcadoresRascunho`), se `AlertasDaPasta[:alertas]` não vazio sem `confirmar_alertas`. Depois valida como `rascunho` (número, tribunal). Mensagens em `en.yml`/`pt_BR.yml`.

- [ ] **Step 3: Commit**

`feat(peticionamento): importar a pasta e travar o confirmar`

---

### Task 7: API

**Files:**
- Modify: `app/controllers/api/v1/accounts/ramon_peticoes_controller.rb`, `app/policies/ramon_peticao_policy.rb`, `config/routes.rb`, `app/javascript/dashboard/api/ramonPeticoes.js`
- Test: `spec/controllers/api/v1/accounts/ramon_peticoes_controller_spec.rb`

**Interfaces:**
- Produces:
  - `POST /ramon_peticoes/pela_pasta {pasta_id}` → petição; 422 `{error: 'pasta_ja_usada', peticao_id}` se já existe.
  - `POST /ramon_peticoes/:id/reler_pasta`; 409 `{error: 'em_leitura'}` se `estado == 'lendo'` há menos de 10 min; volta o status a `conferencia`.
  - `POST /ramon_peticoes/:id/confirmar {confirmar_alertas}`.
  - `show`/`render_peticao` e `pela_pasta` incluem `alertas` e `avisos` de `AlertasDaPasta` quando `conferencia?`.
  - JS: `RamonPeticoesAPI.pelaPasta(pastaId)`, `relerPasta(id)`, `confirmar(id, confirmarAlertas)`.

- [ ] **Step 1: Write the failing tests**

```ruby
it 'apontar cria a petição em conferência e enfileira a leitura, com responsável padrão em quem apontou' do
  expect { post "#{url}/pela_pasta", params: { pasta_id: 'p1' }, headers: ana.create_new_auth_token, as: :json }
    .to have_enqueued_job(Ramon::PeticaoLerPastaJob)
  expect(response.parsed_body).to include('status' => 'conferencia', 'pela_pasta' => true, 'drive_pasta_id' => 'p1')
  expect(response.parsed_body['leitura']).to include('estado' => 'lendo')
end

it 'apontar a mesma pasta de novo devolve 422 com a petição existente' do
  # segundo POST
  expect(response).to have_http_status(:unprocessable_entity)
  expect(response.parsed_body).to include('error' => 'pasta_ja_usada', 'peticao_id' => existente.id)
end

it 'agente fora do jurídico recebe 401 em pela_pasta, reler_pasta e confirmar'

it 'pacote de pasta só muda tipo e principal: arquivos, arquivos_drive, remover_arquivo e ordem dão 422' do
  # atualizar_arquivo continua 200
end

it 'reler em andamento dá 409; lendo há mais de 10 min pode reler' do
end

it 'reler protocolada é recusado' do
end

it 'confirmar sem alertas_confirmados com alerta dá 422 e com confirmação vira rascunho' do
end
```

- [ ] **Step 2: Implementar**

`before_action :exigir_pacote_livre, only: %i[arquivos arquivos_drive remover_arquivo ordem]`, com 422 `pacote_da_pasta` se `pela_pasta?`. `exigir_drive` também em `pela_pasta` e `reler_pasta`. `except` do `carregar_peticao` ganha `pela_pasta`. Tribunal nulo na `index`: o `as_json_hub` já tolera. `ORDEM` da `index`: conferência antes, por `created_at`.

- [ ] **Step 3: Commit**

`feat(peticionamento): API de apontar, reler e confirmar a pasta`

---

### Task 8: Telas de apontar e conferir

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/peticoes/ConferenciaPasta.vue`
- Modify: `.../peticoes/SeletorDrive.vue`, `.../peticoes/PacoteEditor.vue`, `.../peticoes/helpers.js`, `.../peticoes/specs/helpers.spec.js`, `.../ramon/pages/Protocolos.vue`, `i18n/locale/{en,pt_BR}/ramon.json`

**Interfaces:**
- Consumes: API da Task 7.
- Produces:
  - `SeletorDrive`: `peticaoId` opcional; prop `modoPasta` (Boolean); no modo pasta mostra **Usar esta pasta** e emite `pastaEscolhida(pastaId)`.
  - `helpers.js`: `mensagemRecusa(codigo, t) -> String`, `mensagemAviso(codigo, t) -> String`.
  - `ConferenciaPasta`: props `peticao`, `tribunais`; emite `atualizado(peticao)`, `confirmado(peticao)`.

- [ ] **Step 1: Write the failing test**

```js
describe('mensagemRecusa', () => {
  it('traduz código com detalhe', () => {
    const t = (k, p) => `${k}|${p?.detalhe ?? ''}`;
    expect(mensagemRecusa('marcador:[CONFERIR]', t)).toBe('RAMON.PETICOES.PASTA.RECUSA.marcador|[CONFERIR]');
    expect(mensagemRecusa('sem_pdf', t)).toBe('RAMON.PETICOES.PASTA.RECUSA.sem_pdf|');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon/components/peticoes/specs/helpers.spec.js`
Expected: FAIL, `mensagemRecusa` não definida.

- [ ] **Step 3: Implementar**

- `Protocolos.vue`: segmento `conferencia` antes de `rascunho`, só para admin; botão **Apontar pasta** ao lado de Nova petição, só para admin (`// ponytail: tirar o isAdmin no lançamento`); no detalhe, `v-if="peticao.status === 'conferencia'"` mostra `ConferenciaPasta` em vez das ações de protocolo. `rascunho` computed não muda. Tratar `pasta_ja_usada` abrindo a petição existente.
- `ConferenciaPasta`: enquanto `leitura.estado === 'lendo'`, polling de `show` a cada 3 s, com `onUnmounted` limpando. Mostra: recusas em bloco vermelho (botão Confirmar some); alertas com checkbox "conferi e está certo"; avisos; dados editáveis reaproveitando os campos de `PeticaoForm` (cliente, número, inicial/tribunal, responsável, prazo, descrição), com os `incertos` destacados; bloco só leitura "Dados para a distribuição" quando `inicial`; atalho para abrir a peça (`baixarArquivo` da principal); botões **Reler a pasta** e **Confirmar**. Para não duplicar o `PeticaoForm`, extrair os campos para `CamposPeticao.vue` se passar de umas 40 linhas repetidas.
- `PacoteEditor`: prop `pacoteFechado` (= `peticao.pela_pasta`) esconde upload, Drive, mover e remover; mantém tipo e principal.
- Textos em `en` e `pt_BR`.

- [ ] **Step 4: Verificar**

Run: `npx vitest run app/javascript/dashboard/routes/dashboard/ramon/components/peticoes && npx eslint app/javascript/dashboard/routes/dashboard/ramon/components/peticoes app/javascript/dashboard/routes/dashboard/ramon/pages/Protocolos.vue`
Expected: testes verdes e eslint sem erro.

- [ ] **Step 5: Commit**

`feat(peticionamento): apontar a pasta e conferir o protocolo`

---

### Task 9: Lista de pastas prontas

**Files:**
- Create: `db/migrate/20261102120001_create_ramon_pastas_prontas.rb`, `app/models/pasta_pronta.rb`, `app/jobs/ramon/pastas_prontas_job.rb`
- Modify: `db/schema.rb`, `app/models/account.rb`, `app/models/notification.rb`, `lib/ramon/drive_client.rb`, `config/schedule.yml`, `config/locales/{en,pt_BR}.yml`, `i18n/locale/{en,pt_BR}/generalSettings.json`, `app/javascript/dashboard/routes/dashboard/notifications/components/NotificationsView.vue`, `app/controllers/api/v1/accounts/ramon_peticoes_controller.rb`, `app/policies/ramon_peticao_policy.rb`, `config/routes.rb`, `api/ramonPeticoes.js`, `pages/Protocolos.vue`
- Test: `spec/jobs/ramon/pastas_prontas_job_spec.rb`, `spec/controllers/api/v1/accounts/ramon_peticoes_controller_spec.rb`

**Interfaces:**
- Consumes: `pela_pasta` da Task 7.
- Produces, **contrato com a Parte 3 (esteira)**: arquivo `_pasta-pronta.json` dentro da pasta do protocolo, com `{"responsavel_email": "…", "titulo": "…"}`. `responsavel_email` pode ser vazio.
- Produces: `DriveClient.marcadores_de_pasta_pronta -> [{id:, parents:}]`; `GET /ramon_peticoes/pastas_prontas -> { pastas: [{id, drive_pasta_id, titulo, responsavel}] }`.

- [ ] **Step 1: Write the failing tests**

```ruby
it 'marcador novo cria o item e avisa só o responsável, pelo sino' do
  stub_marcador('m1', pasta: 'p1', json: { responsavel_email: brenda.email, titulo: 'Réplica' })
  expect { described_class.perform_now }.to change(account.pastas_prontas, :count).by(1)
  expect(brenda.notifications.where(notification_type: 'ramon_pasta_pronta').count).to eq(1)
  expect(Ramon::NtfyPushJob).not_to have_been_enqueued
end

it 'rodar de novo não duplica nem reavisa' do
  2.times { described_class.perform_now }
  expect(brenda.notifications.count).to eq(1)
end

it 'sem responsável (ou e-mail desconhecido): item sem dono, e avisa os admins' do
end

it 'pasta já virou petição: não cria item; marcador sumiu: remove o item' do
end

it 'JSON quebrado no marcador é ignorado com log, sem derrubar os demais' do
end

# API
it 'responsável vê as dele; agente do time não vê a de outro; admin vê todas, inclusive sem dono' do
end
```

- [ ] **Step 2: Implementar**

Tabela `ramon_pastas_prontas`: `account_id`, `drive_pasta_id`, `titulo`, `responsavel_id` (nullable), timestamps; índice único `[:account_id, :drive_pasta_id]`. `PastaPronta#push_event_data` devolve `{ id:, titulo: }` (`Notification` chama isso no ator). O título entra no sino e é dado interno; nunca usar `NtfyPushJob`. Notificação: enum `ramon_pasta_pronta: 18`, título em `notification.rb` (lista das linhas 116 e 146), locales e rótulo em `generalSettings.json`; clique em `NotificationsView.vue` leva a `ramon_protocolos`. `marcadores_de_pasta_pronta`: `name = '_pasta-pronta.json' and trashed = false`, com `parents`. Conta: a única que usa Drive, via `Account.find` igual aos jobs existentes; verificar no código o padrão de `Ramon::GoogleAgendaPullJob`. Cron de 5 min em `config/schedule.yml` (`spec/configs/schedule_spec.rb` valida). Em `Protocolos.vue`, bloco "Pastas prontas para revisar" no segmento `conferencia`; clicar chama `pelaPasta` e abre a petição. Item some quando a petição existe.

- [ ] **Step 3: Commit**

`feat(peticionamento): lista de pastas prontas para revisar`

---

### Task 10: Fechar a parte do hub

**Files:**
- Modify: `GLOSSARY.md`, `docs/FORK-PONTOS-DE-REGISTRO.md`, `..\..\docs\2026-09-14-smoke-consolidado.md` (fora do repo)
- Create: `docs/adr/0012-peticionamento-pela-pasta.md`

- [ ] **Step 1: Docs**

Termos novos no glossário (pasta do protocolo, conferência, pasta pronta, sobra de rascunho). ADR curta: por que `conferencia` é status da `Peticao` e por que a lista vem de um marcador no Drive em vez de uma rota nova. Notificação nova em `FORK-PONTOS-DE-REGISTRO.md`.

- [ ] **Step 2: Lint e CI**

Run: `rubocop-vps` nos arquivos Ruby alterados; `npx eslint` nos arquivos JS/Vue alterados; PR e `gh pr checks --watch`.
Expected: lint sem erro e CI 100% verde. CI vermelho não mergeia.

- [ ] **Step 3: Seção P do smoke**

Escrever a seção "P. Peticionamento pela pasta" no consolidado: pasta certa; pasta com `[CONFERIR]`; pasta só com Word; CPF diferente; processo de outro cliente; PDF escaneado; reler depois de corrigir; apontar a mesma pasta de novo; marcador `_pasta-pronta.json` à mão aparecendo na lista de quem deve; comprovante na própria pasta depois de registrar.

- [ ] **Step 4: PR, merge e deploy**

O PR sai no regime do hub (merge autônomo com CI verde). Deploy por `!` do Eduardo com a migração à mão: `20261102120000` e `20261102120001`, nesta ordem, conferindo a label da imagem antes. Depois do deploy, prova `rails runner` só de leitura.

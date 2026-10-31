# Peticionamento · Fase 1 (esteira + executor manual) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aba **Protocolos** no hub: criar petição (cliente, processo CNJ, tribunal deduzido, responsável, prazo), montar o pacote (upload ou Drive, tipo genérico, ordem), conferir contra a regra do tribunal, baixar os arquivos numerados, registrar o protocolo com comprovante e arquivar pacote + comprovante na pasta do cliente no Drive.

**Architecture:** Dois modelos (`Peticao`, `PeticaoArquivo`) com Active Storage, um módulo puro de regras (`Ramon::Peticionamento::Tribunais` + `Cnj`), quatro métodos novos no `Ramon::DriveClient`, um controller `ramon_peticoes` (admin ou time `juridico`), um job de arquivamento no Drive e uma página Vue com lista + detalhe + seletor do Drive.

**Tech Stack:** Rails 7.1 (fork Chatwoot 4.15.1), Active Storage (disco local na VPS), gem `audited` (já instalada), `google-apis-drive_v3` (já instalada), `prawn` (já instalada; imagem → PDF), Vue 3 `<script setup>` + Tailwind, vitest.

**Spec:** `docs/superpowers/specs/2026-10-30-peticionamento-design.md` (leia antes). Glossário: `GLOSSARY.md`. ADR: `docs/adr/0010-peticionamento-esteira-no-hub-executor-trocavel.md`.

## Global Constraints

- **Nenhuma gem nova.** (Ruby não roda neste Windows; o `Gemfile.lock` não pode ser regenerado com segurança.)
- **Ruby não roda local.** Lint Ruby: `rubocop-vps` (Git Bash, de dentro do worktree) antes de cada commit. Specs Ruby rodam no CI (`gh workflow run run_foss_spec.yml --ref feat/peticionamento`), não local. Escreva as specs mesmo assim — o CI é a prova.
- **Migração nova:** editar `db/schema.rb` à mão (mesmo formato das tabelas vizinhas, colunas em ordem alfabética não é exigida — siga a ordem da migração) e subir `version:` para a da migração nova.
- Linha Ruby ≤ 150 colunas; módulos/classes compactos (`class Ramon::Peticionamento::Cnj`).
- Vue: Composition API `<script setup>`, Tailwind só, eventos camelCase, nada de texto solto no template (i18n em `app/javascript/dashboard/i18n/locale/en/ramon.json` **e** `pt_BR/ramon.json`, chave `RAMON.PETICOES.*`; menu em `RAMON.NAV.PROTOCOLOS`).
- Português nos nomes de domínio (petição, pacote, tipo, protocolo), como o resto do código Ramon.
- Commits: Conventional Commits, `feat(peticionamento): ...`, sem citar Claude, terminando com as linhas de atribuição da sessão.
- Nenhum texto vai ao cliente. Nenhum protocolo automático.
- Valores fixos (da spec e das pesquisas):
  - Tribunais: `trf4` (eproc, `J=4 TR=04`), `tjsc` (eproc, `J=8 TR=24`), `trt12` (pje, `J=5 TR=12`).
  - Limite por arquivo: `trf4` 11 MB *(não publicado; mesmo sistema do TJSC — ajustar se o eproc recusar)*, `tjsc` 11 MB, `trt12` 3 MB. MB = 1024².
  - Prazo "perto": vence em até 2 dias úteis (seg–sex) a partir de hoje (fuso `America/Sao_Paulo`).
  - Time do jurídico: nome `juridico`.
  - Pasta no Drive: `Protocolos/<AAAA-MM-DD> — <numero_processo ou "Inicial #id">` dentro da pasta-base; sem pasta-base, em `Protocolos sem cliente` na raiz (`RAMON_DRIVE_ROOT_ID`).

## Review Focus

1. **Número CNJ com máscara, sem máscara ou com espaço** — o usuário cola `5001234-56.2026.4.04.7207`, `50012345620264047207` ou com espaços; o hub normaliza para a máscara e valida o dígito. (Task 1, teste `normaliza`.)
2. **Imagem (jpg/png) no pacote** — vira PDF de uma página antes de contar o tamanho; HEIC/outros formatos são recusados com mensagem, não sobem crus. (Task 3.)
3. **Arquivar no Drive falha no meio** (Drive fora, token vencido) — o job não apaga nada local e não marca `arquivada_em`; rodar de novo não duplica o que já subiu (guarda `drive_file_id` por arquivo). (Task 5.)
4. **Usuário fora do `juridico` e não-admin** — todas as rotas devolvem 401 (padrão Pundit do fork), inclusive navegar no Drive. (Task 4.)
5. **Editar o pacote depois de protocolada** — adicionar/remover/reordenar/excluir petição protocolada → 422. (Task 2/4.)

---

### Task 1: Regras do tribunal e número CNJ (Ruby puro)

**Files:**
- Create: `lib/ramon/peticionamento/cnj.rb`, `lib/ramon/peticionamento/tribunais.rb`
- Test: `spec/lib/ramon/peticionamento/cnj_spec.rb`, `spec/lib/ramon/peticionamento/tribunais_spec.rb`

(Confira como `lib/ramon/drive_client.rb` é carregado — autoload de `lib/` — e siga o mesmo; se `lib/ramon/peticionamento/` não autocarregar, ponha em `app/services/ramon/peticionamento/`.)

**Interfaces:**
- Produces:
  - `Ramon::Peticionamento::Cnj.normalizar(texto) -> String | nil` — só dígitos; 20 dígitos → `"NNNNNNN-DD.AAAA.J.TR.OOOO"`; senão `nil`.
  - `Ramon::Peticionamento::Cnj.valido?(numero) -> Boolean` — dígito verificador módulo 97 (Res. CNJ 65/2008): com `N`=7, `A`=4, `JTR`=3, `O`=4 dígitos, `DD == 98 - ((N + A + JTR + O + "00").to_i % 97)`.
  - `Ramon::Peticionamento::Cnj.tribunal(numero) -> String | nil` — `'trf4' | 'tjsc' | 'trt12'` pelos segmentos J e TR; outro → `nil`.
  - `Ramon::Peticionamento::Tribunais::TODOS` — hash `{ 'trf4' => { nome: 'TRF4 / JFSC', sistema: 'eproc', limite_bytes: 11 * 1024 * 1024 }, 'tjsc' => {...'TJSC', 'eproc', 11 MB}, 'trt12' => {...'TRT12', 'pje', 3 MB} }`.
  - `Ramon::Peticionamento::Tribunais::TIPOS` — tipos genéricos, em ordem: `%w[peticao procuracao documento_identificacao comprovante_residencia cnis laudo_medico ppp_ltcat carteira_trabalho contrato_honorarios declaracao outro]`.
  - `Ramon::Peticionamento::Tribunais.tipo_no_tribunal(tribunal, tipo) -> String` — DE/PARA para o nome que o advogado escolhe no sistema. eproc: `peticao` → `"PETIÇÃO"`, `procuracao` → `"PROCURAÇÃO"`, `documento_identificacao` → `"DOCUMENTO DE IDENTIFICAÇÃO"`, `comprovante_residencia` → `"COMPROVANTE DE ENDEREÇO"`, `cnis` → `"CNIS"`, `laudo_medico` → `"LAUDO"`, `ppp_ltcat` → `"PPP"`, `carteira_trabalho` → `"CTPS"`, `contrato_honorarios` → `"CONTRATO"`, `declaracao` → `"DECLARAÇÃO"`, `outro` → `"OUTROS"`; pje usa os mesmos rótulos (ajuste fino na Fase 4). Tipo desconhecido → `"OUTROS"`. *(Rótulos aproximados — conferir no eproc na Fase 2; por isso ficam numa constante só.)*
  - `Ramon::Peticionamento::Tribunais.sugerir_tipo(nome_arquivo) -> String` — por palavra no nome, sem acento e minúsculo: `peti` → peticao, `procura` → procuracao, `rg|cnh|identidade` → documento_identificacao, `residencia|endereco` → comprovante_residencia, `cnis` → cnis, `laudo|atestado|exame|prontuario` → laudo_medico, `ppp|ltcat` → ppp_ltcat, `ctps|carteira` → carteira_trabalho, `contrato` → contrato_honorarios, `declara` → declaracao; senão `outro`. Use `I18n.transliterate` para tirar acento.

- [ ] **Step 1: Escrever as specs**

```ruby
# cnj_spec.rb
it 'normaliza' do
  expect(described_class.normalizar(' 5001234-56.2026.4.04.7207 ')).to eq('5001234-56.2026.4.04.7207')
  expect(described_class.normalizar('50012345620264047207')).to eq('5001234-56.2026.4.04.7207')
  expect(described_class.normalizar('123')).to be_nil
end
it 'valida o dígito (módulo 97)' do
  valido = gerar_valido('5001234', '2026', '404', '7207') # helper no spec: calcula DD pela fórmula e monta a máscara
  expect(described_class.valido?(valido)).to be(true)
  expect(described_class.valido?(valido.sub(/-\d\d\./, '-00.'))).to be(false) unless valido.include?('-00.')
end
it 'deduz o tribunal' do
  expect(described_class.tribunal('0000000-00.2026.4.04.7207')).to eq('trf4')
  expect(described_class.tribunal('0000000-00.2026.8.24.0075')).to eq('tjsc')
  expect(described_class.tribunal('0000000-00.2026.5.12.0041')).to eq('trt12')
  expect(described_class.tribunal('0000000-00.2026.8.26.0100')).to be_nil
end
# tribunais_spec.rb
it { expect(described_class::TODOS['tjsc'][:limite_bytes]).to eq(11 * 1024 * 1024) }
it { expect(described_class.tipo_no_tribunal('trf4', 'procuracao')).to eq('PROCURAÇÃO') }
it { expect(described_class.tipo_no_tribunal('trf4', 'xyz')).to eq('OUTROS') }
it { expect(described_class.sugerir_tipo('02.1 Procuração assinada.pdf')).to eq('procuracao') }
it { expect(described_class.sugerir_tipo('Laudo Dr Fulano.PDF')).to eq('laudo_medico') }
it { expect(described_class.sugerir_tipo('foto.jpg')).to eq('outro') }
```

- [ ] **Step 2: Implementar os dois arquivos** (assinaturas acima).
- [ ] **Step 3: `rubocop-vps lib/ramon/peticionamento spec/lib/ramon/peticionamento`** → `no offenses`.
- [ ] **Step 4: Commit** `feat(peticionamento): regras do tribunal e número CNJ`

---

### Task 2: Modelos `Peticao` e `PeticaoArquivo` (+ migração)

**Files:**
- Create: `db/migrate/20261030120000_create_ramon_peticoes.rb`, `app/models/peticao.rb`, `app/models/peticao_arquivo.rb`
- Modify: `db/schema.rb` (duas tabelas + `version: 2026_10_30_120000`), `app/models/account.rb` (`has_many :peticoes, dependent: :destroy_async` — veja como `chegadas` foi adicionado)
- Test: `spec/models/peticao_spec.rb`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - Tabela `ramon_peticoes`: `account_id` bigint not null, `contact_id` bigint, `criado_por_id` bigint not null, `responsavel_id` bigint not null, `numero_processo` string, `tribunal` string not null, `inicial` boolean default false not null, `prazo` date, `descricao` string, `status` string default `'rascunho'` not null, `executor` string default `'manual'` not null, `numero_evento` string, `protocolada_em` datetime, `protocolada_por_id` bigint, `drive_pasta_base_id` string, `drive_pasta_id` string, `arquivada_em` datetime, timestamps; índices `[account_id, status]`, `[account_id, prazo]`, `contact_id`.
  - Tabela `ramon_peticao_arquivos`: `peticao_id` bigint not null, `nome` string not null, `tipo` string not null, `posicao` integer not null, `principal` boolean default false not null, `origem` string not null (`upload`/`drive`), `drive_origem_id` string, `drive_file_id` string (o do arquivamento), `tamanho` bigint not null, timestamps; índice `[peticao_id, posicao]`.
  - `class Peticao < ApplicationRecord` — `self.table_name = 'ramon_peticoes'`; `STATUS = %w[rascunho protocolada].freeze`; `belongs_to :account, :criado_por, :responsavel (User)`, `belongs_to :contact, :protocolada_por (User), optional: true`; `has_many :arquivos, -> { order(:posicao) }, class_name: 'PeticaoArquivo', dependent: :destroy`; `has_one_attached :comprovante`; `audited only: %w[status numero_processo tribunal responsavel_id prazo numero_evento protocolada_em protocolada_por_id arquivada_em], associated_with: :account`.
    - `before_validation`: `numero_processo = Cnj.normalizar(numero_processo)` quando presente; `tribunal ||= Cnj.tribunal(numero_processo)`.
    - Validações: `tribunal` em `Tribunais::TODOS.keys`; não-inicial exige `numero_processo` e `Cnj.valido?`; `status` em `STATUS`.
    - `protocolada? -> Boolean`; `editavel? -> !protocolada?`.
    - `problemas -> Array<String>` — chaves i18n do backend, nesta ordem: `'sem_arquivos'` (vazio), `'sem_principal'` / `'varias_principais'` (contagem de `principal` ≠ 1), `"acima_do_limite:#{arquivo.id}"` para cada arquivo com `tamanho > limite_bytes`. Vazio = pode protocolar.
    - `prazo_perto? -> Boolean` — `prazo` presente e ≤ hoje + 2 dias úteis (conta seg–sex; fuso São Paulo). Já vencido também é `true`.
    - `registrar_protocolo!(usuario:, numero_evento:, comprovante:)` — levanta `ActiveRecord::RecordInvalid` se `problemas.any?` ou já protocolada; grava `status: 'protocolada'`, `numero_evento`, `protocolada_em: Time.current`, `protocolada_por: usuario`, anexa `comprovante`; depois do commit enfileira `Ramon::PeticaoArquivarJob.perform_later(id)` (Task 5).
    - `as_json_hub -> Hash` — `id, numero_processo, tribunal, tribunal_nome, sistema, inicial, prazo, prazo_perto, descricao, status, executor, numero_evento, protocolada_em, arquivada_em, drive_pasta_id, contato {id, name}, responsavel {id, name}, criado_por {id, name}, problemas, arquivos [PeticaoArquivo#as_json_hub]`, `comprovante_url` (ou nil).
  - `class PeticaoArquivo < ApplicationRecord` — `self.table_name = 'ramon_peticao_arquivos'`; `belongs_to :peticao`; `has_one_attached :file`; validações: `tipo` em `Tribunais::TIPOS`, `origem` em `%w[upload drive]`; `nome_numerado -> "#{format('%02d', posicao)} #{nome}"` (nome já termina em `.pdf`); `as_json_hub -> { id, nome, nome_numerado, tipo, tipo_no_tribunal, posicao, principal, origem, tamanho, url }` (`url` = `Rails.application.routes.url_helpers.rails_blob_url(file, disposition: 'attachment', filename: nome_numerado)` só se `file.attached?` — veja como o fork já gera URL de blob, ex. `Attachment#file_url`).

- [ ] **Step 1: Escrever `spec/models/peticao_spec.rb`**

```ruby
let(:account) { create(:account) }
let(:user) { create(:user, account: account, role: :administrator) }
def nova(**attrs) = account.peticoes.new({ criado_por: user, responsavel: user, numero_processo: numero_valido_trf4 }.merge(attrs))
# numero_valido_trf4: helper que monta um CNJ válido com J=4 TR=04 (mesma fórmula da Task 1)

it 'deduz o tribunal e normaliza o número' do
  p = nova(numero_processo: numero_valido_trf4.delete('^0-9')); p.valid?
  expect(p).to have_attributes(tribunal: 'trf4', numero_processo: numero_valido_trf4)
end
it 'recusa dígito errado' do expect(nova(numero_processo: '5001234-00.2026.4.04.7207')).not_to be_valid end
it 'inicial dispensa número mas exige tribunal' do
  expect(nova(numero_processo: nil, inicial: true, tribunal: 'tjsc')).to be_valid
  expect(nova(numero_processo: nil, inicial: true)).not_to be_valid
end
it 'problemas: vazio, sem principal, acima do limite' do
  p = nova.tap(&:save!)
  expect(p.problemas).to eq(['sem_arquivos'])
  a = p.arquivos.create!(nome: 'Laudo.pdf', tipo: 'laudo_medico', posicao: 1, origem: 'upload', tamanho: 12 * 1024 * 1024)
  expect(p.reload.problemas).to eq(['sem_principal', "acima_do_limite:#{a.id}"])
end
it 'prazo_perto: sexta + 2 úteis = terça' do
  travel_to(Time.find_zone('America/Sao_Paulo').local(2026, 10, 30, 10)) do # sexta
    expect(nova(prazo: Date.new(2026, 11, 3)).prazo_perto?).to be(true)
    expect(nova(prazo: Date.new(2026, 11, 4)).prazo_perto?).to be(false)
  end
end
it 'registrar_protocolo! grava, enfileira o arquivamento e trava edição' do
  p = nova.tap(&:save!)
  p.arquivos.create!(nome: 'Peticao.pdf', tipo: 'peticao', posicao: 1, principal: true, origem: 'upload', tamanho: 10)
  comprovante = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') # confira o caminho de um PDF de fixture existente
  expect { p.registrar_protocolo!(usuario: user, numero_evento: '15', comprovante: comprovante) }
    .to have_enqueued_job(Ramon::PeticaoArquivarJob).with(p.id)
  expect(p.reload).to have_attributes(status: 'protocolada', numero_evento: '15', protocolada_por_id: user.id, editavel?: false)
  expect(p.comprovante).to be_attached
end
it 'registrar_protocolo! recusa pacote com problema' do
  p = nova.tap(&:save!)
  expect { p.registrar_protocolo!(usuario: user, numero_evento: '1', comprovante: nil) }.to raise_error(ActiveRecord::RecordInvalid)
end
```

(O job da Task 5 ainda não existe: crie aqui um `app/jobs/ramon/peticao_arquivar_job.rb` com `perform(peticao_id)` vazio; a Task 5 preenche.)

- [ ] **Step 2: Migração + `db/schema.rb` à mão + modelos + `has_many :peticoes` no Account.**
- [ ] **Step 3: `rubocop-vps`** → sem ofensas.
- [ ] **Step 4: Commit** `feat(peticionamento): petição e pacote (modelos)`

---

### Task 3: Adicionar arquivo ao pacote (upload ou Drive) + Drive client

**Files:**
- Create: `app/services/ramon/peticionamento/adicionar_arquivo.rb`
- Modify: `lib/ramon/drive_client.rb` (4 métodos públicos)
- Test: `spec/services/ramon/peticionamento/adicionar_arquivo_spec.rb`, `spec/lib/ramon/drive_client_spec.rb` (se já existir, acrescente; senão crie)

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `Ramon::DriveClient.children(parent_id) -> Array<Hash>` — `{ id:, name:, mime_type:, modified_time:, size:, pasta: Boolean }`; só pastas, `application/pdf` e `image/jpeg|image/png`; `trashed = false`; ordenado pastas primeiro, depois nome. Passe `supports_all_drives: true, include_items_from_all_drives: true` e `fields: 'files(id,name,mimeType,modifiedTime,size,parents)'`, `page_size: 200`.
  - `Ramon::DriveClient.search(texto) -> Array<Hash>` — mesmo formato; `name contains '<texto escapado>'` + mesmo filtro de tipo; `page_size: 50`. Texto com menos de 3 caracteres → `[]`.
  - `Ramon::DriveClient.parent_of(id) -> String | nil` — `get_file(id, fields: 'parents', supports_all_drives: true).parents&.first`.
  - `Ramon::DriveClient.download(file_id) -> [String bytes, String mime_type, String name]` — `get_file(..., fields: 'name,mimeType')` + `get_file(file_id, download_dest: StringIO.new, supports_all_drives: true)`.
  - `Ramon::Peticionamento::AdicionarArquivo.call(peticao, bytes:, nome:, content_type:, origem:, drive_origem_id: nil, tipo: nil, principal: false) -> PeticaoArquivo`
    - levanta `ArgumentError, 'protocolada'` se `!peticao.editavel?`;
    - `application/pdf` passa; `image/jpeg|image/jpg|image/png` vira PDF A4 de uma página com `prawn` (mesmo jeito do `DriveExportService#to_pdf`); outro tipo → `ArgumentError, 'formato'`;
    - `nome` final = nome sem extensão + `.pdf`;
    - `tipo ||= Tribunais.sugerir_tipo(nome)`; `posicao = (maior posição) + 1`; `tamanho` = bytes do PDF final; anexa em `file`;
    - se `principal: true`, desmarca as outras.

- [ ] **Step 1: Specs**

```ruby
# adicionar_arquivo_spec.rb
it 'PDF entra com tipo sugerido e posição seguinte' do
  pdf = File.binread(Rails.root.join('spec/assets/sample.pdf')) # mesmo fixture da Task 2
  a = described_class.call(peticao, bytes: pdf, nome: 'Procuração.pdf', content_type: 'application/pdf', origem: 'upload')
  b = described_class.call(peticao, bytes: pdf, nome: 'Petição.pdf', content_type: 'application/pdf', origem: 'upload', principal: true)
  expect([a.reload.posicao, a.tipo, b.posicao, b.principal]).to eq([1, 'procuracao', 2, true])
  expect(a.file).to be_attached
end
it 'imagem vira PDF' do
  png = File.binread(Rails.root.join('spec/assets/avatar.png')) # confira um PNG de fixture existente
  a = described_class.call(peticao, bytes: png, nome: 'RG frente.png', content_type: 'image/png', origem: 'upload')
  expect([a.nome, a.file.content_type, a.tipo]).to eq(['RG frente.pdf', 'application/pdf', 'documento_identificacao'])
end
it 'recusa HEIC e petição protocolada' do
  expect { described_class.call(peticao, bytes: 'x', nome: 'a.heic', content_type: 'image/heic', origem: 'upload') }
    .to raise_error(ArgumentError, 'formato')
  peticao.update_columns(status: 'protocolada')
  expect { described_class.call(peticao, bytes: 'x', nome: 'a.pdf', content_type: 'application/pdf', origem: 'upload') }
    .to raise_error(ArgumentError, 'protocolada')
end
# drive_client_spec.rb — stub de Google::Apis::DriveV3::DriveService (instance_double), conferindo:
it 'children filtra e ordena pastas primeiro' # retorna [{pasta: true...}, {pdf}] a partir de 2 files fake
it 'search com menos de 3 letras não chama a API'
```

- [ ] **Step 2: Implementar** (assinaturas acima).
- [ ] **Step 3: `rubocop-vps`** → sem ofensas.
- [ ] **Step 4: Commit** `feat(peticionamento): pacote recebe upload e arquivo do Drive`

---

### Task 4: API `ramon_peticoes` + política

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_peticoes_controller.rb`, `app/policies/ramon_peticao_policy.rb`
- Modify: `config/routes.rb` (perto de `ramon_chegadas`)
- Test: `spec/controllers/api/v1/accounts/ramon_peticoes_controller_spec.rb` (request spec, no padrão de `ramon_chegadas_controller_spec.rb`)

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces (todas sob `/api/v1/accounts/:account_id/ramon_peticoes`, JSON):
  - `GET /` → `{ payload: [Peticao#as_json_hub sem arquivos], tribunais: Tribunais::TODOS (com chave), tipos: Tribunais::TIPOS }`; filtro `?status=rascunho|protocolada`; ordem: rascunhos primeiro por `prazo` (nulls last), depois protocoladas por `protocolada_em desc`; limite 200.
  - `GET /:id` → `as_json_hub` completo.
  - `POST /` (`contact_id, numero_processo, inicial, tribunal, responsavel_id, prazo, descricao`) → cria; `criado_por` = atual; `responsavel` default atual; `drive_pasta_base_id` = `pasta_id` do lead ganho mais recente do contato (`account.leads.where(contact_id:).where.not(won_at: nil).order(won_at: :desc)` → `custom_attributes.dig('drive','pasta_id')`), se houver. Erro de validação → 422 `{ errors: [...] }`.
  - `PATCH /:id` (mesmos campos) → 422 se protocolada.
  - `DELETE /:id` → só rascunho; 422 se protocolada.
  - `POST /:id/arquivos` (multipart `file`, `tipo` opcional, `principal` opcional) → `AdicionarArquivo` com `origem: 'upload'`; `ArgumentError` → 422 `{ error: 'formato' | 'protocolada' }`.
  - `POST /:id/arquivos_drive` (`file_ids: []`) → baixa cada um com `DriveClient.download` e chama `AdicionarArquivo` com `origem: 'drive', drive_origem_id:`.
  - `PATCH /:id/arquivos/:arquivo_id` (`tipo`, `principal`) e `DELETE /:id/arquivos/:arquivo_id` → 422 se protocolada; depois de remover, renumera posições 1..n.
  - `PATCH /:id/ordem` (`ids: [arquivo_id...]`) → grava posições 1..n na ordem dada.
  - `POST /:id/registrar_protocolo` (multipart `numero_evento`, `comprovante`) → **só o responsável ou admin** (senão 401); `registrar_protocolo!`; `RecordInvalid` → 422.
  - `GET /drive?pasta_id=` → `{ pasta_id, pai_id, raiz_id, itens: DriveClient.children }` (sem `pasta_id` → raiz `RAMON_DRIVE_ROOT_ID`; `pai_id` = `nil` na raiz); `GET /drive_busca?q=` → `{ itens: DriveClient.search(q) }`. Sem `DriveClient.configured?` → 503 `{ error: 'DRIVE_OFF' }`.
  - `GET /processos?contact_id=` → `{ processos: [{ numero, tipo }] }` de `PortalCliente.find_by(account:, cpf: contact.cpf)&.processos` (confira o nome da coluna/escopo em `app/models/portal_cliente.rb`); sem CPF/portal → `[]`.
  - Política `RamonPeticaoPolicy`: toda ação exige `@account_user.administrator? || Ramon::Papeis.membro?(@account, @user, 'juridico')`. Adicione `JURIDICO = 'juridico'.freeze` em `Ramon::Papeis`. A checagem "responsável ou admin" do `registrar_protocolo` fica no controller.

- [ ] **Step 1: Spec de request** — no mínimo:

```ruby
it 'agente fora do jurídico recebe 401 em index e drive'
it 'membro do juridico cria com número sem máscara e recebe tribunal trf4'
it 'create com número inválido → 422'
it 'upload de PDF entra no pacote; problemas some quando há principal'
it 'arquivos_drive baixa pelo DriveClient (stub) e grava origem drive'
it 'registrar_protocolo: outro membro do jurídico → 401; responsável → 200 e status protocolada'
it 'depois de protocolada: POST arquivos, DELETE petição e PATCH ordem → 422'
it 'drive sem configuração → 503 DRIVE_OFF'
```

- [ ] **Step 2: Implementar controller, política, rotas.**
- [ ] **Step 3: `rubocop-vps`** → sem ofensas.
- [ ] **Step 4: Commit** `feat(peticionamento): API de petições, pacote e seletor do Drive`

---

### Task 5: Arquivar pacote + comprovante no Drive

**Files:**
- Modify: `app/jobs/ramon/peticao_arquivar_job.rb` (criado vazio na Task 2)
- Test: `spec/jobs/ramon/peticao_arquivar_job_spec.rb`

**Interfaces:**
- Consumes: `DriveClient.ensure_folder/upload` (existentes), `Peticao`, `PeticaoArquivo`.
- Produces: `Ramon::PeticaoArquivarJob#perform(peticao_id)` — `queue_as :low` (confira o nome de fila usado pelos jobs Ramon), `retry_on StandardError, wait: 15.minutes, attempts: 8`.
  1. Sai se `!DriveClient.configured?`, se a petição não está protocolada ou se `arquivada_em` presente.
  2. Pasta: base = `drive_pasta_base_id` ou `ensure_folder('Protocolos sem cliente', root_id)`; `protocolos = ensure_folder('Protocolos', base)` (só quando há base de cliente); `pasta = ensure_folder("#{protocolada_em.in_time_zone('America/Sao_Paulo').to_date.iso8601} — #{numero_processo || "Inicial #{id}"}", protocolos)`; grava `drive_pasta_id`.
  3. Para cada arquivo **sem** `drive_file_id`: `upload(name: nome_numerado, io: StringIO.new(file.download), content_type: 'application/pdf', parent_id: pasta)` e grava `drive_file_id` **na hora** (idempotência).
  4. Comprovante: sobe como `"Comprovante — evento #{numero_evento}#{ext}"` (só se ainda não subiu: guarde o id em `resultado`? — não há coluna; use `drive_file_id` num `PeticaoArquivo`? **Não.** Suba o comprovante por último e trate a conclusão como o marcador: se o job morrer depois do comprovante e antes do passo 5, o retry sobe o comprovante de novo — aceitável, `ponytail:` comentário dizendo isso).
  5. `update!(arquivada_em: Time.current)`; depois `arquivos.each { |a| a.file.purge }` (o comprovante fica no hub).

- [ ] **Step 1: Spec**

```ruby
it 'sobe arquivos numerados e o comprovante, marca arquivada e apaga os arquivos locais' # stub DriveClient: configured? true, ensure_folder → ids, upload → 'f1','f2','c1'
it 'retry depois de falha no 2º arquivo não sobe o 1º de novo' # 1ª execução: upload levanta no 2º; 2ª: espera upload chamado só para o 2º + comprovante
it 'sem pasta-base usa "Protocolos sem cliente"'
```

- [ ] **Step 2: Implementar.**
- [ ] **Step 3: `rubocop-vps`** → sem ofensas.
- [ ] **Step 4: Commit** `feat(peticionamento): arquiva pacote e comprovante na pasta do cliente`

---

### Task 6: Tela Protocolos (Vue)

**Files:**
- Create: `app/javascript/dashboard/api/ramonPeticoes.js`, `app/javascript/dashboard/routes/dashboard/ramon/pages/Protocolos.vue`, `app/javascript/dashboard/routes/dashboard/ramon/components/peticoes/PeticaoForm.vue`, `.../peticoes/PacoteEditor.vue`, `.../peticoes/SeletorDrive.vue`, `.../peticoes/RegistrarProtocolo.vue`, `.../peticoes/helpers.js`
- Modify: `ramon.routes.js` (rotas `ramon_protocolos` → `ramon/protocolos` e `ramon_protocolo` → `ramon/protocolos/:peticaoId`, ambas `permissions: ['administrator', 'agent']`), `helpers/navIntranet.js` (aba `aba('ramon_protocolos', 'PROTOCOLOS', { acende: ['ramon_protocolo'] })` no fim do grupo `clientes`), `helpers/specs/navIntranet.spec.js` (atualizar listas esperadas), `i18n/locale/en/ramon.json` e `pt_BR/ramon.json`
- Test: `.../peticoes/specs/helpers.spec.js`

**Interfaces:**
- Consumes: API da Task 4.
- Produces:
  - `ramonPeticoes.js` — classe `ApiClient('ramon_peticoes', { accountScoped: true })` com `get(params)`, `show(id)`, `create(dados)`, `update(id, dados)`, `delete(id)`, `uploadArquivo(id, file, extras)` (FormData), `adicionarDoDrive(id, fileIds)`, `atualizarArquivo(id, arquivoId, dados)`, `removerArquivo(id, arquivoId)`, `reordenar(id, ids)`, `registrarProtocolo(id, numeroEvento, file)` (FormData), `drive(pastaId)`, `buscarDrive(q)`, `processos(contactId)`.
  - `helpers.js` (puro, testado): `mensagemProblema(problema, arquivos, tribunais, t)` → texto (ex.: `acima_do_limite:12` → "Laudo.pdf tem 14,2 MB; o limite do TJSC é 11 MB — divida o PDF"); `formatarMB(bytes)` → `"14,2 MB"` (vírgula decimal); `baixarTodos(arquivos)` → para cada `url`, cria `<a href download>` e clica, com 400 ms entre um e outro.
  - **Protocolos.vue (lista):** filtro Rascunhos / Protocoladas; tabela com processo, cliente, tribunal, responsável, prazo (vermelho quando `prazo_perto`), status; botão **Nova petição** abre `PeticaoForm`; clicar na linha vai para `ramon_protocolo`. Resposta 401 → mensagem `RAMON.PETICOES.SEM_ACESSO`.
  - **Detalhe (mesma página com `peticaoId`):** cabeçalho com dados + editar; `PacoteEditor` (lista ordenada; subir/descer; select de tipo com `tipo_no_tribunal` ao lado; marcar principal; remover; **Enviar do computador** (input file múltiplo, `accept=".pdf,.jpg,.jpeg,.png"`); **Escolher do Drive** abre `SeletorDrive`); quadro de problemas (vermelho) ou "Pacote pronto"; botão **Baixar todos** (desabilitado com problemas); botão **Registrar protocolo** abre `RegistrarProtocolo` (número do evento + arquivo; só aparece para o responsável ou admin — compare `currentUserId`/`isAdmin` com `responsavel.id`). Protocolada: tudo somente leitura, link do comprovante e, se `drive_pasta_id`, link `https://drive.google.com/drive/folders/<id>`.
  - **PeticaoForm:** cliente (busca de contato nativa do Chatwoot — use a mesma API de busca de contatos que outra tela Ramon já usa; ex. `LinhaDaVida.vue`), ao escolher, carrega `processos` como sugestões do campo número; checkbox **Inicial** (mostra select de tribunal, esconde número); responsável (agentes da conta, padrão o usuário atual); prazo (`<input type="date">`); descrição.
  - **SeletorDrive:** modal; abre em `drive_pasta_base_id` da petição (ou raiz); migalha "Voltar" usando `pai_id`; busca com debounce 400 ms (≥ 3 letras); clicar pasta entra; marcar arquivos (PDF/imagem) e **Adicionar ao pacote** → `adicionarDoDrive`. `DRIVE_OFF` → mensagem.
  - Componentes: siga os de `PortalClientes.vue`/`ConferenciaFases.vue` (botões, modal, tabela de `components-next`), visual branco/preto do hub.

- [ ] **Step 1: `helpers.spec.js`**

```js
it('formatarMB usa vírgula', () => expect(formatarMB(14.2 * 1024 * 1024)).toBe('14,2 MB'));
it('mensagemProblema acima_do_limite cita arquivo, tamanho e tribunal', () => { /* t = (k, v) => `${k}|${JSON.stringify(v)}` e confere chave + nome + '14,2 MB' + 'TJSC' */ });
it('mensagemProblema sem_principal usa a chave i18n', () => {});
```

- [ ] **Step 2: Implementar API, helpers, componentes, rotas, menu, i18n (en + pt_BR).**
- [ ] **Step 3: Lint** — `npx eslint app/javascript/dashboard/routes/dashboard/ramon app/javascript/dashboard/api/ramonPeticoes.js` (worktree precisa da junção `node_modules` → `..\ramon-hub\node_modules`, criada com `cmd /c mklink /J node_modules ..\ramon-hub\node_modules`) → sem erros. vitest não roda pela junção; o CI roda.
- [ ] **Step 4: Commit** `feat(peticionamento): tela Protocolos com pacote, Drive e registro do protocolo`

---

### Task 7: Fechamento

- [ ] Smoke no consolidado: acrescentar **seção N — Peticionamento Fase 1** em `C:\Users\dudsl\RAdvogados\comercial\docs\2026-09-14-smoke-consolidado.md` (criar time `juridico`; criar petição TRF4 com número real; subir PDF e foto; escolher do Drive; ver aviso de limite com arquivo > 11 MB; baixar todos; registrar protocolo com comprovante; conferir a pasta `Protocolos` no Drive e que os arquivos sumiram do hub).
- [ ] Push do branch e `gh workflow run run_foss_spec.yml --ref feat/peticionamento`; esperar verde; corrigir o que o CI pegar. **Não abrir PR** (o Eduardo abre no fim).

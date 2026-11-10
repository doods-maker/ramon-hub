# Planejamento previdenciário no hub (fase 4): plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> **Skills do Matt (regra do dono para todo PR do hub):** `mattpocock-skills:tdd` em toda task com código (teste primeiro); `mattpocock-skills:codebase-design` nas Tasks 2, 4 e 6 (onde vai a costura, ver "Costuras" abaixo); `mattpocock-skills:code-review` antes do merge (Task 9, nunca trocar por revisão genérica); `mattpocock-skills:pr` no corpo do PR (Task 9).

**Goal:** trocar a aba "Planejamento" do Simulador pelo planejamento previdenciário do motor: perfil confirmado em dois passos, textos editáveis, PDF e memória gerados pelo motor, salvos na pasta do cliente no Drive e oferecidos para download, com histórico que reabre os textos editados.

**Architecture:** o hub só transporta `dados` (spec §6.1): "Calcular" é proxy síncrono de `POST /planejamento/previdenciario`; "Gerar" grava o `dados` editado num `Calculo` e enfileira um job Sidekiq que chama `/planejamento/previdenciario/pdf`, recalcula a memória com o mesmo perfil, guarda os dois arquivos no Redis (1 h) e sobe no Drive; a tela consulta o estado a cada 2 s e baixa os arquivos. O front edita só as folhas de texto (string) do `dados`; número nunca é editado nem recalculado no hub.

**Tech Stack:** Rails 7 (fork Chatwoot v4.15.1, branch `ramon`), Sidekiq, `Redis::Alfred`, HTTParty (`Ramon::MotorClient`), Google Drive API (`Ramon::DriveClient`), Vue 3 `<script setup>` + Tailwind + vue-i18n, RSpec + WebMock, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-09-planejamento-previdenciario-design.md` (fase 4 = §6.4; valem também §2, §3, §8). Contrato do motor: `C:\Users\dudsl\RAdvogados\juridico\projetos\motor-calculos\src\motor_calculos\api\main.py:472-579` e `motor\previdenciario\textos\__init__.py` (`montar_dados`).

## Decisões registradas neste plano

- **Síncrono × job (spec §6.4 "conferir rack-timeout"):** conferido na VPS em 09/11 (leitura, `printenv` no `chatwoot-web`): `RACK_TIMEOUT_SERVICE_TIMEOUT` **não está definida** → padrão de 15 s em produção (`rack-timeout` está no grupo `:production` do Gemfile, `config/initializers/rack_timeout.rb` só baixa o log); `WEB_CONCURRENCY=1`, `RAILS_MAX_THREADS=5`.
  - **Calcular = síncrono.** `planejar_previdenciario` mediu 0,02–0,93 s por caso (commits do motor); `read_timeout: 12` (abaixo dos 15 s, para o advogado ver 503 com mensagem, não um 500 do rack).
  - **Gerar = job + polling.** O PDF abre um Chromium por pedido (`render.py:62`, espera de até 30 s) e depois vêm 1 pasta + 2 uploads no Drive: passa de 10 s fácil, e prenderia 1 das 5 threads do único processo web. O job roda no `chatwoot-worker`, que já tem `MOTOR_CALCULOS_URL` e `RAMON_DRIVE_*` (conferido 09/11).
  - Bytes do PDF/memória ficam no Redis (`Redis::Alfred.setex`, 1 h, Base64), não no `Rails.cache` (em produção é file store por container: web e worker não compartilham).
- **Sem migração.** Estado da geração e `dados` editado vão no `calculos.snapshot` (jsonb que já existe).
- **Memória recalculada no job** (mesmo perfil + `data_calculo` lida de `dados.calculo_data`), com trava: se data da aposentadoria, rendas dos cenários ou renda do "parar" do recálculo diferirem do `dados` editado → erro "os números mudaram desde o cálculo — calcule de novo". Garante a anti-meta "número na tela diferente do PDF/memória".
- **`tipo` do histórico continua `'planejamento'`** (rótulos de `Calculos.vue:180` e `Dossie.vue:128` e a aba do `LeadSimulador` já usam). Linha nova tem `params.dados`; linha antiga (sem `dados`) reabre a aba em branco.
- **Histórico nasce no "Gerar"** (uma linha por PDF gerado, com perfil + `dados` editado). "Calcular" não grava histórico.
- **Endpoint/aba antigos saem nesta fase:** `POST /planejamento` (contrato antigo) e `POST /planejamento/pdf` só são usados por `LeadPlanejamento.vue` (e pelo mock de `Calculos.story.vue`); nada em `deploy/`, `enterprise/` ou jobs. A rota `planejamento` é reaproveitada com o contrato novo. **Fica para a fase 6 (motor):** aposentar `/planejamento`, `/planejamento/pdf` e `pdf_planejamento.py` no motor, porque o hub deixa de chamá-los aqui.
- **Mesmo mês, gerar de novo:** substitui os arquivos de mesmo nome na subpasta (regra "só a versão mais nova"), não duplica.
- **`cnis_data`** = data de `lead.cnis.uploaded_at` (o hub não guarda a data de emissão do CNIS; é a melhor aproximação disponível, melhor que a data do cálculo ao reabrir meses depois).

## Costuras (`mattpocock-skills:codebase-design`)

- **Back:** um módulo profundo `Ramon::PlanejamentoPrevidenciario` (`app/services/ramon/planejamento_previdenciario.rb`). Interface pequena: `.payload`, `.nomes`, `.arquivo`, `#gerar!`. Controller e job não sabem de Redis, Drive, nomes de arquivo nem formato do motor. `Ramon::MotorClient` continua só HTTP; `Ramon::DriveClient` ganha uma primitiva (`substituir`).
- **Front:** `helpers/planejamentoTextos.js` é a costura do "só texto é editável" (função pura, testada sozinha). `PlanejamentoTextos.vue` só desenha o que o helper devolve. `LeadPlanejamento.vue` orquestra os passos e o polling.

## Global Constraints

- Sem Ruby local: lint Ruby com `rubocop-vps` (Git Bash, de dentro do checkout) antes de cada commit Ruby; specs Ruby rodam no CI (`run_foss_spec.yml`). Nas tasks Ruby, "ver falhar" = confirmar lendo que o método/rota ainda não existe; "ver passar" = CI do PR. Empurrar T1–T5 juntos para um só ciclo de CI.
- RuboCop com linha de até 150 caracteres.
- Vue: Composition API `<script setup>`, componentes PascalCase, **eventos custom em camelCase**, só classes Tailwind (tokens de `helpers/ui.js`: `AVISO`, `CARTAO`, `TITULO`, `TOM`…), visual branco/preto do hub (`docs/regras-de-design.md`).
- i18n: nenhuma string solta no template; chaves novas em `app/javascript/dashboard/i18n/locale/en/ramon.json` **e** `pt_BR/ramon.json` (o fork mantém pt_BR traduzido), sob `RAMON.SIMULADOR.PLANEJAMENTO_*`; sem `{`, `@` ou `|` soltos (trava `equipeI18n.spec.js`). Mensagens de erro do backend seguem o padrão já existente de `Ramon::MotorClient` (português direto; não há namespace `ramon` em `config/locales`).
- Texto que fala com cliente é do motor (gate do Eduardo, spec §6.5); a UI do hub é interna e tem cópia mínima.
- Conventional Commits (`type(scope): assunto`), em português, como o repo.
- Nada de migração; nada de dado real de cliente em spec (nomes fictícios).
- Pasta no Drive: `Planejamento previdenciário – MM.AA` (travessão `–`, mês da geração) dentro de `pasta_cliente_id`; arquivos `Planejamento previdenciário - <Nome>.pdf` (`Raio-X Elites - <Nome>.pdf` quando `dados.turma` preenchido) e `Memória de cálculo - <Nome>.xlsx` (hífen `-`). Lead sem contato (rascunho da tela Cálculos) → só download.
- `dados.formato_textos == "rascunho"` → gera PDF (o motor põe marca d'água), mas a tela mostra "aguardando aprovação dos textos".
- Deploy: **motor primeiro, depois hub** (web **e** worker). Merge e deploy só com o OK do Eduardo na conversa (lição de 09/11: o OK vale por PR).

## Review Focus

1. **Motor ainda sem os endpoints novos (404) depois do merge do hub** → a aba mostra "motor de cálculos desatualizado" e nada quebra (Task 1 e Task 8).
2. **Worker parado ou job travado em "gerando"** → a tela para de consultar em 2 min e diz que não terminou, com botão de tentar de novo (Task 8).
3. **Drive falha depois que o PDF ficou pronto** → download continua disponível e a tela mostra que não salvou no Drive (Task 4).
4. **Advogado apaga/estraga um marcador `{data_ap}` ou deixa um texto vazio** → o 422 do motor aparece na aba em português, as edições ficam na tela e no histórico (Task 4 e Task 8).
5. **Download depois de 1 h (Redis expirou) ou `calculo_id` de outro lead/conta** → 404 com "arquivo expirou — gere de novo" / sem vazar arquivo de outro lead (Task 5).

---

### Task 1: `Ramon::MotorClient` — endpoints novos, 404 = motor desatualizado, sai o contrato antigo

**Files:**
- Modify: `lib/ramon/motor_client.rb:42-46,60-64` (remover `planejamento`/`planejamento_pdf`), `:127-132` (`handle`)
- Test: `spec/lib/ramon/motor_client_spec.rb`

**Interfaces:**
- Produces: `Ramon::MotorClient.planejamento_previdenciario(payload) -> Hash` (POST `/planejamento/previdenciario`, `read_timeout: 12`); `Ramon::MotorClient.planejamento_previdenciario_pdf(dados) -> String` (bytes; POST `/planejamento/previdenciario/pdf` com corpo `{ dados: }`, `read_timeout: 60`, `raw: true`; só roda no job). HTTP 404 em qualquer endpoint → `UnavailableError` com mensagem começando por `motor de cálculos desatualizado`.

- [ ] **Step 1: Write the failing tests** (mesmo estilo de `describe '.liquidacao_pdf'`, `with_modified_env MOTOR_CALCULOS_URL: 'http://motor:8000'`)

```ruby
describe '.planejamento_previdenciario' do
  it 'posta o payload e devolve o corpo parseado'          # stub 200 {dados:{}, forma_sugerida:{forma:'pro_labore'}} → hash['forma_sugerida']['forma'] == 'pro_labore'
  it 'levanta ValidationError com o detail no 422'          # detail 'vinculos_detalhe inválido' → raise_error(ValidationError, /vinculos_detalhe/)
  it 'levanta UnavailableError "motor de cálculos desatualizado" no 404' do
    # stub 404 {"detail":"Not Found"}
    expect { described_class.planejamento_previdenciario({}) }
      .to raise_error(described_class::UnavailableError, /\Amotor de cálculos desatualizado/)
  end
end
describe '.planejamento_previdenciario_pdf' do
  it 'manda {dados:} e devolve os bytes crus'               # have_requested ... body == {'dados'=>{'nome'=>'X'}}; resultado start_with('%PDF')
  it 'levanta ValidationError no 422'                       # detail 'o PDF não pôde ser gerado: marcador' → /marcador/
end
```

- [ ] **Step 2: Confirmar que falha** — os métodos não existem e o 404 hoje vira "respondeu HTTP 404".
- [ ] **Step 3: Implementar** os dois métodos via `post_json`; em `handle`, antes do `raise UnavailableError` genérico: `raise UnavailableError, "motor de cálculos desatualizado: #{response.request.path} não existe — atualizar o motor na VPS" if response.code == 404`. Remover `planejamento` e `planejamento_pdf` (e o comentário deles).
- [ ] **Step 4:** `rubocop-vps lib/ramon/motor_client.rb spec/lib/ramon/motor_client_spec.rb` → `no offenses`.
- [ ] **Step 5: Commit** `feat(motor): cliente do planejamento previdenciário e 404 como motor desatualizado`

---

### Task 2: `Ramon::PlanejamentoPrevidenciario` — payload e nomes (funções puras)

**Files:**
- Create: `app/services/ramon/planejamento_previdenciario.rb`
- Test: `spec/services/ramon/planejamento_previdenciario_spec.rb`

**Interfaces:**
- Produces:
  - `Ramon::PlanejamentoPrevidenciario.payload(cnis, perfil, segurado_nome:, data_calculo: nil) -> Hash` — `cnis` = `lead.cnis` (Hash string-keyed); `perfil` = Hash string-keyed vindo da tela; devolve `{ segurado:, competencias:, vinculos:, vinculos_detalhe:, perfil:, data_calculo:, cnis_data: }` com `perfil.compact_blank` + `'segurado_nome'`; omite `vinculos_detalhe` quando `cnis['vinculos']` é nil (upload antigo), omite `data_calculo` quando nil, `cnis_data` = data ISO de `cnis['uploaded_at']` (omitida se ausente).
  - `Ramon::PlanejamentoPrevidenciario.nomes(dados, hoje: Date.current) -> { pasta:, pdf:, memoria: }` — nome = `dados['nome']` sem `/\:*?"<>|`, `squish` (mesmo saneamento de `DriveExportService#nome_tese`).

- [ ] **Step 1: Write the failing tests**

```ruby
let(:cnis) do
  { 'entrada' => { 'segurado' => { 'nascimento' => '1978-03-10', 'sexo' => 'M' },
                   'competencias' => [{ 'ano' => 2026, 'mes' => 9, 'salario' => '3000.00' }],
                   'vinculos' => [{ 'inicio' => '2010-01-01', 'fim' => nil, 'tipo' => 'CONTRIBUINTE_INDIVIDUAL', 'indicadores' => [] }] },
    'vinculos' => [{ 'seq' => 1, 'origem' => 'EMPRESA FICTICIA', 'remuneracoes' => [] }],
    'uploaded_at' => '2026-11-05T10:00:00-03:00' }
end

it 'monta o corpo do motor com o detalhe dos vínculos e sem campos vazios do perfil' do
  perfil = { 'forma' => 'pro_labore', 'salario_atual' => '3000.00', 'empresa' => 'Empresa Ficticia',
             'cenario_livre' => '', 'facultativo_semestral' => false, 'descarte_pontos' => 'nao' }
  expect(described_class.payload(cnis, perfil, segurado_nome: 'Fulano de Tal', data_calculo: '2026-11-09')).to eq(
    segurado: cnis['entrada']['segurado'], competencias: cnis['entrada']['competencias'],
    vinculos: cnis['entrada']['vinculos'], vinculos_detalhe: cnis['vinculos'],
    perfil: { 'forma' => 'pro_labore', 'salario_atual' => '3000.00', 'empresa' => 'Empresa Ficticia',
              'descarte_pontos' => 'nao', 'segurado_nome' => 'Fulano de Tal' },
    data_calculo: '2026-11-09', cnis_data: '2026-11-05'
  )
end
it 'sem forma (1ª chamada) e upload antigo: não manda forma, vinculos_detalhe nem data_calculo'
  # payload(cnis.except('vinculos'), {}, segurado_nome: 'X') → keys == %i[segurado competencias vinculos perfil cnis_data]; perfil == {'segurado_nome'=>'X'}
it 'nomes: pasta do mês, PDF e memória com o nome saneado' do
  expect(described_class.nomes({ 'nome' => 'Ana / Souza', 'turma' => '' }, hoje: Date.new(2026, 11, 9))).to eq(
    pasta: 'Planejamento previdenciário – 11.26',
    pdf: 'Planejamento previdenciário - Ana Souza.pdf',
    memoria: 'Memória de cálculo - Ana Souza.xlsx'
  )
end
it 'nomes: com turma o PDF sai como Raio-X Elites'   # pdf == 'Raio-X Elites - Ana Souza.pdf'
```

- [ ] **Step 2: Confirmar que falha** (classe não existe).
- [ ] **Step 3: Implementar** os dois métodos de classe (só esses nesta task).
- [ ] **Step 4:** `rubocop-vps` nos dois arquivos → `no offenses`.
- [ ] **Step 5: Commit** `feat(planejamento): corpo do motor e nomes dos arquivos do planejamento previdenciário`

---

### Task 3: `Ramon::DriveClient.substituir` — mesmo nome na pasta é trocado, não duplicado

**Files:**
- Modify: `lib/ramon/drive_client.rb` (após `upload`, `:52-55`)
- Test: `spec/lib/ramon/drive_client_spec.rb` (padrão `instance_double(Google::Apis::DriveV3::DriveService)` já usado no arquivo)

**Interfaces:**
- Produces: `Ramon::DriveClient.substituir(name:, io:, content_type:, parent_id:) -> String` (id). Procura arquivo não-pasta com nome exato em `conteudo_da_pasta(parent_id)`; achou → `service.update_file(id, upload_source: io, content_type:)` e devolve o mesmo id; não achou → `upload(...)`.

- [ ] **Step 1: Write the failing tests**

```ruby
describe '.substituir' do
  it 'troca o conteúdo do arquivo de mesmo nome' do
    allow(described_class).to receive(:conteudo_da_pasta).with('p1')
      .and_return([{ id: 'f9', name: 'Memória de cálculo - Ana.xlsx', pasta: false }])
    expect(api).to receive(:update_file).with('f9', upload_source: anything, content_type: 'application/pdf')
    expect(described_class.substituir(name: 'Memória de cálculo - Ana.xlsx', io: StringIO.new('x'),
                                      content_type: 'application/pdf', parent_id: 'p1')).to eq('f9')
  end
  it 'sobe novo quando não há arquivo com o nome'    # conteudo_da_pasta → [{name:'outro'}]; expect(described_class).to receive(:upload) → 'n1'
  it 'ignora pasta com o mesmo nome'                 # [{id:'d1', name: X, pasta: true}] → chama upload
end
```

- [ ] **Step 2: Confirmar que falha.** - [ ] **Step 3: Implementar.** - [ ] **Step 4:** `rubocop-vps` → `no offenses`.
- [ ] **Step 5: Commit** `feat(drive): substituir arquivo de mesmo nome na pasta`

---

### Task 4: geração (job + Redis + Drive + trava dos números)

**Files:**
- Modify: `app/services/ramon/planejamento_previdenciario.rb`
- Create: `app/jobs/ramon/planejamento_gerar_job.rb`
- Test: `spec/services/ramon/planejamento_previdenciario_spec.rb`, `spec/jobs/ramon/planejamento_gerar_job_spec.rb`

**Interfaces:**
- Consumes: Task 1 (`planejamento_previdenciario`, `planejamento_previdenciario_pdf`), Task 2 (`payload`, `nomes`), Task 3 (`substituir`); `Ramon::DriveExportService.new(lead).pasta_cliente_id`; `Ramon::DriveClient.ensure_folder(name, parent_id)`.
- Produces:
  - `Ramon::PlanejamentoPrevidenciario.new(calculo).gerar!` — lê `calculo.snapshot['params']` (`'perfil'`, `'dados'`) e `snapshot['cnis']`; grava `snapshot['geracao']` com um destes formatos:
    - `{ 'estado' => 'pronto', 'drive' => { 'pasta_url' => 'https://drive.google.com/drive/folders/<id>' } }`
    - `{ 'estado' => 'pronto', 'drive' => nil, 'drive_motivo' => 'sem_cliente' | 'drive_desligado' }`
    - `{ 'estado' => 'pronto', 'drive' => nil, 'drive_erro' => 'não salvou no Drive: <mensagem>' }`
    - `{ 'estado' => 'erro', 'erro' => '<mensagem em português>' }`
  - `Ramon::PlanejamentoPrevidenciario.arquivo(calculo, tipo) -> String | nil` (`tipo` ∈ `'pdf'`, `'memoria'`; bytes decodificados do Redis, nil se expirou).
  - Chave Redis `"ramon:planejamento:#{calculo.id}:#{tipo}"`, `Redis::Alfred.setex(chave, Base64.strict_encode64(bytes), 1.hour)`.
  - `Ramon::PlanejamentoGerarJob.perform_later(calculo_id)` — `queue_as :medium` (alguém está esperando na tela); `perform` acha o `Calculo` (some → return) e chama `gerar!`. **Sem retry:** `gerar!` captura tudo e grava `estado: erro` (retry do Sidekiq duplicaria arquivos e deixaria a tela em "gerando").

Fluxo de `gerar!`: `data_calculo` = `Date.strptime(dados['calculo_data'], '%d/%m/%Y').iso8601` → `planejamento_previdenciario(payload(cnis, perfil, segurado_nome: dados['nome'], data_calculo:))` → trava dos números → `planejamento_previdenciario_pdf(dados)` → Redis (PDF + memória) → Drive (se `lead.contact.present?` e `DriveClient.configured?`: `ensure_folder(nomes[:pasta], pasta_cliente_id)` + `substituir` dos dois) → estado. Trava: `[dados.dig('aposentadoria','data'), dados['cenarios']&.map { |c| c['rmi'] }, dados.dig('parar','rmi')]` igual entre o recálculo e o `dados` editado; senão `estado: erro`, `erro: 'os números mudaram desde o cálculo — calcule de novo'`, sem chamar o PDF.

- [ ] **Step 1: Write the failing tests** (WebMock no motor; `allow(Ramon::DriveClient)` para `configured?`, `ensure_folder`, `substituir`; `allow_any_instance_of(Ramon::DriveExportService).to receive(:pasta_cliente_id).and_return('cli1')`; nomes fictícios)

```ruby
it 'lead com contato: guarda PDF e memória e salva os dois na subpasta do mês'
  # expect(Ramon::DriveClient).to receive(:ensure_folder).with('Planejamento previdenciário – 11.26', 'cli1').and_return('sub1')
  # expect(Ramon::DriveClient).to receive(:substituir).with(hash_including(name: 'Planejamento previdenciário - Ana Souza.pdf', parent_id: 'sub1'))
  # expect(Ramon::DriveClient).to receive(:substituir).with(hash_including(name: 'Memória de cálculo - Ana Souza.xlsx', parent_id: 'sub1'))
  # depois: calculo.reload.snapshot['geracao'] == {'estado'=>'pronto','drive'=>{'pasta_url'=>'https://drive.google.com/drive/folders/sub1'}}
  # described_class.arquivo(calculo, 'pdf') start_with('%PDF'); arquivo(calculo, 'memoria') == bytes do xlsx do stub
it 'manda ao /pdf exatamente o dados editado'               # have_requested(:post, '.../planejamento/previdenciario/pdf').with(body: { dados: dados_editado }.to_json)
it 'rascunho sem contato: só download, Drive nem é chamado' # expect(Ramon::DriveClient).not_to receive(:ensure_folder); geracao['drive_motivo'] == 'sem_cliente'
it 'Drive falha: arquivos continuam para baixar'            # substituir raise Google::Apis::ServerError → estado 'pronto', drive_erro =~ /não salvou no Drive/, arquivo(calculo,'pdf') presente
it '422 do motor no PDF vira erro com a mensagem do motor'  # stub /pdf 422 detail 'o PDF não pôde ser gerado: marcador {data_apx}' → estado 'erro', erro =~ /marcador/
it '404 do motor vira "motor de cálculos desatualizado"'    # estado 'erro', erro =~ /\Amotor de cálculos desatualizado/
it 'números do recálculo diferentes do dados editado: erro e não gera PDF'
  # recálculo devolve cenarios[0].rmi 2234.62, editado tem 9999.0 → erro == 'os números mudaram desde o cálculo — calcule de novo'; not_to have_requested(/pdf)
# job spec:
it 'perform chama gerar! do cálculo e ignora cálculo apagado'
```

- [ ] **Step 2: Confirmar que falha.**
- [ ] **Step 3: Implementar** `#gerar!`, `.arquivo` e o job (`rescue StandardError` final grava `erro: "não deu para gerar: #{e.class}"` e loga; erros do motor gravam `e.message`).
- [ ] **Step 4:** `rubocop-vps` → `no offenses`.
- [ ] **Step 5: Commit** `feat(planejamento): gerar PDF e memória em job, guardar no Drive do cliente`

---

### Task 5: controller e rotas — calcular, gerar, estado, arquivo

**Files:**
- Modify (reescrever): `app/controllers/api/v1/accounts/lead_planejamentos_controller.rb`
- Modify: `app/controllers/concerns/registra_calculo.rb:115-126` (devolver o registro; `nil` explícito no `rescue` e no `sem_historico?`)
- Modify: `config/routes.rb:448-450`
- Modify: `docs/FORK-PONTOS-DE-REGISTRO.md:105,275,278,279` (+ linhas dos arquivos novos das Tasks 2–4)
- Test (reescrever): `spec/controllers/api/v1/accounts/lead_planejamentos_controller_spec.rb`

**Interfaces:**
- Consumes: Tasks 1, 2, 4.
- Produces (todas com `authorize(@lead, :show?)` e `responder` do `CalculoProxy`):
  - `POST /api/v1/accounts/:account_id/leads/:lead_id/planejamento` body `{ perfil?: {...}, segurado_nome? }` → 200 com o JSON do motor **sem** `memoria_xlsx_b64` (`{ dados, forma_sugerida, avisos }`); 422 `{ error: 'Anexe o CNIS para montar o planejamento.' }` sem `lead.cnis`; 503 com a mensagem do motor (inclusive "motor de cálculos desatualizado"). Não grava histórico.
  - `POST .../planejamento/gerar` body `{ perfil: {...}, dados: {...}, segurado_nome? }` → `calculo = registrar_calculo('planejamento', valor: <rmi do cenário com 'sugestao' => true, ou nil>)`; grava `snapshot['geracao'] = { 'estado' => 'gerando' }`; `Ramon::PlanejamentoGerarJob.perform_later(calculo.id)`; 202 `{ calculo_id: }`. `calculo` nil → 503 `{ error: 'não deu para registrar o planejamento — tente de novo' }`.
  - `GET .../planejamento/geracao?calculo_id=` → 200 `snapshot['geracao']`; 404 se o cálculo não é deste lead/conta.
  - `GET .../planejamento/arquivo?calculo_id=&tipo=pdf|memoria` → `send_data` com `filename` de `nomes(dados, hoje: calculo.created_at.to_date)` e `type` `application/pdf` / `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`; 404 `{ error: 'arquivo expirou — gere de novo' }` quando `arquivo` devolve nil; 404 para cálculo de outro lead.
  - `permitted` = `params.permit(:segurado_nome, perfil: %i[forma salario_atual empresa salario_emprego cenario_livre turma facultativo_semestral descarte_pontos], dados: {})` → `snapshot['params'] = { 'perfil' => {...}, 'dados' => {...}, 'segurado_nome' => ... }` (o `inicial.params` que a tela recebe ao reabrir).
  - Rota: `resource :planejamento, only: [:create], controller: 'lead_planejamentos' do post :gerar; get :geracao; get :arquivo; end` (sai `post :pdf`).

- [ ] **Step 1: Write the failing tests** (reaproveitar `let`s e o 401/outra conta do spec atual)

```ruby
it 'calcular: repassa o corpo montado por PlanejamentoPrevidenciario.payload e tira a memória da resposta'
  # stub /planejamento/previdenciario 200 {dados:{nome:'Ana'}, memoria_xlsx_b64:'eA==', forma_sugerida:{forma:'carne_20'}, avisos:[]}
  # post planejamento, perfil: {forma:'carne_20'} → 200; json.keys == %w[dados forma_sugerida avisos]; request ao motor tem perfil.forma 'carne_20' e vinculos_detalhe
it 'calcular sem CNIS → 422 com "Anexe o CNIS"'
it 'calcular com motor desatualizado (404) → 503 com a mensagem'   # json['error'] =~ /motor de cálculos desatualizado/
it 'calcular não grava histórico'                                   # expect { ... }.not_to change(Calculo, :count)
it 'gerar: grava o dados editado inteiro no histórico e enfileira o job' do
  dados = { 'nome' => 'Ana', 'cenarios' => [{ 'rmi' => 2234.62, 'sugestao' => true, 'bom' => ['a', 'b'] }],
            'pendencias' => [], 'sugestao' => { 'itens' => ['x'] } }
  # expect { post gerar, perfil: {forma:'pro_labore'}, dados: }.to have_enqueued_job(Ramon::PlanejamentoGerarJob)
  # calculo = Calculo.last → tipo 'planejamento'; snapshot['params']['dados'] == dados (arrays aninhados e vazios preservados);
  # snapshot['geracao'] == {'estado'=>'gerando'}; snapshot['valor'] == 2234.62; response 202 json == {'calculo_id'=>calculo.id}
end
it 'geracao devolve o estado; cálculo de outro lead → 404'
it 'arquivo devolve o PDF com o nome do Drive'                      # Redis com o PDF → content-disposition inclui 'Planejamento previdenciário - Ana.pdf'
it 'arquivo expirado → 404 "arquivo expirou — gere de novo"'
```

- [ ] **Step 2: Confirmar que falha.**
- [ ] **Step 3: Implementar** controller, ajuste do `registrar_calculo` (sem mudar o comportamento dos outros proxies: eles ignoram o retorno), rotas e as linhas do `FORK-PONTOS-DE-REGISTRO.md`. Se o spec mostrar que `permit(dados: {})` perde arrays aninhados/vazios, trocar por `params.require(:dados).to_unsafe_h` com comentário (staff autenticado; o motor revalida o `dados`).
- [ ] **Step 4:** `rubocop-vps` → `no offenses`. **Push T1–T5** e abrir PR draft; CI backend verde antes de seguir para o front.
- [ ] **Step 5: Commit** `feat(planejamento): rotas de calcular, gerar, estado e arquivo do planejamento previdenciário`

---

### Task 6: `helpers/planejamentoTextos.js` — só texto é editável

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/planejamentoTextos.js`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/planejamentoTextos.spec.js`

Setup (se o checkout/worktree não tiver `node_modules`): `npx -y pnpm@10.2.0 install --frozen-lockfile --offline --ignore-scripts` e `npx husky install` (lição de 07/11).

**Interfaces:**
- Produces:
  - `SECOES_EDITAVEIS: string[]` = `['pendencias', 'observacoes_internas', 'pode', 'nao_pode', 'sugestao', 'cenarios', 'melhorias', 'passos', 'conferir', 'documentos']` (`melhorias` = versão curta; seção ausente é pulada).
  - `camposEditaveis(dados) -> Array<{ secao: string, caminho: Array<string|number>, valor: string }>` — percorre só as folhas **string** das seções, na ordem acima e na ordem das chaves; em `cenarios[i]` só `lead` e depois `bom`.
  - `definirTexto(dados, caminho, valor) -> void` — muta `dados` no caminho; lança `Error` se a folha atual não for string (número nunca se edita).

- [ ] **Step 1: Write the failing tests**

```js
const dados = () => ({
  nome: 'Ana', formato_textos: 'aprovado',
  cenarios: [{ nome: 'Mínimo', v: 1518, rmi: 2234.62, titulo: 'Cenário 1', lead: 'L', bom: ['a', 'b'] }],
  pode: [{ t: 'T', p: 'P' }],
  sugestao: { curta: 'c', titulo: 't', itens: ['i'] },
  documentos: { separar: ['s'], guardar: ['g'] },
  aposentadoria: { data: '16/03/2040', regra: 'regra dos pontos' },
});
it('lista só as folhas de texto das seções editáveis, na ordem', () => {
  expect(camposEditaveis(dados()).map(c => c.caminho.join('.'))).toEqual([
    'pode.0.t', 'pode.0.p', 'sugestao.curta', 'sugestao.titulo', 'sugestao.itens.0',
    'cenarios.0.lead', 'cenarios.0.bom.0', 'cenarios.0.bom.1',
    'documentos.separar.0', 'documentos.guardar.0',
  ]);
});
it('versão curta sem cenários: lista melhorias e não quebra', ...)  // { versao:'curta', melhorias:[{t:'+12 meses', p:'x', rmi: 3000}] } → ['melhorias.0.t','melhorias.0.p']
it('definirTexto troca o texto no lugar', ...)                      // definirTexto(d, ['cenarios',0,'bom',1], 'novo') → d.cenarios[0].bom[1] === 'novo'
it('definirTexto recusa número', ...)                               // definirTexto(d, ['cenarios',0,'rmi'], '1') → toThrow()
```

- [ ] **Step 2:** `pnpm test app/javascript/dashboard/routes/dashboard/ramon/helpers/specs/planejamentoTextos.spec.js` → FAIL (módulo não existe).
- [ ] **Step 3: Implementar** as três exportações.
- [ ] **Step 4:** mesmo comando → PASS; `npx eslint <arquivos>` → sem erro.
- [ ] **Step 5: Commit** `feat(planejamento): helper dos textos editáveis do planejamento`

---

### Task 7: `PlanejamentoTextos.vue` — editor das seções

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/PlanejamentoTextos.vue`
- Test: `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/PlanejamentoTextos.spec.js`
- Modify: `en/ramon.json`, `pt_BR/ramon.json` (`PLANEJAMENTO_SECAO_<SECAO>` para cada item de `SECOES_EDITAVEIS`, `PLANEJAMENTO_SO_ADVOGADO`)

**Interfaces:**
- Consumes: Task 6.
- Produces: `<PlanejamentoTextos :dados="dados" />` — `dados` é o objeto reativo do pai, editado no lugar via `definirTexto` (sem evento; o pai já é dono do objeto). Agrupa `camposEditaveis(dados)` por `secao` com título i18n; `observacoes_internas` leva o aviso `PLANEJAMENTO_SO_ADVOGADO` ("só para o advogado — não vai no PDF"). Cada campo = `<textarea>` com `data-testid="planejamento-texto-<caminho com pontos>"`.

- [ ] **Step 1: Write the failing tests** (`mount`, mock de `vue-i18n` como em `LeadPlanejamento.spec.js`)

```js
it('um textarea por texto editável e nenhum para número', ...)      // dados() da Task 6 → findAll('textarea').length === 10; sem testid 'planejamento-texto-cenarios.0.rmi'
it('digitar muda o dados do pai', ...)                               // setValue('novo') em 'planejamento-texto-pode.0.p' → dados.pode[0].p === 'novo'
it('observações internas avisam que não vão no PDF', ...)            // observacoes_internas:[{t:'x',p:'y'}] → text contém 'RAMON.SIMULADOR.PLANEJAMENTO_SO_ADVOGADO'
```

- [ ] **Step 2:** `pnpm test .../specs/PlanejamentoTextos.spec.js` → FAIL.
- [ ] **Step 3: Implementar.**
- [ ] **Step 4:** PASS + `pnpm test .../helpers/specs/equipeI18n.spec.js` PASS + eslint limpo.
- [ ] **Step 5: Commit** `feat(planejamento): editor dos textos do planejamento previdenciário`

---

### Task 8: `LeadPlanejamento.vue` novo — perfil em dois passos, gerar com polling, reabrir do histórico

**Files:**
- Modify (reescrever): `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/LeadPlanejamento.vue`
- Modify: `app/javascript/dashboard/api/leads.js:102-110`
- Modify: `en/ramon.json`, `pt_BR/ramon.json` (chaves novas abaixo; remover as `PLANEJAMENTO_*` do contrato antigo que ficarem sem uso, conferindo com grep)
- Modify: `app/javascript/dashboard/routes/dashboard/ramon/pages/Calculos.story.vue:322,447,559-562` (mock no formato novo: `{ dados, forma_sugerida, avisos }`, clique em `planejamento-comecar`)
- Test (reescrever): `app/javascript/dashboard/routes/dashboard/ramon/components/conversation/specs/LeadPlanejamento.spec.js`
- Sem mudança: `LeadSimulador.vue` (mesmas props `lead`, `seguradoNome`, `inicial`; mesmo gate `canPlanejamento`, `:1478-1496`).

**Interfaces:**
- Consumes: Tasks 5 e 7.
- Produces (API, `leads.js`):
  - `planejamento(leadId, payload)` → `POST .../planejamento` (mesmo nome, contrato novo)
  - `planejamentoGerar(leadId, payload)` → `POST .../planejamento/gerar`
  - `planejamentoGeracao(leadId, calculoId)` → `GET .../planejamento/geracao?calculo_id=`
  - `planejamentoArquivo(leadId, calculoId, tipo)` → `GET .../planejamento/arquivo?calculo_id=&tipo=`, `responseType: 'blob'`
  - (sai `planejamentoPdf`)
- Comportamento:
  1. Início: botão `planejamento-comecar` → `planejamento(lead.id, { segurado_nome })` sem perfil → preenche o formulário com `forma_sugerida.forma`/`salario_atual` e mostra o `motivo`. Nada chama o motor ao montar (a aba monta escondida com `v-show`).
  2. Perfil: `forma` (6 opções, `PLANEJAMENTO_FORMA_<FORMA>`), `empresa`, `salario_atual`, `salario_emprego` (só `pro_labore_mais_salario`), `cenario_livre`, `turma`, `facultativo_semestral` (só formas `pro_labore*`), `descarte_pontos` dentro de `<details>` "avançado" (padrão `nao`). Valores monetários vão como string. Botão `planejamento-calcular` → `planejamento(lead.id, { perfil, segurado_nome })`.
  3. Resultado: resumo (aposentadoria `data`/`regra`, tabela de cenários `nome`/`v`/`rmi`/`custo` quando houver, `sugestao.curta`, `parar`), selo `PLANEJAMENTO_AGUARDANDO_TEXTOS` quando `dados.formato_textos === 'rascunho'`, selo `PLANEJAMENTO_VERSAO_CURTA` quando `dados.versao === 'curta'`, `avisos`, e `<PlanejamentoTextos :dados="dados" />`.
  4. Gerar (`planejamento-gerar`) → `planejamentoGerar(lead.id, { perfil, dados, segurado_nome })` → consulta `planejamentoGeracao` a cada 2 s (`setTimeout`, limpo no `onBeforeUnmount`), no máximo 60 vezes; `pronto` → botões `planejamento-baixar-pdf` / `planejamento-baixar-memoria` (download via `planejamentoArquivo` + `URL.createObjectURL`) e linha do Drive (`PLANEJAMENTO_DRIVE_SALVO` com link `pasta_url`, `PLANEJAMENTO_DRIVE_SO_DOWNLOAD` quando `drive_motivo`, `drive_erro` cru quando houver); `erro` → mensagem do servidor; estourou as 60 → `PLANEJAMENTO_DEMOROU`. Erro em qualquer passo usa o `handleError` atual (inclui erro em Blob) e mantém `dados` editado na tela.
  5. Reabrir: `inicial?.dados` presente → restaura `perfil` e `dados` direto no passo 3, sem chamar o motor; `inicial` sem `dados` (linha antiga) → passo 1.
- Chaves i18n novas (en + pt_BR): `PLANEJAMENTO_COMECAR`, `PLANEJAMENTO_LENDO`, `PLANEJAMENTO_SUGERIDA` (com `{motivo}`), `PLANEJAMENTO_FORMA`, `PLANEJAMENTO_FORMA_PRO_LABORE`, `…_PRO_LABORE_MAIS_SALARIO`, `…_CARNE_20`, `…_SIMPLIFICADO_11`, `…_BAIXA_RENDA_5`, `…_EMPREGADO`, `PLANEJAMENTO_EMPRESA`, `PLANEJAMENTO_SALARIO_ATUAL`, `PLANEJAMENTO_SALARIO_EMPREGO`, `PLANEJAMENTO_CENARIO_LIVRE`, `PLANEJAMENTO_TURMA`, `PLANEJAMENTO_FACULTATIVO`, `PLANEJAMENTO_AVANCADO`, `PLANEJAMENTO_DESCARTE_PONTOS`, `…_NAO`, `…_TEMPO_MINIMO`, `PLANEJAMENTO_CALCULAR`, `PLANEJAMENTO_CALCULANDO`, `PLANEJAMENTO_AGUARDANDO_TEXTOS` ("aguardando aprovação dos textos"), `PLANEJAMENTO_VERSAO_CURTA`, `PLANEJAMENTO_GERAR`, `PLANEJAMENTO_GERANDO`, `PLANEJAMENTO_MEMORIA_BAIXAR`, `PLANEJAMENTO_DRIVE_SALVO`, `PLANEJAMENTO_DRIVE_SO_DOWNLOAD`, `PLANEJAMENTO_DEMOROU`. Reaproveitar `PLANEJAMENTO_ERRO`, `PLANEJAMENTO_PDF_BAIXAR`, `PLANEJAMENTO_PRECISA_CNIS`.

- [ ] **Step 1: Write the failing tests** (`vi.mock('dashboard/api/leads')` com as quatro funções; `vi.useFakeTimers()` nos de polling)

```js
it('não chama o motor ao montar', ...)                                      // mount → LeadsAPI.planejamento not called
it('começar: 1ª chamada sem perfil e formulário com a forma sugerida', ...) // click comecar → called with (13, {segurado_nome: undefined}); select forma value 'carne_20'
it('calcular manda o perfil confirmado', ...)                               // muda empresa → click calcular → 2ª chamada com perfil { forma:'carne_20', empresa:'Empresa Ficticia', descarte_pontos:'nao', ... }
it('rascunho de textos mostra "aguardando aprovação dos textos"', ...)      // dados.formato_textos 'rascunho' → text contém PLANEJAMENTO_AGUARDANDO_TEXTOS
it('motor desatualizado aparece como mensagem, sem quebrar', ...)           // planejamento rejeita {response:{status:503,data:{error:'motor de cálculos desatualizado: ...'}}} → planejamento-error contém o texto
it('gerar manda o dados editado e consulta até ficar pronto', ...)          // edita textarea → gerar called com dados editado; geracao: 'gerando' → advanceTimersByTime(2000) → 'pronto' com drive.pasta_url → link visível, botões de baixar
it('para de consultar depois de 60 tentativas', ...)                        // sempre 'gerando' → advanceTimersByTime(2000*61) → planejamentoGeracao 60 vezes; PLANEJAMENTO_DEMOROU visível
it('erro na geração mostra a mensagem e mantém as edições', ...)            // 'erro' com erro 'o PDF não pôde ser gerado: marcador' → mensagem; textarea mantém o texto editado
it('reabrir do histórico restaura perfil e dados sem chamar o motor', ...)  // inicial {perfil:{forma:'pro_labore'}, dados} → passo 3; planejamento not called
it('linha antiga do histórico (sem dados) abre no começo', ...)             // inicial {cenarios:[...]} → botão comecar visível
it('para o polling ao desmontar', ...)                                      // unmount durante 'gerando' → nenhuma chamada nova depois de advanceTimersByTime
```

- [ ] **Step 2:** `pnpm test .../specs/LeadPlanejamento.spec.js` → FAIL.
- [ ] **Step 3: Implementar** componente, `leads.js`, i18n, mock da story.
- [ ] **Step 4:** `pnpm test app/javascript/dashboard/routes/dashboard/ramon` → PASS (inclui `equipeI18n.spec.js` e `LeadSimulador`/`Calculos` specs, se existirem); `npx eslint` nos arquivos tocados → limpo.
- [ ] **Step 5: Commit** `feat(planejamento): aba Planejamento previdenciário no Simulador`

---

### Task 9: revisão, PR, ordem de deploy e smoke

**Files:**
- Modify: `C:\Users\dudsl\RAdvogados\comercial\docs\2026-09-14-smoke-consolidado.md` (próxima seção livre; AM quando este plano foi escrito)

- [ ] **Step 1:** `mattpocock-skills:code-review` desde o merge-base com `origin/ramon` (eixos: padrões do `CLAUDE.md` do hub + este plano e spec §6.4). Corrigir o que vier, com teste.
- [ ] **Step 2:** CI 100% verde (backend + `frontend-fe`). CI vermelho não mergeia.
- [ ] **Step 3: Corpo do PR com `mattpocock-skills:pr`**, contendo obrigatoriamente:
  - **Ordem de deploy: motor primeiro.** (1) Eduardo sobe o motor (`git archive` → `/opt/motor-calculos` → build + up; a imagem cresce com o Chromium). (2) Conferir de dentro do hub: `docker exec intranet-ramon-chatwoot-web-1 sh -c 'curl -s -o /dev/null -w "%{http_code}" -X POST "$MOTOR_CALCULOS_URL/planejamento/previdenciario/pdf" -H "Content-Type: application/json" -d "{\"dados\":{}}"'` → `422` (não `404`). (3) Só então hub: `docker compose pull chatwoot-web chatwoot-worker && docker compose up -d chatwoot-web chatwoot-worker` (**worker obrigatório**: o job novo roda nele). Sem migração.
  - Se o hub subir antes do motor: a aba mostra "motor de cálculos desatualizado" e o resto do hub segue normal.
  - Decisão síncrono × job (com os números de rack-timeout e de tempo do motor) e o follow-up da fase 6 (aposentar `/planejamento`, `/planejamento/pdf` e `pdf_planejamento.py` no motor).
  - Rodapé de atribuição do system-reminder da sessão.
- [ ] **Step 4: Smoke** (seção nova no smoke consolidado, em bloco):
  1. Lead com contato e CNIS → Simulador → Planejamento → "Começar": forma sugerida e motivo aparecem.
  2. Trocar empresa/salário, Calcular: resumo (data, regra, cenários, sugestão, parar) e textos editáveis.
  3. Editar um texto de "bom saber" e um de próximos passos → Gerar → em segundos: link da pasta `Planejamento previdenciário – MM.AA` na pasta do cliente com o PDF e a memória; baixar os dois; o texto editado está no PDF; os números do PDF batem com a tela e com a memória.
  4. Gerar de novo no mesmo mês → a pasta continua com 1 PDF e 1 memória (substituídos).
  5. Marcar turma → PDF sai "Raio-X Elites - <Nome>.pdf" com a capa Raio-X Elites.
  6. Forma `carne_20` → selo "aguardando aprovação dos textos" e PDF com marca d'água.
  7. Cálculos → cálculo rápido (sem cliente) → Planejamento → Gerar → só download, nada no Drive.
  8. Cálculos → histórico → reabrir o planejamento gerado → textos editados de volta, sem recalcular.
  9. Cliente já elegível (se houver) → selo "versão curta" e PDF curto.
- [ ] **Step 5:** merge e deploy **só com o OK do Eduardo na conversa** para este PR; registrar o que subiu na memória `ramon-hub-plano-mestre-e-frentes`.

---

## Self-review (feito)

- **Cobertura do spec §6.4:** aba substituída no mesmo lugar/gate → T8 (sem mudar `LeadSimulador`); perfil com sugestão, empresa, salário, livre, turma, facultativo, descarte em "avançado" → T8; calcular + resumo + seções editáveis → T6–T8; gerar → PDF + memória na pasta do cliente + download → T4/T5/T8; subpasta e nomes → T2/T4; rascunho só download → T4; persistência em `calculos.snapshot` via `RegistraCalculo` → T5/T8; tempo de resposta (rack-timeout conferido, job) → decisões + T4/T5/T8; §6.5 "aguardando aprovação dos textos" → T8; §3 anti-meta "número diferente" → trava da T4 e edição só de string na T6; §8 aprovação para deploy → T9.
- **Tipos consistentes:** `payload(cnis, perfil, segurado_nome:, data_calculo:)`, `nomes(dados, hoje:)`, `arquivo(calculo, tipo)`, `gerar!`, `snapshot['geracao']` (`estado`/`erro`/`drive`/`drive_motivo`/`drive_erro`), `camposEditaveis`/`definirTexto`/`SECOES_EDITAVEIS`, `planejamentoGerar`/`planejamentoGeracao`/`planejamentoArquivo` são usados com os mesmos nomes nas tasks seguintes.
- **Riscos que ficam:** tempo real do Chromium na VPS ainda não medido (o motor novo não está no ar); `permit(dados: {})` com arrays aninhados verificado pelo spec da T5 (com alternativa escrita); `cnis_data` = data do upload é aproximação; linhas antigas de `planejamento` no histórico reabrem em branco.

# Transcrição de áudio (Whisper) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Todo áudio inbound do cliente vira texto automaticamente, transcrito por um container `faster-whisper` grátis na própria VPS, reusando o pipeline de transcrição que o fork já tem.

**Architecture:** O fork (Enterprise overlay do Chatwoot) já dispara transcrição em todo anexo de áudio (`after_create_commit` → `Messages::AudioTranscriptionJob` → `Messages::AudioTranscriptionService`), hoje travado atrás do Captain (AI pago). O plano (1) sobe um container `whisper` compatível-OpenAI no compose, (2) destrava o service e o aponta pro container via `InstallationConfig` reusadas, (3) faz a triagem enxergar o texto transcrito.

**Tech Stack:** Rails 7 / Sidekiq / `ruby-openai` gem (já usada pela EE) / `speaches` (faster-whisper, container CPU, MIT) / Docker Compose.

## Global Constraints

- **Deploy em produção só com OK explícito do Eduardo** (Task 4 é gated).
- **Sem ambiente de teste local confiável (Windows)** → quem valida specs é **PR + CI**. Não mergear com CI vermelho. Comandos `rspec` abaixo rodam local só se houver ambiente; senão o CI é o validador.
- **Migração:** nenhuma (usa a coluna `attachment.meta` jsonb já existente).
- **Enterprise:** edições in-place em `enterprise/` são aceitáveis (é nosso fork, não rebaseia upstream v4.15.1); marcar com comentário `# ramon:`.
- **Rubocop:** 150 col max; `ENV.fetch`; `increment!`/`update_all` exigem disable inline de `Rails/SkipsModelValidations`.
- **Commits:** Conventional Commits; não referenciar Claude na mensagem.
- **Modelo padrão:** `Systran/faster-whisper-medium` (calibrável sem redeploy via `InstallationConfig CAPTAIN_OPEN_AI_MODEL`).

---

### Task 1: Container `whisper` no compose de produção

**Files:**
- Modify: `docker-compose.production.yaml` (adiciona serviço `whisper` + volume)

**Interfaces:**
- Produces: serviço de rede `whisper` alcançável em `http://whisper:8000/` pelos serviços `rails`/`sidekiq`; endpoint compatível-OpenAI `POST /v1/audio/transcriptions`.

- [ ] **Step 1: Adicionar o serviço `whisper` e o volume**

Em `docker-compose.production.yaml`, adicionar o serviço abaixo dentro de `services:` (após `redis:`, antes de `volumes:`):

```yaml
  whisper:
    image: ghcr.io/speaches-ai/speaches:latest-cpu
    restart: always
    environment:
      # cache dos modelos baixados fica no volume (não rebaixa a cada restart)
      - HF_HOME=/data
      # mantém o modelo carregado em memória (sem descarregar por inatividade)
      - WHISPER__TTL=-1
    volumes:
      - whisper_data:/data
    # sem `ports:` — uso interno da rede do compose (rails/sidekiq acham por hostname)
```

E adicionar o volume no bloco `volumes:` no fim do arquivo:

```yaml
volumes:
  storage_data:
  postgres_data:
  redis_data:
  whisper_data:
```

- [ ] **Step 2: Validar o YAML**

Run: `docker compose -f docker-compose.production.yaml config -q`
Expected: sem saída e exit 0 (YAML válido). Se `docker` não estiver disponível localmente, validar o YAML mentalmente/na VPS no deploy (Task 4).

- [ ] **Step 3: Commit**

```bash
git add docker-compose.production.yaml
git commit -m "feat(whisper): adiciona container faster-whisper ao compose de producao"
```

---

### Task 2: Destravar e apontar o `AudioTranscriptionService` pro whisper

**Files:**
- Modify: `enterprise/app/services/messages/audio_transcription_service.rb`
- Test: `spec/enterprise/services/messages/audio_transcription_service_spec.rb`

**Interfaces:**
- Consumes: `Llm::LegacyBaseOpenAiService` (base) — expõe `@client` (OpenAI::Client com `uri_base` de `InstallationConfig CAPTAIN_OPEN_AI_ENDPOINT`) e `@model` (de `InstallationConfig CAPTAIN_OPEN_AI_MODEL`). `account.audio_transcriptions` (boolean, coluna existente).
- Produces: grava `attachment.meta['transcribed_text']`; `perform` retorna `{ success: true, transcriptions: <texto> }` quando `account.audio_transcriptions` está ligado.

- [ ] **Step 1: Atualizar o spec pro novo comportamento (sem Captain)**

Em `spec/enterprise/services/messages/audio_transcription_service_spec.rb`:

(a) **Remover** o contexto que espera erro quando o Captain está desligado (não vale mais — a transcrição não depende do Captain):

```ruby
    context 'when captain_integration feature is not enabled' do
      before do
        account.disable_features!('captain_integration')
      end

      it 'returns transcription limit exceeded' do
        expect(service.perform).to eq({ error: 'Transcription limit exceeded' })
      end
    end
```

(b) No bloco `before` do topo, o mock de `usage_limits` deixa de ser necessário — trocar o `before` por:

```ruby
  before do
    # Configs reusadas pelo base service (uri_base/key/model apontam pro container whisper)
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_API_KEY') { |config| config.value = 'test-api-key' }
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_MODEL') { |config| config.value = 'Systran/faster-whisper-medium' }
  end
```

O contexto `'when audio transcriptions are disabled'` (que faz `account.update!(audio_transcriptions: false)` e espera erro) **permanece** — continua sendo o interruptor válido.

- [ ] **Step 2: Rodar o spec pra ver o vermelho esperado**

Run: `bundle exec rspec spec/enterprise/services/messages/audio_transcription_service_spec.rb`
Expected: o contexto `'when audio transcriptions are disabled'` FALHA (o código ainda barra por `captain_integration`, mas o objetivo é passar a barrar só por `audio_transcriptions`). (Local se disponível; senão o CI valida no PR.)

- [ ] **Step 3: Destravar o gate, usar o modelo da config e remover o consumo de cota**

Em `enterprise/app/services/messages/audio_transcription_service.rb`:

(a) **Remover** a constante hardcoded (linha 4):

```ruby
  TRANSCRIPTION_MODEL = 'gpt-4o-mini-transcribe'.freeze
```

(b) Trocar o método `can_transcribe?` inteiro por:

```ruby
  # ramon: transcrição roda no nosso faster-whisper local (grátis), sem Captain/cota.
  # Interruptor por conta = account.audio_transcriptions.
  def can_transcribe?
    account.audio_transcriptions
  end
```

(c) Em `transcribe_audio`, trocar `model: TRANSCRIPTION_MODEL` por `model: @model` (o `@model` do base lê `CAPTAIN_OPEN_AI_MODEL`):

```ruby
        response = @client.audio.transcribe(
          parameters: {
            model: @model,
            file: file,
            temperature: 0.0
          }
        )
```

(d) Em `instrumentation_params`, trocar `model: TRANSCRIPTION_MODEL` por `model: @model`:

```ruby
  def instrumentation_params(file_path)
    {
      span_name: 'llm.messages.audio_transcription',
      model: @model,
      account_id: account&.id,
      feature_name: 'audio_transcription',
      file_path: file_path
    }
  end
```

(e) Em `update_transcription`, **remover** a linha que consome cota Captain:

```ruby
    message.account.increment_response_usage
```

- [ ] **Step 4: Rodar o spec pra ver o verde**

Run: `bundle exec rspec spec/enterprise/services/messages/audio_transcription_service_spec.rb`
Expected: PASS (todos os contextos). (Local se disponível; senão CI.)

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/messages/audio_transcription_service.rb spec/enterprise/services/messages/audio_transcription_service_spec.rb
git commit -m "feat(whisper): transcreve audio via faster-whisper local sem depender do Captain"
```

---

### Task 3: Triagem enxerga o áudio transcrito

**Files:**
- Modify: `app/services/leads/triage_service.rb:72-82` (método `conversation_transcript`)
- Test: `spec/services/leads/triage_service_spec.rb`

**Interfaces:**
- Consumes: `Message#content_for_llm` (já existe em `app/models/message.rb:273`) — retorna `content`, senão `"[Voice Message] #{transcribed_text}"`, senão `"[Attachment]"`.
- Produces: `source_text` da triagem passa a incluir a transcrição de mensagens só-de-áudio.

- [ ] **Step 1: Escrever o teste que falha**

Adicionar em `spec/services/leads/triage_service_spec.rb`, antes do `end` final do `describe`:

```ruby
  it 'inclui a transcrição de mensagem só de áudio no texto-fonte' do
    audio_msg = create(:message, account: account, conversation: conversation,
                                 message_type: :incoming, content: nil)
    audio_msg.attachments.create!(account: account, file_type: :audio,
                                  meta: { transcribed_text: 'recebi a carta do INSS ontem' })
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('VIABILIDADE: alta'))
    described_class.new(triage).perform
    expect(triage.reload.source_text).to include('recebi a carta do INSS ontem')
  end
```

(Se a factory `:message` recusar `content: nil`, criar sem a chave e limpar depois: `audio_msg.update_column(:content, nil)` antes do `attachments.create!`.)

- [ ] **Step 2: Rodar o teste pra ver o vermelho**

Run: `bundle exec rspec spec/services/leads/triage_service_spec.rb -e "mensagem só de áudio"`
Expected: FAIL — `source_text` não inclui a transcrição (a mensagem de áudio, com `content` nil, é descartada pelo `where.not(content: [nil, ''])`). (Local se disponível; senão CI.)

- [ ] **Step 3: Reescrever `conversation_transcript` pra usar `content_for_llm`**

Substituir o método `conversation_transcript` inteiro (linhas 72-82) por:

```ruby
  def conversation_transcript
    conversation = @lead.conversation
    return nil if conversation.blank?

    messages = conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
                           .order(:created_at).last(MAX_MESSAGES)
    lines = messages.filter_map do |m|
      text = m.content_for_llm
      next if text.blank?

      "#{m.incoming? ? 'Cliente' : 'Atendimento'}: #{text}"
    end
    return nil if lines.empty?

    "Conversa (WhatsApp/chat):\n#{lines.join("\n")}"
  end
```

(Saiu o filtro `where.not(content: [nil, ''])` e o `return nil if messages.empty?`; a exclusão de mensagens vazias agora é por `content_for_llm.blank?` no Ruby, o que deixa passar áudio transcrito. Mensagens `private` seguem excluídas pelo `where`.)

- [ ] **Step 4: Rodar os testes da triagem (novo + regressão)**

Run: `bundle exec rspec spec/services/leads/triage_service_spec.rb`
Expected: PASS em todos — o novo teste passa e os existentes (texto público entra, `private` não, pseudonimização, sem-conversa) continuam verdes. (Local se disponível; senão CI.)

- [ ] **Step 5: Commit**

```bash
git add app/services/leads/triage_service.rb spec/services/leads/triage_service_spec.rb
git commit -m "feat(whisper): triagem inclui audio transcrito via content_for_llm"
```

---

### Task 4: Deploy e configuração (⚠️ GATED — só com OK do Eduardo)

**Não é código.** Executar na VPS após o PR mergear com CI verde. Comandos via `ssh root@185.194.216.67`, `cd /opt/intranet-ramon`.

- [ ] **Step 1: Subir o container whisper e pré-aquecer o modelo**

```bash
# na VPS, dentro de /opt/intranet-ramon (compose = docker-compose.yml da VPS)
docker compose pull whisper
docker compose up -d whisper
# pré-baixa o modelo medium (1ª request baixa ~1.5 GB; pode levar 1-2 min)
docker compose exec rails curl -s -X POST http://whisper:8000/v1/audio/transcriptions \
  -F model=Systran/faster-whisper-medium \
  -F file=@/app/public/audio/api/samples/male.wav | head -c 300
```
Expected: JSON com `text` transcrito (prova que o container responde e o modelo carregou).

- [ ] **Step 2: Setar as InstallationConfigs apontando pro whisper**

```bash
docker compose exec -T rails bundle exec rails runner - <<'RUBY'
{
  'CAPTAIN_OPEN_AI_ENDPOINT' => 'http://whisper:8000/',
  'CAPTAIN_OPEN_AI_API_KEY'  => 'local-whisper',
  'CAPTAIN_OPEN_AI_MODEL'    => 'Systran/faster-whisper-medium'
}.each do |name, value|
  InstallationConfig.find_or_initialize_by(name: name).update!(value: value)
end
puts 'configs ok'
RUBY
```
Expected: `configs ok`.

- [ ] **Step 3: Ligar o interruptor de transcrição na conta da banca (id 2)**

```bash
docker compose exec -T rails bundle exec rails runner \
  "a = Account.find(2); a.update!(audio_transcriptions: true); puts a.audio_transcriptions"
```
Expected: `true`.

- [ ] **Step 4: Deploy da imagem nova do código (rails + sidekiq)**

Seguir o procedimento padrão do fork: `docker pull ghcr.io/doods-maker/ramon-hub:sha-<7>` → `docker tag ... :v4.15.1-ramon` → `docker compose up -d --no-build rails sidekiq`. (Sem migração.)

- [ ] **Step 5: Smoke técnico**

```bash
docker compose exec -T rails bundle exec rails runner \
  "puts Account.find(2).audio_transcriptions; puts InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT').value"
```
Expected: `true` e `http://whisper:8000/`.

- [ ] **Step 6: Smoke visual (Eduardo)**

Mandar um áudio real de um número de teste pra um inbox de WhatsApp → esperar alguns segundos → ver o texto transcrito abaixo do player na conversa → rodar a triagem naquele lead → conferir que o dossiê citou o conteúdo do áudio.

---

## Notas de execução

- **Worktree:** criar via `superpowers:using-git-worktrees` a partir de `ramon`; branch `feat/ramon-whisper-audio`. A spec (`docs/superpowers/specs/2026-07-07-whisper-transcricao-audio-design.md`) entra no 1º commit da branch.
- **schema.rb:** não muda (sem migração) — pular o procedimento de scratch DB.
- **CI:** validar via check-runs do commit exato (N/N completed, zero não-success), não por lista truncada.
- **Imagem speaches:** se `ghcr.io/speaches-ai/speaches:latest-cpu` não expuser `/v1/audio/transcriptions` como esperado no pré-aquecimento (Step 1 da Task 4), o fallback é `fedirz/faster-whisper-server:latest-cpu` (mesma API OpenAI, mesma porta 8000) — trocar só a `image:` na Task 1.

# Transcrição de áudio (Whisper) no ramon-hub — Design

**Data:** 2026-07-07
**Autor:** Eduardo + Claude
**Contexto:** Onda 0 do plano "Organismo" (`2026-07-05-plano-sem-freios.md`) —
Whisper nos áudios. Público 50+ manda voz; a triagem hoje é cega a áudio.

## Objetivo

Todo áudio que o cliente manda no WhatsApp vira texto automaticamente,
transcrito por um container `faster-whisper` **grátis rodando na própria VPS**,
reusando o pipeline de transcrição que o fork já tem (camada Enterprise).

- **Grátis:** `faster-whisper` é MIT, sem API, roda offline. Zero custo de
  licença e zero por minuto.
- **LGPD:** o áudio do cliente **não sai da VPS** (mais seguro que a triagem de
  texto, que manda pseudonimizado pro DeepSeek).
- **VPS aguenta:** 4 vCPU / 7.8 GB RAM (5.9 livre) / 119 GB disco livre, load
  ocioso. Áudio de WhatsApp é curto → transcrição em segundos num job async.

## Decisões de produto (fechadas com o Eduardo)

1. **Gatilho:** todo áudio **inbound** (cliente→banca), em qualquer conversa.
   Áudio outbound (da banca) não é transcrito.
2. **Visibilidade:** só interna — o texto aparece pra equipe abaixo do player
   (comportamento nativo EE) e alimenta a triagem. Cliente nunca vê.
3. **Modelo:** padrão `faster-whisper-medium` — o público (50+, interior de SC,
   áudio ruidoso, fala corrida) é o cenário onde o `small` erra e o `medium`
   compensa; a VPS aguenta e o custo é só alguns segundos a mais num job async.
   `small` fica como plano B (via env) se a fila de áudios crescer e for preciso
   aliviar CPU.

## Descoberta central

O fork **já tem o pipeline de transcrição inteiro** (herdado da camada
Enterprise do Chatwoot), hoje travado atrás do Captain (o AI pago). Não se
constrói do zero — aponta-se o que existe pro container grátis.

Ganchos que já existem:
- `enterprise/app/models/enterprise/concerns/attachment.rb` — `after_create_commit
  :enqueue_audio_transcription` → dispara `Messages::AudioTranscriptionJob` para
  todo anexo `file_type: :audio`.
- `enterprise/app/jobs/messages/audio_transcription_job.rb` — `queue_as :low`,
  `retry_on ActiveStorage::FileNotFoundError`, `discard_on Faraday::BadRequestError`.
- `enterprise/app/services/messages/audio_transcription_service.rb` — baixa o
  blob, chama endpoint **compatível-OpenAI** (`/v1/audio/transcriptions`), grava
  em `attachment.meta['transcribed_text']`.
- `app/models/attachment.rb` — coluna `meta :jsonb`; `audio_metadata` expõe
  `transcribed_text`.
- `app/models/message.rb:273` — `content_for_llm` retorna `content` ou
  `"[Voice Message] #{transcribed_text}"`.

## Componentes (4)

### 1. Container `whisper` no `docker-compose.production.yaml`

Serviço novo (imagem CPU do `speaches`/`faster-whisper-server`, expõe
`/v1/audio/transcriptions` no formato OpenAI).

- Modelo via env `WHISPER_MODEL` (default `Systran/faster-whisper-medium`) — a
  **calibração** fica no env: trocar pra `small` (aliviar CPU) ou `large` sem
  redeploy de código.
- Volume nomeado pra cachear o modelo baixado (não rebaixar a cada restart).
- Alcançável pelo `sidekiq` (que roda o job) como `http://whisper:8000`.
- Sem porta publicada pra fora (uso interno da rede do compose).

### 2. `AudioTranscriptionService` — edição mínima

Arquivo `enterprise/app/services/messages/audio_transcription_service.rb`
(já é do nosso fork; o fork não rebaseia upstream v4.15.1, então edição
in-place é o menor diff honesto — marcada com comentário `# ramon:`).

- **Endpoint via config reusada:** o base service (`Llm::LegacyBaseOpenAiService`)
  já lê `uri_base`, a API key (`find_by!`) e o modelo de três `InstallationConfig`
  no banco (`CAPTAIN_OPEN_AI_ENDPOINT` / `_API_KEY` / `_MODEL`). Reusamos essas
  configs apontando pro container — **zero código no base service**. O Eduardo não
  usa Captain (adiado de propósito), então não há colisão real; bônus: dá pra
  trocar o modelo pela UI Super Admin sem redeploy. (Isolar em envs `WHISPER_*`
  exigiria sobrescrever `uri_base`+key+model — mais diff, sem ganho aqui.)
- **Modelo:** `TRANSCRIPTION_MODEL` (hoje hardcoded `gpt-4o-mini-transcribe`)
  passa a usar o `@model` do base (que lê `CAPTAIN_OPEN_AI_MODEL`).
- **Destrava o gate:** `can_transcribe?` deixa de exigir `captain_integration` /
  cota Captain; vira `account.audio_transcriptions` (interruptor liga/desliga por
  conta, coluna que já existe). O guard de tamanho `audio_too_large?` (25 MB) fica.
- **Sem cota:** remove `message.account.increment_response_usage` do
  `update_transcription` (não há cota Captain a consumir; `usage_limits[:captain]`
  pode nem existir).

### 3. Triagem enxerga o áudio — `app/services/leads/triage_service.rb`

No `conversation_transcript`:
- Troca `m.content` → `m.content_for_llm` (monta `"[Voice Message] <texto>"`).
- Solta o filtro `where.not(content: [nil, ''])` que hoje descarta a mensagem
  só-de-áudio (content nulo) antes do `map`.

A pseudonimização LGPD (`Ramon::Pseudonymizer.mask`) segue aplicada por cima —
o texto transcrito passa pelo mesmo mascaramento antes de ir ao LLM.

### 4. UI — nativa, zero código

A transcrição aparece abaixo do player (feature EE já renderiza
`transcribed_text` via `audio_metadata` / componentes `components-next/message`).
Confirmação só no smoke visual.

## Fluxo de dados

```
Cliente manda áudio (WhatsApp)
  → Chatwoot cria Message + Attachment(file_type: audio)
  → after_create_commit  (EE, já existe)  enfileira AudioTranscriptionJob (queue :low)
  → Service baixa o blob do ActiveStorage
  → POST multipart → http://whisper:8000/v1/audio/transcriptions
  → resposta { text }
  → grava attachment.meta['transcribed_text']
  → message.send_update_event  → UI atualiza em tempo real (texto sob o player)
  → na triagem: content_for_llm inclui o texto → source_text → (pseudonimiza) → LLM
```

## Erros (já cobertos pelo pipeline EE)

| Situação | Comportamento |
|---|---|
| Container fora do ar | `Faraday::ConnectionFailed` → `retry_on` (3×). Persistindo, o áudio só fica sem transcrição; a conversa não quebra. |
| Áudio > 25 MB | Pulado (`audio_too_large?`), anexo mantido. |
| Silêncio / near-silent | `temperature: 0.0` já minimiza alucinação (repetições em loop). |
| 401 do endpoint | Já tratado (`rescue Faraday::UnauthorizedError`) — loga e segue. |

## Teste

Sem ambiente local; quem valida é o CI (regra do fork). Deixar **1 spec** na
mudança da triagem (money-path, filtro sutil): uma mensagem **só de áudio** com
`transcribed_text` no anexo deve entrar no `source_text` da triagem (hoje seria
descartada). Sem specs adicionais além desse (regra do fork: evitar specs não
pedidos; este é o único ponto de lógica não-trivial nova).

## Fora de escopo (YAGNI)

- Transcrever áudio outbound (da banca).
- UI nova (a nativa já mostra).
- Listener Ramon novo (o gancho `after_create_commit` EE já dispara).
- Tocar no `Ramon::LlmClient` (é texto, não áudio).
- Cópia externa / fila dedicada de transcrição.

## Deploy

- **Sem migração** (usa coluna `meta` já existente).
- 3 `InstallationConfig` na VPS (via `rails runner`): `CAPTAIN_OPEN_AI_ENDPOINT=
  http://whisper:8000/`, `CAPTAIN_OPEN_AI_API_KEY=<dummy>`, `CAPTAIN_OPEN_AI_MODEL=
  Systran/faster-whisper-medium`. Ligar o interruptor na conta: `Account.find(2)
  .update!(audio_transcriptions: true)`.
- `docker compose up -d whisper` (baixa a imagem + modelo na 1ª vez) +
  restart de `sidekiq` e `rails`.
- Smoke técnico: container `whisper` responde; áudio de teste inbound gera
  `transcribed_text`. Smoke visual do Eduardo: mandar áudio real → ver o texto
  sob o player → rodar triagem → conferir que o dossiê citou o conteúdo do áudio.

# Área "Reuniões" — gravação, transcrição e ata (design)

**Data:** 2026-07-28 · **Aprovado por:** Eduardo (conversa 28/07)

## Objetivo

Uma tela no hub pra o Dr. Ramon gravar reuniões **presenciais** pelo navegador
e receber, minutos depois, a **ata completa** (resumo + decisões + pendências
com responsável) gerada por IA, com a transcrição bruta disponível embaixo.
Inspiração: meetily (Zackriya) — mas sem instalar nada: o hub já tem o
faster-whisper na VPS e o DeepSeek configurado; falta só a tela e a costura.

## Decisões do Eduardo (28/07)

- **Presencial only** — microfone do navegador; reunião online (Meet/Zoom) fora.
- **Área "Reuniões" separada** — não amarrada a lead/conversa (reunião pode ser
  interna, do jurídico, etc.). Vincular a lead = fatia futura.
- **Ata completa** — resumo + decisões + pendências/ações com responsável.
- **Acesso: todos os agentes da conta** veem a área e todas as gravações.
- Consentimento de gravação: já descartado por ele em 15/07 ("não usaremos") —
  sem fluxo de consentimento.

## Arquitetura

Tudo dentro do fork, reuso máximo:

```
Tela Vue (MediaRecorder) ──POST multipart──▶ ramon_reunioes (ActiveStorage → R2)
                                                   │ status: transcrevendo
                                             Ramon::ReuniaoAtaJob
                                                   │
                          faster-whisper (RAMON_WHISPER_ENDPOINT, já na VPS)
                                                   │ transcrição
                          DeepSeek via Ramon::LlmClient (chat, SEM json_schema)
                                                   │ ata em markdown
                                             status: pronta
```

### Modelo e migração

Tabela `ramon_reunioes`:

| campo | tipo | nota |
|---|---|---|
| account_id | bigint, FK, index | conta 2 na prática |
| user_id | bigint, FK | quem gravou |
| titulo | string | opcional; default "Reunião de DD/MM HH:MM" |
| duracao_segundos | integer | medido no front |
| status | string | `transcrevendo` → `pronta` \| `erro` |
| erro | string | motivo legível quando status=erro |
| transcricao | text | bruta do whisper |
| ata | text | markdown do DeepSeek |
| timestamps | | |

`has_one_attached :audio` (ActiveStorage já aponta pro R2).

### Backend

- `Api::V1::Accounts::RamonReunioesController` — `index`, `show`, `create`
  (multipart: audio + titulo + duracao_segundos; valida content_type de áudio e
  tamanho ≤ 25 MB — limite do endpoint whisper, ver §Gravação), `destroy`
  (apagar gravação errada), `reprocessar` (re-enfileira o job quando status=erro).
- `Ramon::ReuniaoAtaJob` (fila low): baixa o blob pra tmp → POST no whisper
  (client OpenAI igual ao `Messages::AudioTranscriptionService`, **mesmos envs**
  `RAMON_WHISPER_ENDPOINT`/`RAMON_WHISPER_MODEL` e defaults; serviço próprio
  `Ramon::ReuniaoTranscricaoService`, o de mensagens NÃO é tocado) → prompt de
  ata no DeepSeek via `Ramon::LlmClient` (texto íntegro — deepseek está na
  `RAMON_LLM_SENSITIVE_OK_PROVIDERS`, decisão de 20/07) → grava transcrição +
  ata + status. Falha em qualquer etapa: status=erro + motivo; retry do usuário
  pelo botão Reprocessar (transcrição já feita é reaproveitada).
- Prompt da ata (pt-BR): resumo (1 parágrafo), decisões tomadas (lista),
  pendências/ações com responsável e prazo quando citados. Saída = markdown
  puro. **Sem `response_format`/json_schema** — DeepSeek recusa (lição PR #110).

### Frontend

- Item **"Reuniões"** no menu da Intranet (todos os agentes) → rota
  `ramon/reunioes`.
- **Lista:** título, data, quem gravou, duração, status; botão "Nova reunião";
  linha abre o show.
- **Gravação:** `MediaRecorder` (nativo, zero dependência), webm/opus com
  `audioBitsPerSecond: 32000` — voz fica boa e 1h ≈ 15 MB (teto do whisper é
  25 MB ⇒ ~1h40 de reunião; passou disso, erro claro no upload). Timer, pausar/
  continuar, encerrar. Chunks acumulados em memória via `timeslice`; ao
  encerrar, upload único com barra de progresso. Guard `beforeunload` enquanto
  grava.
- **Show:** ata renderizada (markdown), player do áudio, transcrição bruta em
  accordion recolhido, botão Reprocessar quando erro. Enquanto
  status=transcrevendo, **polling leve (10 s)** — sem canal ActionCable novo.

### Testes

RSpec: model, request specs do controller (upload, limites, reprocessar),
job com WebMock (whisper + DeepSeek). Vitest: componente de gravação com
MediaRecorder mockado. CI valida (sem ambiente local).

## Riscos aceitos / fora da v1

- Navegador fechar no meio da gravação perde o áudio (recuperação de crash =
  fatia futura; `beforeunload` avisa).
- Sem diarização ("quem disse o quê") — o faster-whisper atual não separa vozes.
- Sem vínculo com lead/colheita, sem edição de ata, sem expurgo automático,
  sem reunião online.

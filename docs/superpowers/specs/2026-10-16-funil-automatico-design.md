# Funil automático (o kanban se move sozinho, em qualquer modo) — desenho

Data: 16/10/2026 · Pedido do Eduardo · Status: rascunho para aprovação · Vem **antes** de
`2026-10-16-meta-conversoes-funil-design.md`

## Por quê

O time comercial (1 SDR + 1 Closer) começa em 16/11. Hoje mover o card, marcar a reunião, preencher os dados do caso e
fechar o lead perdido são trabalho manual. O Eduardo quer tirar esse trabalho de SDR e Closer para eles focarem em
conversar e fechar.

Hoje a IA só mexe na etapa quando é ela quem atende. O roteiro da tese (`Ramon::Roteiro::Efeitos.mover`) move direto só
nos modos `piloto_total` e "sozinha até…". Nos outros modos ele vira sugestão no Cockpit. No **atendimento manual** nada
da IA lê a conversa. Prova em produção em 16/10: zero eventos do roteiro e zero sugestões em 14 dias.

Este projeto também alimenta o rastreamento da Meta: cada etapa que anda sozinha vira um evento de conversão.

## O que é

O hub mantém o funil em dia sozinho, **em qualquer modo de atendimento** (manual, rascunho, piloto), por dois caminhos.

### 1. Pelo que foi feito (regra fixa, sem IA, na hora)

| Acontecimento | Efeito | Hoje |
|---|---|---|
| Reunião marcada (painel, Cal.com ou pela IA, ver abaixo) | → Reunião agendada | já existe (`Ramon::ReuniaoAgendamento`) |
| Reunião registrada pelo Closer | → Reunião realizada | já existe (`LeadComercial#registrar_reuniao!`) |
| Contrato criado no ZapSign (link de assinatura gerado) | → Negociação | **novo** *(palpite meu, confirmar na leitura)* |
| Contrato **assinado** no ZapSign | → **Ganho** (etapa `is_won`), com a cascata de sempre: ADVBOX, Drive, NPS | **novo. Revoga a regra de 08/10** ("ZapSign nunca marca ganho", em `Ramon::ZapsignLeadStatusJob`), por decisão do Eduardo em 16/10 |

### 2. Pelo que foi conversado (o observador)

Quando a conversa de um lead aberto **fica uns 10 minutos sem mensagem nova**, uma rotina lê o trecho novo, a ficha e a
etapa atual, e decide:

- **Etapa:** move para a frente quando a conversa mostra que o lead avançou. Ex.: respondeu as perguntas de triagem e
  cabe na tese → Qualificação.
- **Reunião:** se SDR e cliente combinaram **dia e hora exatos**, a IA marca a reunião. Antes, confere na agenda do
  Cal.com se o horário está livre e **bloqueia esse horário** (decisão do Eduardo). O resto sai pelo caminho de sempre:
  tarefa, lembretes, etapa, Closer automático e rascunho de confirmação. Horário ocupado ou vago ("quinta à tarde") →
  não marca, e deixa a anotação no card.
- **Colheita:** preenche os dados do caso (CPF, datas, campos da tese) com a extração que já existe
  (`Ramon::ColheitaExtractionService`). Ela foi tirada do automático em 20/07 por custo (re-extração a cada mensagem);
  rodar só na pausa resolve isso.
- **Perdido com motivo:** quando o cliente **recusa claramente**. Por sumiço também: lead que **venceu o prazo de parado
  da etapa "Última chance"** (`stalled_after_days` dela, `Ramon::Cadencia`) vai para Perdido com motivo
  "Sem resposta". Isso é uma regra de tempo e não precisa da IA (decisão do Eduardo).

### 3. Extras aprovados pelo Eduardo (16/10)

- **Promessas viram tarefa.** O observador detecta uma promessa com data na conversa ("te mando o laudo amanhã",
  "falo com minha esposa e te retorno sexta") e cria uma tarefa de cobrança para o SDR do lead, com prazo nessa data.
  Se a promessa é um documento e ele chega antes (o casamento anexo↔item, `Ramon::DocMatchService`, já existe), a tarefa
  fecha sozinha. Data vaga ("semana que vem") → o prazo é o 1º dia útil citado *(decisão minha)*.
- **Pendência de documento no card.** Os documentos que o cliente ficou de mandar aparecem no card como
  "Aguardando: laudo, CNIS" e somem quando chegam. Isso complementa o contador de docs X/Y que já existe (`docs_total`).
  A tabela "Pendências de documentos — Leads" do Notion **continua** até o Eduardo conferir no hub; aposentar a tabela e
  mudar a skill `organizar-documentos-cliente` é um passo à parte *(decisão minha)*.
- **No-show automático.** A hora da reunião passou e, em 2h, ninguém registrou realizada nem falta → aviso no sino do
  Closer do lead e rascunho de remarcação nas notas, que uma pessoa envia. **Não marca a falta sozinho**: a falta entra
  na taxa de comparecimento do painel do SDR (`meeting_no_show`), então quem marca é o Closer *(decisão minha)*.
- **Fila do dia com temperatura.** O observador dá ao lead uma temperatura (quente, morno, frio) com uma frase de
  motivo, regravada a cada pausa da conversa. O SDR ganha a vista "fale primeiro com estes": leads abertos ordenados por
  temperatura e, em segundo lugar, por tempo sem resposta. A forma (filtro do kanban ou tela própria) fica com o builder.
- **Reativação de perdidos.** Lead que foi para Perdido com "Sumiu / não respondeu" ganha, aos 30 e aos 60 dias, um
  rascunho de retomada nas notas, mais uma tarefa para o SDR. Nada é enviado sozinho. Recusa clara não reativa.

## Travas (valem para tudo acima)

- **Nunca volta etapa.** Só para a frente, como `Efeitos.mover` e `advance_stage` já fazem.
- **A IA nunca marca Ganho.** O Ganho só vem da assinatura no ZapSign.
- **Nada vai ao cliente por aqui.** O rascunho de confirmação continua sendo enviado por uma pessoa. A agenda **não pode
  disparar e-mail ou SMS do Cal.com para o cliente** (anti-meta).
- **Desfazer em 1 clique** no card para cada ação da IA: volta a etapa, cancela a reunião que a IA marcou, reabre o
  Perdido. Depois de um desfazer, o observador **não refaz a mesma ação** com base nas mesmas mensagens; só uma conversa
  nova pode levar a ela de novo.
- **Rastro:** cada ação vira atividade no histórico do lead, com **o motivo em uma frase** e a marca de que foi a IA.
- Só leads abertos, ligados a uma conversa. Ganho e Perdido o observador não lê.
- Convive com o roteiro da tese: se o roteiro já moveu, o observador vê a etapa atual e só segue para a frente.
- Sem dado sensível em log (padrão do hub, ex.: `advbox_mcp` só loga nomes de campo).

## Como a equipe fica sabendo

**No resumo das 8h, só para os administradores** (decisão do Eduardo): uma seção "O que a IA mexeu ontem", com o lead, a
ação, o motivo e o link. Entra no resumo que já existe (`Ramon::DailyDigestService` / `DailyDigestJob`). Durante o dia
aparece só no card e no histórico, sem sino. A exceção é o no-show, que avisa o Closer na hora.

## Ligar com segurança

- **Cada peça tem chave própria:** etapa, reunião, colheita, perdido por recusa, perdido por sumiço, ganho pelo ZapSign,
  Negociação pelo ZapSign, Negociação → Última chance por tempo, promessas, pendências, no-show, temperatura e
  reativação. O deploy sobe **desligado**.
- **Ensaio primeiro** *(decisão minha)*: as peças da IA ligam primeiro em modo ensaio. Elas registram "faria: …" sem
  mexer, como o `ensaio?` dos fluxos. O Eduardo confere uns dias no resumo e depois liga de verdade. As regras fixas
  (ZapSign, sumiço) podem ligar direto.
- **Ligar = ação do Eduardo**, com a regra do hub "texto/conduta que afeta cliente é gate dele". Aqui nada fala com o
  cliente, mas o Ganho dispara ADVBOX e NPS.
- **Custo:** um modelo barato pela escolha por função que já existe (`Ramon::LlmEscolha`), uma chamada por pausa e por
  conversa, sob o alerta de gasto que já existe (`Ramon::IaGastoAlerta`).

## Fora do escopo

- Rastreamento Meta (projeto seguinte, desenho próprio).
- Registrar a reunião como qualificada ou não pela ata: isso paga o SDR e segue humano.
- Mexer no roteiro da tese ou nos modos do copiloto.

## Smoke e entrega

Smoke em bloco por seção (regra do Eduardo), na caixa "WhatsApp Cloud (teste)": uma conversa manual que qualifica, combina
horário, recusa e some. Para cada caso, conferir o card, o histórico, o desfazer, a agenda e o resumo do dia. Entrega
registrada em doc de entrega no padrão do hub (regime de merge e deploy autônomos com CI verde).

## Respostas do Eduardo à revisão (16/10)

- **Etapas que o observador move lendo a conversa:** Novo → Qualificação, e → **Última chance** (depois da reunião, o
  cliente travou numa objeção: "vou pensar", preço, família). Mais nenhuma: as outras etapas têm regra própria.
- **Regra de tempo nova (sem IA):** Negociação parada além do `stalled_after_days` dela → Última chance. Somada ao
  Perdido por sumiço, fecha o ciclo Negociação → Última chance → Perdido "Sumiu / não respondeu".
- **Valor no Ganho pelo ZapSign:** usa o `value` estimado, sem tarefa e sem pedir confirmação. Vale só para o caminho
  automático; o kanban manual continua pedindo o clique.
- **Resumo:** uma seção "O que a IA mexeu ontem" no resumo das **8h** (`Ramon::DailyDigestService`), só para os
  administradores. Corrige o "fim do dia" escrito acima.
- **Agenda:** o Cal.com será aposentado e o hub vira a agenda do comercial, com Google Calendar
  (`2026-10-16-agenda-no-hub-design.md`). A ordem aprovada é funil automático → Agenda → Meta. Até a Agenda existir, a
  reunião
  que a IA marca **fica só no hub**: tarefa, lembretes, etapa e rascunho de confirmação, sem bloquear agenda e sem
  Cal.com. Bloquear o horário entra quando a Agenda no hub existir.

## Decisões da revisão do builder (16/10, minhas — conferir)

- **Motivos de perda do catálogo:** sumiço = "Sumiu / não respondeu", que já existe no seed. Na recusa, a IA escolhe entre
  os `LostReason` da conta; se nenhum servir, vale o "Automação: <origem>" de `motivo_da_perda_automatico`.
- **Perdido por recusa cala a IA**, igual ao roteiro (`Efeitos.perder`): etiqueta `desqualificado-ia` e conversa em manual.
- **Contrato assinado com o lead em Perdido → Ganho.** A assinatura vence tudo. O "nunca volta" não se aplica ao Ganho.
- **Contrato criado → Negociação** fica no escopo. Pular "Reunião realizada" não afeta o pagamento, que usa
  `reuniao_resultado` e `contrato_limpo_em`.
- **Colheita segue só para auxílio-acidente**, como o serviço é hoje (`THESIS_MATCH`). Estender para outras teses é outro
  pedido.
- **O debounce do observador mora em `app/`.** Não pode depender de `enterprise/` (`mensagem_superada?` mora lá e o CI de
  código aberto apaga essa pasta): mesmo padrão, código próprio.
- Só contratos gerados pelo painel do hub (`custom_attributes.zapsign.doc_token`) movem o lead. Contrato feito direto no
  ZapSign não move nada.

## Fica com o builder

Gatilho e debounce do observador (padrão `mensagem_superada?` do `ResponseBuilderJob` serve), se a colheita roda no mesmo
job, formato da saída da IA, onde guardar as chaves (env `RAMON_*` ou tela de Automações), como desfazer cada ação, a
integração de agenda (Cal.com API: conferir horário livre e criar a reserva; a reserva volta pelo webhook que já existe,
`calcom_webhooks_controller`, sem marcar duas vezes) e o texto das atividades.

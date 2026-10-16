# Agenda no hub (com Google Calendar) e aposentadoria do Cal.com — desenho

Data: 16/10/2026 · Pedido do Eduardo · Status: rascunho para aprovação · Ordem aprovada: funil automático
(`2026-10-16-funil-automatico-design.md`) → **esta** → rastreamento Meta (`2026-10-16-meta-conversoes-funil-design.md`)

## Por quê

O Eduardo mudou o panorama em 16/10: **o cliente não escolhe mais o horário num link**. Quem oferece as opções é a IA,
o SDR ou o Closer, e o hub precisa ser a agenda do comercial. Hoje a reunião vive no Cal.com, na agenda pessoal do
Eduardo (`cal.com/eduardo-schlata/primeiro-atendimento`). A IA manda esse link pela ferramenta `link_agendamento`, e o
hub só fica sabendo depois, pelo webhook. Com o time entrando em 16/11 e a IA marcando reuniões no funil automático,
o horário precisa ser conferido e bloqueado na hora, por dentro do hub.

## O que é

### Tela de Agenda

- Vistas de **dia e semana** com as reuniões de **todo o comercial**.
- **Filtro por pessoa:** uma, várias ou todas, com uma cor por pessoa.
- Clicar numa reunião abre o lead.
- Quem tem agenda: membros dos times nativos **`sdr`** e **`closer`** (`Ramon::Papeis`) e os administradores. Só o
  comercial, por decisão do Eduardo.
- Os compromissos pessoais do Google aparecem **com o título**, para todo o comercial (decisão do Eduardo).

### Google Calendar, nos dois sentidos

- Cada pessoa **conecta a própria conta Google** uma vez, no hub.
- Reunião marcada, remarcada ou cancelada no hub → criada, alterada ou cancelada no Google dela.
- O que existe no Google dela **ocupa o horário** no hub e aparece na tela.

### Quem oferece o horário

- **IA** (modos em que ela conversa): quando o lead topa a conversa, oferece **2 ou 3 horários livres** da agenda do
  Closer do lead. Se o lead ainda não tem Closer, usa o próximo pelo `Ramon::Papeis.proximo`. O lead escolhe e a IA marca.
  Isso substitui `link_agendamento`.
- **Observador do funil automático** (modo manual): quando SDR e cliente combinam dia e hora, ele marca. Agora ele
  também confere e bloqueia o horário.
- **SDR/Closer:** um botão **"sugerir horários"** na caixa de resposta põe 2 ou 3 horários livres no texto, para a
  pessoa editar e enviar.
- **Na hora de marcar, o horário é conferido de novo.** Se alguém pegou o horário no meio, não marca e avisa.

### Regras de horário

- Reunião de **30 min**, com **15 min de folga** depois (decisão do Eduardo).
- Só dentro do horário comercial que já está configurado (`Ramon::HorarioComercial`, seg–sex 8–18, fuso de São Paulo).
- Oferta nos próximos dias úteis, nunca com menos de 2h de antecedência *(decisão minha)*.

### Formato

- **Vídeo (Google Meet) por padrão:** o evento nasce com o link do Meet.
- **Ligação pelo WhatsApp** quando o cliente não consegue o vídeo: quem marca escolhe, ou troca depois, e o evento sai
  sem Meet e com "ligação pelo WhatsApp".

### O cliente fica sabendo

- **Pelo WhatsApp:** a confirmação traz o dia, a hora, o link do Meet e um link **"salvar na minha agenda"** (link de
  evento do Google + arquivo .ics). É o caminho principal, porque o cliente típico quase não lê e-mail.
- **Pelo e-mail, se o lead tiver:** ele entra como convidado do evento, e o Google manda o convite.
- **Textos:** a mensagem de confirmação e o título e a descrição do convite falam com o cliente, então são **gate do
  Eduardo**. O código sobe e os textos só ativam com o aprovado dele. Até lá, a confirmação continua sendo o rascunho
  nas notas que existe hoje.

### Ao marcar, continua tudo que já existe

`Ramon::ReuniaoAgendamento` segue sendo o ponto único: tarefa, lembretes (24h, 8h, 1h, 30 e 5 min), etapa "Reunião
agendada", Closer automático, rascunho de confirmação, sino e push, e os fluxos de reunião. A Agenda acrescenta o evento
no Google, a conferência de horário e o Meet.

## Cal.com aposentado

- Sai a ferramenta `link_agendamento` (`enterprise/lib/captain/tools/link_agendamento_tool.rb`) e a menção a ela nas
  `response_guidelines` do assistente (`db/seeds/ramon/inteligencia/assistentes.yml`). No lugar entram "horários livres"
  e "marcar reunião". **A troca de texto do assistente é gate do Eduardo.**
- Sai o webhook (`calcom_webhooks_controller`) com as envs `RAMON_CALCOM_URL` e `CALCOM_WEBHOOK_SECRET`, e saem as
  menções ao Cal.com nas fichas dos fluxos (ex.: `lembretes_reuniao.json`).
- **Virada** *(decisão minha)*: o webhook fica vivo até passar a última reunião já marcada no Cal.com, para remarcar ou
  cancelar ainda chegarem ao hub. Depois o código sai. O Eduardo desativa o link público do Cal.com no dia da virada.

## Fora do escopo

- Página pública em que o cliente escolhe o horário: o Eduardo descartou.
- Agenda do jurídico, do Dr. Ramon e das advogadas.
- Salas e recursos do escritório.

## Restrições e riscos

- **App do Google (OAuth):** um projeto no Google Cloud com a Calendar API e um cliente OAuth. Criar é ação do Eduardo,
  com o passo a passo da entrega.
  - O escopo de agenda é "sensível". Em modo **Teste**, o Google **expira o acesso em 7 dias**.
  - Fora do Teste e sem verificação, aparece uma tela de aviso, com limite de 100 usuários. Isso basta para o comercial.
  - Se a banca tiver Google Workspace no domínio, um app "interno" evita as duas coisas.
  - **Passo 0 do builder:** confirmar o caminho com uma conta real (conectar, ler o ocupado, criar evento com Meet) antes
    de construir o resto.
- **Tokens do Google** guardados cifrados (padrão de segredo do hub), nunca em log.
- **Convite ao cliente sai da conta Google do Closer.** O nome dele aparece como organizador.

## Smoke e entrega

Smoke em bloco por seção, regra do Eduardo:
1. Conectar o Google.
2. Agenda com filtro por pessoa.
3. IA oferece horários na caixa de teste.
4. "Sugerir horários" no manual.
5. Marcar, remarcar e cancelar, conferindo cada um no Google.
6. Ligação pelo WhatsApp em vez de Meet.
7. Horário pego no meio.

Doc de entrega no padrão do hub. O regime é merge e deploy autônomos com CI verde, e os textos ao cliente só ativam com o
aprovado.

## Respostas do Eduardo à revisão (16/10)

- **A IA marca conforme o modo:** marca direto (e bloqueia) no `piloto_total` e nos "sozinha até…". Nos modos rascunho e
  `piloto_limitado`, vira sugestão no Cockpit, como a etapa hoje.
- **Confirmação no WhatsApp:** com o texto aprovado, a IA envia sozinha nos modos piloto. No manual e no rascunho, fica
  como rascunho e uma pessoa envia.
- **Contas Google = Gmail pessoal.** O app OAuth é externo: sai do modo Teste (senão o acesso expira em 7 dias) e fica
  sem verificação, com a tela de aviso e o limite de 100 usuários.
- **Convite do Google ao cliente:** o texto (título e descrição) está em aprovação. Proposta abaixo.

### Texto do convite (APROVADO pelo Eduardo em 16/10)

- **Título:** `Conversa com Ramon Antonio Advogados`
- **Descrição:**
  > Olá, {primeiro_nome}! Esta é a nossa conversa sobre o seu caso, com {nome_do_closer}.
  >
  > Para entrar, é só tocar no link do Google Meet no horário marcado. Se preferir, a gente liga no seu WhatsApp.
  >
  > Se não puder comparecer, avise pelo WhatsApp que a gente remarca sem problema.

Aprovado o texto, todo convite sai sozinho para o lead que tem e-mail. Até lá, o evento nasce sem o cliente como
convidado.

## Decisões da revisão do builder (16/10, minhas — conferir)

- **Horário comercial = o do código:** `Ramon::HorarioComercial::JANELAS` (8h30–12h e 13h30–18h, sem o almoço). Corrige o
  "8–18" escrito acima.
- **Feriados:** tabela simples de feriados nacionais e de Tubarão/SC, em que a oferta não cai. Hoje o `HorarioComercial`
  não conhece feriado.
- **Oferta:** próximos **5 dias úteis**. A folga de 15 min vale também em volta dos compromissos do Google.
- **O Closer é fixado no lead na hora da oferta**, e não só na marcação. Assim o horário oferecido é da agenda certa
  (`atribuir_closer!` não troca depois).
- **Closer sem Google conectado:** a oferta usa só a agenda do hub, e o resumo das 8h avisa "Closer X sem Google".
- **Mexeu no Google, o hub acompanha:** evento criado pelo hub e movido no Google → `ReuniaoAgendamento.remarcar`;
  apagado no Google → `cancelar`. Sincronização de verdade dos eventos do hub, não só a leitura do ocupado.
- **Remarcar e cancelar pela conversa** seguem as mesmas regras de marcar, pela IA e pelo observador.
- **`piloto_ate_reuniao`:** marcar a reunião conta como chegar ao limite.
- **Observador:** marcar e bloquear a agenda tem chave própria e começa em ensaio, igual ao funil.
- **Furo que existe hoje:** `CopilotSuggestion#agendar_reuniao` cria só a tarefa e pula `Ramon::ReuniaoAgendamento`
  (sem lembretes, etapa nem Closer). Ela passa a chamar o serviço.
- **Ponto de encaixe:** com os fluxos de reunião no comando (`Ramon::Fluxos::Reunioes.assumiu?`, hoje ligado), o
  `efeitos_da_marcacao` não roda. O evento no Google e a conferência de horário entram num caminho que roda nos dois casos
  (ex.: `na_agenda`).
- **Modelo:** `lead_tasks` não tem duração, dono nem id do evento no Google. Isso vai em coluna ou tabela nova.
- **OAuth:** reaproveitar o cliente e o refresh do Google que o fork já tem (`GoogleConcern`,
  `Google::RefreshOauthTokenService`), com callback e escopo próprios da agenda.
- **Tokens:** `encrypts` do Rails, como nos canais. O builder confere na VPS se as envs `ACTIVE_RECORD_ENCRYPTION_*`
  existem; se não existirem, cria antes de gravar o primeiro token.

## Fica com o builder

Tabelas e modelo de evento, sincronização com o Google (notificação push ou leitura periódica), componente de calendário
na tela, onde fica o botão "conectar Google", formato do .ics e do link "salvar na agenda", como a IA escolhe os 2 ou 3
horários (espalhados no dia, priorizando os mais próximos) e o desenho da ferramenta nova do assistente.

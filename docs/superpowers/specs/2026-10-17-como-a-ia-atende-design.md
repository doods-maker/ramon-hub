# "Como a IA atende": Perfil da IA por tese e por caixa — desenho

Data: 17/10/2026 · Pedido do Eduardo · Status: rascunho para aprovação ·
Mockup aprovado: `2026-10-17-como-a-ia-atende-mockup.html` (visual e interação; as etapas e as linhas de limite
do mockup eram ilustrativas e são substituídas pelo catálogo desta spec) · Decisão: ADR 0009 · Termos: `CONTEXT.md`
(Perfil da IA, Trilha, Marcador, Permissão, Gatilho de equipe, Pausa da conversa).

## Por quê

O Eduardo abriu o hub e encontrou a autonomia da IA espalhada: o botão "Copiloto" na conversa com 7 modos, o
"Modo padrão da IA" na caixa, a "Tese padrão" na caixa, o card "Modo das conversas" em Assistentes, avisos na criação
e na conexão de caixa, a "Mensagem de transferência" do assistente, o modelo de ZapSign e o "na tabela" nos Playbooks
e o teto em US$ em Uso e custo. Os 7 modos são um campo só (`copiloto_modo`), mas cada valor mistura "até onde a IA
vai" com "o que ela pode fazer no caminho", e a regra de cada um está em lugares diferentes do código.

Ele quer **decidir tudo num lugar só, de forma didática e visual**: até onde a IA vai sozinha, o limite de cada ação
em cada etapa, quando ela para e chama a equipe — e **poder otimizar depois dos testes** vendo os números.

## O que é

Uma tela nova em **Inteligência → Como a IA atende** (admin), igual ao mockup aprovado:

- **Coluna da esquerda:** busca + grupos *Escritório* (Padrão do escritório), *Teses* (todas as teses ativas) e
  *Caixas sem tese* (caixas com assistente conectado e sem `ramon_thesis_id`). Cada item mostra a trilha em
  miniatura e o estado: "segue o padrão", o nome do perfil, ou "Equilibrada · 2 ajustes" em azul.
- **Editor do alvo escolhido**, de cima para baixo:
  1. **Perfil:** 3 cartões (Cautelosa, Equilibrada — selo "recomendado", Acelerada). Escolher um preenche tudo.
  2. **Até onde a IA vai sozinha:** a Trilha com o Marcador arrastável (encaixa entre as Etapas; setas do teclado
     movem) e, embaixo de cada Etapa, a etiqueta *Sozinha* / *Rascunho* / *Só equipe*. Clicar numa Etapa abre os
     limites dela. Frase de resumo em português ("A IA conduz sozinha até… Quando o lead chega em…, ela passa a
     escrever rascunhos e avisa o responsável.").
  3. **Limites em {etapa}:** linhas com ícone; Permissão como botão colorido que alterna Sozinha → Rascunho → Nunca;
     linha "Para e chama a equipe quando" com os Gatilhos daquela Etapa (ligam/desligam). Ponto azul = ajustado à mão.
  4. **Números da etapa** (sugestão 1 — ver abaixo).
- **Alvo que segue o padrão:** editor apagado + faixa azul "Esta tese segue o Padrão do escritório (…)" com o botão
  **Personalizar só esta** (copia o padrão para o alvo). Alvo com perfil próprio mostra **Voltar a seguir o padrão**.
- **Ajustou qualquer coisa:** selo "Personalizado · base {perfil} · N ajustes" + "Desfazer ajustes" (volta ao perfil base).
- Cabeçalho: "Inteligência / Como a IA atende", contador de alterações não salvas, **Salvar alterações** (um save
  grava todos os alvos alterados), botões **Testar este perfil** e **Histórico**.
- Visual = hub-v2 (Geist, branco/preto, azul `#2563EB`, cores translúcidas), nos dois temas; no hub usa o kit
  (`ramon/helpers/ui.js` + `components-next`), Tailwind só — o CSS do mockup é referência, não é para copiar.

### Quem manda (decidido: a tese)

Para cada turno da IA, o Perfil efetivo é, nesta ordem: **Pausa da conversa** → **Tese do lead**
(`leads.thesis_id`) → **caixa** → **Padrão do escritório**. Enquanto a IA não sabe a tese, vale a caixa; assim que o
lead ganha tese, vale a tese — **o perfil próprio dela ou, se ela "segue o padrão", o Padrão do escritório** (a caixa
não entra mais; é o que a faixa da tela diz). *Chamada minha.*

Por isso a coluna "Caixas sem tese" lista só caixas com assistente conectado e sem `ramon_thesis_id`: caixa com tese
dá a tese ao lead na 1ª mensagem (`TeseAutomatica` cai no `ramon_thesis_id`), e um perfil de caixa ali nunca valeria.
**Ligar/desligar a IA numa caixa continua em Assistente → Caixas** (conexão `captain_inboxes`); não existe perfil
"Desligada". *Chamada minha.*

### A Trilha usa as Etapas reais do Funil

As Etapas abertas da conta, em ordem (`LeadStage` sem `is_won`/`is_lost`): hoje Novo · Qualificação ·
Reunião agendada · Reunião realizada · Negociação · Última chance. O Marcador fica **depois** de uma delas (ou antes
de todas = "a IA não manda nada sozinha", ou depois de todas = "vai até o contrato") e é gravado pelo `label` da
Etapa (estável a renomeação). Etapa nova criada depois entra na Trilha na sua posição e fica antes ou depois do
Marcador conforme a posição. Lead **Fechado** = IA só escreve rascunho (pós-venda é das pessoas, como hoje).
**Perdido** = Pausa (IA pausada), como hoje.

Regra de resposta comum (texto sem ação): Etapa do lead antes do Marcador → sai sozinha; depois → rascunho + aviso.

### Catálogo de ações (Permissões) — só o que o código consegue garantir

| Chave | Aparece na Etapa | Sozinha | Rascunho | Nunca | Onde o código decide hoje |
|---|---|---|---|---|---|
| `fora_do_horario` | Novo (vale em todas as Etapas) | responde fora do horário comercial | toda resposta fora do horário vira rascunho | — (sem "nunca": exigiria resposta adiada) | novo; usa `Ramon::HorarioComercial` |
| `pedir_documentos` | Qualificação | `solicitar_documento`/`enviar_link_portal` saem | viram rascunho | Tools desligadas | `envia?` |
| `desqualificar` | Qualificação | saída "desqualifica" do roteiro marca Perdido | vira Sugestão `perdido` | vira "chama a equipe" | `Roteiro::Efeitos` (`direto?`) |
| `mover_etapa` | Qualificação | efeito de etapa do roteiro move direto | vira Sugestão `move_stage` | não move nem sugere | `Roteiro::Efeitos` (`direto?`) |
| `marcar_reuniao` | Qualificação | `agendar_reuniao` marca de verdade | vira Sugestão `reuniao` | não oferece horários (`horarios_livres` e `agendar_reuniao` desligadas) | `agendar_reuniao_tool` (`direto?`) |
| `citar_honorario` | Qualificação e Negociação (mesma chave) | resposta com `simular_honorario` sai | vira rascunho | Tool desligada | `envia?` + Tool |
| `logistica` | Reunião agendada | **depois do Marcador**, resposta de pura logística (classificador atual) sai sozinha | tudo depois do Marcador vira rascunho | — | `PilotoLogisticaService` (era o "piloto limitado") |
| `contrato_zapsign` | Negociação | `ContratoAutomatico.preparar` gera e manda | vira Sugestão `zapsign` | não prepara | `ContratoAutomatico` (hoje só `piloto_ate_contrato`) |
| — `desconto` | Negociação | — | — | **sempre nunca** (linha travada, "regra do escritório") | guardrail do assistente |

Regras de combinação (*chamadas minhas*, para a função `decidir`):
- **O Marcador é teto.** Permissão efetiva de uma ação = a mais restrita entre a Permissão dela e o estado da Etapa do
  lead naquele turno (antes do Marcador = sozinha; depois = rascunho). Ex.: `contrato_zapsign` sozinha com o lead numa
  Etapa depois do Marcador → vira Sugestão. Na tela, a linha de uma ação numa Etapa depois do Marcador mostra o valor
  efetivo com a nota "limitado pelo marcador".
- **Quais ações contam para a resposta:** só as Tools cujo resultado vai no texto (`citar_honorario`,
  `pedir_documentos`, link do contrato). Se uma delas está em *rascunho*, a resposta inteira vira rascunho. Efeito do
  roteiro que vira Sugestão (`desqualificar`, `mover_etapa`) **não** segura a resposta.
- *Nunca* = a Tool nem é oferecida ao modelo naquele turno.
- **Depois do Marcador**, só sai sozinha a resposta de pura logística, e só se `logistica` = sozinha.
- **Quem executa direto com *sozinha*:** efeitos do roteiro (mover etapa, Perdido), `agendar_reuniao` e
  `ContratoAutomatico` (também pela `preparar_contrato_zapsign`). As Tools `mover_etapa` e `marcar_perdido`, que o
  modelo chama por conta própria, **continuam sempre Sugestão** (como hoje).
- **Mensagem de transferência:** sai sozinha quando uma resposta logística sairia (antes do Marcador, ou depois com
  `logistica` sozinha) — equivale ao de hoje nos modos piloto; com Pausa ou fora disso vira rascunho, como hoje. O
  aviso de cota estourada segue a mesma regra.
- Falha de Tool no turno → rascunho, como hoje.
- **Confirmação de reunião não entra no Perfil:** hoje quem decide é o fluxo Reuniões (ligado) e a env
  `RAMON_AGENDA_CONFIRMACAO`; uma linha aqui seria a 2ª tela decidindo a mesma coisa (anti-meta). A Etapa "Reunião
  agendada" mostra uma linha só de leitura "Confirmação da reunião: definida no fluxo Reuniões →".

**Fora, por decisão do Eduardo (17/10):** lembretes de reunião e de assinatura, retomada sozinha, resumo do combinado
para o lead e "mensagens seguidas sem resposta" — dependem de modelo aprovado na Meta (fora da janela de 24h/72h) e
"não faz sentido ir pra IA"; **remarcar** fica com uma pessoa ("pra entender bem o lead"); prazo para o lead decidir e
perguntas por mensagem também não entram. Nenhuma fase 2 com ações novas está prevista.

### Gatilhos de equipe (por Etapa)

Lista fixa, ligável por Etapa no Perfil: pediu para falar com uma pessoa · dúvida ou decisão jurídica · outra área do
direito · fora do tema da tese · perguntou o honorário de novo · não consegue ler/escrever · lead irritado · já tem
advogado · pediu desconto · quer mudar cláusula do contrato. Hoje são regras de prompt fixas no assistente
(`response_guidelines`, seed `db/seeds/ramon/inteligencia/assistentes.yml`); passam a ser montadas por conversa a
partir do Perfil e da Etapa do lead e entram no prompt do turno. Os textos de cada gatilho para o prompt saem das
regras atuais (mesma redação); gatilho novo sem regra atual (lead irritado, já tem advogado, pediu desconto, mudar
cláusula) precisa de texto aprovado pelo Eduardo antes de ligar (é instrução à IA, não fala ao cliente, mas muda o
que ela diz). Gatilho é orientação ao modelo, não garantia — a tela diz isso no tooltip.

### Os três perfis prontos

| | Cautelosa | Equilibrada (recomendado) | Acelerada |
|---|---|---|---|
| Marcador depois de | Qualificação | Reunião agendada | Última chance (até o contrato) |
| `fora_do_horario` | rascunho | sozinha | sozinha |
| `pedir_documentos` | sozinha | sozinha | sozinha |
| `desqualificar` | rascunho | rascunho | sozinha |
| `mover_etapa` | rascunho | sozinha | sozinha |
| `marcar_reuniao` | rascunho | sozinha | sozinha |
| `citar_honorario` | nunca | rascunho | sozinha |
| `logistica` | rascunho | sozinha | sozinha |
| `contrato_zapsign` | nunca | rascunho | sozinha |
| Gatilhos | todos ligados | todos, menos "não consegue ler" | pediu pessoa, jurídica, outra área, fora do tema, desconto, cláusula |

Os perfis prontos vivem no código (constante); a conta guarda só o que cada alvo usa (base + valores).

### Limites gerais do escritório (sugestão 5)

Seção extra que aparece **só no Padrão do escritório**, abaixo dos limites por etapa:

| Limite | Hoje | Passa a ser |
|---|---|---|
| Teto de gasto por dia (US$) | `accounts.settings['ramon_ia_teto_diario_usd']` (Uso e custo) | mesmo campo, editável aqui também |
| Horário comercial **do escritório** | fixo em `Ramon::HorarioComercial` (seg–sex 8:30–12 / 13:30–18) | editável (dias + 2 faixas), lido pelo `HorarioComercial`; vale também para os horários livres da Agenda e o "sem resposta há +1h" do painel do SDR — um horário só, com a nota na tela (*chamada minha*) |
| Resposta da IA no piloto: atraso | `RESPOSTA_IA_ATRASO = 30..180 s` | editável (mín/máx, teto 3 min — decisão de 13/10) |
| IA dos fluxos por dia | env `RAMON_FLUXO_IA_DIA` (200) | editável; env vira só o padrão |
| Retomadas por dia / intervalo | `Retomada::TETO = 15`, `INTERVALO_DIAS = 5` | editáveis |
| Agente @claude por dia | `AgenteExecucao::TETO_DIA = 30` (o real é `CAP_DIA` no runner da VPS) | **só leitura** aqui, com a nota de onde muda |

### Números por etapa (sugestão 1)

Embaixo dos limites de cada Etapa, últimos 30 dias, só daquele alvo: respostas enviadas sozinhas, rascunhos (sem
edição / editados / descartados), vezes que chamou a equipe. Regra de sugestão: Etapa (ou ação) em *rascunho* com
≥ 20 rascunhos revisados e ≥ 90 % sem edição → aviso "Passar pra Sozinha?" com botão que aplica (vira ajuste).
Base: `bi_ia_rascunhos`, `bi_ia_conversas`, `META_PILOTO = 20`. **Lacuna:** hoje nenhuma mensagem guarda a Etapa do
lead na hora; passa a gravar `etapa` (label) no carimbo `ramon_piloto`, no carimbo de rascunho
(`ramon_rascunho_ia`) e na chamada de equipe. Os números começam do dia em que a gravação entrar; antes disso a tela
mostra "sem dados ainda".

### Testar este perfil (sugestão 2)

Botão no cabeçalho abre o **Testar** que já existe (`captain/:assistantId/playground`) com a tese do alvo e o perfil
**do jeito que está na tela, mesmo sem salvar**. O playground passa a aceitar `roteiro: { thesis_id, estado, perfil }`
(no lugar de `modo`) e, para cada resposta, mostra a decisão do Perfil: "sairia sozinha" / "viraria rascunho (motivo)"
/ "Tool bloqueada (nunca)". A decisão vem da mesma função que decide em produção (ver Desenho do código).

### Histórico e desfazer (sugestão 3)

`Account` já é auditado (inclui `settings`). O Registro de ações passa a aceitar `Account` filtrando a chave
`ia_atendimento` e mostra frases como "Eduardo mudou BPC/LOAS: marcar reunião rascunho → sozinha". O botão
**Histórico** da tela abre esse registro filtrado; cada mudança tem **Desfazer** (regrava o valor anterior daquele
alvo; também fica no histórico).

### Avisos de dependência (sugestão 4)

No editor, junto da linha afetada, aviso âmbar com link:
- `contrato_zapsign` sozinha/rascunho e a tese sem `zapsign_template_id` → "Esta tese não tem modelo no ZapSign; o
  contrato não sai automático" → Playbooks.
- `citar_honorario` ≠ nunca e tese com `honorario_na_tabela = false` → "Esta tese está fora da tabela; a IA não cita
  valor e chama a equipe" → Playbooks.
- `marcar_reuniao` sozinha e nenhum Closer com Google conectado → "Ninguém do comercial conectou o Google; a reunião
  vira sugestão" → Agenda.
- Tese cujo roteiro não tem saída "Qualificado (fim)" → "O roteiro desta tese não termina em Qualificado" → Roteiro da IA.
- Caixa com perfil e sem assistente conectado → "A IA não está conectada nesta caixa" → Assistente → Caixas.

### Botão da conversa (sugestão 6)

O `CopilotoModoSelector` vira **"IA: {perfil} (da tese | da caixa | do padrão) · {etapa}"**, com 4 ações:
**Pausar a IA nesta conversa** (Pausa = pausada), **Só rascunho nesta conversa** (Pausa = só rascunho),
**Voltar a seguir o perfil** (tira a Pausa) e **Ver na trilha** (abre a tela no alvo). "Assumir" = atribuir a mim +
pausar. O carimbo "enviada pelo piloto" mantém "Pausar" (= só rascunho). Escolher Pausar numa conversa pendente a abre,
como o Manual faz hoje.

### Limpeza (sugestão 7)

Saem, cada um trocado por uma linha com link "Configurar em Como a IA atende":
- "Modo padrão da IA nesta caixa" nas configurações da caixa (`inbox/Settings.vue`);
- a explicação do modo no passo Agentes da criação de caixa (`AddAgents.vue`);
- o card "Modo das conversas" em Assistentes (`captain/assistants/Index.vue`) e as contagens por modo no controller;
- o aviso de modo ao conectar caixa (`ConnectInboxForm.vue`, `AVISO_RASCUNHO`);
- o bloco "Rumo ao piloto limitado / Piloto com limites em vigor" da Visão geral.
A "Tese padrão da caixa" **fica** na caixa (é como a tese é detectada, não autonomia).

## Desenho do código (decidido)

- **Um módulo fundo, `Ramon::PerfilIa`**, substitui `Ramon::CopilotoModo` como única fonte de decisão:
  - `PerfilIa.de(conversation_ou_lead)` → perfil efetivo + origem (pausa | tese | caixa | padrão);
  - `#responde_sozinha?(etapa_label)`, `#permissao(acao)` → `:sozinha | :rascunho | :nunca`,
    `#tools_bloqueadas`, `#gatilhos(etapa_label)`, `#marcador`;
  - `PerfilIa.decidir(perfil, etapa:, tools_usadas:, logistica:, handoff:, falhou:)` → `:envia | :rascunho` + motivo
    — **função pura**, usada pelo `ResponseBuilderJob`, pelo playground (Testar) e pelos specs.
  - Os chamadores de hoje trocam `CopilotoModo.envia?/direto?/piloto?/of` por perguntas ao perfil: `ResponseBuilderJob`,
    `hook_execution_service` (atraso só quando a resposta pode sair sozinha), `Roteiro::Efeitos`, `agendar_reuniao_tool`,
    `ReuniaoAgendamento`, `ContratoAutomatico`, `FunilAcao` (desfazer), `LeadRoteiro` (simulado), assistants controller.
- **`Ramon::CopilotoLimite`** vira o aviso de **cruzar o Marcador**: quando o lead passa para uma Etapa depois do
  Marcador, carimba `copiloto_limite` (uma vez por Marcador) e chama `AvisoDaIa`. Não muda mais o modo da conversa: a
  decisão é recalculada a cada turno pela Etapa. A resposta do turno que cruzou continua saindo (igual a hoje).
- **Gravação:** `accounts.settings['ia_atendimento'] = { 'padrao' => cfg, 'teses' => { id => cfg }, 'caixas' => { id => cfg } }`,
  `cfg = { 'base', 'marcador' (label ou '_inicio'/'_fim'), 'permissoes' {chave => s|r|n}, 'gatilhos' {label => [chaves]} }`.
  Tese ausente = segue o padrão; caixa ausente = segue o padrão (sem chave 'desligada'). Dono único da chave = `Ramon::PerfilIa` (padrão `FunilAutomatico`). Limites gerais
  em `accounts.settings['ia_limites']` (teto US$ continua na chave atual).
- **Pausa da conversa:** `conversation.custom_attributes['ia_pausa'] = 'pausada' | 'rascunho'`. `Efeitos` (Perdido →
  pausada; roteiro humano → rascunho; reabrir → tira) e `FunilAcao` (desfazer) passam a usar essa chave.
- **API:** `resource :ramon_ia_atendimento, only: [:show, :update]` (molde: `ramon_ia_uso_controller.rb`,
  `RamonIaPolicy#gerenciar?`); `show` devolve perfis prontos, alvos, etapas, avisos e números; `update` grava alvos.
- **Front:** rota `captain/como-a-ia-atende` (`metaAdmin`), item no menu Inteligência logo depois de Visão geral.

## Migração (sem perder o que está no ar)

Estado da VPS em 13/10: só a caixa "Teste" tem assistente; WhatsApp/IG sem IA; env `RAMON_COPILOTO_MODO_DEFAULT =
piloto_limitado` (decisão D7).
- **Padrão do escritório inicial (Eduardo, 17/10): igual a hoje** = env `piloto_limitado` traduzido: Personalizado
  (base Cautelosa) com Marcador em `_inicio` e quatro ajustes para bater com o de hoje: `logistica` sozinha,
  `fora_do_horario` sozinha (hoje a logística sai a qualquer hora), `citar_honorario` rascunho e `contrato_zapsign`
  rascunho (hoje as duas Tools existem e viram rascunho/Sugestão; "nunca" as tiraria). O resto como a Cautelosa. Única
  diferença, mais conservadora: resposta que usou Tool de texto (pedir documento) depois do Marcador vira rascunho mesmo
  se o classificador disser logística (Marcador é teto). *Chamada minha* (correção na hora do plano).
- Caixa com `ramon_copiloto_modo` preenchido → perfil pela tabela: rascunho → o padrão inicial acima com
  `logistica` rascunho; piloto_limitado → o padrão inicial acima; até qualificação →
  Cautelosa; até reunião → Equilibrada; até contrato / piloto total → Acelerada. Caixa **sem tese** → perfil da
  caixa. Caixa **com tese** → o perfil vai para a tese dela, se a tese ainda não tiver um; senão é descartado (e o
  rake de migração lista o que descartou).
- Conversa com `copiloto_modo = manual` → `ia_pausa = pausada`; com `rascunho` **e** o carimbo
  `copiloto_modo_antes_roteiro` (o roteiro chamou humano) → `ia_pausa = rascunho`. Os outros valores são ignorados:
  eram carimbo do padrão da caixa, ou limite atingido (que o Marcador recalcula). Impacto baixo: só a caixa Teste tem IA.
  *Chamadas minhas.*
- Depois da migração: coluna `inboxes.ramon_copiloto_modo`, env `RAMON_COPILOTO_MODO_DEFAULT`, `copilotoModo.js`,
  `CopilotoModoSelector.vue`, `carimbar_padrao` e as strings `RAMON.COPILOTO.MODOS.*` saem (código morto não fica).
  A coluna sai numa migração própria, num PR depois do deploy da troca.

## Metas, não-metas, anti-metas

- **Meta:** um lugar só, didático; por tese e por caixa; números para soltar a IA aos poucos com segurança.
- **Não-meta:** mudar o roteiro, os textos que a IA manda ao cliente, o classificador de logística, a detecção de
  tese, o modelo/provedor de IA, ou criar ações novas (remarcar, lembrete de assinatura).
- **Anti-meta (falharia mesmo funcionando):** linha na tela que o código não cumpre; perfil que deixa a IA dar
  desconto ou prometer resultado; a IA mandar algo ao cliente em caixa que hoje está sem IA só por causa da migração;
  voltar a ter duas telas que decidem a mesma coisa.

## Restrições

- Conteúdo que fala com cliente = gate do Eduardo: a troca sobe com **todas as caixas reais iguais a hoje**; ligar
  perfil em caixa real é ação dele, depois do smoke.
- OAB (Provimento 205/2021) e POP JUR-02: honorário só da tabela; desconto nunca; nada de promessa de resultado.
- Sem ambiente local: valida por PR + CI; specs da função pura `decidir` cobrem a tabela de combinação.
- Migração nova → `schema.rb` via scratch DB na VPS.

## Fica com quem constrói

Fatiamento em PRs (sugestão: 1 motor `PerfilIa` + migração com a tela antiga ainda viva; 2 tela nova; 3 botão da
conversa + limpeza; 4 números, testar, histórico, avisos), nomes de componentes, cópia fina da tela (seguindo o
mockup), ícones, como mostrar "sem dados ainda".

## Pendências para o Eduardo

- Texto para o prompt dos gatilhos novos (lead irritado, já tem advogado, pediu desconto, mudar cláusula) antes de ligá-los.
- As decisões marcadas *chamada minha* nesta spec, para conferência.

## Smoke (depois do deploy)

Roteiro no doc de entrega: caixa Teste em cada perfil, conversa de teste passando pelas Etapas, cruzar o Marcador
(aviso no sino), Pausa no botão, tese sem ZapSign com aviso, Testar sem salvar, desfazer pelo Histórico.

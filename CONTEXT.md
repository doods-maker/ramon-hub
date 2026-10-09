# Comercial Ramon (ramon-hub)

O contexto comercial da banca: o funil de vendas que recebe leads dos canais de
aquisição digital, qualifica, conduz até o contrato e entrega o caso ao jurídico.
Vive dentro do fork do Chatwoot porque a matéria-prima do comercial são conversas.

## Language

### Pessoas e papéis

**Lead**:
Uma oportunidade comercial: pessoa com interesse ativo em contratar a banca,
acompanhada pelo funil do nascimento ao ganho/perda. Distinto de Contato
(a pessoa/cadastro) e de Conversa (o diálogo) — um Lead aponta para ambos.
_Avoid_: prospect, oportunidade, card

**SDR**:
Quem faz o primeiro atendimento e a qualificação do lead. Hoje é o Eduardo,
com triagem automática (quiz das LPs + agente de IA) como primeira linha.

**Closer**:
Quem conduz reunião, negociação e fechamento. Hoje também o Eduardo.

### Funil

**Funil**:
A sequência de Etapas que todo Lead percorre. É um só para todo o comercial;
topo = aquisição por canal, meio = qualificação, fundo = fechamento.
_Avoid_: pipeline, kanban (kanban é a visualização, não o funil)

**Etapa**:
Uma fase do Funil, com probabilidade de fechamento e prazo próprio de
estagnação. Exatamente uma etapa é a de ganho e uma a de perda.
_Avoid_: fase, coluna, estágio

**Ganho**:
Lead que fechou contrato. Dispara a passagem para o jurídico e o cadastro
no ADVBOX.
_Avoid_: fechado (ambíguo com "conversa fechada"), convertido

**Perdido**:
Lead que saiu do funil sem contratar. Exige um Motivo de Perda.

**Motivo de Perda**:
A razão registrada quando um Lead é Perdido (sem viabilidade, sumiu,
honorário, concorrente, fora da área…). Obrigatório, vem de catálogo.

**Parado**:
Lead que está há mais tempo na Etapa atual do que o prazo de estagnação
daquela etapa permite. Pede ação de cadência.
_Avoid_: stalled, frio

### Aquisição

**Canal**:
De onde o Lead veio, em vocabulário fixo (meta_ads, landing_page, instagram,
google_seo, indicacao, whatsapp_direto, outro). Fato imutável do lead;
dimensão de análise, nunca uma Etapa.
_Avoid_: mídia, fonte (ver Origem)

**Indicação**:
Canal do lead que chega ao WhatsApp sem rastreamento de anúncio — nos números
da banca, quem chega sem anúncio presume-se indicado. Entra no Funil como
qualquer lead; só fica fora das métricas de aquisição paga (CPL, ROI).

**Origem**:
O identificador específico da aquisição dentro do Canal: qual campanha, LP
ou anúncio trouxe o lead. Texto livre, acompanhado das UTMs.
_Avoid_: source, campanha (a campanha é um valor possível de origem)

### Qualificação e cadência

**Tese**:
A tese jurídica do caso do lead (auxílio-doença, BPC/LOAS, auxílio-acidente…),
com regra de honorário própria. Define os critérios de qualificação.

**Triagem**:
A avaliação inicial de viabilidade do lead — pelo quiz da LP e/ou pelo
agente de IA sobre a conversa — antes do toque humano.
_Avoid_: qualificação (qualificação é a etapa inteira; triagem é o primeiro filtro)

**Cadência**:
O ritmo de follow-up planejado sobre um lead: as tarefas com prazo que
impedem o lead de ficar Parado sem dono.

**SLA de primeira resposta**:
O tempo máximo entre a chegada do lead e a primeira resposta humana ou
automática. Estourar o SLA é evento visível no funil.

**Colheita**:
A extração automática (por IA) dos dados do caso a partir da conversa —
o que o cliente já contou, o que falta perguntar.
_Avoid_: usar "colheita" para documentos (ver Coleta de Documentos)

### Pós-venda

**Pós-venda**:
A fase do comercial depois do Ganho: coletar os documentos do cliente até o
caso estar completo e entregue. Conduzida pelo comercial (com apoio da
controller quando preciso); só então o trabalho vira do jurídico.

**Checklist de Documentos**:
A lista, definida por Tese, dos documentos que o caso exige, com o status de
cada um (pendente, solicitado, recebido). "Recebido" é sempre veredito humano —
a IA no máximo sugere; é o que o ADR-0002 chama de documento "conferido".
_Avoid_: conferido como quarto status (é sinônimo de recebido)

**Coleta de Documentos**:
A atividade do Pós-venda: cobrar, receber e conferir os itens do Checklist
de Documentos.
_Avoid_: colheita (é a extração de dados da conversa)

**Concluído**:
Lead ganho com o Checklist de Documentos completo e o pacote de documentos
entregue. O verdadeiro fim do Funil.

### Previsão

**Valor Estimado**:
O honorário previsto do lead, calculado pela regra da Tese sobre o valor do
benefício assim que conhecidos. Ajustável à mão; vira Valor do Contrato no Ganho.

**Previsão**:
A receita esperada do funil: soma dos Valores Estimados ponderados pela
probabilidade da Etapa de cada lead.

### Inteligência

**Assistente**:
Um agente de IA configurado na área Inteligência, com público definido —
hoje dois: o de *Atendimento* (fala com o lead, humano no meio) e o *Copiloto do
Escritório* (responde à equipe). Cresce por Skills, não por multiplicação de
assistentes.
_Avoid_: agente (genérico), bot, capitão

**Skill**:
Uma situação que o Assistente sabe conduzir (qualificar lead novo, preparar
reunião, cobrar documento…): instrução + Tools permitidas. Editável na tela,
sem código.
_Avoid_: cenário, scenario

**Tool**:
Uma capacidade que o Assistente pode invocar (calcular benefício, buscar no
ADVBOX…). Tool de leitura responde; Tool de escrita nunca executa — gera uma
Sugestão pendente.

**Sugestão**:
Uma ação proposta pela IA à espera do clique humano (rascunho, alerta, mover
etapa, ação externa). Aplicar ou dispensar é sempre decisão de pessoa.
_Avoid_: ação automática

**Execução**:
O registro auditável de uma Tool invocada: quando, com o quê, o que voltou,
quanto demorou.
_Avoid_: confundir com Execução de fluxo (a passada de um Fluxo, ver Automações)

**Modo do Copiloto**:
O grau de autonomia da IA numa conversa específica: manual (não age),
rascunho (propõe, humano envia), piloto limitado (envia sozinha só logística),
piloto total. Padrão é rascunho.

**FAQ**:
Pergunta que o *lead* faz e a resposta aprovada da banca, por Tese; o
Assistente consulta antes de responder.

**Documento (da Inteligência)**:
Página da web ou texto colado que o administrador cadastra para **gerar FAQs
pendentes**. O *Assistente* não lê o documento: ele só usa as FAQs depois de
aprovadas (decisão D4, 16/08/2026). Distinto de Documento do cliente no Checklist.
_Avoid_: usar "documento" sem qualificar quando o contexto for pós-venda

**Memória do contato**:
A nota "MEMÓRIA DA IA" que a IA grava no Lead ao resolver uma conversa, com o
que vale lembrar da pessoa (benefício de interesse, trabalho, datas,
documentos, objeções). Nunca guarda dado de saúde nem dado pessoal (ADR 0007).
Não é a Colheita (que extrai os dados do caso durante a conversa) nem uma Nota
escrita por pessoa.
_Avoid_: memória (sem qualificar), resumo da conversa

### Automações

**Fluxo**:
Uma automação desenhada no quadro da Inteligência: um Gatilho e os Passos
ligados por setas, de cima para baixo. Só administrador monta; mensagem ao
cliente sai sempre como rascunho. Não é a Automação nativa do Chatwoot (saiu do
menu) nem a Cadência (o ritmo de follow-up, que um fluxo executa).
_Avoid_: automação (sem qualificar), regra, workflow, n8n

**Gatilho**:
O evento que começa um Fluxo — exatamente um por fluxo (conversa nova, lead
parado, reunião marcada, Horário da conta, rodar na mão…). Define o alvo da
execução: lead, conversa, a conta ou o registro de um evento de fora do funil.
_Avoid_: evento, trigger

**Passo**:
Uma caixinha do Fluxo depois do Gatilho: condição (se, escolha), espera,
controle ou ação (mover etapa, rascunho, sino, tarefa, Rotina pronta…).
_Avoid_: nó, etapa (Etapa é do Funil), ação (ação é um tipo de passo)

**Rotina pronta**:
Um Passo que chama um pedaço do código do hub como está (dossiê de passagem,
NPS, abrir caso no ADVBOX, resumo do dia, escalar a chegada). Encaixa no
fluxo, mas o que ela faz por dentro não se edita na tela.
_Avoid_: rotina (sem qualificar), job

**Execução de fluxo**:
Uma passada de um Fluxo por um alvo, com a Trilha dos passos por onde andou.
Roda na versão publicada em que começou. O **ensaio** é a execução de mentira:
avalia as condições num alvo real, descreve as ações e não executa nada.
_Avoid_: Execução (é o registro de uma Tool da IA), teste, simulação

**Fluxo do sistema**:
O desenho só-leitura, na aba "Do sistema", de uma das 29 automações que
vivem no código. Nunca roda pelo motor; existe para mostrar e para levar a
Ficha. Cada um tem um selo: "roda no fluxo" (há um Fluxo migrado que roda) ou
"regra fixa".
_Avoid_: fluxo padrão, modelo (modelo é ponto de partida de fluxo novo)

**Fluxo migrado**:
Um Fluxo comum que assumiu uma automação do código, marcado com a chave da
automação que substitui (`sistema_chave`). Editável como qualquer fluxo, mas
só age quando a Chave está virada; senão, quem faz é o código.
_Avoid_: fluxo do sistema (é o desenho só-leitura)

**Modo sombra / normal**:
O modo de um Fluxo. Em **normal** ele age; em **sombra** cada execução é
ensaio — no Fluxo migrado, sombra quer dizer "o código está no comando".
Não é ligado/desligado: um fluxo desligado não roda nem em sombra.
_Avoid_: rascunho (rascunho é a mensagem ao cliente ou o desenho não publicado)

**Chave (de migração)**:
A condição para um Fluxo migrado estar no comando: a variável de ambiente da
automação ligada **e** os fluxos dela ligados, publicados, em modo normal, com
o gatilho certo e sem limite do dia. Qualquer peça fora devolve o comando ao
código. Vira e volta por comando na VPS, sem deploy.
_Avoid_: flag, interruptor (o interruptor da tela é só "ligado")

**Reserva pelo código**:
Quando o Fluxo migrado está no comando mas não começou aquele evento (ocupado
com o mesmo alvo, filtro editado, erro do motor), o código faz o evento como
antes — nunca em dobro, nunca nenhum (ADR 0005). Execução que começou e falhou
não aciona a reserva.
_Avoid_: fallback, plano B

**Regra fixa**:
Uma das automações do sistema que fica no código de propósito (22 das 29),
com o selo "regra fixa" na aba Do sistema. Não vira fluxo; para mudar, pede-se
ao Claude. Para acrescentar comportamento ao mesmo evento, usa-se um Fluxo
comum no mesmo Gatilho (ADR 0006).
_Avoid_: legado, "ainda não migrada"

**Ficha**:
O cartão em linguagem simples de cada uma das 29 automações do sistema: o que
faz, quando, o que mexe, travas, por que está onde está e como pedir mudança;
nas que rodam no fluxo, o link para o Fluxo de verdade.
_Avoid_: documentação, "Como roda hoje" (é o detalhe técnico, por baixo da ficha)

**Gatilho de fora do funil**:
Gatilho cujo alvo não é lead nem conversa, e sim o registro de um evento
(assinatura e documento pelo Painel, reunião gravada, peça publicada, peça
mudou de status). Existe para os fluxos comuns do Eduardo; só aceita Passos que
rodam sem lead.
_Avoid_: gatilho externo, webhook

**Horário da conta**:
O Gatilho de relógio cujo alvo é a própria conta: uma vez por dia a partir de
uma hora, ou a cada N minutos, nos dias escolhidos (fuso de São Paulo). Também
só aceita Passos sem lead.
_Avoid_: cron, agendamento (agendamento é o de reunião)

### Atendimento do escritório

**Caixa do escritório**:
A caixa do número do escritório (flag técnica `portaria_enabled`). Não cria
lead e não tem menu: toda conversa nova cai na Recepção, que distribui. As
caixas de tese não são caixa do escritório. (Até 02/10/2026 tinha a
**Portaria**, um menu de botões que o cliente usava pra escolher o Setor —
removido, ver ADR 0004.)
_Avoid_: Portaria (nome antigo), URA, bot

**Setor**:
Quem atende na caixa do escritório — Recepção, Controladoria ou Advogados. A
Recepção é membro da caixa e vê tudo; a Controladoria é um time e vê a fila do
time; cada advogado vê só as conversas **atribuídas** a ele.
_Avoid_: departamento, time (nome técnico), equipe

**Atribuir (na caixa do escritório)**:
O gesto da Recepção de passar a conversa a um advogado (responsável) ou ao time
da Controladoria. É o único jeito de a conversa aparecer na tela de quem não é
da Recepção.
_Avoid_: encaminhar (Encaminhar é mandar ao comercial), transferir

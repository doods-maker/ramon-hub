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

**Modo do Copiloto**:
O grau de autonomia da IA numa conversa específica: manual (não age),
rascunho (propõe, humano envia), piloto limitado (envia sozinha só logística),
piloto total. Padrão é rascunho.

**FAQ**:
Pergunta que o *lead* faz e a resposta aprovada da banca, por Tese; o
Assistente consulta antes de responder.

**Documento (da Inteligência)**:
Material de referência que o *Assistente* consulta (guia da tese, política de
honorários, checklist) — distinto de Documento do cliente no Checklist.
_Avoid_: usar "documento" sem qualificar quando o contexto for pós-venda

### Atendimento do escritório

**Portaria**:
O menu de entrada do número do escritório: recebe quem chega, pergunta com
quem quer falar e encaminha ao Setor escolhido. Não responde dúvida nem
resolve nada — só encaminha. Existe por caixa; as caixas de tese não têm.
_Avoid_: URA, bot, triagem (Triagem é qualificação do lead), menu de atendimento

**Setor**:
Um destino humano da Portaria — Recepção, Controladoria ou Advogados. Cada
Setor tem sua fila e suas pessoas; quem é de um Setor vê só as conversas dele.
_Avoid_: departamento, time (nome técnico), equipe

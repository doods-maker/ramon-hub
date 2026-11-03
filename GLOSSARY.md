# ramon-hub

Sistema central da Ramon Antonio Advogados: CRM comercial, atendimento, painel do cliente e, a partir de 30/10/2026,
peticionamento. Termos ainda são registrados à medida que cada área é redesenhada.

## Peticionamento

**Petição**:
Um pedido de protocolo de um conjunto de arquivos num processo (ou de uma inicial), com advogado responsável e prazo.
_Avoid_: protocolo (é o ato no tribunal), peça (é só o arquivo principal)

**Pacote**:
A lista ordenada de arquivos de uma petição, cada um com um tipo; exatamente um é a peça principal.
_Avoid_: anexos, documentos (quando se quer dizer o conjunto)

**Peça principal**:
O arquivo do pacote que é a petição redigida pelo advogado.

**Tipo genérico**:
O nome que o hub dá a cada arquivo do pacote (Petição, Procuração, CNIS, Laudo…), traduzido para o nome do tribunal
na hora do protocolo.
_Avoid_: tipo do eproc (é a tradução, não o tipo do hub)

**Regra do tribunal**:
Os limites de formato e tamanho que um pacote precisa respeitar para ser aceito por aquele tribunal.

**Protocolo**:
O ato de entregar o pacote ao tribunal, que gera número do evento e comprovante.
_Avoid_: envio, peticionamento (quando se quer dizer o ato)

**Comprovante**:
O documento do tribunal que prova o protocolo; sem ele a petição não está protocolada.

**Executor**:
Quem faz o protocolo no tribunal: o próprio advogado (manual), um robô ou um fornecedor contratado.

**Cofre**:
O lugar do hub onde ficam, cifradas, as credenciais de cada advogado para os tribunais.
_Avoid_: senhas, credenciais (quando se quer dizer o lugar)

**Pasta do protocolo**:
A pasta do Drive que contém só um protocolo: a peça final em PDF e os anexos numerados. É a única entrada que a pessoa
informa; não é a pasta geral do cliente.
_Avoid_: pasta do cliente

**Conferência**:
O status da petição criada a partir de uma pasta, enquanto a pessoa revisa os dados lidos e o pacote. Só depois de
confirmar ela vira rascunho pronto para protocolar.
_Avoid_: revisão (é o que o revisor da esteira faz na peça)

**Pasta pronta**:
Pasta do protocolo que a esteira deixou para um advogado revisar, marcada no Drive por `_pasta-pronta.json`. Aparece na
lista de Protocolos e no sino, e some quando vira petição.

**Sobra de rascunho**:
Texto que não pode chegar ao tribunal e ainda está na peça: campo em aberto (`[CONFERIR]`, `[CPF]`…) ou bloco interno da
esteira (`CONTROLE INTERNO`, `Notas ao advogado`…). O hub recusa a pasta que a tem.

## Esteira de agentes

**Painel dos agentes**:
A tela do hub que mostra ao vivo o que as sessões da esteira de petições estão fazendo. É o foreman-vision em um iframe,
restrito por lista de e-mails (ADR 0013).
_Avoid_: Esteira (no hub, é outra tela: a fila de tarefas do dia), vision (é o nome da ferramenta)

**Aprovação**:
Um pedido de permissão de uma sessão da esteira, respondido na tela Agentes (ADR 0014).
_Avoid_: aprovado (é o OK do Eduardo a algo que sai para o mundo), permissão (é a regra do Claude Code)

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
Quem faz o protocolo no tribunal: o próprio advogado (manual), um robô, o MNI ou um fornecedor contratado.

**Cofre**:
O lugar do hub onde ficam, cifradas, as credenciais de cada advogado para os tribunais.
_Avoid_: senhas, credenciais (quando se quer dizer o lugar)

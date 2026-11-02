# Peticionamento pela pasta do Drive

**Data:** 02/11/2026. **Autor do pedido:** Eduardo Schlata.
**Parte de:** `2026-10-30-peticionamento-design.md` (Fase 1 no ar, PR #301). Aquele desenho continua valendo para o que
este não muda: cofre, robô do eproc, fila, regras do tribunal e auditoria. As mudanças estão em "O que muda no desenho
de 30/10".

## Por quê

Hoje a pessoa digita cliente, número do processo e tribunal e monta o pacote arquivo por arquivo. Tudo isso já está na
petição e na pasta. O Eduardo quer **apontar uma pasta do Drive e o peticionamento acontecer a partir dela**, com volume
de 300 a 1.000 petições por mês. Digitação e montagem manual não sustentam esse volume.

## O fluxo

1. **A esteira prepara.** Quando o revisor aprova a peça, a esteira cria uma pasta só daquele protocolo, com os anexos
   numerados e a peça em **Word timbrado**.
2. **O advogado fecha.** Revisa, completa os campos em aberto e salva o PDF final nessa mesma pasta.
3. **Aponta no hub.** Em Protocolos, escolhe a pasta. O hub baixa os arquivos, lê a peça e monta o protocolo.
4. **Confere.** Vê os dados lidos e o pacote, corrige o que precisar e informa o prazo, se houver.
5. **Protocola.** Clique em Protocolar; o robô entra no eproc com o login do advogado, protocola e guarda o comprovante.

Pasta montada à mão, sem a esteira, segue o mesmo caminho a partir do passo 3. A esteira é uma origem da pasta, não uma
exigência do hub.

## Objetivos

- A pasta é a única entrada que a pessoa precisa dar; só o prazo é digitado.
- Funciona para petição **intermediária e inicial**.
- O que está na pasta é o que vai ao tribunal; o que não está, não vai.
- Um advogado sempre revisa a peça e clica para protocolar.

## Fora de escopo

- Editar a petição dentro do hub.
- Hub ou robô escolherem quais documentos do cliente anexar.
- Requerimento administrativo no INSS (`05 Requerimento`): não passa pelo eproc.
- Protocolo automático no TJSC e no TRT12 (seguem as Fases 3 e 4 do desenho de 30/10; até lá, ficam manuais com os dados
  já lidos).
- Buscar o prazo no ADVBOX ou lê-lo da peça.

## O que faria isto um fracasso

Valem os anti-objetivos do desenho de 30/10, e também:

- Protocolo no processo errado ou para o cliente errado porque a leitura errou e ninguém viu.
- Peça com campo em aberto ou com o bloco "CONTROLE INTERNO" chegando ao tribunal.
- Rascunho, `_originais` ou documento de outra pasta indo no pacote.
- A mesma pasta protocolada duas vezes.
- Dado lido com pouca certeza aparecendo como se fosse certo.

## Decisões do Eduardo

1. **Entrada:** a pessoa só aponta a pasta (02/11).
2. **Conteúdo da pasta:** só o protocolo: peça final e anexos numerados. Não é a pasta geral do cliente.
3. **Autonomia:** apontar, conferir e clicar já protocola; o robô faz parte da entrega.
4. **Peça final:** a esteira gera Word timbrado; o advogado revisa, completa e salva o PDF na pasta. O hub recusa pasta
   sem PDF ou com campo em aberto.
5. **Prazo:** digitado na conferência, opcional.
6. **Inicial no robô:** o robô começa pela intermediária; a inicial vem logo depois, sobre o robô já testado. Até lá, o
   hub lê a inicial e mostra os dados para protocolo manual.
7. **Lançamento:** a equipe só começa a usar quando pasta, robô e timbrado estiverem prontos **e a esteira instalada**.
8. **Login do protocolo:** o do **associado que assina**; o do Dr. Ramon só quando ele assina sozinho. A pessoa pode trocar
   o responsável na conferência. Advogado sem habilitação no processo: o robô para e avisa.
9. **Réplica:** passa a ter revisor; a pasta só nasce com `APROVADA`, como na petição nova.
10. **Aviso:** lista no hub, por advogado, das pastas prontas para revisar, com o sino para o responsável.
11. **Volume na largada:** a esteira fica como está (assinatura do Eduardo, 3 casos novos por dia). O lançamento espera o
    teste previsto (3 casos + uma réplica). O resto do volume vem de pastas montadas pelos advogados. Trocar a assinatura é
    projeto à parte.

## O que muda no desenho de 30/10

- **Inicial:** deixa de ser "sempre manual". Ela era manual porque o hub não tinha partes, classe, assuntos e valor da
  causa; agora eles vêm da leitura da peça.
- **Pacote pela pasta:** nova forma de criar a petição. A criação manual da Fase 1 continua existindo.
- **Arquivamento:** com pasta apontada, o comprovante e o número do evento ficam nessa mesma pasta, sem cópia para
  `Protocolos\<data> — …`.

## Parte 1: leitura da pasta (hub)

### Regras da pasta *(minhas decisões)*

- **Ordem:** pelo número no início do nome (`01 Petição.pdf`, `02 Procuração.pdf`).
- **Peça principal:** o PDF de menor número. O hub confirma pela leitura; se aquele arquivo não parecer uma petição,
  avisa e exige que a pessoa marque a principal.
- **Tipos de arquivo:** PDF entra; JPG e PNG viram PDF como hoje; o Word é ignorado se existe o PDF de mesmo número.
  Outro formato ou arquivo sem número no nome: o hub mostra o arquivo e trava até resolverem na pasta. Subpastas são
  ignoradas e citadas no aviso.
- **Recusa de cara:** pasta sem PDF principal; só Word; pasta que já pertence a outra petição (rascunho ou protocolada);
  peça com sobra de rascunho no texto, por **lista fechada** *(minha decisão: qualquer colchete recusaria `[...]` e `[sic]`,
  que são legítimos)*:
  - marcadores: `[CAMPO`, `[CONFERIR]`, `[NB]`, `[DIB]`, `[CPF]`, `[VALOR]`, `[DATA]`, `[OAB]`, `[NOME DA PARTE]`,
    `[ADVOGADO(A) ASSOCIADO(A)]`;
  - blocos da esteira: `CONTROLE INTERNO`, `RASCUNHO`, `Notas ao advogado`, `Conferência humana`,
    `O que esta minuta NÃO faz`.

  A lista inicial sai dos modelos e agentes atuais, é conferida contra eles na construção e fica em constante no código.
  `[CONFERIR]` recusa em vez de só alertar, porque marca citação não verificada. *(minha decisão)*
- **Limite de tamanho:** vale a regra atual por tribunal (`Peticao#problemas`).
- **Reler a pasta:** o hub trabalha com o que baixou ao apontar, e vai ao tribunal exatamente o que foi conferido. Se o
  advogado corrigir algo no Drive, usa o botão **Reler a pasta**, que refaz tudo. *(minha decisão)*

### O que é lido

| Dado | Intermediária | Inicial |
|---|---|---|
| Tipo da peça | sim | sim |
| Número do processo (com validação do dígito) | sim | não tem |
| Tribunal | pelo número, como hoje | pelo endereçamento da peça |
| Cliente | CPF ou nome, buscando no hub | idem |
| Advogado responsável | o associado da assinatura; Dr. Ramon se assina sozinho | idem |
| Descrição curta | título da peça | título da peça |
| Tipo de cada anexo | `sugerir_tipo` pelo nome, como hoje | idem |
| Partes (nome, CPF), classe, assuntos, valor da causa, competência | não | sim |

### Como é lido *(minhas decisões)*

- Pelo mesmo caminho do `DocMatchService`: `Ramon::LlmClient` com a chave da API e o PDF como anexo. Sem assinatura do
  Claude. Modelo e prompt ficam com quem construir.
- Saída estruturada, com indicação de certeza por campo. Na dúvida, o campo vem vazio. **Nunca chutar.**
- Falha da leitura não trava: a conferência abre com os campos vazios para a pessoa preencher e um aviso.
- Classe e assunto devem acabar escolhidos da lista do tribunal, porque a peça raramente os traz nos termos exatos.
  A leitura apenas sugere.

### Conferências cruzadas *(minhas decisões)*

Travam o botão até a pessoa corrigir ou confirmar o alerta explicitamente:

- CPF da peça diferente do CPF no nome da pasta `Clientes/<Nome — CPF>`, quando a pasta estiver ali dentro.
- Número do processo fora da lista do cliente no espelho do ADVBOX. Se o espelho estiver vazio, só avisa.
- Advogado que assina sem usuário no hub, ou sem credencial no cofre: não trava a conferência, mas só permite o
  protocolo manual.

### Lista de pastas prontas

Em Protocolos, cada advogado vê as pastas que a esteira deixou para ele revisar, e o sino do hub o avisa quando chega uma
nova. Admin vê todas, inclusive as sem responsável identificado. Abrir um item leva ao passo de apontar, já com a pasta
escolhida; a pasta montada à mão continua entrando pelo seletor do Drive. O item sai da lista quando vira petição.
A forma como o hub fica sabendo da pasta nova (chamada da esteira ou leitura do Drive) fica com quem construir: vale a que
tiver menos peças, sem expor rota pública sem autenticação.

### Conferência (tela)

Dados lidos, com os incertos destacados; pacote numerado com o tipo de cada arquivo; prazo; atalho para abrir a peça.
Depois, a "Etapa 1 — conferir no tribunal" do desenho de 30/10 mostra classe e partes do processo real antes do clique.

### Quem pode

Admin ou time `advogados`, como hoje. Clique em Protocolar: responsável ou admin, como hoje, e o protocolo sai no login
do responsável. *(minha decisão: admin pode clicar, mas nunca cadastra a credencial alheia)*

### Depois do protocolo

`drive_pasta_id` passa a ser a pasta apontada e os arquivos guardam o `drive_file_id` de origem. Assim o
`PeticaoArquivarJob`, sem subir cópia, só acrescenta o comprovante e apaga os PDFs do disco do hub. *(minha decisão)*

## Parte 2: cofre e robô do eproc

Segue o desenho de 30/10 (Fase 2): contêiner `protocolador`, TOTP por advogado, etapa de conferir, fila, comprovante,
conferência de juntada, parada em erro de credencial.

**Ordem:**
1. Cofre e intermediária no TRF4/JFSC.
2. Inicial no TRF4/JFSC, com os dados da leitura.

**Dependências do Eduardo:** sessão logado no eproc para mapear as telas, e a credencial de um advogado para o primeiro
teste. Os rótulos de `Tribunais::ROTULOS` são aproximados e precisam ser conferidos na tela real.

## Parte 3: Word timbrado e pasta (esteira)

Repositório `juridico\projetos\esteira-agentes`.

- **Quando:** só com o revisor em `APROVADA`, nas rotas judiciais (`05 Petição` e `R2` da réplica). Reprovada duas
  vezes: não cria a pasta, e o caso termina como já termina hoje. A pasta nasce **antes** do pedido de permissão do
  ADVBOX, para o Eduardo não virar gargalo.
- **Revisor na réplica:** a rota da réplica passa a chamar o `esteira-revisor` depois do `R2`, com a mesma volta única de
  correção; ele precisa aprender a ler o `R2`, e o aviso "ninguém revisa depois de você" sai do `esteira-replica`.
- **Dono do caso:** o responsável da tarefa do ADVBOX que abriu o caso preenche o associado no Word e na lista do hub.
  Sem responsável: `[ADVOGADO(A) ASSOCIADO(A)]` fica em aberto, e o item aparece para os admins como "sem responsável".
  *(minha decisão; a réplica não vem de tarefa, então busca o responsável pelo processo do cliente)*
- **Pasta:** `Clientes/<Nome — CPF>/Protocolos/<AAAA-MM-DD> — <título>/`. *(minha decisão)*
- **Conteúdo:** `01 <título>.docx` timbrado, com os `[CAMPO: …]` destacados e **sem** o bloco de controle interno, que
  continua em `Esteira/`; anexos numerados na ordem da peça, copiados da pasta do cliente.
- **Gerador:** aproveita `gerar_peca_branded.py` e `timbrado.docx` do plugin jurídico, por script root-owned em
  `/opt/esteira/bin`, no padrão do `pasta.py`. A sessão da esteira continua sem Python liberado. *(minha decisão)*
- **Pastas alheias:** a Recepção e a vigília passam a ignorar `Protocolos/`, para não reorganizar a pasta nem tomar PDF
  dela como contestação nova.
- **Aviso:** pela lista e pelo sino do hub (ver Parte 1), não pelo ntfy.
- **Correção de brinde nos pushes atuais:** `vigilia.py` e `hooks/ntfy.sh` hoje põem o nome do cliente no título, contra a
  regra do ntfy público. Passam a usar só o número do caso. *(minha decisão: é pouca coisa, e a instalação ainda não
  aconteceu)*
- **Saída do agente:** o `.md` continua sendo a saída; o Word é gerado a partir dele.

## Lançamento

Antes de a equipe usar:

- Smoke N (Fase 1) aprovado, porque o fluxo novo se apoia nele.
- Esteira instalada na VPS: Eduardo faz os passos 1–6 do roteiro `comercial\docs\2026-10-31-roteiro-instalacao-esteira.md`;
  depois, a Task 7 em conjunto.
- Teste da esteira concluído (3 casos + uma réplica), com a peça aprovada pelo Eduardo.
- Cofre com a credencial de ao menos um advogado.
- Primeiros protocolos em volume baixo, com **100% dos comprovantes conferidos à mão** (regra da Fase 2).

**Na largada:** robô só no TRF4/JFSC e só intermediária. Iniciais (a maior parte do que a esteira redige) e demais
tribunais usam a leitura da pasta, com o protocolo à mão até a etapa seguinte. Na esteira, são no máximo 3 casos novos por
dia, e a réplica é a única peça dela que o robô faz desde o primeiro dia.

## Fica com quem construir

Modelo e prompt da leitura; extração do texto do PDF para as recusas; modelo de dados dos campos da inicial; desenho da
tela, seguindo o visual do hub; divisão em PRs; nome exato do script e dos arquivos na esteira.

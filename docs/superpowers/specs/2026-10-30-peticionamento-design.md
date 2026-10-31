# Peticionamento no hub — desenho

Data: 30/10/2026 · Pedido do Eduardo · Status: rascunho para aprovação (escrito sem rodada de perguntas, a pedido dele:
"pula as perguntas e escreve a spec direto"). Pesquisas que sustentam este desenho:
`comercial\docs\2026-10-30-pesquisa-peticionamento-mni.md` (fontes oficiais) e
`comercial\docs\2026-10-30-pesquisa-peticionamento-concorrentes.md` (mercado).

## Por quê

O Eduardo quer protocolar petições **de dentro do hub**, no estilo do Legis (legishub.com.br/peticionamento):
o time não abre o eproc nem o PJe. O hub já é o centro do escritório (CRM, atendimento, painel do cliente) e já guarda
a pasta de cada cliente no Google Drive (ADR-0002). Falta o último passo: pegar os documentos da pasta, montar a
petição e protocolar. Volume: **300 a 1.000 petições por mês** (resposta do Eduardo, 30/10). Começa pelo **Sul**:
previdenciário, cível e trabalhista.

## O que os tribunais exigem (resumo das pesquisas)

| Área | Tribunal | Sistema | Como se assina | 2FA | Arquivo |
|---|---|---|---|---|---|
| Previdenciário | TRF4, JFSC (JEF e vara) | eproc | **login + senha valem como assinatura** (Lei 11.419, art. 1º §2º III b); sem certificado | **obrigatório** (código de app, TOTP) desde 22/04/2024 | limite na tela do sistema |
| Cível (e acidentário estadual) | TJSC | eproc (mesmo sistema) | login + senha; certificado opcional | obrigatório para advogado desde 2025 | **PDF até 11 MB**; acima disso, dividir |
| Trabalhista | TRT12 | PJe-JT | **certificado ICP-Brasil (A1 ou A3)** + assinador | login só pela PDPJ; MFA obrigatório desde 03/11/2025 | **PDF/A**; 3 MB por arquivo (ato de 2017, a confirmar) |

- **Via oficial de máquina (MNI): descartada (Eduardo, 31/10/2026).** No TRF4 o acesso institucional exige convênio,
  que a Res. TRF4 17/2010 (art. 58) só prevê para órgão público; TJSC e PJe-JT só oferecem MNI a órgão público
  conveniado; a API do PDPJ/Jus.br é para tribunais. Nenhuma lawtech protocola por MNI. Pesquisa:
  `comercial\docs\2026-10-31-pesquisa-mni-acesso-escritorio.md`.
- **Como o mercado faz:** Legis, Intima.ai, Oystr e PeticionaMais protocolam com **robô usando as credenciais do
  advogado** (login, senha, semente do 2FA e, no PJe, o A1). Só a Intima.ai tem API de protocolo documentada.
- **A1 está acabando:** o ITI extingue o A1 até 02/03/2029 (Res. CG ICP-Brasil 211/2024). O substituto que roda em
  servidor é o **A3 em nuvem** (API padrão DOC-ICP-17.01, OAuth, sessão de até 7 dias). **A3 em token/cartão não
  roda em servidor.** Os advogados da banca usam hoje A1 e A3 em token (resposta do Eduardo, 30/10).

**Consequência que define o desenho:** previdenciário e cível no Sul = **um sistema só (eproc), sem certificado**.
O trabalhista (PJe) é o caso difícil e fica por último.

## Decisões deste desenho

1. **O hub é a esteira; quem aperta o botão no tribunal é um "executor" trocável.** A esteira (pacote, regras de
   arquivo, aprovação, fila, comprovante, auditoria) é igual para qualquer executor. Executores previstos:
   - **Manual** (Fase 1): o advogado protocola no tribunal com o pacote pronto que o hub montou e registra o protocolo
     no hub. Funciona hoje, sem credencial nenhuma.
   - **Robô eproc** (Fase 2): navegador automático, com login, senha e 2FA do advogado tirados do cofre. Cobre TRF4,
     JFSC e TJSC de uma vez.
   - **API contratada** (Fase 4, TRT12): Intima.ai ou Legis, cotados antes. Construir robô de PJe fica para depois.
2. **Drive, não Dropbox.** A pasta do cliente já vive no Drive (`Clientes\<Nome — CPF>`), o hub já fala com ele
   (`Ramon::DriveClient`) e o escritório é Google. O hub **lê** os documentos da pasta e **grava** o pacote e o
   comprovante numa subpasta `Protocolos\<data> — <processo> (#id)`. *(minha decisão)*
3. **Cofre dentro do hub, com a criptografia nativa do Rails** (Active Record Encryption), que já está ligada na VPS
   e já guarda o 2FA dos usuários e os tokens da Agenda. Sem Vault/Infisical: um serviço a mais para manter não
   compra segurança que a VPS única já não tenha. *(minha decisão)*
4. **Ninguém protocola sem o clique de uma pessoa.** O princípio de aprovação do estatuto vale aqui ao pé da letra:
   o hub monta e confere; o protocolo só sai quando o **advogado responsável ou um administrador** clica
   **Protocolar** (executor automático) ou registra que protocolou (executor manual). Nada é protocolado por IA, fluxo
   ou agendamento sozinho. *(minha decisão: o "aprovado do Eduardo" do estatuto é sobre o que o Claude produz; aqui
   quem protocola é gente do escritório, e o clique dela é a aprovação. O Eduardo é admin e pode tudo.)*
5. **Escopo do primeiro plano = Fase 1.** A Fase 2 depende de mapear as telas do eproc com o Eduardo logado e da
   resposta do TRF4; o cofre e a fila entram no plano dela. Este documento já fixa o desenho dos dois para que a
   Fase 1 não feche portas.

## Glossário

Termos (petição, pacote, peça principal, tipo genérico, regra do tribunal, protocolo, comprovante, executor, cofre)
em `GLOSSARY.md` na raiz. Decisão de arquitetura em `docs/adr/0010-peticionamento-esteira-no-hub-executor-trocavel.md`.

## Como funciona

### 1. Criar a petição

- **Onde:** uma aba nova **Protocolos** no grupo *Clientes* do menu (lista + "Nova petição"). Quem usa:
  administradores e membros do time nativo **`advogados`** (já existia no hub) (mesmo padrão de `Ramon::Papeis`: time do Chatwoot, sem
  tabela própria); os demais veem "sem acesso". Botão **Peticionar** na ficha do cliente fica para depois da Fase 1.
  *(minha decisão)*
- **Campos:**
  - **Cliente** (contato do hub) — opcional, mas é ele que liga a pasta do Drive.
  - **Número do processo** no padrão CNJ (`NNNNNNN-DD.AAAA.J.TR.OOOO`), com validação do dígito verificador. Ao
    escolher o cliente, o hub sugere os números que já conhece pelo espelho do ADVBOX (`PortalCliente#processos`).
    Petição **inicial** não tem número: escolhe-se o tribunal na mão. **A inicial fica sempre no executor manual**
    nesta fase e na Fase 2: distribuir pede partes, classe, assuntos e valor da causa, que o hub não estrutura. O robô
    da Fase 2 faz só petição intermediária. *(minha decisão)*
  - **Tribunal**, deduzido do número: `J=4, TR=04` → TRF4 (origem `72xx` = JFSC); `J=8, TR=24` → TJSC;
    `J=5, TR=12` → TRT12. Fora disso, a petição fica só com o executor manual.
  - **Advogado responsável** (usuário do hub) — padrão: quem criou.
  - **Prazo** (data, opcional). A lista ordena por prazo e destaca o que vence em até 2 dias úteis.
  - **Descrição curta** (ex.: "Juntada de CNIS atualizado").

### 2. Montar o pacote

- **Peça principal:** upload do PDF final (vem do Word/Docs do advogado ou do plugin jurídico).
- **Anexos:** escolher arquivos **do Drive** ou fazer upload do computador. O hub baixa do Drive para dentro do pacote
  no momento da escolha (o pacote não muda se a pasta mudar depois).
- **Seletor do Drive** — os documentos não vivem num lugar só: a pasta do hub é `Clientes\<Nome — CPF>`, a skill
  `organizar-documentos-cliente` usa `<Nome>` com subpasta `~<Tese> – MM.AA`, e procuração/contrato ficam em
  `Documentação Leads\<Nome>`. Por isso o seletor *(minhas decisões)*:
  - abre na pasta do cliente quando o hub a conhece (`drive.pasta_id` do lead ganho);
  - **navega** pastas (entrar em subpasta, voltar até a raiz configurada `RAMON_DRIVE_ROOT_ID`);
  - tem **busca por nome** (pasta ou arquivo) em todo o Drive que a conta do escritório enxerga — é assim que se acha
    o cliente antigo ou a pasta `Documentação Leads`;
  - mostra só PDF e imagem.
  Cliente antigo cujo documento só está no ADVBOX: baixa de lá e sobe pelo upload. ADVBOX como fonte direta fica fora
  desta versão.
- **Tipo** de cada arquivo: escolhido numa lista curta de tipos genéricos; o hub sugere pelo nome do arquivo
  (o padrão `NN.N Nome` da skill `organizar-documentos-cliente` ajuda). *(sugestão por nome é minha decisão; IA fica
  para depois)*
- **Conferência automática** (antes de liberar o protocolo):
  - todo arquivo é PDF (imagem jpg/png vira PDF, como o `DriveExportService` já faz);
  - nenhum arquivo passa do limite do tribunal. **Fase 1: o hub avisa e trava** ("Laudo tem 14 MB; o limite do TJSC é
    11 MB — divida o PDF"). Dividir sozinho em partes ("Laudo — parte 1 de 2") entra quando o primeiro arquivo real
    travar, com a gem `combine_pdf` — sem Ruby local não dá para atualizar o `Gemfile.lock` com segurança nesta
    rodada. *(minha decisão)*
  - existe exatamente uma peça principal;
  - número do processo válido (dígito verificador).
  O que falhar aparece em vermelho e trava o botão.

### 3. Protocolar

**Executor manual (Fase 1):**
- O hub mostra o pacote pronto: arquivos renomeados na ordem (`01 Petição.pdf`, `02 Procuração.pdf`…), com o tipo
  que o advogado deve escolher no eproc ao lado de cada um, e um botão **Baixar todos** (baixa um a um, já com o nome
  numerado; sem zip, para não pôr gem nova). *(minha decisão)*
- O advogado protocola no tribunal e volta ao hub: **Registrar protocolo** com o número do evento e o comprovante
  (PDF ou print). O hub salva o comprovante na pasta do cliente no Drive e marca a petição como protocolada.

**Executor automático (Fase 2+):**
- **Etapa 1 — conferir o processo:** ao clicar **Conferir no tribunal**, o executor entra no processo e devolve
  **classe, partes e tipos de documento disponíveis**. O advogado vê na tela e confere que é o processo certo.
  (Ideia da Intima.ai: evita protocolo no processo errado.)
- **Etapa 2 — protocolar:** o advogado clica **Protocolar**. A petição entra na fila; o executor envia, guarda o
  número do evento e o comprovante, e **confere depois que o documento foi juntado** (reconsulta o processo).
- **Fila:** status `rascunho → pronta → na_fila → enviando → protocolada` ou `erro`/`tribunal_fora`. Tribunal fora
  do ar → nova tentativa a cada 15 min por até 6 h, e alerta ao advogado se o prazo estiver em risco. Erro de
  credencial ou de tela → para e avisa (não insiste: 2FA errado repetido pode bloquear a conta).
- **Lote:** marcar várias petições prontas e clicar **Protocolar selecionadas** (mesmo advogado). Um clique aprova
  todas as marcadas.

### 4. Depois do protocolo

- **O Drive é a cópia definitiva.** Ao registrar o protocolo, o hub sobe **o pacote inteiro + o comprovante** para
  `Protocolos\<AAAA-MM-DD> — <processo ou "Inicial"> (#id)\` dentro da pasta do cliente (a pasta onde o seletor abriu; sem pasta
  conhecida, em `Protocolos sem cliente\` na raiz). Subiu tudo → o hub **apaga os arquivos do pacote** do próprio
  disco (Active Storage é disco local na VPS; 1.000 pacotes/mês encheriam o disco) e guarda só os IDs do Drive e o
  comprovante. Falhou a subida → mantém tudo e tenta de novo. *(minha decisão)*
- Tarefa no ADVBOX? **Não nesta versão** — o ADVBOX já recebe o andamento pelo tribunal. *(minha decisão)*
- Nada é mandado ao cliente automaticamente (texto ao cliente é gate do Eduardo).

### 5. Auditoria

- A petição é `audited` (trilha só-inclusão que o hub já usa e que aparece no **Registro de ações**): quem criou,
  quem mudou o pacote, quem aprovou o protocolo, quando, qual executor, resultado.
- O executor automático guarda o **print da tela final** junto do comprovante.

## O cofre

**O que guarda, por advogado (usuário do hub):**
- **eproc** (um registro por sistema: `eproc_trf4`, `eproc_tjsc`): usuário, senha e **semente do 2FA** (a chave que
  o app autenticador recebe no QR code).
- **Certificado A1** (`.pfx`) + senha, com a data de vencimento lida do próprio arquivo — só quando o PJe entrar e
  se o executor escolhido precisar.

**Regras:**
- Cifrado com `encrypts` (Active Record Encryption, chaves no `chatwoot.env` da VPS, fora do banco). Backup do banco
  sozinho não abre o cofre.
- **Só escrita pela tela:** o advogado cadastra e troca; ninguém (nem admin) vê o valor de volta. A tela mostra só
  "cadastrado em …, por …".
- **O dono da credencial é um usuário do hub.** Quem protocola no login de um advogado precisa que esse advogado
  tenha usuário no hub (mesmo que só para isso — ex.: Dr. Ramon, se a maior parte sair no login dele). Cada um
  cadastra a própria credencial; quem não usa o hub pode cadastrar numa sessão com o Eduardo ao lado. Admin não
  cadastra credencial de outra pessoa. *(minha decisão)*
- **Lote** = petições prontas **do mesmo dono de credencial** (o protocolo sai no login dele).
- Cadastrar ou trocar exige que o usuário tenha **2FA do hub ligado** (o 2FA nativo do Chatwoot que já existe) e
  pede o código do 2FA do hub na hora.
- Quem lê o segredo decifrado: só o job do executor, no momento do protocolo. Cada leitura fica registrada
  (quem disparou, qual petição).
- **Alerta de vencimento** do A1: 30 e 7 dias antes, no sino do hub.
- **Apagar** a credencial: o próprio advogado ou admin (para desligamento de funcionário).

**Risco que o Eduardo precisa aceitar (honesto):** guardar a **semente do 2FA** junto com a senha faz o hub ter os
dois fatores. Quem invadir a VPS e pegar as chaves do `chatwoot.env` protocola em nome do advogado. É o que todo o
mercado faz (Intima.ai e Promad guardam a semente) e é o que permite fila e lote. Mitigações: chaves fora do banco,
2FA obrigatório no hub para quem aprova, auditoria de cada uso, VPS só com ssh por chave. Alternativa mais segura e
mais chata: o advogado digita o código do 2FA do tribunal a cada **Protocolar** (vale 30 s; um lote usa uma sessão).
**Recomendo guardar a semente**; a alternativa fica registrada caso ele prefira.

## Fases

| Fase | O que entra | Depende de |
|---|---|---|
| **0 — Eduardo, sem código** | Cotar Intima.ai e Legis para o TRT12. Usuários dos advogados criados no hub e no time `advogados` (feito em 31/10). | — |
| **1 — Esteira + executor manual** | Tela Protocolos, petição, pacote (upload + Drive), conferência de limite (avisa e trava; sem divisão nem zip), registrar protocolo, comprovante no Drive, auditoria. | nada |
| **2 — Cofre + robô eproc (TRF4/JFSC)** | Cofre (eproc), etapa "conferir no tribunal", protocolo automático, fila, comprovante, conferência de juntada. Começa com volume baixo e 100% dos comprovantes conferidos à mão. | sessão com o Eduardo logado no eproc para mapear as telas; credencial de um advogado |
| **3 — TJSC** | Mesmo robô, outro endereço e a regra de 11 MB. | Fase 2 estável |
| **4 — TRT12 (PJe)** | Executor por API contratada (PDF/A e assinatura ficam com o fornecedor). A1 no cofre se o fornecedor pedir. | cotação e contrato |

## Técnico (para quem for construir)

- **Modelos:** `Peticao` (tabela `ramon_peticoes`: account, contato opcional, lead opcional, criador, responsável,
  `numero_processo`, `tribunal`, `inicial` bool, `prazo`, `descricao`, `status`, `executor`, `numero_evento`,
  `protocolada_em`, `drive_pasta_id`, `resultado` jsonb) com `audited`; `PeticaoArquivo` (tabela
  `ramon_peticao_arquivos`: peticao, `tipo`, `posicao`, `principal` bool, `origem` (`upload`/`drive`),
  `drive_file_id`, Active Storage `file`). Comprovante = Active Storage na própria `Peticao`.
- **Regras do tribunal:** uma constante Ruby (`Ramon::Peticionamento::Tribunais`) com sistema, limite por arquivo,
  formato e a tabela DE/PARA de tipos. Sem tela de configuração (muda raramente; muda por PR).
- **Tribunal pelo número CNJ:** função pura, com o dígito verificador (módulo 97, Res. CNJ 65/2008).
- **Divisão de PDF (depois da Fase 1):** gem `combine_pdf` (MIT, Ruby puro) — divide por páginas até caber no
  limite. Compressão (ghostscript) fica de fora até um arquivo real não caber nem dividido. PDF/A não entra (Fase 4 é
  do fornecedor).
- **Drive:** `Ramon::DriveClient` ganha `children(parent_id)` (pastas + PDF/imagem), `search(texto)` (nome contém,
  em todo o Drive da conta), `parent_of(id)` e `download(file_id)`. A pasta inicial vem de
  `custom_attributes['drive']['pasta_id']` do lead ganho; senão abre na raiz. Upload do pacote final reaproveita
  `ensure_folder` e `upload`.
- **Executor (Fase 2):** contêiner próprio na VPS (`protocolador`, Python + Playwright, no padrão do `motor`), só na
  rede interna do docker. Sem estado: recebe do job do hub as credenciais decifradas, os arquivos e a instrução;
  devolve JSON com resultado, número do evento, comprovante e print. Gera o código TOTP na hora a partir da semente.
  O hub nunca expõe essa rota para fora.
- **Cofre (Fase 2):** `CredencialTribunal` (tabela `ramon_credenciais_tribunal`: user, account, `sistema`,
  `usuario`, `senha`, `totp_semente`, `pfx` (binário cifrado), `pfx_senha`, `vence_em`), com `encrypts` em tudo que
  é segredo. Sem `Chatwoot.encryption_configured?` o cofre se recusa a salvar (diferente dos canais, que caem para
  texto puro).
- **Permissão:** controller sob `api/v1/accounts/ramon_peticoes`; admin ou time `advogados`. Credencial: só o próprio
  usuário cria/troca.

## Fora de escopo (por enquanto)

- Dropbox.
- Gerar a petição com IA dentro do hub (o plugin jurídico já redige; aqui entra o PDF final).
- Habilitação em processos e substabelecimento.
- e-SAJ, Projudi, TJPR, TJRS, tribunais superiores.
- Intimações/prazos lidos do tribunal (o ADVBOX já faz).
- Mandar mensagem ao cliente sobre o protocolo.

## Anti-objetivos (o que faria isto um fracasso mesmo funcionando)

- Protocolo saindo sem o clique de um advogado.
- Senha ou semente aparecendo em log, tela, e-mail ou erro do Sentry.
- Robô insistindo em login errado até bloquear a conta do advogado no tribunal.
- Petição dada como "protocolada" sem comprovante.

## Decisões revisadas (Eduardo aprovou as 12 em 31/10/2026)

1. Drive em vez de Dropbox.
2. Cofre no próprio hub (criptografia do Rails), sem serviço de cofre separado.
3. **Guardar a semente do 2FA** (com o risco escrito acima) em vez de digitar o código a cada protocolo.
4. Time nativo `advogados` (já existia no hub, vazio) define quem vê Protocolos — em vez de criar um `juridico` igual.
5. Cada advogado cadastra só a própria credencial.
6. Sem tarefa no ADVBOX depois do protocolo.
7. Ordem das fases: esteira manual antes do robô — entrega valor já e o robô entra em cima dela.
8. TRT12 por API contratada, não robô próprio.
9. Quem protocola/registra: advogado responsável ou admin (não só o Eduardo).
10. Inicial fica no manual; robô só intermediária.
11. Drive guarda o pacote definitivo; o hub apaga os arquivos do próprio disco depois de subir.
12. Seletor do Drive navega e busca em todo o Drive do escritório (os documentos estão em três lugares diferentes).

**Respostas do Eduardo (31/10/2026):**
- As petições saem **no login de cada advogado** → cada advogado tem usuário no hub e cadastra a própria credencial no
  cofre; o lote é sempre de um dono só.
- A pasta `Documentação Leads` **está dentro da raiz** que o hub enxerga → o seletor chega nela navegando.

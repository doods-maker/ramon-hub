# Etapa Documentos e agente de documentos — desenho

Data: 07/11/2026 · Status: **aprovado pelo Eduardo em 07/11**, com 3 ajustes dele (acompanhamento
do SDR antes do travado, aviso ao desmarcar depois do Jurídico, fim da tarefa "1º contato")

Desenho da conversa de 07/11 com o Eduardo, aberta durante o smoke V (Drive por caso).
Pesquisas de apoio, em `comercial\docs\` (fora deste repo, que é público):
- `2026-11-07-pesquisa-govbr-meu-inss.md` — conta gov.br, duas etapas, caminho de cada documento;
- `2026-11-07-pesquisa-whatsapp-janelas.md` — janela de 24 h, janela grátis de anúncio, preço, categoria.

## Por que

Hoje, mover o lead para Ganho cria cliente, caso e a tarefa "1º CONTATO COM O LEAD" no ADVBOX
(`Ramon::AdvboxClosingService`), e o caso para ali. A esteira de agentes de petição só começa
quando existe a tarefa **ANÁLISE DO CASO** (tipo ADVBOX 8745386); o desenho da esteira supõe que
o hub a cria, mas o hub não cria. E ninguém conduz o cliente até a pasta ficar completa: a IA de
vendas foi treinada para qualificar e fechar, e o grosso dos documentos que faltam sai do
**Meu INSS**, que pede conta gov.br e, às vezes, desligar as duas etapas ou um código na hora.

O que o Eduardo quer: depois do contrato, o caso fica numa etapa de documentos com uma IA
**específica e treinada**, que tenta resolver sozinha (inclusive mandando as fotos do passo a
passo) e chama uma pessoa do comercial quando o cliente trava. Só com contrato **e** documentos
completos o caso vai para os agentes do jurídico, e de lá para o advogado revisar.

## O fluxo, de ponta a ponta

1. **Antes do contrato (como hoje).** A IA de vendas qualifica e fecha. O lead costuma mandar por
   conta própria atestados, laudos, receitas e fotos; a IA lê e marca no checklist (PR #274). Para
   fechar, o vendedor pede **RG/CPF e comprovante de residência**, que o contrato exige.
2. **Contrato assinado → etapa Documentos.** O lead entra na etapa de ganho **Documentos**. Quem
   responde o cliente passa a ser o **agente de documentos**. Ele começa do que já chegou e pede
   só o que falta.
3. **Cobrança com relógio**, em horas, calculando a janela do WhatsApp a cada envio.
4. **Gatilhos de humano**: o cliente trava → **SDR do lead**; SDR indisponível → **closer do lead**.
5. **Checklist completo → etapa Jurídico**, tarefa ANÁLISE DO CASO no ADVBOX, esteira faz análise
   e petição em rascunho, advogado revisa e protocola pela tela Protocolos.

## Decisões do Eduardo (07/11)

- O gatilho do jurídico é **Ganho + documentos completos**, nunca o Ganho sozinho.
- Faltando documento, o lead fica na **etapa Documentos**, com um **agente de IA próprio**,
  separado do de vendas, para ser específico e bem treinado.
- **Documentos e Jurídico são etapas reais no funil** (colunas do Kanban), não estado derivado.
  Isso revoga em parte o ADR 0001 (ver seção 1).
- A **troca de agente é do hub**, automática, na assinatura. A IA não decide passar a conversa.
- **Quem marca o documento: a IA marca direto** como recebido, e **avisa o SDR / closer /
  responsável do comercial para verificar**. Revoga, para a etapa Documentos, a decisão de 18/10
  (lead ganho só ganhava sugestão).
- **A IA pode pedir a senha gov.br** ao cliente (seção 4). O código das duas etapas vai para uma
  pessoa.
- Quem assume quando o cliente trava: **o SDR; se ele não estiver, o closer.**
- Silêncio do cliente **vira chamado para o SDR**, com cobrança em **horas**, sempre calculando a
  janela.
- Cobrança fora da janela de 24 h vai por **modelo aprovado pela Meta**, a ser criado.
- **Só teses previdenciárias** entram em Documentos → Jurídico → ANÁLISE DO CASO no começo.
  Trabalhista e isenção de IR seguem com as pessoas.
- Documentos antes da assinatura continuam com a IA de vendas.
- O CNIS que vale é o **completo, com remunerações**.
- O passo a passo vem das **fotos do Eduardo** mais a **pesquisa no site oficial**.

## As partes

### 1. Etapas do funil (revoga em parte o ADR 0001)

Hoje `LeadStage#ensure_single_won_lost` só permite **uma** etapa `is_won` por conta, e o ADR 0001
decidiu que o lead ganho fica para sempre em "Fechado", com o pós-venda como estado derivado. O
Eduardo escolheu etapas reais. Então:

- **Liberar várias etapas de ganho** (`is_won`) por conta; perdido continua único.
- **Etapas novas, depois de "Fechado":** **Documentos** e **Jurídico**, ambas `is_won`.
  `Lead#apply_stage_timestamps` já preserva `won_at` entre etapas de ganho, então andar entre elas
  **não** dispara de novo a cascata do Ganho (dossiê, ADVBOX, NPS), porque `won_at` não muda.
- **Revisar todo código que procura "a" etapa de ganho** (`find_by(is_won: true)` e parecidos):
  `Ramon::AdvboxEventRegras`, regras do funil, importação CSV, `Ramon::Fluxos::Migracao`, funil e
  Kanban do dashboard, views de BI (`bi_leads_v0x`), Painel do Time, métricas de conversão. Regra
  para cada um: "entrar no ganho" = entrar em **Documentos** (a primeira etapa de ganho, por
  `position`); "está ganho" = qualquer etapa `is_won`.
- **Leads já ganhos** ficam em **Fechado**, como estão. Fechado continua etapa de ganho, mas nada
  novo cai nela, e o agente de documentos e a cobrança **não** olham para ela. *(Decisão do
  Claude: evita cobrar cliente antigo.)* Ligado o recurso, o Ganho passa a levar para Documentos.
- **Tese não previdenciária, ou lead sem tese ou sem checklist:** ao ganhar, vai para **Fechado**,
  como hoje, e fica com as pessoas. *(Decisão do Claude.)*
- **ADR novo** registrando a revogação parcial do 0001 e o porquê (o Eduardo quer ver Documentos e
  Jurídico como colunas, e o agente é escolhido pela etapa).

### 2. Qual IA responde: escolha pela etapa

- Hoje o assistente vem de `inbox.captain_assistant`
  (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb`). Passa a vir
  de um ponto único: lead da conversa numa etapa com assistente próprio → esse assistente; senão,
  o da caixa, como hoje.
- A ligação etapa → assistente é configuração na tela, não fixa no código.
- Todos os pontos que leem `inbox.captain_assistant` no atendimento passam por esse ponto único:
  resposta, handoff, aviso de handoff, limite de cota, atraso do piloto,
  `captain_handling_conversation?`. Quem constrói lista esses pontos antes.
- **Perfil da IA:** hoje `Ramon::PerfilIa#estado` devolve `:fechado` para qualquer etapa de ganho
  ("pós-venda é das pessoas: só rascunho"), e a tela "Como a IA atende" só mostra etapas abertas.
  A etapa **Documentos** é a exceção: entra na tela com permissões e gatilhos próprios, e o agente
  **envia sozinho** (decisão do Eduardo: o agente tenta resolver e só passa a uma pessoa quando não
  consegue). Fechado e Jurídico continuam `:fechado`.
- Ao entrar em Documentos, a conversa do lead volta para **pendente**, porque o assistente só
  responde conversa pendente.
- Não usar os "cenários" do Captain, em que a própria IA decide trocar de agente.

### 3. O agente de documentos

Um assistente do Captain separado, **"Documentos"**, com instruções e ferramentas próprias.

**O que ele sabe**
- O que falta vem do **checklist da tese** (`thesis_items` com `section: 'documento'` +
  `custom_attributes.doc_status`). Não se duplica lista de documentos no prompt.
- O "como conseguir" de cada documento, da pesquisa (resumo abaixo), em texto curto revisado pelo
  Eduardo.
- O passo a passo do gov.br: criar conta, subir nível, duas etapas, recuperar senha.

**Resumo da pesquisa que entra no conhecimento dele** (fonte e ressalvas no arquivo da pesquisa)
- Para os documentos do Meu INSS desta lista, **nível bronze basta**.
- **CNIS:** Meu INSS → "Do que você precisa?" → "CNIS" → escolher sempre a opção com a palavra
  **"remunerações"** ("Relações Previdenciárias e Remunerações"; no app aparece como "Vínculos,
  contribuições e remunerações"). "Relações Previdenciárias" sozinho e "Ano Civil" não servem.
- **Decisão do INSS (concessão ou indeferimento):** "Consultar Pedidos" → "Detalhar".
- **Cópia do processo:** "Consultar Pedidos" → "Detalhar" → "Baixar Processo".
- **Resultado de perícia:** "Resultado de Benefício por Incapacidade", a partir das 21h do dia da
  perícia.
- **Laudo:** busca "Laudo médico" (incapacidade e BPC); nos demais, vem na cópia do processo.
- **CAT:** busca "Comunicação de acidente" → "Consultar CAT". Quem registra é a empresa; se ela não
  registrou, o trabalhador ou o sindicato podem registrar.
- **Duas etapas:** o código sai **só do app gov.br no celular do cliente** (não vai por SMS nem
  e-mail). Desligar só pelo app: "Segurança da conta" → "Verificação em duas etapas" →
  "Desabilitar". Quem entra de outro aparelho dispara e-mail de aviso ao cliente.
- **Lacunas sem fonte oficial** (nome de botão vindo de manual de prefeitura, desligar duas etapas
  pelo site, conta bloqueada): conferir com as fotos do Eduardo antes de ligar.

**O que ele faz**
- Ao entrar na etapa: apresenta-se e diz o que falta, em poucas mensagens, sem juridiquês.
- Manda as **imagens do passo a passo** quando o cliente precisa. Hoje o assistente não envia
  imagem: ferramenta nova, por exemplo `enviar_passo_a_passo(tema)`, que manda as imagens
  guardadas no hub para aquele tema.
- **Lê e marca direto** o que chega (seção 5).
- Pede a senha gov.br quando o cliente não consegue baixar sozinho (seção 4).
- Fecha quando o checklist completa (seção 7).

**O que ele nunca faz**
- Não fala de honorário, de chance de êxito nem de prazo do INSS. Não promete resultado.
- Não repete, cita nem confirma a senha na conversa.

**Imagens do passo a passo**
- Vêm das fotos do Eduardo, conferidas contra o site oficial. Nenhuma pode mostrar CPF, nome,
  telefone ou rosto: recortar ou refazer antes de subir.
- Guardadas no hub, por tema, com nome e ordem. O repositório é público: **não** vão para o git.

### 4. Senha gov.br (decisão do Eduardo: a IA pode pedir)

A senha é o dado mais sensível que passa pelo hub. O pedido é da IA, o uso é de uma pessoa.

- **Quando pedir:** depois que o passo a passo não resolveu, ou quando o cliente diz que não
  consegue baixar sozinho. Nunca na primeira mensagem.
- **Onde guardar:** campo **criptografado** no lead (Active Record Encryption, o mesmo do cofre do
  peticionamento), visível só para SDR, closer, time `advogados` e admin, com registro de quem viu
  no Registro de ações.
- **Fora do histórico:** quando a senha chega, o hub a tira da mensagem (o conteúdo vira "senha
  recebida 🔒") e ela **não volta ao modelo de IA** em turnos seguintes.
  *(Ponto a confirmar por quem constrói: a mensagem já foi entregue pelo webhook e gravada; o que
  se troca é o que o hub guarda e mostra. Se algum log ou o resumo da IA já a tiver capturado, isso
  precisa ser tratado no mesmo PR.)*
- **Depois de guardar:** a IA chama o SDR (gatilho `govbr_senha_recebida`), que entra no Meu INSS
  e baixa os documentos. Se o login pedir o código das duas etapas, é o gatilho `govbr_codigo`:
  pessoa online, porque o código expira.
- **Senha nas anotações do ADVBOX em texto aberto:** a skill `organizar-documentos-cliente` grava
  assim hoje. Este desenho **não** copia a senha para o ADVBOX. *(Decisão do Claude; o risco das
  senhas que já estão lá continua aberto, fora deste escopo.)*
- **Alternativa registrada, não implementada:** a pesquisa achou a procuração eletrônica gov.br no
  Meu INSS (desde nov/2025): o advogado entra com o próprio CPF e consulta os documentos do
  cliente, sem senha. Cliente e advogado precisam de nível prata ou ouro. Está no radar
  (`comercial\docs\2026-10-05-radar-procuracao-meu-inss.md`) por decisão do Eduardo de 05/10; fica anotada aqui como caminho
  para tirar a senha do fluxo no futuro.

### 5. Quem marca o documento (revoga 18/10 na etapa Documentos)

- Na etapa **Documentos**, `Ramon::DocMatchService#marcar_direto?` passa a valer também para lead
  ganho: a IA **marca recebido**, com o anexo. Fora dela, continua como está.
- **CNIS:** só marca se for o completo com remunerações. O resumido gera um pedido de novo, com o
  caminho certo.
- **Aviso para verificar:** a cada marcação feita pela IA, o **SDR do lead** recebe aviso no sino
  ("IA marcou <documento> de <lead>: verificar"); sem SDR, o **closer**; sem nenhum, os admins.
  Desmarcar na aba Documentos continua sendo o desfazer.
- **Consequência:** `docs_completos_em` passa a contar marcações da IA. Isso alimenta o Contrato
  limpo e a variável do SDR e do Closer. A ficha do `docs_completos` (seed) diz hoje que "só conta
  o que uma pessoa marcou": atualizar a ficha.
- Documento enviado pelo Painel do Cliente segue a mesma regra da conversa.

### 6. Gatilhos de humano

Mesmo mecanismo de hoje (`Ramon::PerfilIa::Gatilhos`: chave, nome na tela, linha de prompt; texto
`nil` = pendente de aprovação). Novos, ligados só no perfil da etapa Documentos:

| Chave (sugestão) | Quando |
|---|---|
| `govbr_senha_recebida` | O cliente mandou a senha: uma pessoa precisa entrar no Meu INSS. |
| `govbr_codigo` | O login pede o código das duas etapas, ou o cliente precisa mandar um código. |
| `govbr_sem_acesso` | O cliente não consegue criar a conta, subir o nível, entrar ou recuperar a senha. |
| `sem_documento` | O cliente diz que não tem o documento, ou que só a empresa ou o médico tem (laudo, CAT). |

Valem também os de hoje: `pediu_pessoa`, `irritado`, `juridica`. Dois são de relógio (seção 7):
**silêncio** e **travado**.

**No gatilho**
- A IA para de responder (pausa, como no handoff de hoje); a conversa vira **aberta** e vai para o
  **SDR do lead** (`leads.sdr_id`).
- **SDR indisponível** → **closer do lead** (`leads.closer_id`). *(Decisão do Claude:
  indisponível = sem SDR no lead ou SDR offline no hub. Se o status de disponibilidade não for
  confiável na operação, trocar por horário de trabalho.)*
- Aviso no sino e push; o texto do push **sem dado pessoal** (o ntfy é público): o lead aparece
  pela tese, como em `Ramon::NtfyPushJob.rotulo`.
- Nota privada na conversa com o gatilho e o que falta.
- Terminou, a pessoa devolve à IA pelo botão "Devolver à IA".

### 7. Cobrança e janelas

**Ritmo** *(proposta do Claude a partir do "em horas"; números em configuração)*

| Momento (horário comercial) | O que acontece |
|---|---|
| Entrou em Documentos | Apresentação + o que falta. |
| 3 h úteis sem resposta | Lembrete 1. |
| Manhã do dia útil seguinte, ainda sem resposta | Lembrete 2. |
| 4 h úteis depois do lembrete 2, sem resposta | **Gatilho silêncio → SDR.** |
| Cliente responde, mas 1 dia útil sem nenhum documento novo | **Aviso de acompanhamento ao SDR** (sino): "<lead> está em Documentos sem avanço hoje: faltam X". A IA continua atendendo; o SDR só confere se está andando. |
| Cliente responde, mas 2 dias úteis sem documento novo | **Gatilho travado → SDR assume.** |

- Horário comercial = a janela de horário que os fluxos já usam. A **cobrança** nunca sai fora
  dela; a **resposta** a um cliente que escreveu fora do horário segue a permissão
  `fora_do_horario` do perfil, como hoje.
- Resposta do cliente zera o relógio do silêncio.
- Teto: os dois lembretes e nada mais até uma pessoa agir.

**Janela, calculada a cada envio** (pesquisa de 07/11; os pontos marcados ⚠️ lá valem conferir
no navegador antes de virar código)
- **Permissão:** só a **janela de 24 h** decide. Ela abre e reabre com mensagem ou ligação do
  cliente. Dentro: texto livre. Fora: só **modelo aprovado**. Reaproveitar
  `Conversations::MessageWindowService`.
- **A "janela de 72 h" não dá permissão.** A janela grátis de anúncio (Click-to-WhatsApp, cliente
  no celular, escritório respondeu em 24 h) muda **só o preço** e, no modelo de cobrança atual, dura
  até 7 dias. Passadas 24 h sem o cliente escrever, mesmo dentro dela, só vai modelo, que sai de
  graça. Saber se está aberta: status de envio com `pricing.type = free_entry_point`, ou o objeto
  `conversation` com `expiration_timestamp`.
- **Preço (mudou em 01/10/2026):** modelo utility dentro da janela de 24 h voltou a ser cobrado;
  texto livre passa a ser cobrado depois de 1.000 mensagens/mês por número. Brasil, utility:
  US$ 0,0068 por mensagem (jul/2026). Custo pequeno, mas registrar o envio em Uso e custo.
- **Categoria do modelo:** **utility**, desde que puramente informativo ("faltam estes documentos
  para o seu processo"), sem nenhuma oferta. A Meta pode reclassificar depois (webhook
  `template_category_update`).
- **Risco real é bloqueio e denúncia:** derrubam a qualidade e pausam o modelo (3 h, 6 h, depois
  desativado). Daí o teto de dois lembretes.
- O texto do modelo é **gate do Eduardo**: rascunho → aprovação → submissão à Meta.
- Antes do número oficial, a caixa do escritório não tem modelo: a cobrança fora da janela fica
  desligada lá e vira gatilho silêncio direto.

**Onde roda** *(decisão do Claude)*: job recorrente do hub, como "regra fixa" (igual a
`docs_completos` e `sdr_automatico`), porque envia mensagem de verdade, e os fluxos visuais só
deixam rascunho.

### 8. Documentos completos → jurídico

Gancho: `leads.docs_completos_em` passa de nulo para preenchido
(`LeadComercial#stamp_docs_completos`) com o lead na etapa Documentos. Nesse momento:

1. O lead vai para a etapa **Jurídico**.
2. A pasta da tese ganha `— COMPLETO` (já é assim, `DriveExportService#concluir`).
3. O hub cria a tarefa **ANÁLISE DO CASO** (tipo 8745386) no caso do ADVBOX que o Ganho criou
   (`custom_attributes.advbox.lawsuits_id`), com o caminho da pasta da tese nas notas:
   `Clientes\<Nome — CPF>\<Tese> – MM.AA\`. Responsável: o Eduardo enquanto a esteira está em
   teste (ordem dele, 02/11).
4. O agente manda ao cliente a mensagem de encerramento (texto aprovado pelo Eduardo).
5. A IA sai da conversa.

**Idempotente:** uma tarefa por caso (id guardado no lead). Se o checklist voltar a ficar
incompleto (a pessoa desmarcou um documento da IA), o lead **não** volta para Documentos sozinho;
quem desmarcou decide. Mas **sempre avisa** (pedido do Eduardo, 07/11):
- sino para o SDR do lead (sem SDR, o closer) e para o responsável da tarefa ANÁLISE DO CASO:
  "<documento> foi desmarcado de <lead>, que já está no Jurídico: decidir se volta para Documentos";
- nota privada na conversa e linha no histórico do lead, com quem desmarcou;
- push sem dado pessoal, como os demais.
A tarefa no ADVBOX não é apagada nem alterada: a esteira pode já estar trabalhando no caso, e a
decisão é de uma pessoa.

**Ajuste na esteira** (repo `esteira-agentes`, fora deste PR): a Recepção lê a pasta indicada na
tarefa, com fallback para `Clientes\<Nome — CPF>\`. Sem isso, a esteira não vê a pasta da tese do
PR #318. A vigília está **desligada**: a tarefa espera até o Eduardo ligá-la.

### 9. ADVBOX no Ganho

- Continua: cliente + caso na etapa CONTRATO FECHADO (Marketing).
- **A tarefa "1º CONTATO COM O LEAD" (tipo 8745394) deixa de ser criada** para o lead que vai para
  Documentos: o primeiro contato agora é do agente (decisão do Eduardo, 07/11). A única tarefa do
  caso passa a ser a ANÁLISE DO CASO, na hora do completo. O lead que vai para Fechado (tese não
  previdenciária ou sem checklist) segue como hoje, com a tarefa, porque lá o contato continua
  sendo de uma pessoa. *(Esta separação é decisão do Claude.)*
- O Ganho pode estar rodando como fluxo visual (`Ramon::Fluxos::LeadGanho` →
  `Migracao.decidir('lead_ganho', ...)`): toda mudança no que o Ganho faz vale nos dois caminhos.

## Objetivos

- Contrato fechado de tese previdenciária sai do comercial para o jurídico **sozinho**, no
  instante em que a pasta fica completa.
- O cliente tem ajuda específica para o Meu INSS a qualquer hora e encontra uma pessoa quando
  precisa.
- O SDR só entra onde a IA não resolve, e confere o que a IA marcou.

## Fora do escopo

- Robô que entra no Meu INSS com a senha do cliente.
- Procuração eletrônica gov.br (fica no radar).
- Trabalhista e isenção de IR na etapa Documentos.
- Mudanças no fluxo de vendas antes do contrato.
- Ligar a vigília da esteira.
- Integração ZapSign → Ganho.
- Senhas que já estão nas anotações do ADVBOX.

## O que seria fracasso, mesmo funcionando

- Mensagem fora da janela sem modelo, ou cobrança de madrugada.
- Lembrete repetido depois de o cliente já ter mandado o documento.
- Cliente antigo (lead em Fechado) recebendo cobrança.
- Caso indo para o jurídico com CNIS resumido marcado como recebido.
- Senha gov.br aparecendo na conversa, no prompt, em log, no push ou no ADVBOX.
- Imagem do passo a passo com dado de alguém.
- SDR sem aviso no gatilho ou na marcação da IA.
- Tarefa ANÁLISE DO CASO duplicada.
- Métrica de conversão, BI ou ADVBOX quebrando por haver mais de uma etapa de ganho.

## Gates do Eduardo antes de ligar

- Instruções do agente de documentos e o texto "como conseguir" de cada documento.
- Linhas de prompt dos gatilhos novos.
- Apresentação, lembretes, pedido de senha e encerramento.
- Modelo de cobrança da Meta.
- Imagens do passo a passo, já recortadas.

## Deixado para quem constrói

- Nome técnico das chaves, colunas, jobs e da ferramenta de imagens.
- Como guardar as imagens por tema (fora do git).
- Como reconhecer "tese previdenciária" (`theses.area`: conferir os valores em produção).
- Fatiamento em PRs. Sugestão: (1) várias etapas de ganho + ADR; (2) escolha de assistente por
  etapa + perfil Documentos; (3) marcação direta + avisos + gatilhos; (4) senha criptografada;
  (5) cobrança e janelas; (6) completo → Jurídico + ANÁLISE DO CASO.

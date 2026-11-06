# Organização do Drive do escritório — desenho

Data: 06/11/2026 · Status: **aprovado pelo Eduardo em 06/11 (decisões no fim)**

Desenho aprovado na conversa de 06/11: **cliente primeiro, tese dentro do cliente**.
Descartamos a árvore por advogada (PROTOCOLIZAR > BRENDA > ADM > tese > lead):
caso troca de dono e de fase, e a fila "quem protocola o quê" já é a aba
Protocolos do hub (responsável + status).

## Conta e raiz

Meu Drive de `ramonantonio.comercial@gmail.com`, raiz `Documentos ADVBOX (hub)`
(`RAMON_DRIVE_ROOT_ID` = `17zh-_2biW1Zkj8x1p5xYIToWXKWQIWab`). Não muda.

## Árvore

```
Documentos ADVBOX (hub)\
├─ Clientes\
│  └─ <Nome> — <CPF>\
│     ├─ 00 Pessoais\                  grupos 03–05: identidade, residência, CNIS/CTPS
│     ├─ <Tese> – MM.AA\               um por caso (lead ganho)
│     │  ├─ 01.1-procuracao…, 02.1-contrato…, 06–10 (médicos, INSS, judicial, outros)
│     │  ├─ _originais\  _duplicados\
│     │  ├─ Esteira\                   (fase 2 — ver "Esteira")
│     │  └─ Protocolos\
│     │     └─ <AAAA-MM-DD> — <nº do processo | Inicial> (#id)\
│     └─ <Outra tese> – MM.AA\
├─ Documentação Leads - ARQUIVO\       absorvida nos clientes (decisão 3)
├─ A enviar ao ADVBOX\<data>\          atalhos do export (já existe no código)
├─ Protocolos sem cliente\             (já existe no código)
├─ Escritório\                         sem dado de cliente
│  ├─ Modelos de petição\<Tese>\
│  ├─ Contratos e procurações\
│  ├─ Requerimentos INSS\
│  └─ Banco de laudos\
├─ Digitalizados\<Pessoa>\             caixa de entrada do scanner; esvazia movendo p/ o cliente
└─ Arquivo\                            cliente encerrado: move a pasta inteira
```

## Regras

1. **Nome da pasta do cliente:** `<Nome> — <CPF>` (como o hub já cria). Sem CPF → só o nome.
2. **Nome da pasta da tese:** `<nome da tese no hub> – MM.AA`, MM.AA = mês do
   `won_at` do lead. Caracteres proibidos (`/\:*?"<>|`) saem do nome, então
   `BPC/LOAS` vira `BPCLOAS`. Some o `~` da skill. A lista de teses é a tabela
   `theses` do hub: tese nova se cadastra lá, nunca nasce no Drive.
3. **Contrato e procuração são do caso**, não do cliente: vão na pasta da tese (grupos 01–02).
   `00 Pessoais` guarda só o que serve para qualquer caso (03 identidade, 04 residência, 05 CNIS/CTPS).
4. **ADM ou Judicial não viram pasta.** A fase aparece no nome do protocolo (nº do processo ou `Inicial`).
5. **Por pessoa, só `Digitalizados`.** Fila de trabalho é filtro do hub, não pasta.
6. **`Escritório`, `Digitalizados` e `Arquivo` são criados à mão.** Nenhum código grava ali.

## Mudanças no hub

| # | Onde | Hoje | Passa a ser |
|---|---|---|---|
| H1 | `Ramon::DriveExportService` | sobe tudo solto em `Clientes\<cliente>\` | cria `<Tese> – MM.AA` (id salvo em `custom_attributes.drive.tese_pasta_id`) e sobe ali; item do checklist cujo título bate em `RG\|CPF\|CNH\|identidade\|resid[eê]ncia\|CNIS\|CTPS` vai para `00 Pessoais` |
| H2 | `DriveExportService#concluir` | renomeia a **pasta do cliente** para `… — COMPLETO` | renomeia a **pasta da tese**. Corrige também um defeito: a pasta do cliente renomeada faz o `ensure_folder` (busca por nome) criar uma pasta duplicada no 2º lead do mesmo cliente |
| H3 | `RamonPeticoesController#pasta_base` | `drive.pasta_id` do último lead ganho → `Protocolos` na pasta do cliente | `drive.tese_pasta_id` desse lead; se faltar, `pasta_id`; se faltar, `Protocolos sem cliente` (como hoje) |
| H4 | `peticao_arquivar_job.rb` | — | não muda: continua criando `Protocolos\` dentro da base recebida |

Lead antigo sem `tese_pasta_id`: H1 cria na próxima exportação; H3 cai em `pasta_id` (comportamento de hoje).

Fora do escopo: o hub saber a tese da petição por outro caminho além do último lead ganho do contato.
Cliente com 2 casos ganhos protocola no mais recente; trocar para "escolher o caso na petição" só se acontecer na prática.

## Esteira

`pasta.py` e `vigilia.py` tratam como cliente o 1º nível abaixo de `Clientes\`,
então as subpastas novas não quebram nada. **Fase 2 (sem plano):** gravar `Esteira\` e o
`_pasta-pronta.json` dentro da pasta da tese, e não na do cliente.

## Skill `organizar-documentos-cliente`

- A subpasta passa de `~<Tese abreviada> – MM.AA` para a regra 2.
- Grupos 03–05 vão para `00 Pessoais`. 01–02 e 06–10 vão para a tese. A cópia vinda de `Documentação Leads` sai da skill.

## Migração (51 pastas em `Clientes`, levantadas em 06/11)

Pastas de tese existentes: `~Aux. Doença` (19), `~Aux. Acidente` (24), `Invalidez` (2), em `MM.AA` de 07 a 10/26.

1. Zip/`rclone lsjson -R --hash` da raiz antes de tudo (lição da migração de 02/11).
2. Renomear as pastas de tese pela regra 2. **Ambíguo:** `~Aux. Acidente` pode ser B36 ou B94 no hub.
   Resolver pelo lead ganho do cliente; se não houver lead, manter o nome antigo sem o `~`.
3. Mover 03–05 de cada tese para `00 Pessoais`. Arquivo repetido entre teses fica uma vez só.
4. Arquivo solto na raiz de `Clientes` (ex.: `CNH-e.pdf (2).pdf`) e `_to_delete`: o Eduardo decide.
5. Leads ganhos com `drive.pasta_id`: gravar `tese_pasta_id` por script na VPS, para H3 já apontar certo.
6. Conferir pelo hash, como em 02/11.

Ordem: H1–H3 (um PR) → deploy → migração → skill.

## Decisões do Eduardo (06/11)

1. **Nome da tese = nome completo do hub** (`Auxílio-acidente (B36) – 10.26`). Sem campo novo.
2. **Equipe com acesso a tudo, inclusive `Clientes`** (Editor na raiz). Quem compartilha é o Eduardo.
   ⚠️ É Meu Drive de conta Gmail, sem Drive compartilhado: **o arquivo criado pela conta de alguém da
   equipe é dono dessa pessoa**. Se a conta for apagada, o arquivo some. O hub também não consegue
   mandar esse arquivo à lixeira (lição de 02/11). Regra: antes de desligar alguém, transferir a
   propriedade dos arquivos dele para `ramonantonio.comercial`.
3. **`Documentação Leads` é absorvida:** contrato e procuração de cada cliente vão para a pasta da
   tese (`01.1`, `02.1`). Depois, a pasta é renomeada para `Documentação Leads - ARQUIVO` e só é
   apagada com aprovado. Contrato novo vai direto para a pasta da tese. A esteira (`pasta.py`) lê
   `Documentação Leads`: tirar essa leitura na fase 2, porque até lá ela é só leitura e não quebra.
4. **Migração feita juntos, por etapas:** pelo `G:\`, com backup e conferência por hash. O que mexe
   na VPS (passo 5) vai pronto para o Eduardo rodar com `!`.

Passo extra da migração (entre 3 e 4): casar as 75 pastas de `Documentação Leads` com os clientes
por nome e CPF. A pasta que não casar fica numa lista para o Eduardo, e não se cria cliente novo.

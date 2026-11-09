# Colheita por tese: lista de campos

> **APROVADO pelo Eduardo em 09/11/2026.** Decisões: (1) estrutura de blocos aprovada; (2) `cliente` =
> pessoa do benefício (autor), quem conversa vai em `cliente.representante`; (3) trabalhista: **guardar
> o nome das testemunhas** quando o lead disser (`contrato.provas_disponiveis` + `contrato.testemunhas[]`
> `{nome, relacao}`); (4) criar no núcleo `outras_teses_sinal[]` `{tese, motivo}` — só aviso, a tese do
> lead não muda sozinha; (5) sobe tudo junto (11 teses). A colheita só registra o que foi dito; perguntar
> mais no roteiro é texto ao cliente e passa pelo gate do Eduardo.

> 09/11/2026 · Rascunho para o Eduardo aprovar. Nada aqui é código.
> Base: `colheita_extraction_service.rb` (esquema aprovado do auxílio-acidente), itens e roteiros do hub
> por tese, fichas `plugin/teses/` (incapacidade, bpc-loas, salario-maternidade), modelos
> `minuta-inicial/modelos/` (beneficio-incapacidade, auxilio-acidente) e o desenho
> `esteira-agentes/docs/2026-11-08-atendimento-na-esteira-design.md`.

**Legenda da fonte:** `item` = item do hub (qualificação/documento/colheita) · `roteiro` = passo do
roteiro do WhatsApp · `ficha` = ficha de tese · `modelo` = `[CAMPO]` do modelo de inicial ·
`desenho` = lista do design de 08/11 · `proposta` = sugestão minha com base em ficha/lei ·
`proposta sem ficha` = trabalhista e IR, onde não existe ficha da banca.

**Regras que valem para todos os blocos (as mesmas de hoje):** dado não dito = `null` + entrada em
`lacunas`; dito com incerteza = preenche + `confirmar`; datas `AAAA-MM-DD` (só mês/ano = dia 15,
como no roteiro); máscara LGPD vira lacuna; a IA **não calcula** nada (renda per capita, prazos,
carência): só registra o que foi dito; o cálculo fica com o hub ou com o jurídico.

---

## 1. Núcleo comum (todas as 11 teses)

### 1.1 `cliente` (o que já existe, com dois acréscimos)

Já existe: `nome_completo`, `cpf`, `rg`, `nascimento`, `estado_civil`, `profissao`, `endereco`,
`whatsapp`, `renda_aproximada` (gratuidade).

Acréscimos:
- `cliente.nacionalidade`: está na qualificação dos dois modelos (`modelo`) e no item de colheita do
  B36 ("Estado civil, profissão e nacionalidade"), mas falta no JSON de hoje.
- `cliente.representante`: `{nome, parentesco, motivo}`, preenchido quando quem conversa **não** é a
  pessoa do benefício: BPC, salário-maternidade e IR já têm o passo "para quem é" (`roteiro`), e no
  BPC de criança ou de pessoa incapaz, no 25% e no B32 por doença mental a inicial precisa do
  representante legal (`proposta`). Regra: `cliente` = **pessoa do benefício (autor)**; quem fala
  vai em `representante`.

### 1.2 `beneficios` (histórico no INSS: o que já existe, ampliado)

Já existe: `[{nb, especie, dib, dcb, situacao, motivo}]`.

Acréscimos:
- `beneficios[].der`: data do requerimento. O modelo de incapacidade pede "NB – DER" do novo pedido
  (`modelo`) e o desenho lista "pedidos anteriores (NB, DER)" (`desenho`).
- `beneficios[].prorrogacao_pedida`: `sim | nao | nao_sabe`. O modelo escolhe entre "pedido de
  prorrogação" e "novo pedido" (`modelo`, `desenho`).
- `beneficios[].especie`: o enum passa de `B31|B91|B94|outro` para incluir `B32|B92|B36|B87|B88|B80|B41|B42|B21`
  (aposentadorias, BPC, salário-maternidade e pensão). Isso é o que o 25%, o BPC (acúmulo), a
  maternidade e o IR (de qual benefício vem a renda) precisam.

### 1.3 `fechamento`, `confirmar`, `lacunas`, `checklist_ok`

Sem mudança. O honorário muda por tese, mas os campos são os mesmos.

> Nota ao construtor (não é decisão do Eduardo): vários campos abaixo já são respondidos no
> **roteiro** (marcados `roteiro`). A colheita pode copiar a resposta do roteiro em vez de extrair de
> novo; os dois só não podem divergir sem aparecer em `confirmar`.

---

## 2. Agrupamento: 11 teses, 11 blocos reutilizáveis

| Bloco | Usado por |
|---|---|
| **P1 `segurado`** (qualidade de segurado) | B31, B32, Salário-maternidade |
| **P2 `saude`** (doenças, CID, tratamentos) | B31, B32, 25%, BPC (PcD), IR |
| **P3 `incapacidade`** | B31, B32 |
| **P4 `dependencia`** (ajuda de terceiros) | 25%, B32 (quando houver) |
| **P5 `assistencial`** (grupo familiar + impedimento) | BPC |
| **P6 `maternidade`** | Salário-maternidade |
| **P7 `ir`** | Isenção de IR |
| **A `qualificacao` + `acidente` + `sequela`** (B36, aprovado) | B36; `acidente` e `sequela` reaproveitados no Trab. acidente |
| **T1 `contrato`** | as 4 trabalhistas |
| **T2 `queixas`** | Rescisão indireta, Direito suprimido |
| **T3 `vinculo`** | Reconhecimento de vínculo |
| **T4 `responsabilidade`** | Trab. acidente/doença |

| Tese | Blocos (além do núcleo) |
|---|---|
| 1 B31 | P1 + P2 + P3 |
| 2 B32 | P1 + P2 + P3 (+ P4 quando precisar de cuidador) |
| 3 B36 | A (como está) |
| 4 BPC | P2 (só PcD) + P5 |
| 5 Acréscimo 25% | P2 + P4 |
| 10 Salário-maternidade | P1 + P6 |
| 12 Isenção de IR | P2 + P7 |
| 13 Trab. acidente/doença | T1 + `acidente` + `sequela` + T4 |
| 15 Rescisão indireta | T1 + T2 |
| 16 Vínculo | T1 + T3 |
| 14 Direito suprimido | T1 + T2 |

---

## 3. Blocos previdenciários e assistenciais

### P1 `segurado`: B31, B32, Salário-maternidade

Data de referência: no B31/B32, quando parou de trabalhar; na maternidade, a data do parto.
- `segurado.regime_na_data`: `carteira | rural_pesca | autonomo_mei | facultativa | servidor | desempregado`
  (`roteiro` B36/maternidade; `item` B31 "Você contribui para o INSS?")
- `segurado.servidor_rpps`: `sim | nao | nao_sabe`. Servidor de regime próprio sai do atendimento (`roteiro` B36)
- `segurado.ultima_contribuicao`: última contribuição ou saída do último emprego de carteira (`item` B31, `roteiro` maternidade)
- `segurado.mais_de_120`: `sim | nao | nao_sabe`. Mais de 10 anos pagando sem perder a qualidade; estende a graça (art. 15, §1º, Lei 8.213/91) (`roteiro`, `ficha`)
- `segurado.desemprego_comprovado`: `seguro | sine | outro_meio | nao`. Estende a graça (art. 15, §2º); prova por qualquer meio (`roteiro`, `ficha`)

### P2 `saude`: B31, B32, 25%, BPC-PcD, IR

- `saude.doencas[]`: `{nome, cid, diagnostico_em}`. É a "natureza das enfermidades" e o `[CID]` do modelo; no IR, `diagnostico_em` é o marco da restituição (`modelo`, `desenho`, `item` IR)
- `saude.tratamentos[]`: `{tipo (cirurgia | conservador | internação | medicação), onde, quando}`. É o mapa dos prontuários (`desenho`, `item` B36 reaproveitado)
- `saude.laudo_disponivel`: `sim | nao | parcial` (`roteiro` B36/BPC/IR "não precisa ter agora")

### P3 `incapacidade`: B31, B32

- `incapacidade.funcao_exigencias`: o que a atividade habitual exige do corpo, em fatos (esforço, tempo em pé, carga). Alimenta o art. 129-A, I, "b" (`modelo` 2.2, `desenho`)
- `incapacidade.parou_em`: quando parou de trabalhar por causa da doença. Aproxima a DII e é cruzada com a graça (`desenho`, `ficha` armadilha 1)
- `incapacidade.afastado_hoje`: `afastado | trabalhando | desempregado` (`item` B31)
- `incapacidade.limitacoes_atuais`: o que não consegue fazer hoje, em fatos. Alimenta o art. 129-A, I, "a" (`modelo` 2.1, `desenho`)
- `incapacidade.evolucao`: `piorando | estavel | melhorando`. O modelo afirma "sintomática e sem melhora" (`modelo`)
- `incapacidade.prognostico`: o que o médico disse sobre voltar a trabalhar. Qualificação do B32 (`item` B32)
- `incapacidade.escolaridade`: com a idade (que vem do `nascimento`), sustenta as condições pessoais, a ponte parcial→permanente da Súmula 47/TNU (`item` B32, `ficha`)
- `incapacidade.pericia_desconsiderou`: o que o cliente diz que a perícia do INSS ignorou. Alimenta o art. 129-A, I, "c" (`modelo` 2.3, `desenho`)
- `incapacidade.ligada_ao_trabalho`: `sim | nao | nao_sabe`. Se for acidentária, a competência é da Justiça Estadual, a peça muda e há sinal de tese trabalhista (`ficha` seção 5)

### P4 `dependencia`: 25% e B32

- `dependencia.precisa_ajuda`: `sim | nao | parcial` (`item` B32/25%)
- `dependencia.atividades[]`: `alimentar | higiene | vestir | locomover | medicacao | supervisao` (`item` 25% "tarefas básicas")
- `dependencia.desde`: desde quando precisa de ajuda (`proposta`, para o marco do pedido)
- `dependencia.quem_cuida`: parentesco, sem nome (`proposta`)
- `dependencia.laudo_cuidador`: `sim | nao | nao_sabe` (`item` 25%/B32)

No 25%, a aposentadoria sobre a qual incide o acréscimo vem de `beneficios` (B32/B92, DIB). O acréscimo
é do art. 45 da Lei 8.213/91; a extensão a outras aposentadorias depende de lei (Tema 1095/STF, como diz o item do hub).

### P5 `assistencial`: BPC

- `assistencial.cadunico`: `{inscrito: sim|nao|nao_sabe, atualizado: sim|nao|nao_sabe}`. É requisito (`item`, `roteiro`, `ficha`)
- `assistencial.impedimento.o_que_limita`: o que a doença/deficiência atrapalha no dia a dia (criança: nas atividades da idade) (`roteiro`, `ficha`)
- `assistencial.impedimento.desde`: há quanto tempo. O marco é de 2 anos (art. 20, §2º, Lei 8.742/93) (`roteiro`, `ficha`)
- `assistencial.impedimento.barreiras`: escola, transporte, trabalho, acesso a tratamento. É a avaliação social (`ficha` armadilha 5, `proposta`)
- `assistencial.moradores[]`: `{parentesco, idade, renda_mensal, fonte}`, só os membros do art. 20, §1º (`roteiro`, `ficha`)
- `assistencial.renda_total_declarada`: o total que o lead confirmou no resumo (`roteiro`)
- `assistencial.rendas_excluidas[]`: `{parentesco, tipo}`. BPC de outro morador, ou benefício de até 1 salário mínimo de idoso 65+ ou de PcD (RE 580.963) (`roteiro`, `ficha`)
- `assistencial.gastos_saude[]`: `{item, valor_mensal}`. Sustenta a miserabilidade em concreto (Tema 27/STF) (`roteiro`, `ficha`)
- `assistencial.moradia`: `propria | alugada | cedida`, + aluguel, se houver (`proposta`, para a miserabilidade em concreto)

A modalidade (idoso ou PcD) sai do `nascimento` + `saude`; não precisa de campo.

### P6 `maternidade`: Salário-maternidade

- `maternidade.fato`: `gestante | parto | natimorto | adocao | guarda_adocao | aborto` (`item`, `roteiro`)
- `maternidade.data_fato`: data do parto, da adoção ou da guarda; gestante = data provável (`roteiro`)
- `maternidade.semanas`: só para gestante (`roteiro`)
- `maternidade.ja_recebeu`: por este parto (`item`, `roteiro`)
- `maternidade.trabalho_na_data`: `domestica | empregada_mei | intermitente | mei | autonoma | facultativa | desempregada | rural_pesca | empregada_empresa` (`item`). Empregada de empresa: quem paga é a empresa
- `maternidade.facultativa_dona_casa`: pagava como dona de casa ou estudante (`roteiro`)
- `maternidade.rural`: `{atividade (lavoura | pesca), onde, regime_familiar, desde, documentos_que_tem[]}`. A prova material dos 12 meses antes do parto; testemunha sozinha não basta (Súmula 149/STJ) (`item`, `ficha`)
- `maternidade.demitida_gestante`: `sim | nao`. Sinal de estabilidade (ADCT, art. 10, II, "b") e de tese trabalhista (`proposta`)

O pedido no INSS (inclusive o anterior aos 5 anos) vai em `beneficios` com espécie B80.

### P7 `ir`: Isenção de IR por doença grave (proposta sem ficha)

- `ir.fonte`: `inss | rpps | outro`. RPPS sai do atendimento (decisão de 14/10) (`item`, `roteiro`)
- `ir.tipo_renda`: `aposentadoria | pensao`. Na pensão, a doença é do pensionista, não do falecido (`roteiro`)
- `ir.valor_mensal`: o aproximado; se o cliente não disser, `5001` (passa) ou `5000` (não passa) (`roteiro`)
- `ir.outras_fontes[]`: segunda aposentadoria/pensão ou previdência privada. Muda o alcance do pedido (`proposta sem ficha` [CONFERIR alcance sobre previdência complementar])
- `ir.doenca_lista`: a doença com as palavras da pessoa + enquadramento `lista | nao_tem_certeza` no art. 6º, XIV, Lei 7.713/88 (+ fibrose cística) (`roteiro`, `item`)
- `ir.situacao_doenca`: `em_tratamento | controlada | curada`. A isenção não exige sintoma atual (Súmula 627/STJ [CONFERIR]) (`roteiro` "câncer operado também conta")
- `ir.ja_pediu`: `{onde (inss | receita), quando, resultado}` (`roteiro`)

Data do diagnóstico = `saude.doencas[].diagnostico_em`. A data de início da aposentadoria vem de
`beneficios[].dib`; as duas datas juntas definem desde quando cabe a restituição (`item`). Laudo
oficial em juízo: Súmula 598/STJ [CONFERIR].

---

## 4. Auxílio-acidente (B36): o esquema aprovado fica

Fica como está: `qualificacao` (aposentado, qualidade_segurado_epoca/como, recebeu_auxilio_doenca),
`acidente` (data, tipo, descricao, cat_emitida, empregador_na_epoca), `sequela` (descricao, cid,
consolidada, limitacao_concreta, tratamentos).

**O que os modelos pedem e o esquema aprovado não tem** (só apontado; nada muda sem o seu ok):
1. `cliente.nacionalidade`: está na qualificação do modelo (já entra pelo núcleo).
2. `acidente.lesao`: o modelo separa a **lesão inicial** ("culminou em [LESÃO] ([CID])") do **quadro
   atual** (que está em `sequela`). Hoje só existe `sequela.cid`.
3. `sequela.tratamentos[]` sem formato: o modelo pede "Em [DATA] realizou [cirúrgico/conservador]".
   Proposta: usar o formato de `saude.tratamentos[]` (`{tipo, onde, quando}`).
4. `beneficios[].der`: falta a DER do pedido de auxílio-acidente que já foi feito (item "Já requereu
   auxílio-acidente? (DER, NB…)"); entra pelo núcleo.
5. `pericia_desconsiderou` (art. 129-A, I, "c"): no modelo do B36 o texto é fixo ("ignorou todo o
   contexto"), então é opcional aqui. Útil se a perícia do INSS disse algo específico.

---

## 5. Blocos trabalhistas (proposta sem ficha: não há ficha trabalhista da banca)

### T1 `contrato`: as 4 trabalhistas

- `contrato.empregador`: nome/razão social e cidade. É o polo passivo; o CNPJ fica como lacuna, a buscar na CTPS (`proposta sem ficha`)
- `contrato.funcao`: função exercida (e a registrada, se diferente) (`roteiro` 15/16/14)
- `contrato.carteira`: `assinada | sem_carteira | pj_mei` (`item`, `roteiro` 16/14)
- `contrato.admissao`: início do trabalho (`proposta sem ficha`, para o período e as verbas)
- `contrato.ainda_trabalha`: `sim | afastado_inss | ferias | saiu` (`roteiro` 13/15)
- `contrato.saida_em`: data da saída (CTPS ou último dia). O prazo é de 2 anos após a extinção, com 5 anos para trás (art. 7º, XXIX, CF) (`roteiro`, `item`)
- `contrato.tipo_saida`: `sem_justa_causa | justa_causa | pediu | acordo | fim_contrato` (`item`, `roteiro` 14)
- `contrato.salario`: `{registrado, real, por_fora: sim|nao}` (`item` 14/15 "salário por fora")
- `contrato.jornada`: `{horario, dias_semana, horas_extras: sim|nao, pagas_certo: sim|nao}` (`roteiro` 16, queixas 15/14)
- `contrato.processo_anterior`: `nao | sim_julgado | arquivado_sem_julgamento` (`roteiro`, todas)
- `contrato.provas_disponiveis[]`: `mensagens | fotos | audios | ponto | contracheque | testemunhas`, + quantas testemunhas (`item`)

### T2 `queixas`: Rescisão indireta, Direito suprimido

- `queixas[]`: `{hipotese, descricao, desde, ainda_acontece, periodo}`
  - `hipotese`: `salario_atrasado | fgts_sem_deposito | verbas_rescisorias | horas_extras | salario_por_fora | desvio_acumulo | insalubridade_periculosidade | descontos | assedio | ferias | beneficio_cortado | transferencia | acidente_doenca` (o mesmo enum dos passos `hipotese` dos roteiros 15 e 14)
  - `descricao`: com as palavras da pessoa (`roteiro`)
  - `desde` / `ainda_acontece`: na rescisão indireta, mostram que a falta é **atual** (art. 483 CLT; a imediatidade é tese do jurídico) (`proposta sem ficha`)
  - `periodo`: meses de atraso ou de horas extras, para estimar o valor (`proposta sem ficha`)
- Se aparecer `acidente_doenca`, há sinal de tese 13 (o roteiro já pergunta).

### T3 `vinculo`: Reconhecimento de vínculo (art. 3º CLT)

- `vinculo.pf_ou_pj`: `pessoa_fisica | pj | mei`. PJ/MEI vai sempre para a equipe (`roteiro`, `item`)
- `vinculo.pessoalidade`: era sempre ele ou podia mandar outro, e se isso já aconteceu (`roteiro` substituto)
- `vinculo.habitualidade`: `{dias_semana, tempo_servico}`. Em casa de família, precisa ser mais de 2 dias por semana (LC 150/2015, art. 1º) (`roteiro`)
- `vinculo.domestico`: `sim | nao`, se era em casa de família (`roteiro` julgamento)
- `vinculo.pagamento`: `{forma (mes | dia | hora | tarefa | comissao), valor, meio (pix | dinheiro | recibo)}` (`roteiro`, `item`)
- `vinculo.subordinacao`: `{ordens_de_quem, horario_fixo, justificava_faltas, punicoes}` (`roteiro`)
- `vinculo.avaliacao`: uma linha por requisito (`sim | nao | duvida`), já gerada pelo passo `julgamento` (`roteiro`)

### T4 Trab. acidente/doença: reaproveita `acidente` + `sequela` do B36, + `responsabilidade`

- `acidente.*`: o bloco do B36. O enum `tipo` ganha `doenca_trabalho` (o roteiro 13 separa acidente, trajeto e doença)
- `sequela.*`: o bloco do B36 (descrição com as palavras da pessoa, a lista do roteiro 13, consolidada, limitação)
- `responsabilidade.culpa_fatos`: o que a empresa fez ou deixou de fazer (sem EPI, sem treinamento, sem pausa, máquina sem proteção) (`item` 13)
- `responsabilidade.atividade_risco`: `sim | nao`, com a atividade descrita (`item` 13)
- `responsabilidade.nexo_doenca`: na doença, como o trabalho causou ou piorou (`roteiro` 13 evento)
- `responsabilidade.aso`: exames ocupacionais feitos (admissional, periódico, demissional) (`item` 13)
- `responsabilidade.dispensado_apos_alta`: dispensa em até 12 meses após o fim do auxílio-doença acidentário. É sinal de estabilidade (art. 118, Lei 8.213/91) (`proposta sem ficha`)
- `responsabilidade.gastos`: despesas com tratamento pagas pelo cliente, para o dano material (`proposta sem ficha`)

O afastamento pelo INSS vai em `beneficios` (B91/B31). A CAT vai em `acidente.cat_emitida`.

---

## 6. Perguntas para o Eduardo

1. **Quem é o "cliente" quando fala um familiar?** Proposta: `cliente` = pessoa do benefício (autor
   da ação) e quem conversa vai em `cliente.representante` (BPC, maternidade, IR, 25%). Aprova?
2. **BPC: renda morador a morador pelo WhatsApp?** Hoje o roteiro pega só o número de pessoas e o
   total da casa. A peça e as exclusões (RE 580.963) ficam melhores com a renda de cada morador, mas
   isso é uma pergunta a mais e mais sensível. Colhemos no WhatsApp ou deixamos para a reunião?
3. **Trabalhista: dados de terceiros.** Colher pelo WhatsApp o nome do empregador (necessário para
   o polo passivo) e o **nome das testemunhas**, ou só "tem testemunhas: sim, quantas" e os nomes na
   reunião?
4. **Sinal de outra tese na ficha.** Trab. acidente costuma ser também B36; maternidade com
   demissão na gravidez vira trabalhista; B31 ligado ao trabalho muda a competência. Criamos no
   núcleo um campo `outras_teses_sinal[]` para a equipe ver na hora, ou fica fora da colheita?
5. **Ordem de entrada.** O desenho de 08/11 diz: B36 e incapacidade primeiro, o resto depois.
   Mantemos (B31/B32 agora, com P1–P3; as outras teses em pacote seguinte) ou sobe tudo junto,
   já que os blocos são compartilhados?

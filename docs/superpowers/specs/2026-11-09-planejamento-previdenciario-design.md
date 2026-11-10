# Planejamento previdenciário no hub (o "Raio-X" vira produto) — desenho

*09/11/2026 · Dono: Eduardo · Repos: `juridico\projetos\motor-calculos` (motor),
`comercial\projetos\ramon-hub` (hub), `juridico\projetos\raio-x-previdenciario`
(origem do modelo do PDF e dos 4 casos de referência).*

## 1. Por que

O PDF de planejamento da turma **Raio-X Elites** (out/2026) foi aprovado e vendido.
Hoje cada caso custa: a Brenda roda 3 projeções no Previdenciarista + uma sessão do
Claude montando `dados.json` à mão. Ela não consegue calcular as hipóteses novas que
o Dr. Ramon pediu (outro valor de contribuição, descarte do art. 26 §6º, facultativo),
e quem confere é o Dr. Ramon. O motor de cálculos do hub já lê o CNIS, conhece as
regras e faz descarte; falta alinhar com o Previdenciarista e acrescentar a camada
de planejamento e o nosso PDF.

**Sucesso:** alguém da equipe jurídica sobe o CNIS no hub, confirma 3–4 campos,
revisa os textos, clica em gerar, e o PDF no visual aprovado + a memória de cálculo
caem na pasta do cliente no Drive. Ninguém abre o Previdenciarista. O Dr. Ramon
confere pela memória.

## 2. Decisões do Eduardo (09/11/2026)

| Tema | Decisão |
|---|---|
| Quem usa | **Equipe jurídica**; o Dr. Ramon confere |
| Previdenciarista | **Sai do fluxo** depois que o hub bater com a Brenda nos 4 casos |
| Observações do CNIS | **Rascunho automático + edição** pelo advogado |
| Saída | **Pasta do cliente no Drive + baixar** |
| Visual | **Igual ao aprovado** (modelo do raio-x) |
| Cenários | **4 fixos (mínimo, média, R$ 5 mil, teto) + 1 valor livre** |
| Textos do PDF | **Automáticos (sem IA, determinísticos) e editáveis** antes de gerar |
| Capa | Sempre **"Planejamento previdenciário"**; só alunos da turma saem como **"Raio-X Elites"** |
| Aba atual "Planejamento" | **Substituída** pela nova (uma ferramenta só) |
| Forma de contribuir | **Detectada no CNIS e confirmada** pelo advogado (com a empresa) |
| Página "sair da administração / facultativo semestral" | **Opção marcada pelo advogado** |
| Descarte na data exata da regra dos pontos | **Leitura estrita por padrão, com chave** (aguarda o Dr. Ramon). Estrita = **não descarta nada** na data dos pontos (foi o que se descreveu ao Eduardo) |
| Formas de contribuir na 1ª versão | **Todas** (pró-labore, pró-labore + salário, carnê 20%, facultativo, planos 11%/5%, empregado) — textos de cada forma passam pelo aprovado do Eduardo (§6.5) |

Também valem, sem reabrir, as regras de conteúdo do raio-x
(`raio-x-previdenciario\CLAUDE.md`, seção "Regras"): linguagem de cliente (sem
coeficiente/RMI/siglas), "você paga / você recebe", retorno simples sem juros, IR na
conta quando a contribuição sai do pró-labore, "vale a pena contribuir mais?" com
coluna "Compensa?" (padrão 10 anos) decidindo a sugestão, "parar" possível mas não
recomendado, nota "contribuir ao menos X e parar" nunca entra, aviso OAB "não garante
a concessão", logo oficial, capa/contracapa só no marrom escuro, contracapa com
WhatsApp/Instagram/site clicáveis e sem e-mail.

## 3. Metas, não-metas, anti-metas

**Metas**
1. O motor reproduz a Brenda nos 4 casos de referência (data e renda de cada cenário,
   "se parar"), como teste automático permanente.
2. Planejamento completo num único pedido ao motor, rápido o bastante para a tela.
3. PDF idêntico ao aprovado, gerado pelo motor, a partir do mesmo `dados` que a tela mostra.
4. Aba nova no Simulador do hub, com rascunho editável, PDF e memória salvos no Drive.

**Não-metas:** enviar o PDF ao cliente (quem envia é o Eduardo); mexer nas outras
abas do Simulador; IA escrevendo texto; reajuste anual automático de salário mínimo,
teto e IR (continua manual, com data de revisão).

**Anti-metas (falhou mesmo que "funcione"):** número na tela diferente do PDF; dois
planejamentos no hub dando números diferentes; PDF sem memória de cálculo; data de
aposentadoria "aproximada" sem aviso; texto com promessa ou juridiquês; dados de
cliente real em repositório versionado do motor (ver §8).

## 4. O que já existe e onde mexer

**Motor** (`motor-calculos`, FastAPI, sem remote, deploy por `git archive` na VPS):
- `motor/planejamento.py`: cenários + `_buscar_fechamento` (malha mensal de chamadas ao painel).
- `motor/painel.py`: cartões de regra (`_cartao_ec103`) — **sem descarte** nos cartões de aposentadoria.
- `motor/comparador.py` + `motor/descartes.py::otimizar`: descarte com divisor mínimo 108 (já usado em `/calcular`).
- `motor/media.py::memoria_calculo(hist, der, corrigir_ate)`: memória mês a mês.
- `api/pdf_planejamento.py`: PDF atual (fpdf2) — será aposentado.
- Parser do CNIS (`cnis/parser.py`): `VinculoCnis{seq, tipo, origem, inicio, fim, indicadores, remuneracoes}`.

**Hub** (`ramon-hub`, branch `ramon`):
- `LeadPlanejamentosController` (`create`, `pdf`) + `CalculoProxy` + `RegistraCalculo` (grava `calculos.snapshot`).
- `LeadPlanejamento.vue`, montado em `LeadSimulador.vue` (aba gated por CNIS), usado em `Calculos.vue`.
- `lead.cnis` jsonb: `entrada` (segurado, competências, vínculos), `vinculos` (detalhe), `segurado_nome/cpf`, `avisos`, `parametros`.
- Drive: `Ramon::DriveClient.upload(name:, io:, content_type:, parent_id:)` +
  `Ramon::DriveExportService.new(lead).pasta_cliente_id` / `pasta_tese_id`.
- `Ramon::MotorClient`: síncrono, `planejamento` com read_timeout 60 s; **`rack-timeout` de produção
  tem padrão de 15 s** (variável `RACK_TIMEOUT_SERVICE_TIMEOUT` não está no repo — conferir na VPS).

**Raio-x** (`raio-x-previdenciario`): `template.html` + `assets/` (modelo aprovado),
`parametros.json` (SM, teto, IR 2026, dados do escritório), `calculo/motor.py` (reprodução
do Previdenciarista que já bate nos 4 casos) e `calculo/gabarito-hub/` (comparação de 09/11).

## 5. Diagnóstico de 09/11 (base das correções)

Os 4 CNIS da turma rodados no motor do hub × Brenda (`raio-x\calculo\gabarito-hub\`):
- **Média do histórico bate** quando corrigida até 08/2026 (índice que o Previdenciarista
  usou em 15/10/2026): José Carlos e Caroline no centavo, Ana +0,01%, Daniel −0,24%
  (o motor do raio-x tem o mesmo resíduo — causa ainda desconhecida, provavelmente teto
  de meses concomitantes 2009–2017 ou IPC-r 1994-95).
- **Diferença 1 — índice:** o hub corrige até o último INPC publicado (09/2026, +0,82%). Correto
  para uso real; nos testes de referência, fixar `corrigir_ate` na data da Brenda.
- **Diferença 2 — data:** a data dos pontos sai ~1 mês depois em Daniel, Ana e José Carlos. Causa
  provável: `_projetar` começa no mês **seguinte à data do cálculo**, deixando sem contribuição os
  meses entre o fim do CNIS e o cálculo; e `_buscar_fechamento` anda em malha mensal a partir de um
  chute, não acha o dia exato.
- **Diferença 3 — alíquota:** `Cenario.aliquota < 0.20` vira plano simplificado (só idade). O 11%
  **retido do pró-labore** dá direito a todas as regras.
- **Lacuna — descarte:** cartões de aposentadoria do painel não trazem `rmi_com_descartes`
  ("se parar" do Daniel: hub R$ 3.339,55; com descarte R$ 3.822,97).

### Referência numérica (Brenda + motor do raio-x, calculado em 15/10/2026, índice até 08/2026)

| Caso | Regra / data | Mínimo | Média (v) | R$ 5 mil | Teto | Parar (sem → com descarte) |
|---|---|---|---|---|---|---|
| A (H, 1978) | pontos 16/03/2040 | 3.635,35 | 4.483,22 (4.169,65) | 4.759,44 | 5.915,66 | 16/07/2043: 3.320,30 → 3.822,97 |
| B (M, 1978) | pontos 02/04/2040 | 3.102,33 | 3.625,75 (3.038,37) | 4.350,16 | 5.633,65 | 29/09/2040: 2.899,87 → 3.069,29 |
| C (H, 1988) | pontos 24/08/2050 | 2.234,62 | 3.213,92 (3.296,86) | 4.209,18 | 6.240,16 | 22/01/2053: 1.695,25 → 1.909,87 |
| D (M, 1994) | progressiva/idade 31/03/2056 | 1.785,22 | 3.418,59 (3.568,24) | 4.619,57 | 7.534,90 | não se aposenta (4a3m) |

Mínimo/média/teto/parar sem descarte = Previdenciarista (Brenda). R$ 5 mil e "com descarte"
= motor do raio-x (memórias em Drive `Área Jurídica\Raio-X Elites\`, conferência da Brenda em
andamento). Daniel (A) também tem o facultativo semestral: 34 × R$ 324,20, idade aos 65,
R$ 3.380,69 sem descarte → R$ 3.822,97 com descarte.

## 6. O desenho

### 6.1 A costura: `dados` é o contrato entre cálculo e PDF

O `dados.json` do raio-x já é um contrato provado (13–15 páginas, conferências no template).
O motor passa a **produzir** esse `dados` e a **renderizar** o PDF a partir dele. O hub só
transporta e deixa editar os textos. Assim tela e PDF nunca divergem: o PDF é `render(dados)`,
e a tela mostra o mesmo `dados`.

Dois pedidos ao motor, interface pequena:
- `POST /planejamento/previdenciario` → `{dados, memoria, avisos}` a partir de `{entrada (CNIS),
  perfil, data_calculo?}`.
- `POST /planejamento/previdenciario/pdf` → bytes do PDF a partir de `{dados}` (possivelmente
  editado). O motor **revalida** `dados` (as mesmas conferências que o template já faz: reta dos
  cenários, coeficiente × tempo, página estourando) e recusa com 422 em português.

`perfil` (o que o advogado confirma na tela):
`forma_contribuicao` (ver tabela abaixo), `empresa` (nome, para os textos), `salario_atual`
(sugerido do CNIS), `salario_emprego` (só em `pro_labore_mais_salario`), `cenario_livre` (valor
opcional), `turma` (opcional → capa "Raio-X Elites"), `facultativo_semestral` (bool, só para
`pro_labore*`), `descarte_na_data_dos_pontos` (`nao` padrão | `tempo_minimo`), `segurado_nome`.

| `forma_contribuicao` | Regras que valem | Custo por cenário | IR na conta | Cenários |
|---|---|---|---|---|
| `pro_labore` | todas | 11% retido do valor | sim (pró-labore + aposentadoria) | 4 fixos + livre |
| `pro_labore_mais_salario` (caso B) | todas | 11% sobre a soma (aproximação; a premissa explica que o salário segue a tabela do empregado) | sim, sobre a soma | 4 fixos + livre; `v` = soma |
| `carne_20` (autônomo/CI ou facultativo, 20%) | todas | 20% do valor | só na aposentadoria | 4 fixos + livre |
| `simplificado_11` (CI/facultativo 11% sobre o mínimo) | só idade (regra atual do motor) | 11% do mínimo | só na aposentadoria | mínimo a 11% **+ os mesmos 4 valores a 20%** ("e se passar para 20%?"), porque a 20% voltam as regras por tempo |
| `baixa_renda_5` (MEI / facultativo baixa renda, 5%) | só idade | 5% do mínimo | só na aposentadoria | idem ao anterior |
| `empregado` | todas | tabela progressiva do empregado sobre o salário (ilustrativo; quem desconta é a empresa) | só na aposentadoria | **só "seu salário de hoje"** (empregado não escolhe quanto contribuir) + parar/idade; sem página de sugestão de valor — a sugestão vira "siga contribuindo e confira o CNIS" |

*Calls do Claude nesta tabela (Eduardo confere ao ler):* custo do empregado pela tabela
progressiva; `simplificado_11`/`baixa_renda_5` comparando com os mesmos valores a 20%;
empregado sem cenários de valor.

A memória sai como planilha (.xlsx com fórmulas, mesmo formato de
`raio-x\calculo\memoria.py`: abas Leia-me, Salários, Índices, Hipóteses), gerada pelo motor.

### 6.2 Motor — módulo de planejamento previdenciário (deep module)

Interface: `planejar_previdenciario(hist, perfil, data_calculo) -> (dados, memoria)`.
Por dentro (costuras internas, testáveis pela própria interface):
1. **Projeção correta:** contribuir desde o mês seguinte ao **último mês do CNIS** (não da data do
   cálculo) até a aposentadoria. *Builder confirma nos 4 casos se isso sozinho fecha a data; se não,
   investigar a contagem em dias — a referência é a soma idade + tempo exata do Previdenciarista
   (ex.: caso A 61a8m + 43a4m em 16/03/2040).*
2. **Data uma vez só:** a data de fechamento de cada regra não depende do valor contribuído (só da
   forma de contribuir). Achar a data **uma vez** (com refino até o dia) e calcular a renda de cada
   cenário nessa data. Substitui as ~9 chamadas de painel por cenário/regra de hoje (o teste de
   09/11 levou minutos por cliente). Meta: pedido completo em poucos segundos.
3. **Forma de contribuir no lugar da alíquota:** pró-labore 11% retido (todas as regras, IR no
   pró-labore), carnê 20% (todas), plano simplificado 11% (só idade, regra atual), empregado
   (custo ilustrativo). Custo e IR saem da forma, não do cenário.
4. **Descarte nos cartões de aposentadoria** (reusar `descartes.otimizar`, divisor 108): por idade,
   mínimo de 15 anos (usado no "se parar" e no facultativo); na regra dos pontos e nas demais regras
   por tempo, conforme a chave: `nao` (padrão — nenhum descarte; é o que bate com a Brenda) ou
   `tempo_minimo` (até 35/30 anos de contribuição).
5. **Cenários:** mínimo, média dos salários, R$ 5 mil, teto, + livre; ordenados por valor (formas
   da tabela de 6.1). **Média dos salários = média das últimas 36 competências corrigidas** (*call do
   Claude, pelo builder check de 09/11*): bate no centavo com a Brenda nos casos C e D e a R$ 0,61 no
   A; o caso B (3.038,37) não bateu com nenhuma janela simples — investigar na fase 1 (suspeita:
   salário do emprego novo de 08/2026 ou concomitância); se não explicar, vale o valor do hub e o
   teste do caso B usa o valor do hub para esse cenário.
6. **IR:** tabela e redução da Lei 15.270/2025 vindas de dado versionado com data de revisão
   (hoje em `raio-x\parametros.json`), IR mensal do pró-labore e da aposentadoria.
7. **Sugestão:** "vale a pena contribuir mais?" (cada cenário vs. o anterior, já com IR; compensa se
   volta em até 10 anos) → maior cenário que compensa. Determinística.
8. **Parar:** aposentadoria por idade (art. 18 EC 103) sem novas contribuições, com e sem descarte;
   ou "não se aposenta" (< 15 anos).
9. **Facultativo semestral** (se marcado): 1 contribuição de 20% sobre 1 SM a cada 6 meses do mês
   seguinte ao cálculo até a idade; com e sem descarte; custo total.
10. **Observações do CNIS (rascunho):** a partir de indicadores e remunerações do parser — meses
    abaixo do mínimo (antes/depois da EC 103), vínculo sem remuneração em algum mês, contribuição em
    atraso (indicador de extemporânea), alertas IREM/PEXT etc., meses pré-07/1994 ignorados — cada
    uma vira item `{titulo, impacto, texto}` + documento sugerido a separar. *Builder: lista de
    indicadores tratados fica documentada no código; o que não reconhecer vira "conferir".*
11. **Textos:** gerados por modelo de frase a partir dos números (os do caso A são o exemplo de tom:
    `raio-x\clientes\daniel-sonaglio\dados.json`). Toda frase com número usa os marcadores do
    template (`{data_ap}`, `{parar_rmi}`…) para não divergir. Um conjunto de modelos por forma de
    contribuir (§6.5).
12. **Detecção da forma de contribuir:** pela origem das últimas competências (EMPREGO → empregado;
    RECOLHIMENTO próprio → carnê/facultativo; contribuinte individual por empresa/eSocial →
    provável pró-labore) — vai como sugestão em `avisos`, o advogado confirma.

### 6.3 Motor — renderização do PDF

- O `template.html` + `assets/` + fontes passam a morar no motor (fonte única). Fontes **embutidas
  localmente** (sem Google Fonts em produção).
- Render com Chromium sem tela (Playwright para Python) dentro do container do motor. A imagem
  cresce (~300–400 MB); aceito pelo Eduardo ao escolher "igual ao aprovado".
- Mudanças no template: capa sem a palavra "turma" fixa → título "Planejamento previdenciário", e
  "Raio-X Elites" só quando `turma` vier; o resto já aceita 3–5 cenários, página do facultativo
  opcional e `premissa_extra`.
- O raio-x local (`render.cjs`) fica até o go-live do hub; depois o projeto vira arquivo (regra
  "só a versão mais nova").

### 6.4 Hub

- **Aba "Planejamento" substituída** (mesmo lugar no `LeadSimulador`, mesmo gate de CNIS).
  Passos na tela:
  1. Perfil: forma de contribuir (pré-selecionada pela sugestão do motor) + empresa, salário atual,
     cenário livre, turma (opcional), "incluir página sair da administração", chave do descarte nos
     pontos (escondida em "avançado", padrão estrita).
  2. Calcular → mostra o resumo (data, regra, tabela dos cenários, sugestão, parar) e as seções de
     texto **editáveis** (observações do CNIS, pode/não pode, sugestão, bom saber de cada cenário,
     próximos passos, documentos).
  3. Gerar → hub manda `dados` editado ao motor, recebe PDF + memória, **salva os dois na pasta do
     cliente** e oferece o download.
- **Pasta no Drive:** `pasta_cliente_id` (planejamento não é tese) numa subpasta
  `Planejamento previdenciário – MM.AA`. Nomes: `Planejamento previdenciário - <Nome>.pdf`
  (`Raio-X Elites - <Nome>.pdf` quando houver turma) e `Memória de cálculo - <Nome>.xlsx`.
  *Lead rascunho da página Cálculos (sem contato) → só download.*
- **Persistência:** o último `dados` editado fica no `calculos.snapshot` (via `RegistraCalculo`),
  para reabrir do histórico com os textos editados.
- **Tempo de resposta:** se o pedido não couber em ~10 s, o gerar vira job (Sidekiq) com aviso na
  tela ao terminar. Conferir `rack-timeout` na VPS antes de decidir.

### 6.5 Textos por forma de contribuir (gate do Eduardo)

- `pro_labore` e `pro_labore_mais_salario`: os modelos saem dos 4 PDFs aprovados (A, C, D = pró-labore;
  B = pró-labore + salário). Já estão aprovados no conteúdo.
- `carne_20`, `simplificado_11`, `baixa_renda_5`, `empregado`: modelos novos. O builder escreve, gera
  um PDF de exemplo por forma (com caso fictício ou com um dos 4 casos trocando a forma) e entrega ao
  Eduardo como rascunho. **Cada forma só liga na tela depois do aprovado dele** (as outras aparecem como
  "aguardando aprovação dos textos"). Regras de linguagem do raio-x valem para todas.

## 7. Ordem de entrega (cada fase fecha antes da próxima)

1. **Gabarito no motor (sem tela):** os 4 casos como teste de referência; correções 6.2 (1)–(4);
   o motor do hub roda **sem calibração** (não há Brenda no uso real) e com `corrigir_ate` fixado em
   08/2026 só no teste. Aceite (*call do Claude*): **data de cada regra igual à da Brenda (dia
   exato)**, renda de cada cenário e do "parar" a **até R$ 1,00** nos casos B, C e D; no caso A, a
   diferença de 0,24% é resolvida ou documentada com a causa. As colunas "R$ 5 mil" e "com descarte"
   da tabela do §5 vêm do motor do raio-x, calibrado; no hub valem com a mesma tolerância e ficam
   sujeitas à conferência da Brenda em andamento.
2. **Planejamento previdenciário no motor:** `/planejamento/previdenciario` (6.2 completo) +
   memória .xlsx; teste: o `dados` gerado para os 4 casos tem os mesmos números dos PDFs aprovados.
3. **PDF no motor:** template + Chromium + `/pdf`; teste: os 4 PDFs saem sem erro de conferência.
4. **Hub:** aba nova, Drive, histórico; PR com as skills do Matt (tdd, codebase-design,
   code-review, pr).
5. **Textos das outras formas (§6.5):** PDFs de exemplo → aprovado do Eduardo → liga cada forma.
6. **Go-live:** smoke do Eduardo; aposentar `pdf_planejamento.py` e a aba antiga; raio-x vira arquivo.
   O pró-labore pode ir ao ar antes das outras formas, se os textos delas ainda não estiverem aprovados.

## 8. Restrições

- **LGPD:** o repo do motor não pode receber nome/CPF/valores de cliente real em arquivo versionado.
  Os 4 casos entram como `caso-A..D` em fixture **gitignored** (`tests/cnis/reais/`, já é a regra),
  com os números esperados também fora do versionamento ou anonimizados. Histórico do motor ainda
  tem a pendência do `git filter-repo` antes de qualquer remote.
- Smart App Control na máquina do Eduardo: testes do motor com `.venv-store`.
- Deploy do motor: `git archive` → `/opt/motor-calculos` → build + up (serviço compose do hub =
  `chatwoot-web`). Nada sai sem o "aprovado" do Eduardo; merge e deploy com OK dele na conversa.
- Citações legais novas em texto de cliente → `revisor-citacoes` antes.

## 9. Fica com quem constrói

Nomes internos de funções e módulos; formato exato do JSON além dos campos acima; como a tela
organiza as seções editáveis; o algoritmo de refino da data (desde que bata nos 4 casos);
mapeamento completo de indicadores do CNIS para observações; layout da planilha além das 4 abas.

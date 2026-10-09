# Memória do contato nunca grava dado de saúde

A Memória do contato (A5, I-X7) lê o fim de uma conversa resolvida e grava no
Lead uma nota com o que vale lembrar da pessoa. Ela roda em conversa de **lead**,
que ainda não assinou contrato nem procuração — a base de consentimento que a
banca usa (contrato + procuração) ainda não existe nessa hora, e dado de saúde
é dado sensível. Para a tese seria útil guardar CID e diagnóstico.

Decidimos (Eduardo, decisão N1, 2026-10-07) que **a memória nunca grava dado de
saúde**, com duas camadas (`Ramon::MemoriaContato`):

- **O prompt é a regra:** lista o que pode ser anotado (benefício de interesse,
  trabalho, datas, benefício já recebido ou negado, documentos, "tem laudo:
  sim/não", horário, objeções) e proíbe doença, diagnóstico, CID, lesão, parte
  do corpo, remédio, exame, tratamento, CPF, RG, telefone, e-mail, endereço e
  dados de terceiros. O texto vai à IA mascarado e sem notas privadas.
- **O filtro `SAUDE` é a rede:** item que bate na lista de palavras não é
  gravado nem se a IA escrever. Nomes oficiais de benefício (auxílio-doença,
  aposentadoria por incapacidade, BPC/LOAS) e a espécie do INSS (B31, B91…)
  saem do item antes do teste, para passar — menos a espécie perto de
  laudo/atestado/perícia, onde pode ser código CID.
- **Sai para o lado seguro:** na dúvida o item cai; perder um fato é aceitável,
  gravar saúde não.
- **Teto de gasto:** no dia em que o gasto de IA da conta chega ao teto (US$ 2/dia,
  em Uso e custo), a memória não chama a IA. Sem lead, sem memória. Nasce
  desligada; liga-se em Configurações → Atendimento.

Consequências: falsos positivos conhecidos (fato inocente com "mão", "coluna",
"olhos" cai fora); o que escapar se resolve somando palavras ao filtro.

Alternativas descartadas:

- **Gravar também CID/diagnóstico** (opção b): mais útil para a tese, mas é dado
  sensível antes de existir a base do contrato.
- **Só o prompt**: a IA pode escorregar e o erro iria direto para o lead.
- **Só o filtro**: lista de palavras não cobre paráfrase; o prompt evita que a IA
  sequer escreva.

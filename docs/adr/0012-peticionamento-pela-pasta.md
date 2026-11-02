# Peticionamento pela pasta do Drive

Desenho em `docs/superpowers/specs/2026-11-02-peticionamento-pela-pasta-design.md`. Complementa o ADR 0010.

O Eduardo quer apontar uma pasta do Drive e dela sair a petição. Decisões de construção:

- **`conferencia` é um status da `Peticao`, não uma tabela à parte.** Depois de conferida, a petição segue o mesmo caminho
  da criada à mão (pacote, regras do tribunal, registro, arquivamento). Uma tabela de "importação" duplicaria tudo isso.
- **A leitura da peça usa a chave da API** (`Ramon::LlmClient`), como o `DocMatchService`. Nunca a assinatura do Claude.
  Falha da leitura não trava: a conferência abre com os campos vazios e um aviso.
- **A lista de pastas prontas vem do marcador `_pasta-pronta.json` no Drive, não de uma rota nova.** O
  `Ramon::PastasProntasJob` (a cada 5 min) varre o Drive e preenche `ramon_pastas_prontas`. São poucas peças por dia, e
  assim não existe rota pública para a esteira chamar.
- **Contrato do marcador:** `{"responsavel_email","titulo"}`, gravado dentro da pasta do protocolo, sob
  `RAMON_DRIVE_ROOT_ID`. O hub manda o marcador para a lixeira quando a petição existe.
- **Pasta apontada à mão pode estar em qualquer lugar do Drive do escritório.** Já a lista só aceita marcador dentro da
  raiz, para uma pasta alheia não aparecer como pronta.

Limites conhecidos:

- A conta é `RAMON_PETICOES_ACCOUNT_ID` (padrão 2).
- O responsável é achado pelo nome. Os usuários têm só o primeiro nome, então nome de uma palavra é marcado como incerto
  e a pessoa precisa confirmar o responsável na conferência. Esse checkbox existe só na tela: o backend não guarda nem
  confere a marcação.
- Tetos de tamanho: arquivo acima de 30 MB ou pasta acima de 100 MB é recusado antes de baixar, porque o job carrega tudo
  na memória. Tamanho que o Drive não informa conta como 0.
- A mesma pasta não vira duas petições (índice único por conta e pasta). Apagada a petição em conferência, a pasta pode
  ser apontada de novo.

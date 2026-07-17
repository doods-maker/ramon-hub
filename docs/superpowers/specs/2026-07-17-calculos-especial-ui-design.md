# Cálculos por cliente + tempo especial no Simulador (design)

**Data:** 17/07/2026 · **Aprovação do design:** Eduardo, 17/07 na conversa.
**Pré-requisito no motor:** F4 NO AR (motor master d1a4afc, VPS 17/07) — `/calcular` e
`/painel` aceitam `especial: {grau, inicio?, fim?}` dentro de cada item de `vinculos`
e devolvem cartões `especial_pre|especial_ec103|especial_pontos` + avisos.

## Objetivo (pedido do Eduardo)

1. Marcar **atividade especial** por vínculo no Simulador do lead.
2. Uma página interna **"Cálculos"** na área do escritório (menu junto de Funil,
   Playbooks, Linha da Vida): buscar o cliente e abrir o painel de possibilidades
   dele "como a página do Previdenciarista" — o mesmo painel de cartões já aprovado
   no smoke de 15/07 (referência visual: print iPrev/Resultado enviado em 13/07).

## Fatia 1 — Especial no painel "Ajustar vínculos" (LeadSimulador.vue)

- Cada vínculo do CNIS (`vinculos_detalhe`, por `seq`) ganha, além do checkbox de
  exclusão e da mensalidade: select **"Especial: — / 15 / 20 / 25 anos"** e, quando
  selecionado, 2 campos de data opcionais (início/fim do trecho de exposição —
  vazios = vínculo inteiro).
- Vínculos manuais (`vinculosExtras`, ex.: rural) ganham o mesmo select/campos.
- **Transporte (corrigido pós-exploração do código):** parâmetro novo `especiais`
  (JSON string, mapa `seq → {grau, inicio?, fim?}`) enviado no **POST
  `leads/:id/painel`** — não no `/cnis`: especial não afeta o parse do CNIS, só o
  painel, então **não exige re-upload do PDF** (UX melhor que excluir/mensalidade).
  O `LeadPaineisController#motor_payload` funde a marcação nos itens de `vinculos`
  por `seq`; `vinculos_extras` ganham campo `especial` embutido no item. O
  controller também persiste `especiais` em `lead.cnis['parametros']` (onde já
  vivem `excluir_seqs`/`mensalidades`) pra marcação sobreviver ao reload.
- **Erros:** 422 do motor (trecho fora do vínculo, graus sobrepostos, benefício
  marcado como especial) já chega com mensagem em pt — exibir no mesmo lugar dos
  erros atuais do painel, sem tradução extra.
- Os cartões `especial_*` e os avisos novos do motor renderizam no painel de
  possibilidades **sem trabalho novo** (o componente já itera cartões e avisos) —
  conferir apenas que nada filtra por lista fixa de ids.
- LGPD inalterada: PDF do CNIS segue só na memória do browser; reaplicar ajustes
  reenvia o arquivo (fluxo atual).

## Fatia 2 — Página interna "Cálculos"

- **Padrão Linha da Vida** (`pages/LinhaDaVida.vue`): item de menu novo
  "Cálculos", página tela cheia (`w-full h-full` — lição registrada), busca de
  pessoa (mesma API de busca da Linha da Vida).
- Selecionada a pessoa: resolve o(s) lead(s)/conversa(s) vinculados e renderiza o
  **LeadSimulador** existente em tela cheia para o lead escolhido (se >1 caso,
  lista pra escolher; se nenhum, estado vazio com orientação "abra uma conversa/
  lead pra esta pessoa").
- Nenhuma tela nova de cartões: o LeadSimulador é o componente-fonte; se ele tiver
  acoplamentos com o contexto de conversa (props/route), extrair o miolo pra um
  componente reutilizável é permitido, mantendo a tela da conversa intacta
  (spec 11/11 do componente continua valendo).

## Testes e entrega

- Vitest local (Windows: `npx vitest run <dir>`) pros componentes tocados
  (LeadSimulador.spec.js estende; página nova ganha spec de fumaça: busca →
  seleção → render). RSpec (backend: fusão do `especiais` no corpo) roda no CI.
- Entrega: branch `feat/calculos-especial-ui` → PR pra `ramon` → CI verde →
  **merge com OK do Eduardo na conversa** → deploy padrão (workflow ramon-publish
  builda no push; VPS: `docker compose pull && up -d` web/worker).
- Coordenação: há outra sessão ativa no hub hoje (finalizar-hub) — antes do
  deploy, confirmar que a `ramon` remota não avançou (rebase se preciso) e avisar
  na conversa.

## Fora de escopo

Liquidação (F3) na UI do hub (fatia futura); edição de vínculo do CNIS além da
marcação de especial; tábuas por sexo no motor.

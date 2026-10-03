# Redesign v2 do hub — fiel ao mockup aprovado (03/10/2026)

**Alvo visual (fonte da verdade):** `docs/superpowers/specs/mockups/2026-10-03-hub-v2.html`
(abra no navegador; barra de baixo troca tema, papel e tela; `#dark,sdr,hoje` abre direto).
Eduardo, 03/10: *"quero que fique EXATAMENTE assim, FAÇA ISSO!"*. Divergir do mockup só
com motivo técnico explícito, registrado no PR e avisado no roteiro de smoke.

## Por que

Eduardo achou o visual anterior (creme/bronze, "Material Claro") marrom, confuso,
com coisa demais na tela, navegação dupla (trilho + sidebar) e estilos misturados
(Chatwoot × telas nossas). O time comercial (SDR + Closer) entra em 03/11/2026 e a
caixa do escritório liga em nov/2026 — o hub novo precisa estar no ar antes, pra
ninguém aprender a ferramenta duas vezes.

## Regras visuais (valem em toda onda)

- Claro = branco puro; escuro = preto puro; neutros sem tom.
- Destaque AZUL nos dois temas: botão `#2563EB` (`n-blue-9`), texto de destaque
  `n-blue-11` (#1D4ED8 claro / #60A5FA escuro).
- Cor só com significado: vermelho = atraso/risco, âmbar = atenção/pendente,
  verde = ganho/ok. Etapa do funil = etiqueta (pill) com a cor da etapa.
- **Todo fundo colorido é translúcido** (a cor com alpha), nunca bloco chapado.
  Em Tailwind: `bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16]`,
  `bg-n-amber-9/15`, `bg-n-ruby-9/10`, `bg-n-teal-9/15`.
- Fonte: Geist (texto) + Geist Mono (`font-mono`) em números, horários, valores,
  telefones, CPF e nº de processo.
- Sem emoji na interface; ícones Lucide (`i-lucide-*`).
- Seções separadas por linha fina, sem cartão dentro de cartão.

## Ondas

| Onda | Escopo | Estado |
|---|---|---|
| 1 | Cores, fonte, etiquetas de etapa, avisos translúcidos | branch `feat/visual-branco-preto` (a2e76ff) |
| 2 | Menu único por papel (sai trilho + sidebar Chatwoot + sidebar Intranet) | este plano: `plans/2026-10-03-onda2-menu-unico.md` |
| 3 | Tela "Hoje" por papel (endpoint `ramon_hoje` + página) | plano a escrever ao fim da 2 |
| 4 | Conversa: lista com etiqueta+selo de prazo, cabeçalho enxuto, painel por caixa (lead × cliente ADVBOX + "Atribuir a…"), chegada em tela cheia | plano a escrever |
| 5 | Funil (filtro "Ganhos com docs pendentes", tese, cabeça de coluna em bloco), Clientes (lista) + Ficha em abas, busca Ctrl K própria | plano a escrever |

## Papéis

`papelDe({ isAdmin, nomesDosTimes })` (front, cosmético — o guard real segue nas rotas
e no backend):

1. administrador → `gestor`
2. time `recepção` ou `controladoria` → `recepcao` (Thaís substitui a Recepção)
3. time `closer` → `closer`
4. time `sdr` → `sdr`
5. time `advogados` → `advogada`
6. nenhum → `equipe` (vê o mesmo que SDR/Closer)

## Menu por papel (Onda 2)

| Item | Rota | gestor | sdr/closer/equipe | recepcao | advogada |
|---|---|---|---|---|---|
| Hoje | `ramon_index` (vira a tela Hoje na Onda 3) | ✓ | ✓ | ✓ | ✓ |
| Conversas (+ não lidas) | `home` | ✓ | ✓ | ✓ | ✓ |
| Funil | `ramon_funil` | ✓ | ✓ | | |
| Clientes | `ramon_pessoas` (vira lista própria na Onda 5) | ✓ | ✓ | ✓ | ✓ |
| Agenda (+ tarefas de hoje) | `ramon_agenda` | ✓ | ✓ | ✓ | ✓ |
| Cálculos | `ramon_calculos` | ✓ | ✓ | | ✓ |
| Conteúdo (+ aguardando aprovação) | `ramon_conteudo` | ✓ | | | |
| Resultados | gestor `ramon_relatorios`; demais `ramon_extrato` | ✓ | ✓ | | |
| Mais | lista expansível | ✓ | | | |

"Mais" (gestor): Esteira, Pós-venda, Radar de prescrição, Reuniões, Painel do cliente,
Extrato da variável, Placar de TV, Playbooks, Configurações do funil, Captain,
Contatos, Relatórios do Chatwoot, Configurações, atalhos externos + "Gerenciar atalhos".

Topo do menu: marca "RA" (quadrado bronze — único bronze do hub), botão
**Chegou cliente** (só `recepcao`), campo **Buscar · Ctrl K** (abre a command bar; vira
paleta própria na Onda 5), botão de nova conversa (ícone lápis — preserva função do
Chatwoot que o mockup não desenhou). Rodapé: avatar + nome + papel (abre o menu de
perfil do Chatwoot).

## Decisões das lacunas (Ondas 3–5)

- **Perícias/audiências da semana:** serviço novo sobre `Ramon::AdvboxClient.posts`
  (próximos 7 dias, tarefas cujo nome contém PERÍCIA/AUDIÊNCIA), cache 30 min
  (cota ADVBOX 500/dia compartilhada). Nomes reais das tarefas conferidos na VPS antes.
- **"Atribuída por X · hh:mm" e "Atribuídas hoje":** gravar quem/quando atribuiu na
  conversa (`additional_attributes.ramon_atribuicao = {por_id, por_nome, em}`) num
  callback de mudança de `assignee_id`/`team_id`. "Devolver" = tirar responsável e time.
- **Aguardando assinatura:** `custom_attributes.zapsign` preenchido e `won_at` nulo
  (o webhook do ZapSign não avisa o lead — fora de escopo).
- **Meta do mês da equipe:** soma de `ramon_metas_comerciais` do papel closer no mês;
  sem meta cadastrada, mostra só o número (sem "/ meta").
- **Pós-venda e Radar:** viram filtros do Funil calculados no front sobre o payload
  slim (já traz `won_at`, `docs_received/total`, `dcb_em`).
- **Clientes:** lista baseada no modo Lista do funil (`LeadListView`), rota própria.
- **Etapa na lista de conversas:** bloco slim `ramon_lead {stage_name, stage_color,
  thesis_name}` no jbuilder da conversa (preload pra não virar N+1). Prazo de 5 min
  calculado no front com `created_at`/`first_reply_created_at` + `first_response_sla_minutes`
  da inbox (helper extraído do `LeadCard`).
- **Busca Ctrl K:** paleta própria (grupos Clientes e leads · Processos · Ações) sobre
  `search/leads`, `search/contacts`, ADVBOX por CPF (11 dígitos) e por nº CNJ (padrão
  de processo, com debounce); a command bar antiga continua em Ctrl+Shift+K.

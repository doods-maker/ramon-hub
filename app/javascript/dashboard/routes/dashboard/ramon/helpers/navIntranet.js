// Menu da Intranet agrupado (decisão Eduardo 06/10): telas irmãs viram um item
// só, com abas no topo da página. Rotas e telas não mudam.
// Aba: `name` = rota de destino; `names` = rotas que acendem (deep-links
// contextuais acendem a aba-mãe). `adminOnly` espelha o guard da rota.
const aba = (name, label, extra = {}) => ({
  name,
  label: `RAMON.NAV.${label}`,
  names: [name, ...(extra.acende || [])],
  adminOnly: !!extra.adminOnly,
});

const SECOES = [
  {
    label: 'RAMON.NAV.OPERACAO',
    grupos: [
      {
        key: 'hoje',
        label: 'RAMON.NAV.HOJE',
        icon: 'i-lucide-layout-dashboard',
        abas: [aba('ramon_index', 'OVERVIEW'), aba('ramon_esteira', 'ESTEIRA')],
      },
      {
        key: 'funil',
        label: 'RAMON.NAV.FUNIL',
        icon: 'i-lucide-filter',
        abas: [
          aba('ramon_funil', 'FUNIL'),
          aba('ramon_radar', 'RADAR'),
          aba('ramon_pos_venda', 'POS_VENDA'),
        ],
      },
      {
        key: 'agenda',
        label: 'RAMON.NAV.AGENDA',
        icon: 'i-lucide-calendar-days',
        abas: [
          aba('ramon_agenda', 'AGENDA'),
          aba('ramon_reunioes', 'REUNIOES', { acende: ['ramon_reuniao'] }),
        ],
      },
      {
        key: 'clientes',
        label: 'RAMON.NAV.CLIENTES',
        icon: 'i-lucide-heart-pulse',
        abas: [
          aba('ramon_pessoas', 'LINHA_DA_VIDA', {
            acende: ['ramon_linha_da_vida', 'ramon_lead_dossie'],
          }),
          aba('ramon_portal_clientes', 'PORTAL'),
          aba('ramon_calculos', 'CALCULOS', {
            acende: ['ramon_calculos_lead'],
          }),
        ],
      },
    ],
  },
  {
    label: 'RAMON.NAV.GESTAO',
    grupos: [
      {
        key: 'conteudo',
        label: 'RAMON.NAV.CONTEUDO',
        icon: 'i-lucide-instagram',
        abas: [aba('ramon_conteudo', 'CONTEUDO', { adminOnly: true })],
      },
      {
        key: 'resultados',
        label: 'RAMON.NAV.RESULTADOS',
        icon: 'i-lucide-bar-chart-3',
        abas: [
          aba('ramon_extrato', 'EXTRATO'),
          aba('ramon_relatorios', 'RELATORIOS', { adminOnly: true }),
          // Placar é standalone (fora do layout): a aba só navega até ele.
          aba('ramon_tv', 'TV', { adminOnly: true }),
        ],
      },
      {
        key: 'configuracoes',
        label: 'RAMON.NAV.CONFIGURACOES',
        icon: 'i-lucide-sliders-horizontal',
        abas: [
          aba('ramon_funil_config', 'FUNIL_CONFIG', { adminOnly: true }),
          aba('ramon_playbooks', 'PLAYBOOKS', { adminOnly: true }),
        ],
      },
    ],
  },
];

// Seções visíveis para o papel: tira aba adminOnly e grupo/seção que esvaziar.
export const secoesIntranet = isAdmin =>
  SECOES.map(secao => ({
    ...secao,
    grupos: secao.grupos
      .map(grupo => ({
        ...grupo,
        abas: grupo.abas.filter(a => isAdmin || !a.adminOnly),
      }))
      .filter(grupo => grupo.abas.length),
  })).filter(secao => secao.grupos.length);

// Grupo (já filtrado pelo papel) que contém a rota atual; undefined se nenhum.
export const grupoDaRota = (routeName, isAdmin) =>
  secoesIntranet(isAdmin)
    .flatMap(secao => secao.grupos)
    .find(grupo => grupo.abas.some(a => a.names.includes(routeName)));

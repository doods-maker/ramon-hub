// Menu único (redesign v2 — mockup 03/10). `papeis` = quem vê o item;
// `names` = rotas que acendem o item. Rotas admin-only só aparecem pro gestor.
const TODOS = ['gestor', 'sdr', 'closer', 'recepcao', 'advogada', 'equipe'];
const COMERCIAL = ['gestor', 'sdr', 'closer', 'equipe'];

// Todas as rotas de conversation.routes.js, menos kanban_board.
export const CONVERSA_ROUTES = [
  'home',
  'inbox_conversation',
  'inbox_dashboard',
  'conversation_through_inbox',
  'label_conversations',
  'conversations_through_label',
  'team_conversations',
  'conversations_through_team',
  'folder_conversations',
  'conversations_through_folders',
  'conversation_mentions',
  'conversation_through_mentions',
  'conversation_unattended',
  'conversation_through_unattended',
  'conversation_participating',
  'conversation_through_participating',
];

// Caixa de notificações (inbox-view) acende o sino do topo.
export const NOTIFICACAO_ROUTES = ['inbox_view', 'inbox_view_conversation'];

// Abaixo de Conversas quando ela está acesa (as caixas entram no componente).
export const SUBITENS_CONVERSAS = [
  {
    key: 'mencoes',
    rota: 'conversation_mentions',
    names: ['conversation_mentions', 'conversation_through_mentions'],
  },
  {
    key: 'participando',
    rota: 'conversation_participating',
    names: ['conversation_participating', 'conversation_through_participating'],
  },
  {
    key: 'nao_atendidas',
    rota: 'conversation_unattended',
    names: ['conversation_unattended', 'conversation_through_unattended'],
  },
].map(item => ({ ...item, label: `RAMON.MENU.${item.key.toUpperCase()}` }));

// Áreas nativas do Chatwoot: ali o Dashboard monta o sidebar do Chatwoot
// (submenus de Configurações, Captain, Relatórios, Contatos, Campanhas, Central de ajuda).
const AREA_CHATWOOT =
  /\/accounts\/[^/]+\/(settings|captain|reports|contacts|companies|campaigns|portals)(\/|$)/;
export const ehAreaChatwoot = path => AREA_CHATWOOT.test(path);

const MENU = [
  {
    key: 'hoje',
    icon: 'i-lucide-sun',
    rota: 'ramon_index',
    names: ['ramon_index'],
    papeis: TODOS,
  },
  {
    key: 'conversas',
    icon: 'i-lucide-message-circle',
    rota: 'home',
    names: CONVERSA_ROUTES,
    papeis: TODOS,
    contador: 'conversas',
  },
  {
    key: 'funil',
    icon: 'i-lucide-columns-3',
    rota: 'ramon_funil',
    names: ['ramon_funil', 'kanban_board', 'ramon_pos_venda', 'ramon_radar'],
    papeis: COMERCIAL,
  },
  {
    key: 'clientes',
    icon: 'i-lucide-users',
    rota: 'ramon_pessoas',
    names: [
      'ramon_pessoas',
      'ramon_linha_da_vida',
      'ramon_lead_dossie',
      'ramon_portal_clientes',
    ],
    papeis: TODOS,
  },
  {
    key: 'agenda',
    icon: 'i-lucide-calendar',
    rota: 'ramon_agenda',
    names: ['ramon_agenda', 'ramon_reunioes', 'ramon_reuniao'],
    papeis: TODOS,
    contador: 'agenda',
  },
  {
    key: 'calculos',
    icon: 'i-lucide-calculator',
    rota: 'ramon_calculos',
    names: ['ramon_calculos', 'ramon_calculos_lead'],
    papeis: [...COMERCIAL, 'advogada'],
  },
  {
    key: 'conteudo',
    icon: 'i-lucide-image',
    rota: 'ramon_conteudo',
    names: ['ramon_conteudo'],
    papeis: ['gestor'],
    contador: 'conteudo',
  },
  {
    key: 'resultados',
    icon: 'i-lucide-chart-no-axes-column',
    rota: null,
    names: ['ramon_relatorios', 'ramon_extrato'],
    papeis: COMERCIAL,
  },
  {
    key: 'mais',
    icon: 'i-lucide-ellipsis',
    rota: null,
    names: [],
    papeis: ['gestor'],
  },
];

const MAIS = [
  {
    key: 'painel',
    icon: 'i-lucide-layout-dashboard',
    rota: 'ramon_painel',
  },
  { key: 'esteira', icon: 'i-lucide-zap', rota: 'ramon_esteira' },
  { key: 'pos_venda', icon: 'i-lucide-package-check', rota: 'ramon_pos_venda' },
  { key: 'radar', icon: 'i-lucide-radar', rota: 'ramon_radar' },
  { key: 'reunioes', icon: 'i-lucide-mic', rota: 'ramon_reunioes' },
  { key: 'portal', icon: 'i-lucide-smartphone', rota: 'ramon_portal_clientes' },
  { key: 'extrato', icon: 'i-lucide-receipt', rota: 'ramon_extrato' },
  { key: 'tv', icon: 'i-lucide-tv', rota: 'ramon_tv' },
  { key: 'playbooks', icon: 'i-lucide-book-open', rota: 'ramon_playbooks' },
  {
    key: 'funil_config',
    icon: 'i-lucide-sliders-horizontal',
    rota: 'ramon_funil_config',
  },
  {
    key: 'captain',
    icon: 'i-lucide-bot',
    rota: 'captain_assistants_index',
    params: { navigationPath: 'captain_assistants_responses_index' },
  },
  {
    key: 'contatos',
    icon: 'i-lucide-contact',
    rota: 'contacts_dashboard_index',
  },
  {
    key: 'relatorios_atendimento',
    icon: 'i-lucide-chart-line',
    rota: 'account_overview_reports',
  },
  { key: 'configuracoes', icon: 'i-lucide-settings', rota: 'settings_home' },
  {
    key: 'atalhos',
    icon: 'i-lucide-external-link',
    rota: 'ramon_external_shortcuts',
  },
];

const comLabel = item => ({
  ...item,
  label: `RAMON.MENU.${item.key.toUpperCase()}`,
});

const rotaResultados = papel =>
  papel === 'gestor' ? 'ramon_relatorios' : 'ramon_extrato';

export const itensDoMenu = papel =>
  MENU.filter(item => item.papeis.includes(papel)).map(item =>
    comLabel(
      item.key === 'resultados'
        ? { ...item, rota: rotaResultados(papel) }
        : item
    )
  );

export const itensDoMais = papel =>
  papel === 'gestor' ? MAIS.map(comLabel) : [];

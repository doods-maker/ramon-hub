// Menu da Intranet agrupado (decisão Eduardo 06/10): telas irmãs viram um item
// só, com abas no topo da página. Rotas e telas não mudam.
// Aba: `name` = rota de destino; `names` = rotas que acendem (deep-links
// contextuais acendem a aba-mãe). `adminOnly` espelha o guard da rota; `soPainel`
// só aparece para quem o backend liberou no painel dos agentes.
// `assistente`: rota com :assistantId (Captain). `query`: a aba só acende quando
// a query bate (ex.: Registro com tipo=ia = "Mudanças da IA").
const aba = (name, label, extra = {}) => ({
  name,
  label: `RAMON.NAV.${label}`,
  names: [name, ...(extra.acende || [])],
  adminOnly: !!extra.adminOnly,
  soPainel: !!extra.soPainel,
  assistente: !!extra.assistente,
  query: extra.query || null,
});
// ponytail: o flag CAPTAIN da conta não é checado aqui (instalação de 1 conta, ligado);
// o guard da rota segue barrando se um dia desligar.
const doAssistente = (name, label, extra = {}) =>
  aba(name, label, { ...extra, assistente: true });

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
          aba('ramon_conferencia_fases', 'CONFERENCIA_FASES'),
          aba('ramon_calculos', 'CALCULOS', {
            acende: ['ramon_calculos_lead'],
          }),
          aba('ramon_protocolos', 'PROTOCOLOS', {
            acende: ['ramon_protocolo'],
          }),
          aba('ramon_validacao_apto', 'VALIDACAO_APTO'),
        ],
      },
    ],
  },
  {
    label: 'RAMON.NAV.GESTAO',
    grupos: [
      {
        // Área Marketing (spec 2026-11-07): conteúdo + tráfego (Metabase) + custos e metas.
        key: 'marketing',
        label: 'RAMON.NAV.MARKETING',
        icon: 'i-lucide-megaphone',
        abas: [
          aba('ramon_conteudo', 'CONTEUDO', { adminOnly: true }),
          aba('ramon_marketing_trafego', 'TRAFEGO', { adminOnly: true }),
          aba('ramon_marketing_custos', 'CUSTOS_METAS', { adminOnly: true }),
        ],
      },
      {
        key: 'resultados',
        label: 'RAMON.NAV.RESULTADOS',
        icon: 'i-lucide-bar-chart-3',
        abas: [
          aba('ramon_painel_time', 'PAINEL_TIME'),
          aba('ramon_extrato', 'EXTRATO'),
          aba('ramon_relatorios', 'RELATORIOS', { adminOnly: true }),
          // Placar é standalone (fora do layout): a aba só navega até ele.
          aba('ramon_tv', 'TV', { adminOnly: true }),
        ],
      },
      {
        key: 'agentes',
        label: 'RAMON.NAV.PAINEL_AGENTES',
        icon: 'i-lucide-bot',
        abas: [
          aba('ramon_agentes', 'PAINEL_AGENTES', {
            adminOnly: true,
            soPainel: true,
          }),
        ],
      },
      {
        key: 'configuracoes',
        label: 'RAMON.NAV.CONFIGURACOES',
        icon: 'i-lucide-sliders-horizontal',
        abas: [
          aba('ramon_funil_config', 'FUNIL_CONFIG', { adminOnly: true }),
          aba('ramon_registro_acoes', 'REGISTRO_ACOES', { adminOnly: true }),
        ],
      },
    ],
  },
  {
    // Inteligência num lugar só (plano 2026-11-22): toda a IA do hub aqui.
    label: 'RAMON.NAV.INTELIGENCIA',
    grupos: [
      {
        key: 'ia_visao_geral',
        label: 'RAMON.NAV.IA_VISAO_GERAL',
        icon: 'i-lucide-sparkles',
        abas: [aba('captain_visao_geral_index', 'IA_VISAO_GERAL')],
      },
      {
        key: 'ia_como_atende',
        label: 'RAMON.NAV.IA_COMO_ATENDE',
        icon: 'i-lucide-route',
        abas: [
          aba('captain_como_ia_atende_index', 'IA_COMO_ATENDE', {
            adminOnly: true,
          }),
        ],
      },
      {
        key: 'ia_teses',
        label: 'RAMON.NAV.IA_TESES',
        icon: 'i-lucide-book-open',
        abas: [
          aba('ramon_playbooks', 'IA_TESES', { adminOnly: true }),
          doAssistente('captain_assistants_responses_index', 'IA_FAQS', {
            acende: [
              'captain_assistants_responses_pending',
              'captain_assistants_documents_index',
            ],
          }),
        ],
      },
      {
        key: 'ia_assistentes',
        label: 'RAMON.NAV.IA_ASSISTENTES',
        icon: 'i-lucide-bot-message-square',
        abas: [
          aba('captain_assistants_create_index', 'IA_ASSISTENTES'),
          doAssistente('captain_assistants_settings_index', 'IA_REGRAS', {
            acende: [
              'captain_assistants_guidelines_index',
              'captain_assistants_guardrails_index',
            ],
          }),
          doAssistente('captain_assistants_scenarios_index', 'IA_SKILLS'),
          aba('captain_ferramentas_index', 'IA_ACOES', {
            acende: ['captain_tools_index'],
          }),
          doAssistente('captain_assistants_inboxes_index', 'IA_CAIXAS'),
        ],
      },
      {
        key: 'ia_automacoes',
        label: 'RAMON.NAV.IA_AUTOMACOES',
        icon: 'i-lucide-workflow',
        abas: [
          aba('captain_automacoes_index', 'IA_AUTOMACOES', {
            adminOnly: true,
            acende: [
              'captain_automacoes_editor',
              'captain_automacoes_execucao',
            ],
          }),
        ],
      },
      {
        key: 'ia_testar',
        label: 'RAMON.NAV.IA_TESTAR',
        icon: 'i-lucide-flask-conical',
        abas: [
          doAssistente('captain_assistants_playground_index', 'IA_TESTAR'),
          doAssistente('captain_assistants_casos_teste_index', 'IA_CASOS', {
            adminOnly: true,
          }),
        ],
      },
      {
        key: 'ia_historico',
        label: 'RAMON.NAV.IA_HISTORICO',
        icon: 'i-lucide-history',
        abas: [
          aba('captain_execucoes_index', 'IA_EXECUCOES'),
          aba('captain_ia_uso_index', 'IA_USO', { adminOnly: true }),
          aba('ramon_registro_acoes', 'IA_MUDANCAS', {
            adminOnly: true,
            query: { tipo: 'ia' },
          }),
        ],
      },
    ],
  },
];

// Seções visíveis para o papel: tira aba adminOnly e grupo/seção que esvaziar.
export const secoesIntranet = (isAdmin, painel = false) =>
  SECOES.map(secao => ({
    ...secao,
    grupos: secao.grupos
      .map(grupo => ({
        ...grupo,
        abas: grupo.abas.filter(
          a => (isAdmin || !a.adminOnly) && (painel || !a.soPainel)
        ),
      }))
      .filter(grupo => grupo.abas.length),
  })).filter(secao => secao.grupos.length);

// A aba vale para esta rota (e, se pede query, para esta query).
export const abaBate = (a, routeName, query = {}) =>
  a.names.includes(routeName) &&
  Object.entries(a.query || {}).every(([k, v]) => query[k] === v);

// Grupo (já filtrado pelo papel) que contém a rota atual; undefined se nenhum.
// Aba com query bate primeiro: Registro com tipo=ia é do Histórico da IA.
export const grupoDaRota = (routeName, isAdmin, painel = false, query = {}) => {
  const grupos = secoesIntranet(isAdmin, painel).flatMap(s => s.grupos);
  const grupoCom = exigeQuery =>
    grupos.find(g =>
      g.abas.some(a => !!a.query === exigeQuery && abaBate(a, routeName, query))
    );
  return grupoCom(true) || grupoCom(false);
};

// Destino da aba (o componente põe o accountId). Aba de assistente passa pelo
// resolvedor do Captain, como o menu antigo: ele lembra o último assistente e
// abre FAQs sempre no assistente que fala com o lead (I-FQ5).
export const linkDaAba = a => {
  const query = { ...(a.query || {}) };
  if (!a.assistente) return { name: a.name, params: {}, query };
  return {
    name: 'captain_assistants_index',
    params: { navigationPath: a.name },
    query,
  };
};

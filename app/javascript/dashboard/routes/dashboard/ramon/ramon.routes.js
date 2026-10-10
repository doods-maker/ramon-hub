import { frontendURL } from '../../../helper/URLHelper';
import CommandCenter from './pages/CommandCenter.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ramon'),
    name: 'ramon_index',
    component: CommandCenter,
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/esteira'),
    name: 'ramon_esteira',
    component: () => import('./pages/Esteira.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/atalhos'),
    name: 'ramon_external_shortcuts',
    component: () => import('./pages/ExternalShortcuts.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/funil'),
    name: 'ramon_funil',
    component: () => import('./pages/Funil.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/agenda'),
    name: 'ramon_agenda',
    component: () => import('./pages/Agenda.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/config'),
    name: 'ramon_funil_config',
    component: () => import('./pages/FunilConfig.vue'),
    meta: { permissions: ['administrator'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/playbooks'),
    name: 'ramon_playbooks',
    component: () => import('./pages/Playbooks.vue'),
    meta: { permissions: ['administrator'], world: 'intranet' },
  },
  {
    // Registro de ações (audit log): só o gestor — o backend também barra.
    path: frontendURL('accounts/:accountId/ramon/registro-de-acoes'),
    name: 'ramon_registro_acoes',
    component: () => import('./pages/RegistroAcoes.vue'),
    meta: { permissions: ['administrator'], world: 'intranet' },
  },
  {
    // Sem contactId a mesma página vira a busca de pessoa (entrada do menu).
    path: frontendURL('accounts/:accountId/ramon/pessoa'),
    name: 'ramon_pessoas',
    component: () => import('./pages/LinhaDaVida.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/pessoa/:contactId'),
    name: 'ramon_linha_da_vida',
    component: () => import('./pages/LinhaDaVida.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/radar'),
    name: 'ramon_radar',
    component: () => import('./pages/RadarPrescricao.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/pos-venda'),
    name: 'ramon_pos_venda',
    component: () => import('./pages/PosVenda.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/lead/:leadId/dossie'),
    name: 'ramon_lead_dossie',
    component: () => import('./pages/Dossie.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    // Sem leadId a mesma página vira a busca de pessoa (entrada do menu).
    path: frontendURL('accounts/:accountId/ramon/calculos'),
    name: 'ramon_calculos',
    component: () => import('./pages/Calculos.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/calculos/:leadId'),
    name: 'ramon_calculos_lead',
    component: () => import('./pages/Calculos.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/reunioes'),
    name: 'ramon_reunioes',
    component: () => import('./pages/Reunioes.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/reunioes/:reuniaoId'),
    name: 'ramon_reuniao',
    component: () => import('./pages/Reunioes.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/conteudo'),
    name: 'ramon_conteudo',
    component: () => import('./pages/Conteudo.vue'),
    meta: { permissions: ['administrator'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/portal'),
    name: 'ramon_portal_clientes',
    component: () => import('./pages/PortalClientes.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    // Agente também entra (marca); aplicar no ADVBOX só o admin — o backend barra.
    path: frontendURL('accounts/:accountId/ramon/conferencia-de-fases'),
    name: 'ramon_conferencia_fases',
    component: () => import('./pages/ConferenciaFases.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    path: frontendURL('accounts/:accountId/ramon/relatorios'),
    name: 'ramon_relatorios',
    component: () => import('./pages/Relatorios.vue'),
    meta: { permissions: ['administrator'], world: 'intranet' },
  },
  {
    // Agente também entra: o backend só devolve o próprio extrato.
    path: frontendURL('accounts/:accountId/ramon/extrato'),
    name: 'ramon_extrato',
    component: () => import('./pages/Extrato.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
  {
    // Agente também entra: o backend só devolve a própria linha.
    path: frontendURL('accounts/:accountId/ramon/painel-do-time'),
    name: 'ramon_painel_time',
    component: () => import('./pages/PainelTime.vue'),
    meta: { permissions: ['administrator', 'agent'], world: 'intranet' },
  },
];

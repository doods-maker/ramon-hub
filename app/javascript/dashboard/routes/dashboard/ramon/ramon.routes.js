import { frontendURL } from '../../../helper/URLHelper';
import RamonOverview from './pages/RamonOverview.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ramon'),
    name: 'ramon_index',
    component: RamonOverview,
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
];

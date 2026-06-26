import { frontendURL } from '../../../helper/URLHelper';
import RamonOverview from './pages/RamonOverview.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ramon'),
    component: RamonOverview,
    children: [
      {
        path: '',
        name: 'ramon_index',
        component: RamonOverview,
        meta: { permissions: ['administrator', 'agent'] },
      },
    ],
  },
];

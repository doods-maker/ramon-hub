import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INSTALLATION_TYPES } from 'dashboard/constants/installationTypes';
import { frontendURL } from '../../../helper/URLHelper';

import CaptainPageRouteView from './pages/CaptainPageRouteView.vue';
import AssistantsIndexPage from './pages/AssistantsIndexPage.vue';
import AssistantEmptyStateIndex from './assistants/Index.vue';

import AssistantSettingsIndex from './assistants/settings/Settings.vue';
import AssistantInboxesIndex from './assistants/inboxes/Index.vue';
import AssistantPlaygroundIndex from './assistants/playground/Index.vue';
import AssistantGuardrailsIndex from './assistants/guardrails/Index.vue';
import AssistantGuidelinesIndex from './assistants/guidelines/Index.vue';
import AssistantScenariosIndex from './assistants/scenarios/Index.vue';
import DocumentsIndex from './documents/Index.vue';
import ResponsesIndex from './responses/Index.vue';
import ResponsesPendingIndex from './responses/Pending.vue';
import CustomToolsIndex from './tools/Index.vue';

const meta = {
  permissions: ['administrator', 'agent'],
  featureFlag: FEATURE_FLAGS.CAPTAIN,
  installationTypes: [INSTALLATION_TYPES.CLOUD, INSTALLATION_TYPES.ENTERPRISE],
};

const metaCustomTools = {
  permissions: ['administrator', 'agent'],
  featureFlag: FEATURE_FLAGS.CAPTAIN_CUSTOM_TOOLS,
  installationTypes: [INSTALLATION_TYPES.CLOUD, INSTALLATION_TYPES.ENTERPRISE],
};

const metaV2 = {
  permissions: ['administrator', 'agent'],
  featureFlag: FEATURE_FLAGS.CAPTAIN_V2,
  installationTypes: [INSTALLATION_TYPES.CLOUD, INSTALLATION_TYPES.ENTERPRISE],
};

// ramon: Automações (fluxos) — a API é só de administrador.
const metaAdmin = { ...meta, permissions: ['administrator'] };

const assistantRoutes = [
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/faqs'),
    component: ResponsesIndex,
    name: 'captain_assistants_responses_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/documents'),
    component: DocumentsIndex,
    name: 'captain_assistants_documents_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/tools'),
    component: CustomToolsIndex,
    name: 'captain_tools_index',
    meta: metaCustomTools,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/scenarios'),
    component: AssistantScenariosIndex,
    name: 'captain_assistants_scenarios_index',
    meta: metaV2,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/playground'),
    component: AssistantPlaygroundIndex,
    name: 'captain_assistants_playground_index',
    meta,
  },
  // ramon: Casos de teste da IA — aba do Testar, só administrador.
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/casos-teste'),
    component: () => import('./casos/CasosTeste.vue'),
    name: 'captain_assistants_casos_teste_index',
    meta: metaAdmin,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/inboxes'),
    component: AssistantInboxesIndex,
    name: 'captain_assistants_inboxes_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/faqs/pending'),
    component: ResponsesPendingIndex,
    name: 'captain_assistants_responses_pending',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:assistantId/settings'),
    component: AssistantSettingsIndex,
    name: 'captain_assistants_settings_index',
    meta,
  },
  // Settings sub-pages (guardrails and guidelines)
  {
    path: frontendURL(
      'accounts/:accountId/captain/:assistantId/settings/guardrails'
    ),
    component: AssistantGuardrailsIndex,
    name: 'captain_assistants_guardrails_index',
    meta: metaV2,
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/:assistantId/settings/guidelines'
    ),
    component: AssistantGuidelinesIndex,
    name: 'captain_assistants_guidelines_index',
    meta: metaV2,
  },
  {
    path: frontendURL('accounts/:accountId/captain/assistants'),
    component: AssistantEmptyStateIndex,
    name: 'captain_assistants_create_index',
    meta: {
      permissions: ['administrator', 'agent'],
      installationTypes: [
        INSTALLATION_TYPES.CLOUD,
        INSTALLATION_TYPES.ENTERPRISE,
      ],
    },
  },
  // ramon: telas da área de IA que são da conta, não de um assistente —
  // precisam vir ANTES do catch-all :navigationPath.
  {
    path: frontendURL('accounts/:accountId/captain/ferramentas'),
    component: () => import('./pages/Ferramentas.vue'),
    name: 'captain_ferramentas_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/execucoes'),
    component: () => import('./pages/Execucoes.vue'),
    name: 'captain_execucoes_index',
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/captain/visao-geral'),
    component: () => import('./pages/VisaoGeral.vue'),
    name: 'captain_visao_geral_index',
    meta,
  },
  // ramon: Uso e custo da IA — custo, provedor/modelo por função e alerta (só admin).
  {
    path: frontendURL('accounts/:accountId/captain/uso-e-custo'),
    component: () => import('./pages/UsoCusto.vue'),
    name: 'captain_ia_uso_index',
    meta: metaAdmin,
  },
  // O Vigia virou bloco da Visão geral: link antigo cai lá.
  {
    path: frontendURL('accounts/:accountId/captain/watchdog'),
    redirect: to => ({
      name: 'captain_visao_geral_index',
      params: to.params,
    }),
  },
  {
    path: frontendURL('accounts/:accountId/captain/automacoes'),
    component: () => import('./automacoes/Lista.vue'),
    name: 'captain_automacoes_index',
    meta: metaAdmin,
  },
  {
    path: frontendURL('accounts/:accountId/captain/automacoes/:fluxoId'),
    component: () => import('./automacoes/Editor.vue'),
    name: 'captain_automacoes_editor',
    meta: metaAdmin,
  },
  {
    path: frontendURL(
      'accounts/:accountId/captain/automacoes/:fluxoId/execucoes/:execId'
    ),
    component: () => import('./automacoes/Execucao.vue'),
    name: 'captain_automacoes_execucao',
    meta: metaAdmin,
  },
  {
    path: frontendURL('accounts/:accountId/captain/:navigationPath'),
    component: AssistantsIndexPage,
    name: 'captain_assistants_index',
    meta,
  },
];

export const routes = [
  {
    path: frontendURL('accounts/:accountId/captain'),
    component: CaptainPageRouteView,
    // A área abre na Visão geral (backlog §0).
    redirect: to => ({
      name: 'captain_visao_geral_index',
      params: to.params,
    }),
    children: [...assistantRoutes],
  },
];

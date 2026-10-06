import { frontendURL } from '../../../../helper/URLHelper';

// FORK(ramon): a Automação nativa saiu de Configurações (B3 das Automações em
// fluxo, decisão do Eduardo 06/10). O motor nativo segue no código, sem tela; o
// link antigo cai em Inteligência → Automações. Index.vue e o formulário ficam
// no código (sem rota) para o merge com o upstream.
const paraAutomacoes = to => ({
  name: 'captain_automacoes_index',
  params: { accountId: to.params.accountId },
});

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/automation'),
      redirect: paraAutomacoes,
    },
    {
      path: frontendURL('accounts/:accountId/settings/automation/list'),
      redirect: paraAutomacoes,
    },
  ],
};

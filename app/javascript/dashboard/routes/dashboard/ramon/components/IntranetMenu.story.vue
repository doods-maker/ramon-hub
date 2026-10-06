<script setup>
// Story do menu da Intranet agrupado + faixa de abas (aprovação por print,
// claro/escuro). Repete a casca do Dashboard.vue no mundo intranet: menu à
// esquerda, coluna com a faixa e a página (h-full, rolagem interna).
// Sem rede: window.axios responde vazio; sem router: a rota entra por provide.
import { provide, reactive } from 'vue';
import { routeLocationKey, routerKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import IntranetSidebar from './IntranetSidebar.vue';
import AbasIntranet from './AbasIntranet.vue';
import RamonPageHeader from './RamonPageHeader.vue';
import Agenda from '../pages/Agenda.vue';
import Calculos from '../pages/Calculos.vue';
import { CARTAO } from '../helpers/ui';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const responder = async () => ({ data: { payload: [] } });
window.axios = {
  get: responder,
  post: responder,
  patch: responder,
  put: responder,
  delete: responder,
};

const store = useStore();
// sem router: getCurrentAccountId lê a conta de rootState.route
store.registerModule('route', { state: { params: { accountId: 1 } } });
const papel = role =>
  store.commit(types.SET_CURRENT_USER, {
    id: 1,
    name: 'Eduardo Schlata',
    accounts: [{ id: 1, role, permissions: [role] }],
  });

const rota = reactive({
  name: 'ramon_funil',
  params: { accountId: 1 },
  query: {},
  meta: { world: 'intranet' },
});
provide(routeLocationKey, rota);
provide(routerKey, {
  push: () => Promise.resolve(),
  replace: () => Promise.resolve(),
  resolve: () => ({ href: '#' }),
  currentRoute: { value: rota },
});

const ir = (role, nome) => () => {
  papel(role);
  rota.name = nome;
};
const LINHAS = Array.from({ length: 30 }, (_, i) => i + 1);
</script>

<template>
  <Story
    title="Ramon/Menu da Intranet"
    :layout="{ type: 'single', iframe: true }"
  >
    <Variant
      v-for="v in [
        ['Admin', 'administrator', 'ramon_funil'],
        ['Agente', 'agent', 'ramon_extrato'],
        ['Clientes', 'administrator', 'ramon_calculos'],
        ['Agenda', 'agent', 'ramon_agenda'],
        ['Sidebar admin', 'administrator', 'ramon_funil'],
        ['Sidebar agente', 'agent', 'ramon_funil'],
      ]"
      :key="v[0]"
      :title="v[0]"
      :init-state="ir(v[1], v[2])"
    >
      <div class="flex h-screen overflow-hidden text-n-slate-12">
        <IntranetSidebar />
        <main
          class="flex flex-1 h-full w-full min-h-0 overflow-hidden bg-n-surface-1"
        >
          <div
            v-if="!v[0].startsWith('Sidebar')"
            class="flex flex-col flex-1 min-w-0 min-h-0"
          >
            <AbasIntranet />
            <div class="flex flex-1 min-h-0">
              <Agenda v-if="v[0] === 'Agenda'" />
              <Calculos v-else-if="v[0] === 'Clientes'" />
              <div
                v-else
                class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8"
              >
                <div class="mx-auto flex w-full max-w-3xl flex-col gap-3">
                  <RamonPageHeader
                    eyebrow="Página de exemplo"
                    title="Conteúdo da tela"
                    subtitle="A tela real entra aqui; a rota não muda."
                  />
                  <div v-for="n in LINHAS" :key="n" :class="CARTAO">
                    {{ `Linha ${n}` }}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </main>
      </div>
    </Variant>
  </Story>
</template>

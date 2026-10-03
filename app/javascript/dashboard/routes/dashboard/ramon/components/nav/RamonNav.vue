<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { getModifierKey } from 'dashboard/composables/utils/useKbd';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import SidebarProfileMenu from 'dashboard/components-next/sidebar/SidebarProfileMenu.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import { useRamonPapel } from '../../composables/useRamonPapel';
import { useNavContadores } from '../../composables/useNavContadores';
import {
  itensDoMenu,
  itensDoMais,
  NOTIFICACAO_ROUTES,
  SUBITENS_CONVERSAS,
} from '../../helpers/navItems';
import { DEFAULT_EXTERNAL_SHORTCUTS } from '../../externalShortcutsDefaults';

// Menu único (redesign v2, mockup 03/10): substitui trilho + sidebar do
// Chatwoot + sidebar da Intranet. Itens por papel em helpers/navItems.js.
defineProps({ isMobileSidebarOpen: { type: Boolean, default: false } });
const emit = defineEmits(['closeMobileSidebar', 'openKeyShortcutModal']);

const { t } = useI18n();
const route = useRoute();
const { accountScopedRoute } = useAccount();
const { uiSettings } = useUISettings();
const chegadas = useChegadasStore();
const { papel } = useRamonPapel();
const contadores = useNavContadores(papel);
const notificacoes = useMapGetter('notifications/getUnreadCount');
const caixas = useMapGetter('inboxes/getInboxes');

const itens = computed(() => itensDoMenu(papel.value));
const mais = computed(() => itensDoMais(papel.value));
const atalhos = computed(
  () => uiSettings.value.external_shortcuts ?? DEFAULT_EXTERNAL_SHORTCUTS
);
const maisAtivo = computed(() => mais.value.some(i => i.rota === route.name));
const maisAberto = ref(false);
watch(
  maisAtivo,
  ativo => {
    if (ativo) maisAberto.value = true;
  },
  { immediate: true }
);

const atalhoBusca = `${getModifierKey()} K`;
const ativo = item => item.names.includes(route.name);
const para = item => accountScopedRoute(item.rota, item.params);
const sinoAtivo = computed(() => NOTIFICACAO_ROUTES.includes(route.name));

// Com uma caixa só, listar a caixa é repetir "Conversas".
const caixasVisiveis = computed(() =>
  caixas.value?.length > 1 ? caixas.value : []
);
const caixaAtiva = caixa =>
  ['inbox_dashboard', 'conversation_through_inbox'].includes(route.name) &&
  String(route.params?.inbox_id) === String(caixa.id);

const ATIVO =
  'bg-n-blue-9/[0.08] font-medium text-n-blue-11 dark:bg-n-blue-9/[0.16]';
const INATIVO = 'text-n-slate-11 hover:bg-n-slate-3 hover:text-n-slate-12';
const SUBLISTA =
  'flex flex-col gap-0.5 border-n-weak ltr:ml-4 ltr:border-l ltr:pl-2 rtl:mr-4 rtl:border-r rtl:pr-2';
const SUBITEM = 'flex items-center gap-2 rounded-[7px] px-2 py-1 text-[13px]';
const CONTADOR_COR = {
  conversas: 'bg-n-blue-9 text-white',
  conteudo: 'bg-n-amber-9/15 text-n-amber-11',
  agenda: 'text-n-slate-9',
};
const numero = item => (item.contador ? contadores[item.contador].value : 0);

const abrirBusca = () => emitter.emit(BUS_EVENTS.OPEN_COMMAND_BAR);
const fechar = () => emit('closeMobileSidebar');

onMounted(contadores.carregar);
</script>

<template>
  <div
    v-if="isMobileSidebarOpen"
    class="fixed inset-0 z-30 bg-black/40 md:hidden"
    @click="fechar"
  />
  <aside
    class="fixed top-0 z-40 flex h-full w-[228px] flex-col border-n-weak bg-n-background px-2.5 py-3 transition-transform duration-200 ease-out ltr:left-0 ltr:border-r rtl:right-0 rtl:border-l md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0"
    :class="
      isMobileSidebarOpen
        ? 'translate-x-0 shadow-lg md:shadow-none'
        : 'ltr:-translate-x-full rtl:translate-x-full'
    "
  >
    <div class="flex items-center gap-2.5 px-2 pb-3 pt-1">
      <span
        class="grid size-[26px] place-items-center rounded-[7px] bg-[#754D2A] text-[11px] font-semibold text-white dark:bg-[#C4A882] dark:text-black"
      >
        {{ t('RAMON.MENU.MARCA_SIGLA') }}
      </span>
      <span class="text-[13.5px] font-semibold text-n-slate-12">
        {{ t('RAMON.MENU.MARCA') }}
      </span>
    </div>

    <button
      v-if="papel === 'recepcao' && chegadas.podeAvisar"
      type="button"
      data-test="chegou-cliente"
      class="mb-2.5 flex items-center justify-center gap-1.5 rounded-[9px] bg-n-blue-9 px-4 py-[9px] text-sm font-medium text-white hover:brightness-110"
      @click="chegadas.pedirPainel()"
    >
      <span class="i-lucide-bell-ring size-4" />
      {{ t('RAMON.CHEGADA.BOTAO') }}
    </button>

    <div class="mb-2.5 flex gap-1.5">
      <button
        type="button"
        data-test="buscar"
        class="flex min-w-0 flex-1 items-center gap-2 rounded-lg border border-n-weak px-2.5 py-1.5 text-[13px] text-n-slate-9 hover:border-n-strong"
        @click="abrirBusca"
      >
        <span class="i-lucide-search size-4 flex-shrink-0" />
        {{ t('RAMON.MENU.BUSCAR') }}
        <kbd
          class="font-mono text-[11px] text-n-slate-9 ltr:ml-auto rtl:mr-auto"
        >
          {{ atalhoBusca }}
        </kbd>
      </button>
      <router-link
        :to="accountScopedRoute('inbox_view')"
        :title="t('RAMON.MENU.NOTIFICACOES')"
        class="relative grid size-[34px] flex-shrink-0 place-items-center rounded-lg border border-n-weak"
        :class="sinoAtivo ? ATIVO : INATIVO"
        @click="fechar"
      >
        <span class="i-lucide-bell size-4" />
        <span
          v-if="notificacoes > 0"
          class="absolute -top-1.5 min-w-4 rounded-full bg-n-blue-9 px-1 text-center font-mono text-[10px] font-medium leading-4 text-white ltr:-right-1.5 rtl:-left-1.5"
        >
          {{ notificacoes }}
        </span>
      </router-link>
      <ComposeConversation align="start">
        <template #trigger>
          <button
            type="button"
            class="grid size-[34px] place-items-center rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-slate-3"
            :title="t('RAMON.MENU.NOVA_CONVERSA')"
          >
            <span class="i-lucide-pen-line size-4" />
          </button>
        </template>
      </ComposeConversation>
    </div>

    <nav class="flex min-h-0 flex-1 flex-col gap-0.5 overflow-y-auto">
      <template v-for="item in itens" :key="item.key">
        <button
          v-if="item.key === 'mais'"
          type="button"
          data-test="mais"
          class="flex items-center gap-2.5 rounded-[7px] px-2 py-1.5 text-[13.5px]"
          :class="INATIVO"
          @click="maisAberto = !maisAberto"
        >
          <span :class="item.icon" class="size-4 flex-shrink-0" />
          {{ t(item.label) }}
          <span
            class="size-4 ltr:ml-auto rtl:mr-auto"
            :class="
              maisAberto ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
            "
          />
        </button>
        <router-link
          v-else
          :to="para(item)"
          class="flex items-center gap-2.5 rounded-[7px] px-2 py-1.5 text-[13.5px]"
          :class="ativo(item) ? ATIVO : INATIVO"
          @click="fechar"
        >
          <span :class="item.icon" class="size-4 flex-shrink-0" />
          {{ t(item.label) }}
          <span
            v-if="numero(item)"
            class="rounded-full px-[7px] py-px font-mono text-[11px] font-medium ltr:ml-auto rtl:mr-auto"
            :class="CONTADOR_COR[item.contador]"
          >
            {{ numero(item) }}
          </span>
        </router-link>
        <div v-if="item.key === 'conversas' && ativo(item)" :class="SUBLISTA">
          <router-link
            v-for="sub in SUBITENS_CONVERSAS"
            :key="sub.key"
            :to="para(sub)"
            :class="[SUBITEM, ativo(sub) ? ATIVO : INATIVO]"
            @click="fechar"
          >
            {{ t(sub.label) }}
          </router-link>
          <router-link
            v-for="caixa in caixasVisiveis"
            :key="caixa.id"
            :to="accountScopedRoute('inbox_dashboard', { inbox_id: caixa.id })"
            :class="[SUBITEM, caixaAtiva(caixa) ? ATIVO : INATIVO]"
            @click="fechar"
          >
            <span class="truncate">{{ caixa.name }}</span>
          </router-link>
        </div>
      </template>

      <div v-if="maisAberto && mais.length" :class="SUBLISTA">
        <button
          v-if="chegadas.podeAvisar"
          type="button"
          data-test="mais-avisar-chegada"
          :class="[SUBITEM, INATIVO]"
          @click="chegadas.pedirPainel()"
        >
          <span class="i-lucide-bell-ring size-3.5 flex-shrink-0" />
          {{ t('RAMON.CHEGADA.TITULO') }}
        </button>
        <router-link
          v-for="item in mais"
          :key="item.key"
          :to="para(item)"
          :class="[SUBITEM, route.name === item.rota ? ATIVO : INATIVO]"
          @click="fechar"
        >
          <span :class="item.icon" class="size-3.5 flex-shrink-0" />
          {{ t(item.label) }}
        </router-link>
        <a
          v-for="atalho in atalhos"
          :key="atalho.url"
          :href="atalho.url"
          target="_blank"
          rel="noopener noreferrer"
          :class="[SUBITEM, INATIVO]"
        >
          <span
            :class="atalho.icon || 'i-lucide-external-link'"
            class="size-3.5 flex-shrink-0"
          />
          {{ atalho.label }}
        </a>
      </div>
    </nav>

    <div class="border-t border-n-weak px-1 pt-2">
      <SidebarProfileMenu
        :subtitle="t(`RAMON.MENU.PAPEL.${papel}`)"
        :avatar-size="24"
        @open-key-shortcut-modal="emit('openKeyShortcutModal')"
      />
    </div>
  </aside>
</template>

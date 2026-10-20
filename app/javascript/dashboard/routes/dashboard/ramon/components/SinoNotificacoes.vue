<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import NotificationsAPI from 'dashboard/api/notifications';
import { dynamicTime, shortTimestamp } from 'shared/helpers/timeHelper';

// Sino do canto superior direito (Eduardo, 20/10): todas as notificações do
// usuário — as do Chatwoot (conversa) e as do hub (primary_actor = Lead, texto
// no push_message_title / meta.label). Notificação nova pelo cable vira um
// toast discreto por 6 s. A chegada de cliente não passa por aqui (tem o
// alerta azul próprio, evento ramon.chegada.*).
const TOAST_MS = 6000;

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const meta = useMapGetter('notifications/getMeta');
const notificacoes = useMapGetter('notifications/getNotifications');
const aberto = ref(false);
const toast = ref(null);
let toastTimer = null;

const contagem = computed(() => {
  const n = meta.value?.unreadCount || 0;
  if (!n) return '';
  return n > 99 ? '99+' : String(n);
});

// Título: o do servidor (no cable vem igual ao corpo); hub: o label do meta.
const titulo = n => n.push_message_title || n.meta?.label || '';
const corpo = n =>
  n.push_message_body && n.push_message_body !== titulo(n)
    ? n.push_message_body
    : '';
// Sem data não quebra o sino inteiro (date-fns lança em data inválida).
const quando = n => {
  const ts = n.last_activity_at || n.created_at;
  return ts ? shortTimestamp(dynamicTime(ts)) : '';
};

// Conversa (id = display_id) ou lead: a conversa dele, senão a ficha.
// ponytail: lead.conversation_id vai na URL como display_id — coincidem em
// produção (mesmo atalho do LeadPanelBody e do Dossiê).
const destino = n => {
  const ator = n.primary_actor || {};
  if (n.primary_actor_type === 'Conversation') {
    return { name: 'inbox_conversation', params: { conversation_id: ator.id } };
  }
  if (n.primary_actor_type !== 'Lead') return null;
  return ator.conversation_id
    ? {
        name: 'inbox_conversation',
        params: { conversation_id: ator.conversation_id },
      }
    : { name: 'ramon_lead_dossie', params: { leadId: n.primary_actor_id } };
};

const fechar = () => {
  aberto.value = false;
};
const alternar = () => {
  aberto.value = !aberto.value;
  if (aberto.value) store.dispatch('notifications/get');
};

const abrir = n => {
  fechar();
  toast.value = null;
  // Por id (PATCH): o read do store marca por primary_actor e o backend só
  // aceita Conversation — com Lead ele marcaria TODAS como lidas. A contagem
  // volta atualizada pelo notification.updated do cable.
  if (!n.read_at) NotificationsAPI.update(n.id, {}).catch(() => {});
  const rota = destino(n);
  if (rota) router.push(rota);
};

const marcarTodas = () =>
  store.dispatch('notifications/readAll').catch(() => {});

useEmitter(BUS_EVENTS.RAMON_NOTIFICACAO_NOVA, n => {
  if (aberto.value || !n) return;
  toast.value = n;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.value = null;
  }, TOAST_MS);
});

// No mundo Intranet a sidebar do Chatwoot (que buscava a contagem) não monta.
onMounted(() => store.dispatch('notifications/unReadCount'));
</script>

<template>
  <div v-on-click-outside="fechar" class="relative">
    <button
      type="button"
      data-testid="sino"
      :title="t('RAMON.SINO.TITULO')"
      :aria-label="t('RAMON.SINO.TITULO')"
      class="relative grid size-8 place-content-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
      :class="{ 'bg-n-alpha-2 text-n-slate-12': aberto }"
      @click="alternar"
    >
      <span class="i-lucide-bell size-4" />
      <span
        v-if="contagem"
        data-testid="sino-contagem"
        class="absolute -top-1 grid h-4 min-w-4 place-items-center rounded-full bg-n-ruby-9 px-1 text-[10px] font-medium leading-none text-white ltr:-right-1.5 rtl:-left-1.5"
      >
        {{ contagem }}
      </span>
    </button>

    <div
      v-if="aberto"
      data-testid="sino-painel"
      class="absolute top-full z-50 mt-2 flex w-[22rem] max-w-[calc(100vw-2rem)] flex-col overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 shadow-lg ltr:right-0 rtl:left-0"
    >
      <div
        class="flex items-center justify-between gap-2 border-b border-n-weak px-3 py-2"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('RAMON.SINO.TITULO') }}
        </span>
        <button
          type="button"
          data-testid="sino-marcar-todas"
          class="text-xs text-n-blue-11 hover:underline disabled:opacity-50 disabled:no-underline"
          :disabled="!contagem"
          @click="marcarTodas"
        >
          {{ t('RAMON.SINO.MARCAR_TODAS') }}
        </button>
      </div>
      <div class="max-h-[60vh] overflow-y-auto">
        <p
          v-if="!notificacoes.length"
          class="px-3 py-6 text-center text-xs text-n-slate-10"
        >
          {{ t('RAMON.SINO.VAZIO') }}
        </p>
        <button
          v-for="n in notificacoes"
          :key="n.id"
          type="button"
          data-testid="sino-item"
          class="flex w-full items-start gap-2 px-3 py-2.5 text-start hover:bg-n-alpha-2"
          @click="abrir(n)"
        >
          <span
            class="mt-1.5 size-2 shrink-0 rounded-full"
            :class="n.read_at ? 'bg-transparent' : 'bg-n-blue-9'"
          />
          <span class="min-w-0 flex-1">
            <span
              class="line-clamp-2 text-[13px]"
              :class="
                n.read_at ? 'text-n-slate-11' : 'font-medium text-n-slate-12'
              "
            >
              {{ titulo(n) }}
            </span>
            <span
              v-if="corpo(n)"
              class="mt-0.5 block truncate text-xs text-n-slate-10"
            >
              {{ corpo(n) }}
            </span>
          </span>
          <span class="shrink-0 text-[11px] text-n-slate-10">
            {{ quando(n) }}
          </span>
        </button>
      </div>
      <router-link
        :to="accountScopedRoute('inbox_view')"
        data-testid="sino-ver-todas"
        class="border-t border-n-weak px-3 py-2 text-center text-xs text-n-blue-11 hover:bg-n-alpha-2"
        @click="fechar"
      >
        {{ t('RAMON.SINO.VER_TODAS') }}
      </router-link>
    </div>

    <button
      v-if="toast"
      type="button"
      data-testid="sino-toast"
      class="fixed top-12 z-[60] flex w-80 max-w-[calc(100vw-2rem)] items-start gap-2 rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5 text-start shadow-lg ltr:right-3 rtl:left-3"
      @click="abrir(toast)"
    >
      <span class="i-lucide-bell mt-0.5 size-4 shrink-0 text-n-blue-11" />
      <span class="line-clamp-2 text-[13px] text-n-slate-12">
        {{ titulo(toast) }}
      </span>
    </button>
  </div>
</template>

<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { useChegadasStore } from 'dashboard/stores/chegadas';

// Alerta que insiste (Equipe · Fatia 1): overlay + toque em loop + notificação
// do sistema + título piscando até a pessoa responder. Montado sempre no
// Dashboard; recarregar a página recupera as pendências via carregar().
const RINGTONE_URL = '/audio/dashboard/ringtone.mp3';

const { t } = useI18n();
const getters = useStoreGetters();
const chegadas = useChegadasStore();

const userId = computed(() => getters.getCurrentUserID.value);
const alertas = computed(() => chegadas.alertasPara(userId.value));
const atual = computed(() => alertas.value[0]);
const souDestinatario = computed(
  () => atual.value?.destinatario.id === userId.value
);
const resposta = ref('');
const enviando = ref(false);

const ringtone = new Audio(RINGTONE_URL);
ringtone.loop = true;
let piscar = null;
let tituloOriginal = '';
const notificados = new Set();

const notificarSistema = chegada => {
  if (notificados.has(chegada.id)) return;
  if (!('Notification' in window) || Notification.permission !== 'granted')
    return;
  notificados.add(chegada.id);
  const params = { cliente: chegada.cliente_nome };
  const titulo =
    chegada.destinatario.id === userId.value
      ? t('RAMON.CHEGADA.NOTIF_CHEGOU', params)
      : t('RAMON.CHEGADA.NOTIF_SEM_RESPOSTA', params);
  // eslint-disable-next-line no-new
  new Notification(titulo, {
    body: chegada.motivo || '',
    requireInteraction: true,
    tag: `chegada-${chegada.id}-${chegada.estado}`,
  });
};

const pararPiscar = () => {
  if (!piscar) return;
  clearInterval(piscar);
  piscar = null;
  document.title = tituloOriginal;
};

const comecarPiscar = () => {
  if (piscar) return;
  tituloOriginal = document.title;
  piscar = setInterval(() => {
    document.title =
      document.title === tituloOriginal
        ? `🔔 ${atual.value?.cliente_nome || ''}`
        : tituloOriginal;
  }, 1000);
};

const parar = () => {
  ringtone.pause();
  ringtone.currentTime = 0;
  pararPiscar();
};

// Só reage à troca da 1ª da fila (id), não a upsert do mesmo item (ex.:
// escalou) — senão apagaria a resposta digitada e reiniciaria o toque.
watch(
  () => atual.value?.id,
  id => {
    if (id === undefined) {
      parar();
      return;
    }
    resposta.value = '';
    ringtone.play().catch(() => {});
    comecarPiscar();
  },
  { immediate: true }
);

// Notifica todas as pendentes (a fila pode crescer com a aba em segundo plano).
watch(alertas, lista => lista.forEach(notificarSistema), { immediate: true });

const enviar = async () => {
  if (!resposta.value.trim() || enviando.value) return;
  enviando.value = true;
  try {
    await chegadas.responder(atual.value.id, resposta.value.trim());
  } finally {
    enviando.value = false;
  }
};

// Navegador só pede permissão com gesto do usuário: no 1º clique em qualquer
// lugar do hub, pergunta (uma vez). Vale pra todo mundo, não só a recepção.
const pedirPermissao = () => {
  if (atual.value) ringtone.play().catch(() => {}); // autoplay bloqueado antes do 1º clique
  if ('Notification' in window && Notification.permission === 'default')
    Notification.requestPermission();
};

onMounted(() => {
  chegadas.carregar().catch(() => {});
  document.addEventListener('click', pedirPermissao, { once: true });
});
onBeforeUnmount(() => {
  parar();
  document.removeEventListener('click', pedirPermissao);
});
</script>

<template>
  <div
    v-if="atual"
    data-testid="alerta-chegada"
    class="fixed inset-0 z-[100] flex items-center justify-center bg-n-alpha-black1 p-4 backdrop-blur-[4px]"
  >
    <div
      class="w-full max-w-md rounded-xl bg-n-solid-1 p-6 shadow-xl outline outline-1 outline-n-weak"
    >
      <p class="text-sm text-n-slate-11">
        {{
          souDestinatario
            ? t('RAMON.CHEGADA.CHEGOU', { quem: atual.criado_por.name })
            : t('RAMON.CHEGADA.SEM_RESPOSTA', { quem: atual.destinatario.name })
        }}
      </p>
      <h2 class="mt-1 text-2xl font-semibold text-n-slate-12">
        {{ atual.cliente_nome }}
      </h2>
      <p v-if="atual.motivo" class="mt-1 text-n-slate-11">{{ atual.motivo }}</p>

      <form
        v-if="souDestinatario"
        class="mt-4 flex flex-col gap-2"
        @submit.prevent="enviar"
      >
        <textarea
          v-model="resposta"
          data-testid="chegada-resposta"
          rows="2"
          autofocus
          :placeholder="t('RAMON.CHEGADA.RESPOSTA_PLACEHOLDER')"
          class="w-full rounded-lg bg-n-alpha-black2 p-2 text-n-slate-12 outline outline-1 outline-n-weak"
          @keydown.enter.exact.prevent="enviar"
        />
        <button
          type="submit"
          :disabled="!resposta.trim() || enviando"
          class="rounded-lg bg-n-brand px-4 py-2 font-medium text-white disabled:opacity-50"
        >
          {{ t('RAMON.CHEGADA.RESPONDER') }}
        </button>
      </form>
      <button
        v-else
        type="button"
        class="mt-4 w-full rounded-lg bg-n-brand px-4 py-2 font-medium text-white"
        @click="chegadas.marcarVisto(atual.id)"
      >
        {{ t('RAMON.CHEGADA.ENTENDI') }}
      </button>

      <p v-if="alertas.length > 1" class="mt-3 text-xs text-n-slate-11">
        {{ t('RAMON.CHEGADA.MAIS', { n: alertas.length - 1 }) }}
      </p>
    </div>
  </div>
</template>

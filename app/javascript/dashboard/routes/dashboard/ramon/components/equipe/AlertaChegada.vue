<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import { useAlert } from 'dashboard/composables';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';

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
const dialogRef = ref(null);

const ringtone = new Audio(RINGTONE_URL);
ringtone.loop = true;
let piscar = null;
let tituloOriginal = '';
const notificacoes = new Map(); // id → Notification aberta

const notificarSistema = chegada => {
  if (notificacoes.has(chegada.id)) return;
  if (!('Notification' in window) || Notification.permission !== 'granted')
    return;
  const params = { cliente: chegada.cliente_nome };
  const titulo =
    chegada.destinatario.id === userId.value
      ? t('RAMON.CHEGADA.NOTIF_CHEGOU', params)
      : t('RAMON.CHEGADA.NOTIF_SEM_RESPOSTA', params);
  const n = new Notification(titulo, {
    body: chegada.motivo || '',
    requireInteraction: true,
    tag: `chegada-${chegada.id}-${chegada.estado}`,
  });
  n.onclick = () => {
    window.focus();
    n.close();
  };
  notificacoes.set(chegada.id, n);
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

// O overlay é <dialog> modal (top layer): fica acima de outros Dialog abertos
// com showModal(), que senão o cobririam e o deixariam inerte.
watch(
  [() => !!atual.value, dialogRef],
  ([temAlerta, el]) => {
    if (!el) return;
    if (temAlerta && !el.open) el.showModal?.();
    else if (!temAlerta) el.close?.();
  },
  { flush: 'post' }
);

// Esc pode fechar o <dialog> mesmo com cancel.prevent (o Chrome deixa na 2ª
// vez sem gesto): enquanto houver alerta, reabre.
const manterAberto = () => {
  if (atual.value) dialogRef.value?.showModal?.();
};

// Notifica todas as pendentes (a fila pode crescer com a aba em segundo plano)
// e fecha a notificação do sistema de quem saiu da fila.
watch(
  alertas,
  lista => {
    lista.forEach(notificarSistema);
    notificacoes.forEach((n, id) => {
      if (lista.some(c => c.id === id)) return;
      n.close();
      notificacoes.delete(id);
    });
  },
  { immediate: true }
);

// A Recepção fica sabendo da resposta mesmo com o painel fechado. As já
// respondidas no 1º carregar não viram toast (recarregar a página).
const respostasAvisadas = new Set();
let respostasProntas = false;
const minhasRespondidas = () =>
  chegadas.itens.filter(c => c.criado_por.id === userId.value && c.resposta);
watch(minhasRespondidas, lista => {
  if (!respostasProntas) return;
  lista.forEach(c => {
    if (respostasAvisadas.has(c.id)) return;
    respostasAvisadas.add(c.id);
    useAlert(
      t('RAMON.CHEGADA.RESPONDEU', {
        quem: c.destinatario.name,
        resposta: c.resposta,
      })
    );
  });
});

const recarregar = () => chegadas.carregar().catch(() => {});
useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT, recarregar);

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

onMounted(async () => {
  await recarregar();
  minhasRespondidas().forEach(c => respostasAvisadas.add(c.id));
  respostasProntas = true;
  document.addEventListener('click', pedirPermissao, { once: true });
});
onBeforeUnmount(() => {
  parar();
  document.removeEventListener('click', pedirPermissao);
});
</script>

<template>
  <dialog
    ref="dialogRef"
    class="w-[calc(100%-2rem)] max-w-md bg-transparent p-0 backdrop:bg-n-alpha-black1 backdrop:backdrop-blur-[4px]"
    @cancel.prevent
    @close="manterAberto"
  >
    <div
      v-if="atual"
      data-testid="alerta-chegada"
      class="w-full rounded-xl bg-n-solid-1 p-6 shadow-xl outline outline-1 outline-n-weak"
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
  </dialog>
</template>

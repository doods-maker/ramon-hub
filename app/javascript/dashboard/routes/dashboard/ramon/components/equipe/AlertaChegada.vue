<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import { useAlert } from 'dashboard/composables';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useIntervalFn } from '@vueuse/core';
import { BTN_CHEIO, BTN_LINHA, horaDe } from '../hoje/hoje';

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

const responderCom = async texto => {
  if (!texto || enviando.value) return;
  enviando.value = true;
  try {
    await chegadas.responder(atual.value.id, texto);
  } finally {
    enviando.value = false;
  }
};
const enviar = () => responderCom(resposta.value.trim());

// Redesign v2 (mockup #chegada): respostas prontas — vão pra quem AVISOU
// (interno), nunca pro cliente. "Responder outra coisa" abre o texto livre.
const RAPIDAS = [
  'RAMON.CHEGADA.ATENDER_AGORA',
  'RAMON.CHEGADA.AGUARDAR',
  'RAMON.CHEGADA.NAO_POSSO',
];
const outraCoisa = ref(false);
watch(
  () => atual.value?.id,
  () => {
    outraCoisa.value = false;
  }
);

// "Sem resposta em m:ss, o aviso volta pra …" — mesmo prazo do
// Ramon::ChegadaEscalarJob (Chegada::ESCALAR_APOS = 3 min).
// ref próprio (não o do useNow): o do vueuse não re-renderiza nos testes.
const ESCALAR_APOS_MS = 3 * 60 * 1000;
const agora = ref(Date.now());
useIntervalFn(() => {
  agora.value = Date.now();
}, 1000);
const voltaEm = computed(() => {
  if (atual.value?.estado !== 'aguardando' || !atual.value.created_at)
    return null;
  const fim = new Date(atual.value.created_at).getTime() + ESCALAR_APOS_MS;
  const s = Math.max(0, Math.round((fim - agora.value) / 1000));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
});

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
  <!-- tela inteira em azul translúcido + desfoque; cartão no centro -->
  <dialog
    ref="dialogRef"
    class="m-0 h-screen max-h-none w-screen max-w-none place-items-center border-0 bg-n-blue-9/[0.18] p-4 backdrop-blur-md backdrop:bg-transparent open:grid dark:bg-n-blue-9/[0.22]"
    role="alertdialog"
    :aria-label="t('RAMON.CHEGADA.CLIENTE_CHEGOU')"
    @cancel.prevent
    @close="manterAberto"
  >
    <div
      v-if="atual"
      data-testid="alerta-chegada"
      class="w-[460px] max-w-[calc(100vw-32px)] rounded-[18px] border border-n-blue-9/40 bg-n-background p-7 text-center shadow-[0_24px_80px_rgb(37_99_235/0.35)]"
    >
      <div
        class="mx-auto mb-3.5 grid size-[52px] animate-pulse place-items-center rounded-full bg-n-blue-9/[0.08] text-n-blue-11 motion-reduce:animate-none dark:bg-n-blue-9/[0.16]"
      >
        <span class="i-lucide-bell-ring size-6" />
      </div>
      <p class="text-[12.5px] font-semibold uppercase text-n-blue-11">
        {{
          souDestinatario
            ? t('RAMON.CHEGADA.CLIENTE_CHEGOU')
            : t('RAMON.CHEGADA.SEM_RESPOSTA', { quem: atual.destinatario.name })
        }}
      </p>
      <h2 class="my-1 text-[28px] font-semibold tracking-tight text-n-slate-12">
        {{ atual.cliente_nome }}
      </h2>
      <p v-if="atual.created_at" class="text-[13.5px] text-n-slate-11">
        {{
          t('RAMON.CHEGADA.AVISADO_POR', {
            quem: atual.criado_por.name,
            hora: horaDe(atual.created_at),
          })
        }}
      </p>
      <p
        v-if="atual.motivo"
        class="mt-4 rounded-[10px] bg-n-amber-9/15 px-3 py-2.5 text-left text-[13px] text-n-slate-12"
      >
        <b class="font-semibold text-n-amber-11">
          {{ t('RAMON.CHEGADA.RECADO') }}
        </b>
        {{ atual.motivo }}
      </p>

      <template v-if="souDestinatario">
        <div class="mt-5 flex flex-col gap-2">
          <button
            v-for="(chave, i) in RAPIDAS"
            :key="chave"
            type="button"
            :data-testid="`chegada-rapida-${i}`"
            :class="[
              i === 0 ? BTN_CHEIO : BTN_LINHA,
              { '!border-transparent !text-n-slate-11': i === 2 },
            ]"
            class="justify-center !rounded-[9px] !px-4 !py-[9px] !text-sm disabled:opacity-50"
            :disabled="enviando"
            @click="responderCom(t(chave))"
          >
            {{ t(chave) }}
          </button>
        </div>
        <button
          v-if="!outraCoisa"
          type="button"
          data-testid="chegada-outra-coisa"
          class="mt-3 text-xs text-n-blue-11 underline underline-offset-2"
          @click="outraCoisa = true"
        >
          {{ t('RAMON.CHEGADA.OUTRA_COISA') }}
        </button>
        <form v-else class="mt-3 flex flex-col gap-2" @submit.prevent="enviar">
          <textarea
            v-model="resposta"
            data-testid="chegada-resposta"
            rows="2"
            autofocus
            :placeholder="t('RAMON.CHEGADA.RESPOSTA_PLACEHOLDER')"
            class="!mb-0 w-full rounded-[9px] border border-n-strong bg-transparent p-2 text-left text-sm text-n-slate-12 outline-none focus:border-n-blue-9"
            @keydown.enter.exact.prevent="enviar"
          />
          <button
            type="submit"
            :disabled="!resposta.trim() || enviando"
            :class="BTN_LINHA"
            class="justify-center disabled:opacity-50"
          >
            {{ t('RAMON.CHEGADA.RESPONDER') }}
          </button>
        </form>
        <p
          v-if="voltaEm"
          data-testid="chegada-volta-em"
          class="mt-3.5 text-xs text-n-slate-9"
        >
          {{
            t('RAMON.CHEGADA.VOLTA_EM', {
              tempo: voltaEm,
              quem: atual.criado_por.name,
            })
          }}
        </p>
      </template>
      <button
        v-else
        type="button"
        :class="BTN_CHEIO"
        class="mt-5 w-full justify-center !rounded-[9px] !px-4 !py-[9px] !text-sm"
        @click="chegadas.marcarVisto(atual.id)"
      >
        {{ t('RAMON.CHEGADA.ENTENDI') }}
      </button>

      <p v-if="alertas.length > 1" class="mt-3 text-xs text-n-slate-9">
        {{ t('RAMON.CHEGADA.MAIS', { n: alertas.length - 1 }) }}
      </p>
    </div>
  </dialog>
</template>

<script setup>
import { onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave } from 'vue-router';
import ReunioesAPI from 'dashboard/api/reunioes';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import { CAMPO_GRANDE, CARTAO } from '../../helpers/ui';

const props = defineProps({
  leadId: { type: [Number, String], default: null },
});
const emit = defineEmits(['created']);
defineOptions({ name: 'ReuniaoRecorder' });
const { t } = useI18n();
const estado = ref('parado'); // parado | gravando | pausado | enviando | falha
const segundos = ref(0);
const titulo = ref('');
const progresso = ref(0);

let recorder = null;
let stream = null;
let chunks = [];
let timer = null;

// ponytail: 32 kbps opus = voz nítida e 1h ≈ 15 MB (teto do whisper é 25 MB).
const OPCOES = { audioBitsPerSecond: 32000 };
const mimeType = ['audio/webm;codecs=opus', 'audio/mp4'].find(tipo =>
  window.MediaRecorder?.isTypeSupported(tipo)
);

const formatoTempo = total => {
  const min = String(Math.floor(total / 60)).padStart(2, '0');
  const seg = String(total % 60).padStart(2, '0');
  return `${min}:${seg}`;
};

const avisoSaida = event => {
  event.preventDefault();
  // eslint-disable-next-line no-param-reassign
  event.returnValue = t('RAMON.REUNIOES.LEAVE_WARNING');
};

const limpar = () => {
  clearInterval(timer);
  window.removeEventListener('beforeunload', avisoSaida);
  stream?.getTracks().forEach(track => track.stop());
  recorder = null;
  stream = null;
  chunks = [];
  segundos.value = 0;
  progresso.value = 0;
  estado.value = 'parado';
};

const gravar = async () => {
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch {
    useAlert(t('RAMON.REUNIOES.MIC_ERROR'));
    return;
  }
  chunks = [];
  recorder = new MediaRecorder(stream, { ...OPCOES, mimeType });
  recorder.ondataavailable = event => {
    if (event.data.size) chunks.push(event.data);
  };
  recorder.start(1000);
  segundos.value = 0;
  timer = setInterval(() => {
    if (estado.value === 'gravando') segundos.value += 1;
  }, 1000);
  window.addEventListener('beforeunload', avisoSaida);
  estado.value = 'gravando';
};

const pausar = () => {
  recorder.pause();
  estado.value = 'pausado';
};

const continuar = () => {
  recorder.resume();
  estado.value = 'gravando';
};

const enviar = async () => {
  estado.value = 'enviando';
  const extensao = mimeType?.startsWith('audio/mp4') ? 'mp4' : 'webm';
  const blob = new Blob(chunks, { type: mimeType });
  const dados = new FormData();
  dados.append('audio', blob, `reuniao.${extensao}`);
  if (titulo.value.trim()) dados.append('titulo', titulo.value.trim());
  dados.append('duracao_segundos', segundos.value);
  if (props.leadId) dados.append('lead_id', props.leadId);
  try {
    const { data } = await ReunioesAPI.criar(dados, event => {
      progresso.value = Math.round((event.loaded / (event.total || 1)) * 100);
    });
    emit('created', data);
    titulo.value = '';
    limpar();
  } catch {
    useAlert(t('RAMON.REUNIOES.UPLOAD_ERROR'));
    // recorder já está inactive (stop() foi chamado em encerrar()) — não dá
    // pra retomar gravação, só reenviar os chunks que já estão em memória.
    stream?.getTracks().forEach(track => track.stop());
    estado.value = 'falha';
  }
};

const encerrar = () => {
  if (!recorder) return;
  recorder.onstop = enviar;
  recorder.stop();
};

const descartar = () => limpar();

onBeforeUnmount(limpar);

// ponytail: window.confirm aqui de propósito — guard de rota precisa de
// resposta síncrona; ConfirmModal não segura a navegação.
onBeforeRouteLeave(() => {
  if (estado.value === 'parado') return true;
  return window.confirm(t('RAMON.REUNIOES.LEAVE_WARNING'));
});
</script>

<template>
  <div :class="CARTAO" class="flex flex-col gap-3 !p-4">
    <input
      v-model="titulo"
      type="text"
      :class="CAMPO_GRANDE"
      :placeholder="t('RAMON.REUNIOES.TITLE_PLACEHOLDER')"
      :disabled="estado === 'enviando'"
    />
    <div class="flex flex-wrap items-center gap-2">
      <div
        v-if="estado !== 'parado'"
        class="flex items-center gap-2 me-2 font-mono text-lg font-medium tabular-nums text-n-slate-12"
        data-testid="recorder-timer"
      >
        {{ formatoTempo(segundos) }}
        <span
          v-if="estado === 'gravando'"
          class="size-2 animate-pulse rounded-full bg-n-ruby-9"
        />
      </div>
      <Button
        v-if="estado === 'parado'"
        sm
        icon="i-lucide-mic"
        data-testid="recorder-start"
        :label="t('RAMON.REUNIOES.RECORD')"
        @click="gravar"
      />
      <template v-else-if="estado === 'gravando' || estado === 'pausado'">
        <Button
          v-if="estado === 'gravando'"
          sm
          faded
          slate
          icon="i-lucide-pause"
          :label="t('RAMON.REUNIOES.PAUSE')"
          @click="pausar"
        />
        <Button
          v-else
          sm
          faded
          slate
          icon="i-lucide-play"
          :label="t('RAMON.REUNIOES.RESUME')"
          @click="continuar"
        />
        <Button
          sm
          icon="i-lucide-square"
          data-testid="recorder-stop"
          :label="t('RAMON.REUNIOES.STOP')"
          @click="encerrar"
        />
        <Button
          sm
          ghost
          slate
          :label="t('RAMON.REUNIOES.CANCEL')"
          @click="descartar"
        />
      </template>
      <template v-else-if="estado === 'falha'">
        <Button
          sm
          icon="i-lucide-upload"
          data-testid="recorder-retry"
          :label="t('RAMON.REUNIOES.RETRY_UPLOAD')"
          @click="enviar"
        />
        <Button
          sm
          ghost
          slate
          :label="t('RAMON.REUNIOES.CANCEL')"
          @click="descartar"
        />
      </template>
      <span v-else class="text-sm text-n-slate-11">
        {{ t('RAMON.REUNIOES.UPLOADING', { progress: progresso }) }}
      </span>
    </div>
  </div>
</template>

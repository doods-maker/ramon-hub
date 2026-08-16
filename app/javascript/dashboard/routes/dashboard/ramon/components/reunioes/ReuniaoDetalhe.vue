<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import ReunioesAPI from 'dashboard/api/reunioes';
import { useAlert } from 'dashboard/composables';
import ConfirmModal from '../ConfirmModal.vue';

const props = defineProps({
  reuniaoId: { type: [String, Number], required: true },
});

const emit = defineEmits(['deleted']);

defineOptions({ name: 'ReuniaoDetalhe' });

const { t } = useI18n();
const { formatMessage } = useMessageFormatter();

const reuniao = ref(null);
const hasError = ref(false);
const mostrarTranscricao = ref(false);
const showDeleteConfirm = ref(false);
let poll = null;

// ponytail: polling de 10s enquanto processa — sem canal ActionCable novo.
const carregar = async () => {
  try {
    const { data } = await ReunioesAPI.show(props.reuniaoId);
    reuniao.value = data;
    hasError.value = false;
  } catch {
    hasError.value = true;
  }
  clearInterval(poll);
  if (reuniao.value?.status === 'transcrevendo') {
    poll = setInterval(carregar, 10000);
  }
};

const agendarPoll = () => {
  clearInterval(poll);
  if (reuniao.value?.status === 'transcrevendo') {
    poll = setInterval(carregar, 10000);
  }
};

const reprocessar = async () => {
  try {
    const { data } = await ReunioesAPI.reprocessar(props.reuniaoId);
    reuniao.value = data;
    agendarPoll();
  } catch {
    useAlert(t('RAMON.REUNIOES.LOAD_ERROR'));
  }
};

const confirmarApagar = async () => {
  showDeleteConfirm.value = false;
  await ReunioesAPI.delete(props.reuniaoId);
  emit('deleted');
};

onMounted(carregar);
onBeforeUnmount(() => clearInterval(poll));
</script>

<template>
  <div v-if="reuniao" class="mx-auto flex w-full max-w-3xl flex-col gap-6">
    <div class="flex items-start justify-between gap-4">
      <div class="min-w-0">
        <h1
          class="truncate font-cormorant text-2xl font-semibold text-n-slate-12"
        >
          {{ reuniao.titulo }}
        </h1>
        <p v-if="reuniao.user_name" class="text-sm text-n-slate-11">
          {{ t('RAMON.REUNIOES.RECORDED_BY', { name: reuniao.user_name }) }}
        </p>
      </div>
      <button
        type="button"
        class="shrink-0 text-sm text-n-ruby-11"
        data-testid="reuniao-delete"
        @click="showDeleteConfirm = true"
      >
        {{ t('RAMON.REUNIOES.DELETE') }}
      </button>
    </div>

    <div
      v-if="reuniao.status === 'transcrevendo'"
      class="rounded-lg bg-n-amber-3 p-4 text-sm text-n-amber-11"
      data-testid="reuniao-processing"
    >
      {{ t('RAMON.REUNIOES.PROCESSING_HINT') }}
    </div>

    <div
      v-else-if="reuniao.status === 'erro'"
      class="flex items-center justify-between gap-4 rounded-lg bg-n-ruby-3 p-4 text-sm text-n-ruby-11"
    >
      <span class="min-w-0 truncate">{{ reuniao.erro }}</span>
      <button
        type="button"
        class="shrink-0 underline"
        data-testid="reuniao-reprocess"
        @click="reprocessar"
      >
        {{ t('RAMON.REUNIOES.REPROCESS') }}
      </button>
    </div>

    <section
      v-if="reuniao.ata"
      class="rounded-xl border border-n-weak bg-n-solid-1 shadow-sm p-4"
    >
      <h2 class="mb-2 text-sm font-semibold uppercase text-n-slate-11">
        {{ t('RAMON.REUNIOES.ATA_TITLE') }}
      </h2>
      <div
        class="text-sm text-n-slate-12 [&_h2]:mb-1 [&_h2]:mt-4 [&_h2]:font-semibold [&_li]:mb-1 [&_p]:mb-2 [&_ul]:list-disc [&_ul]:ps-4"
        data-testid="reuniao-ata"
        v-html="formatMessage(reuniao.ata)"
      />
    </section>

    <section
      v-if="reuniao.audio_url"
      class="rounded-xl border border-n-weak bg-n-solid-1 shadow-sm p-4"
    >
      <h2 class="mb-2 text-sm font-semibold uppercase text-n-slate-11">
        {{ t('RAMON.REUNIOES.AUDIO_TITLE') }}
      </h2>
      <audio controls :src="reuniao.audio_url" class="w-full" />
    </section>

    <section
      v-if="reuniao.transcricao"
      class="rounded-xl border border-n-weak bg-n-solid-1 shadow-sm p-4"
    >
      <button
        type="button"
        class="mb-2 text-sm font-semibold uppercase text-n-slate-11 underline"
        data-testid="reuniao-toggle-transcricao"
        @click="mostrarTranscricao = !mostrarTranscricao"
      >
        {{ t('RAMON.REUNIOES.TRANSCRICAO_TITLE') }}
      </button>
      <p
        v-if="mostrarTranscricao"
        class="whitespace-pre-wrap text-sm text-n-slate-11"
      >
        {{ reuniao.transcricao }}
      </p>
    </section>

    <ConfirmModal
      v-if="showDeleteConfirm"
      :title="t('RAMON.REUNIOES.DELETE')"
      :message="t('RAMON.REUNIOES.DELETE_CONFIRM')"
      :confirm-label="t('RAMON.REUNIOES.DELETE')"
      @confirm="confirmarApagar"
      @cancel="showDeleteConfirm = false"
    />
  </div>
  <div
    v-else-if="hasError"
    class="flex items-center gap-2 text-sm text-n-ruby-11"
  >
    {{ t('RAMON.REUNIOES.LOAD_ERROR') }}
    <button type="button" class="underline" @click="carregar">
      {{ t('RAMON.LEAD_PANEL.RETRY') }}
    </button>
  </div>
</template>

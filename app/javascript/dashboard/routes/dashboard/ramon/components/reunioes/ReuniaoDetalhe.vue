<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import ReunioesAPI from 'dashboard/api/reunioes';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ConfirmModal from '../ConfirmModal.vue';
import ReuniaoVincularLead from './ReuniaoVincularLead.vue';
import { AVISO, CARTAO, CHIP, TITULO, TOM } from '../../helpers/ui';

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
const vincularAberto = ref(false);

const vincular = async lead => {
  try {
    const { data } = await ReunioesAPI.vincularLead(props.reuniaoId, lead.id);
    reuniao.value = data;
    vincularAberto.value = false;
  } catch {
    useAlert(t('RAMON.REUNIOES.LINK_ERROR'));
  }
};
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
  <div v-if="reuniao" class="mx-auto flex w-full max-w-3xl flex-col gap-4">
    <div class="flex items-start justify-between gap-4 mb-2">
      <div class="min-w-0">
        <h1 class="truncate text-2xl font-semibold text-n-slate-12">
          {{ reuniao.titulo }}
        </h1>
        <p v-if="reuniao.user_name" class="mt-0.5 text-sm text-n-slate-11">
          {{ t('RAMON.REUNIOES.RECORDED_BY', { name: reuniao.user_name }) }}
        </p>
        <div class="flex flex-wrap items-center gap-2 mt-2">
          <router-link
            v-if="reuniao.lead_id"
            data-testid="reuniao-lead-link"
            :to="{
              name: 'ramon_lead_dossie',
              params: { leadId: reuniao.lead_id },
            }"
            :class="[CHIP, TOM.blue]"
            class="hover:underline"
          >
            <span class="i-lucide-user size-3" />
            {{ reuniao.lead_name }}
          </router-link>
          <Button
            data-testid="reuniao-vincular"
            xs
            :variant="reuniao.lead_id ? 'link' : 'faded'"
            :color="reuniao.lead_id ? 'slate' : 'blue'"
            icon="i-lucide-link"
            :label="
              reuniao.lead_id
                ? t('RAMON.REUNIOES.LINK_CHANGE')
                : t('RAMON.REUNIOES.LINK_LEAD')
            "
            @click="vincularAberto = true"
          />
        </div>
      </div>
      <Button
        sm
        ghost
        ruby
        icon="i-lucide-trash-2"
        class="shrink-0"
        data-testid="reuniao-delete"
        :label="t('RAMON.REUNIOES.DELETE')"
        @click="showDeleteConfirm = true"
      />
    </div>

    <div
      v-if="reuniao.status === 'transcrevendo'"
      :class="[AVISO, TOM.amber]"
      class="flex items-center gap-2 !text-sm"
      data-testid="reuniao-processing"
    >
      <span class="i-lucide-loader-circle size-4 shrink-0 animate-spin" />
      {{ t('RAMON.REUNIOES.PROCESSING_HINT') }}
    </div>

    <div
      v-else-if="reuniao.status === 'erro'"
      :class="[AVISO, TOM.ruby]"
      class="flex items-center justify-between gap-4 !text-sm"
    >
      <span class="min-w-0 truncate">{{ reuniao.erro }}</span>
      <Button
        xs
        faded
        ruby
        icon="i-lucide-refresh-cw"
        class="shrink-0"
        data-testid="reuniao-reprocess"
        :label="t('RAMON.REUNIOES.REPROCESS')"
        @click="reprocessar"
      />
    </div>

    <section v-if="reuniao.ata" :class="CARTAO" class="!p-4">
      <h2 :class="TITULO" class="mb-2">
        {{ t('RAMON.REUNIOES.ATA_TITLE') }}
      </h2>
      <div
        class="text-sm leading-relaxed text-n-slate-12 [&_h2]:mb-1 [&_h2]:mt-4 [&_h2]:text-sm [&_h2]:font-semibold [&_li]:mb-1 [&_p]:mb-2 [&_ul]:list-disc [&_ul]:ps-4"
        data-testid="reuniao-ata"
        v-html="formatMessage(reuniao.ata)"
      />
    </section>

    <section v-if="reuniao.audio_url" :class="CARTAO" class="!p-4">
      <h2 :class="TITULO" class="mb-2">
        {{ t('RAMON.REUNIOES.AUDIO_TITLE') }}
      </h2>
      <audio
        controls
        :src="reuniao.audio_url"
        class="w-full dark:[color-scheme:dark]"
      />
    </section>

    <section v-if="reuniao.transcricao" :class="CARTAO" class="!p-4">
      <button
        type="button"
        :class="TITULO"
        class="flex items-center gap-1 !p-0 hover:text-n-slate-12"
        data-testid="reuniao-toggle-transcricao"
        @click="mostrarTranscricao = !mostrarTranscricao"
      >
        {{ t('RAMON.REUNIOES.TRANSCRICAO_TITLE') }}
        <span
          class="size-3.5"
          :class="
            mostrarTranscricao ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
          "
        />
      </button>
      <p
        v-if="mostrarTranscricao"
        class="mt-2 mb-0 whitespace-pre-wrap text-sm text-n-slate-11"
      >
        {{ reuniao.transcricao }}
      </p>
    </section>

    <ReuniaoVincularLead
      v-if="vincularAberto"
      @cancel="vincularAberto = false"
      @escolhido="vincular"
    />
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
    <Button link xs :label="t('RAMON.LEAD_PANEL.RETRY')" @click="carregar" />
  </div>
</template>

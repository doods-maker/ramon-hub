<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import {
  stageMode,
  kitBlocks,
} from 'dashboard/routes/dashboard/ramon/helpers/kitBlocks';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'LeadKit' });

const { t } = useI18n();
const triages = ref([]);
const isLoading = ref(false);
const isStarting = ref(false);

const loadTriages = async () => {
  isLoading.value = true;
  try {
    const { data } = await LeadsAPI.getTriages(props.lead.id);
    triages.value = data;
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  if (props.lead?.id) loadTriages();
});

watch(
  () => [props.lead?.id, props.lead?.latest_triage],
  ([leadId, next], [prevLeadId, prev] = []) => {
    if (leadId !== prevLeadId) {
      triages.value = [];
      if (leadId) loadTriages();
      return;
    }
    if (!next) return;
    if (next.id !== prev?.id || next.kit_status !== prev?.kit_status) {
      loadTriages();
    }
  }
);

const doneTriage = computed(
  () => triages.value.find(triage => triage.status === 'done') || null
);
const kit = computed(() =>
  doneTriage.value?.kit_status === 'ready' ? doneTriage.value.kit : null
);
const kitError = computed(() =>
  doneTriage.value?.kit_status === 'error'
    ? doneTriage.value.kit?.error
    : null
);
const isGenerating = computed(
  () => doneTriage.value?.kit_status === 'running'
);

const mode = computed(() => stageMode(props.lead));
const blocks = computed(() =>
  kit.value ? kitBlocks(mode.value).filter(hasContent) : []
);

function hasContent(block) {
  const value = kit.value?.[blockKey(block)];
  if (block === 'venda_objecoes') {
    return Boolean(value?.pitch || value?.objecoes?.length);
  }
  return Array.isArray(value) ? value.length > 0 : Boolean(value);
}

function blockKey(block) {
  return block === 'roteiro' ? 'roteiro_perguntas' : blockField(block);
}
function blockField(block) {
  return block === 'resumo' ? 'resumo_leigo' : block;
}

const blockText = block => {
  const value = kit.value?.[blockKey(block)];
  if (block === 'roteiro') return (value || []).join('\n');
  if (block === 'documentos') {
    return (value || [])
      .map(doc => `${doc.documento} — ${doc.porque}`)
      .join('\n');
  }
  if (block === 'venda_objecoes') {
    const objecoes = (value?.objecoes || [])
      .map(item => `${item.objecao} → ${item.resposta}`)
      .join('\n');
    return [value?.pitch, objecoes].filter(Boolean).join('\n\n');
  }
  return value || '';
};

const generateKit = async () => {
  if (!doneTriage.value) return;
  isStarting.value = true;
  try {
    await LeadsAPI.createKit(props.lead.id, doneTriage.value.id);
    useAlert(t('RAMON.KIT.STARTED'));
    await loadTriages();
  } catch (error) {
    useAlert(t('RAMON.KIT.ERROR'));
  } finally {
    isStarting.value = false;
  }
};

const copyBlock = async block => {
  try {
    await copyTextToClipboard(blockText(block));
  } catch (error) {
    useAlert(t('RAMON.DOCS.COPY_FAILED'));
    return;
  }
  useAlert(t('RAMON.PLAYBOOK.COPIED'));
};

const blockLabelKey = block => `RAMON.KIT.BLOCKS.${block.toUpperCase()}`;
</script>

<template>
  <div class="flex flex-col gap-4 p-1" data-testid="lead-kit">
    <p
      v-if="mode === 'encerrado'"
      class="text-sm text-n-slate-10"
      data-testid="kit-closed"
    >
      {{ $t('RAMON.KIT.CLOSED') }}
    </p>

    <template v-else>
      <p
        v-if="!isLoading && !doneTriage"
        class="text-sm text-n-slate-10"
        data-testid="kit-empty"
      >
        {{ $t('RAMON.KIT.EMPTY') }}
      </p>

      <template v-else-if="doneTriage">
        <div class="flex items-center justify-between gap-2">
          <button
            type="button"
            data-testid="kit-generate"
            class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
            :disabled="isGenerating || isStarting"
            @click="generateKit"
          >
            {{
              isGenerating
                ? $t('RAMON.KIT.GENERATING')
                : $t(kit ? 'RAMON.KIT.REGENERATE' : 'RAMON.KIT.GENERATE')
            }}
          </button>
          <span class="text-xs text-n-slate-10">
            {{ $t('RAMON.KIT.MODE_LABEL') }}:
            {{ $t(`RAMON.KIT.MODE.${mode.toUpperCase()}`) }}
          </span>
        </div>

        <p
          v-if="kitError"
          class="text-sm text-n-ruby-11"
          data-testid="kit-error"
        >
          {{ $t('RAMON.KIT.ERROR') }}: {{ kitError }}
        </p>

        <div
          v-for="block in blocks"
          :key="block"
          :data-testid="`kit-block-${block}`"
          class="flex flex-col gap-2 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
        >
          <div class="flex items-center justify-between gap-2">
            <h4 class="text-xs uppercase tracking-widest text-n-slate-9">
              {{ $t(blockLabelKey(block)) }}
            </h4>
            <button
              type="button"
              :data-testid="`kit-copy-${block}`"
              class="px-2 py-0.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
              @click="copyBlock(block)"
            >
              {{ $t('RAMON.KIT.COPY_BLOCK') }}
            </button>
          </div>

          <p
            v-if="block === 'resumo' || block === 'proximo_passo'"
            class="text-sm whitespace-pre-wrap text-n-slate-12"
          >
            {{ blockText(block) }}
          </p>

          <ul
            v-else-if="block === 'roteiro'"
            class="flex flex-col gap-1 text-sm text-n-slate-12 list-disc ps-4"
          >
            <li v-for="(pergunta, i) in kit.roteiro_perguntas" :key="i">
              {{ pergunta }}
            </li>
          </ul>

          <ul
            v-else-if="block === 'documentos'"
            class="flex flex-col gap-1 text-sm text-n-slate-12"
          >
            <li v-for="doc in kit.documentos" :key="doc.documento">
              <span class="font-medium">{{ doc.documento }}</span>
              <span class="text-n-slate-10"> — {{ doc.porque }}</span>
            </li>
          </ul>

          <div
            v-else-if="block === 'venda_objecoes'"
            class="flex flex-col gap-2 text-sm text-n-slate-12"
          >
            <p v-if="kit.venda_objecoes.pitch" class="whitespace-pre-wrap">
              {{ kit.venda_objecoes.pitch }}
            </p>
            <div
              v-for="objecao in kit.venda_objecoes.objecoes"
              :key="objecao.objecao"
              class="p-2 rounded-lg bg-n-alpha-2"
            >
              <p class="font-medium">{{ objecao.objecao }}</p>
              <p class="text-n-slate-11">{{ objecao.resposta }}</p>
            </div>
          </div>
        </div>

        <p
          v-if="!kit && !kitError && !isGenerating"
          class="text-xs text-n-slate-10"
        >
          {{ $t('RAMON.KIT.NEED_DONE') }}
        </p>
      </template>
    </template>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { dynamicTime } from 'shared/helpers/timeHelper';
import RamonCopilotAPI from 'dashboard/api/ramonCopilot';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, TITULO } from '../../helpers/ui';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
defineOptions({ name: 'LeadCopilot' });

const { t } = useI18n();
const summary = ref('');
const generatedAt = ref(null);
const loading = ref(''); // '' | 'summary' | 'draft'

const generatedAgo = computed(() =>
  generatedAt.value ? dynamicTime(generatedAt.value / 1000) : null
);

const generate = async mode => {
  if (loading.value) return;
  loading.value = mode;
  try {
    const { data } = await RamonCopilotAPI.generate(props.conversationId, mode);
    if (mode === 'summary') {
      summary.value = data.content;
      generatedAt.value = Date.now();
    } else {
      // Cai como rascunho no editor de resposta (ReplyBox escuta este evento);
      // nada é enviado — quem envia é o Eduardo.
      emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, data.content);
      useAlert(t('RAMON.COPILOT.DRAFT_READY'));
    }
  } catch (error) {
    useAlert(error?.response?.data?.error || t('RAMON.COPILOT.ERROR'));
  } finally {
    loading.value = '';
  }
};
</script>

<template>
  <!-- Card "Resumo da IA" do mock 1f: header + texto + chips de ação -->
  <div data-testid="lead-copilot" :class="CARTAO">
    <div class="flex items-center justify-between gap-2">
      <p :class="TITULO">
        {{ $t('RAMON.COPILOT.SUMMARY_TITLE') }}
      </p>
      <span
        v-if="generatedAgo"
        data-testid="copilot-summary-time"
        class="text-[10.5px] text-n-slate-9"
      >
        {{ generatedAgo }}
      </span>
    </div>
    <p
      data-testid="copilot-summary"
      class="mt-1.5 text-[12.5px] leading-[1.55] whitespace-pre-wrap break-words"
      :class="summary ? 'text-n-slate-11' : 'text-n-slate-9'"
    >
      {{ summary || $t('RAMON.COPILOT.EMPTY') }}
    </p>
    <div class="flex flex-wrap items-center gap-1.5 mt-2.5">
      <Button
        data-testid="copilot-suggest"
        sm
        icon="i-lucide-sparkles"
        :disabled="Boolean(loading)"
        :label="
          loading === 'draft'
            ? $t('RAMON.COPILOT.WORKING')
            : $t('RAMON.COPILOT.SUGGEST')
        "
        @click="generate('draft')"
      />
      <Button
        data-testid="copilot-summarize"
        sm
        faded
        slate
        :disabled="Boolean(loading)"
        :label="
          loading === 'summary'
            ? $t('RAMON.COPILOT.WORKING')
            : $t('RAMON.COPILOT.REFRESH')
        "
        @click="generate('summary')"
      />
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import RamonCopilotAPI from 'dashboard/api/ramonCopilot';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
defineOptions({ name: 'LeadCopilot' });

const { t } = useI18n();
const summary = ref('');
const loading = ref(''); // '' | 'summary' | 'draft'

const generate = async mode => {
  if (loading.value) return;
  loading.value = mode;
  try {
    const { data } = await RamonCopilotAPI.generate(props.conversationId, mode);
    if (mode === 'summary') {
      summary.value = data.content;
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
  <div class="flex flex-col gap-2" data-testid="lead-copilot">
    <div class="flex flex-wrap items-center gap-2">
      <button
        type="button"
        data-testid="copilot-summarize"
        class="px-3 py-1 text-[11.5px] rounded-[7px] bg-n-alpha-1 text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-40 disabled:cursor-not-allowed"
        :disabled="Boolean(loading)"
        @click="generate('summary')"
      >
        {{
          loading === 'summary'
            ? $t('RAMON.COPILOT.WORKING')
            : $t('RAMON.COPILOT.SUMMARIZE')
        }}
      </button>
      <button
        type="button"
        data-testid="copilot-suggest"
        class="px-3 py-1 text-[11.5px] font-semibold rounded-[7px] bg-[#c9a97c]/[.14] text-n-iris-11 hover:bg-[#c9a97c]/[.22] disabled:opacity-40 disabled:cursor-not-allowed"
        :disabled="Boolean(loading)"
        @click="generate('draft')"
      >
        {{
          loading === 'draft'
            ? $t('RAMON.COPILOT.WORKING')
            : $t('RAMON.COPILOT.SUGGEST')
        }}
      </button>
    </div>
    <div
      v-if="summary"
      data-testid="copilot-summary"
      class="flex flex-col gap-2 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
    >
      <div class="flex items-center justify-between gap-2">
        <h4 class="text-xs uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.COPILOT.SUMMARY_TITLE') }}
        </h4>
        <button
          type="button"
          data-testid="copilot-summary-close"
          class="text-n-slate-10 hover:text-n-slate-12"
          :aria-label="$t('RAMON.COPILOT.CLOSE')"
          @click="summary = ''"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>
      <p class="text-sm whitespace-pre-wrap break-words text-n-slate-12">
        {{ summary }}
      </p>
    </div>
  </div>
</template>

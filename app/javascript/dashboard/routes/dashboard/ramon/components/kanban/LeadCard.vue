<script setup>
import { computed } from 'vue';

const props = defineProps({
  lead: { type: Object, required: true },
  benefitTypes: { type: Array, default: () => [] },
  priorities: { type: Array, default: () => [] },
});
const emit = defineEmits(['open-conversation']);

const benefitName = computed(
  () => props.benefitTypes.find(b => b.id === props.lead.benefit_type_id)?.name
);
const priorityName = computed(
  () => props.priorities.find(p => p.id === props.lead.lead_priority_id)?.name
);
</script>

<template>
  <div class="p-3 mb-2 rounded-xl bg-n-solid-2 border border-n-weak">
    <div class="flex items-start justify-between gap-2">
      <p class="text-sm font-medium text-n-slate-12">{{ lead.name }}</p>
      <button
        v-if="lead.conversation_id"
        :title="$t('RAMON.FUNIL.OPEN_CONVERSATION')"
        class="text-n-slate-10 hover:text-n-iris-11"
        @click="emit('open-conversation', lead.conversation_id)"
      >
        <span class="i-lucide-message-square size-4" />
      </button>
    </div>
    <span v-if="benefitName" class="inline-block mt-2 px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11">
      {{ benefitName }}
    </span>
    <div v-if="priorityName" class="mt-2">
      <p class="text-[9px] tracking-widest uppercase text-n-slate-9">{{ $t('RAMON.FUNIL.PRIORITY') }}</p>
      <span class="inline-flex items-center gap-1 mt-1 px-2 py-0.5 text-[11px] rounded-full bg-n-iris-9 text-white">
        <span class="i-lucide-flag size-3" />{{ priorityName }}
      </span>
    </div>
  </div>
</template>

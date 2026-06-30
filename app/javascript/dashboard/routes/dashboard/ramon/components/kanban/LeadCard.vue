<script setup>
import { computed } from 'vue';

const props = defineProps({
  lead: { type: Object, required: true },
});
const emit = defineEmits(['open-conversation', 'open-lead']);

const formattedValue = computed(() => {
  const v = props.lead.value;
  if (v === null || v === undefined || v === '') return null;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(Number(v));
});

const ownerName = computed(
  () => props.lead.closer_name || props.lead.sdr_name || null
);
const ownerInitials = computed(() => {
  if (!ownerName.value) return null;
  return ownerName.value
    .trim()
    .split(/\s+/)
    .map(word => word[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
});
</script>

<template>
  <div
    class="p-3 mb-2 rounded-xl bg-n-solid-2 border border-n-weak cursor-pointer hover:border-n-iris-8"
  >
    <div class="flex items-start justify-between gap-2">
      <button
        data-testid="lead-card-body"
        class="flex-1 text-left"
        @click="emit('open-lead', lead)"
      >
        <p class="text-sm font-medium text-n-slate-12">{{ lead.name }}</p>
      </button>
      <button
        v-if="lead.conversation_id"
        data-testid="open-conversation"
        :title="$t('RAMON.FUNIL.OPEN_CONVERSATION')"
        class="text-n-slate-10 hover:text-n-iris-11"
        @click.stop="emit('open-conversation', lead.conversation_id)"
      >
        <span class="i-lucide-message-square size-4" />
      </button>
    </div>

    <div class="flex flex-wrap items-center gap-1.5 mt-2">
      <span
        v-if="lead.stage_name"
        data-testid="stage-chip"
        class="inline-block px-2 py-0.5 text-[11px] rounded-full text-white"
        :style="{ backgroundColor: lead.stage_color || '#71717a' }"
      >
        {{ lead.stage_name }}
      </span>
      <span
        v-if="lead.benefit_type_name"
        class="inline-block px-2 py-0.5 text-[11px] rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        {{ lead.benefit_type_name }}
      </span>
    </div>

    <div class="flex items-center justify-between mt-2">
      <div class="flex items-center gap-2">
        <span
          v-if="lead.lead_priority_name"
          class="inline-flex items-center gap-1 px-2 py-0.5 text-[11px] rounded-full bg-n-iris-9 text-white"
        >
          <span class="i-lucide-flag size-3" />{{ lead.lead_priority_name }}
        </span>
        <span v-if="formattedValue" class="text-xs font-medium text-n-slate-12">
          {{ formattedValue }}
        </span>
      </div>
      <span
        v-if="ownerInitials"
        :title="ownerName"
        class="inline-flex items-center justify-center size-6 text-[10px] rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        {{ ownerInitials }}
      </span>
    </div>
  </div>
</template>

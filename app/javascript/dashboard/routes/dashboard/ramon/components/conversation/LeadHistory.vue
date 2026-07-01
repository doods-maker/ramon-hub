<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';

const props = defineProps({
  leadId: { type: [Number, String], required: true },
});
defineOptions({ name: 'LeadHistory' });

const store = useStore();
const { t } = useI18n();
const activities = ref([]);

const load = async () => {
  activities.value = await store.dispatch(
    'leads/fetchActivities',
    Number(props.leadId)
  );
};
watch(() => props.leadId, load, { immediate: true });

// mais recente no topo
const ordered = computed(() => [...activities.value].reverse());

const labelKey = kind => `RAMON.LEAD_PANEL.HISTORY.KIND.${kind.toUpperCase()}`;

const detail = activity => {
  let text = ` · ${t(labelKey(activity.kind))}`;
  if (activity.to_value) text += ` → ${activity.to_value}`;
  return text;
};
</script>

<template>
  <div class="flex flex-col gap-3 p-1">
    <div
      v-for="activity in ordered"
      :key="activity.id"
      data-testid="activity-row"
      class="flex flex-col gap-0.5 border-l-2 pl-3"
    >
      <span class="text-sm">
        <strong v-if="activity.author_name">{{ activity.author_name }}</strong>
        <span v-else>{{ $t('RAMON.LEAD_PANEL.HISTORY.SYSTEM') }}</span>
        <span>{{ detail(activity) }}</span>
      </span>
      <span class="text-xs opacity-60">{{ activity.created_at }}</span>
    </div>
  </div>
</template>

<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';

defineOptions({ name: 'LeadFollowUpBanner' });

const { t } = useI18n();
const store = useStore();
const { updateUISettings } = useUISettings();

const currentChat = useMapGetter('getSelectedChat');
const leadByConv = useMapGetter('leads/getLeadByConversationId');

const conversationId = computed(() => currentChat.value?.id ?? null);
const lead = computed(() =>
  conversationId.value
    ? leadByConv.value(Number(conversationId.value))
    : undefined
);

// Consulta somente-leitura: nunca cria lead pra conversa fora do funil.
// Watch pelo id, não pelo objeto; falha na busca só silencia o banner.
watch(
  conversationId,
  async id => {
    if (!id || lead.value) return;
    try {
      await store.dispatch('leads/peekForConversation', {
        conversationId: Number(id),
      });
    } catch (e) {
      // conversa sem lead: o banner simplesmente não aparece
    }
  },
  { immediate: true }
);

// Dias parado na etapa (mesma conta do LeadCard); null sem data.
const stalledDays = computed(() => {
  const entered = lead.value?.stage_entered_at;
  if (!entered) return null;
  const diff = Date.now() - new Date(entered).getTime();
  if (Number.isNaN(diff)) return null;
  return Math.max(0, Math.floor(diff / 86400000));
});

const label = computed(() => {
  const parts = [];
  if (lead.value?.stalled)
    parts.push(
      t('RAMON.FOLLOW_UP.BANNER_STALLED', { days: stalledDays.value ?? 0 })
    );
  const count = Number(lead.value?.follow_up_count) || 0;
  if (count > 0) parts.push(t('RAMON.FOLLOW_UP.BANNER_RETRIES', { count }));
  return parts.join(' · ');
});

// Mesmo efeito do LeadPanelToggle: abre o painel do lead (e fecha o Copilot).
const openPanel = () => {
  updateUISettings({
    is_contact_sidebar_open: true,
    is_copilot_panel_open: false,
  });
};
</script>

<template>
  <button
    v-if="label"
    type="button"
    data-testid="lead-follow-up-banner"
    :title="label"
    class="hidden sm:inline-flex items-center gap-1 min-w-0 max-w-48 px-2 py-1 text-xs rounded-full bg-n-amber-3 text-n-amber-11 hover:bg-n-amber-4"
    @click="openPanel"
  >
    <span class="i-lucide-history size-3.5 shrink-0" />
    <span class="truncate">{{ label }}</span>
  </button>
</template>

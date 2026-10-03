<script setup>
import { computed, ref, watch } from 'vue';
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
// Lead achado por contato (fallback do peek) não casa com o getter por
// conversa — guardamos o retorno pra ele também acender o banner.
const peeked = ref(null);
const lead = computed(() => {
  const byConv = conversationId.value
    ? leadByConv.value(Number(conversationId.value))
    : undefined;
  return byConv || peeked.value || undefined;
});

// Consulta somente-leitura: nunca cria lead pra conversa fora do funil.
// Watch pelo id, não pelo objeto; falha na busca só silencia o banner.
watch(
  conversationId,
  async id => {
    peeked.value = null;
    if (!id || lead.value) return;
    try {
      const result = await store.dispatch('leads/peekForConversation', {
        conversationId: Number(id),
      });
      // guard contra resposta atrasada após troca de conversa
      if (conversationId.value === id) peeked.value = result;
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

// Chip de SLA de 1ª resposta (Ramon::Cadencia via payload do lead).
// replied_at presente → verde com o tempo gasto (due - alvo = criação);
// pendente no prazo → âmbar com contagem; vencido → ruby. Date.now() aqui
// não é reativo — o chip re-renderiza quando o lead muda (broadcast), o que
// basta: o estado "estourado" chega junto com qualquer atividade nova.
const slaChip = computed(() => {
  const sla = lead.value?.sla;
  if (!sla?.due_at) return null;
  const due = new Date(sla.due_at).getTime();
  const targetMs = (Number(sla.minutes) || 0) * 60000;
  if (sla.replied_at) {
    const taken = Math.max(
      0,
      Math.round(
        (new Date(sla.replied_at).getTime() - (due - targetMs)) / 60000
      )
    );
    return {
      tone: 'bg-n-teal-3 text-n-teal-11',
      icon: 'i-lucide-check',
      text: t('RAMON.SLA.CHIP_OK', { minutes: taken }),
    };
  }
  const leftMin = Math.floor((due - Date.now()) / 60000);
  if (leftMin >= 0)
    return {
      tone: 'bg-n-amber-3 text-n-amber-11',
      icon: 'i-lucide-timer',
      text: t('RAMON.SLA.CHIP_PENDING', { minutes: leftMin }),
    };
  return {
    tone: 'bg-n-ruby-3 text-n-ruby-11',
    icon: 'i-lucide-timer-off',
    text: t('RAMON.SLA.CHIP_BREACHED'),
  };
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
  <span
    v-if="label || slaChip"
    class="hidden sm:inline-flex items-center gap-1.5"
  >
    <span
      v-if="slaChip"
      data-testid="lead-sla-chip"
      :title="slaChip.text"
      class="inline-flex items-center gap-1 px-2 py-1 text-xs rounded-full"
      :class="slaChip.tone"
    >
      <span class="size-3.5 shrink-0" :class="slaChip.icon" />
      <span class="truncate max-w-40">{{ slaChip.text }}</span>
    </span>
    <button
      v-if="label"
      type="button"
      data-testid="lead-follow-up-banner"
      :title="label"
      class="inline-flex items-center gap-1 min-w-0 max-w-48 px-2 py-1 text-xs rounded-full bg-n-amber-3 text-n-amber-11 hover:bg-n-amber-4"
      @click="openPanel"
    >
      <span class="i-lucide-history size-3.5 shrink-0" />
      <span class="truncate">{{ label }}</span>
    </button>
  </span>
</template>

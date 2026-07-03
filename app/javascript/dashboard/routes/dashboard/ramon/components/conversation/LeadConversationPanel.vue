<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import LeadFields from 'dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue';
import ConversationAction from 'dashboard/routes/dashboard/conversation/ConversationAction.vue';
import MacrosList from 'dashboard/routes/dashboard/conversation/Macros/List.vue';
import ResolveAction from 'dashboard/components/buttons/ResolveAction.vue';
import LeadHistory from 'dashboard/routes/dashboard/ramon/components/conversation/LeadHistory.vue';
import LeadPlaybook from 'dashboard/routes/dashboard/ramon/components/conversation/LeadPlaybook.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
const emit = defineEmits(['discarded']);

defineOptions({ name: 'LeadConversationPanel' });
const store = useStore();
const leadByConv = useMapGetter('leads/getLeadByConversationId');
const theses = useMapGetter('theses/getTheses');
const activeTab = ref('resumo');
const lead = computed(() => leadByConv.value(Number(props.conversationId)));

const ensure = async () => {
  await store.dispatch('leads/ensureForConversation', {
    conversationId: Number(props.conversationId),
  });
};
watch(() => props.conversationId, ensure, { immediate: true });

onMounted(() => {
  if (!theses.value.length) store.dispatch('theses/get');
});

const discard = async () => {
  if (!lead.value) return;
  await store.dispatch('leads/delete', lead.value.id);
  emit('discarded');
};
</script>

<template>
  <div class="flex flex-col h-full" data-testid="lead-conversation-panel">
    <div class="flex items-center gap-2 border-b px-3 py-2">
      <button
        :class="{ 'font-semibold': activeTab === 'resumo' }"
        @click="activeTab = 'resumo'"
      >
        {{ $t('RAMON.LEAD_PANEL.TABS.SUMMARY') }}
      </button>
      <button
        :class="{ 'font-semibold': activeTab === 'historico' }"
        data-testid="tab-historico"
        @click="activeTab = 'historico'"
      >
        {{ $t('RAMON.LEAD_PANEL.TABS.HISTORY') }}
      </button>
      <button
        :class="{ 'font-semibold': activeTab === 'playbook' }"
        data-testid="tab-playbook"
        @click="activeTab = 'playbook'"
      >
        {{ $t('RAMON.LEAD_PANEL.TABS.PLAYBOOK') }}
      </button>
      <button
        class="ml-auto text-xs"
        data-testid="lead-discard"
        @click="discard"
      >
        {{ $t('RAMON.LEAD_PANEL.DISCARD') }}
      </button>
    </div>
    <div v-if="lead" class="flex-1 overflow-y-auto p-3">
      <template v-if="activeTab === 'resumo'">
        <div class="mb-4 flex flex-col gap-2">
          <ConversationAction :conversation-id="conversationId" />
          <MacrosList :conversation-id="conversationId" />
          <ResolveAction />
        </div>
        <LeadFields :lead="lead" />
      </template>
      <LeadHistory v-else-if="activeTab === 'historico'" :lead-id="lead.id" />
      <LeadPlaybook v-else-if="activeTab === 'playbook'" :lead="lead" />
    </div>
  </div>
</template>

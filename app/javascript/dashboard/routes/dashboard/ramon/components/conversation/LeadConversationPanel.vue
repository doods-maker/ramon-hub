<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import LeadFields from 'dashboard/routes/dashboard/ramon/components/lead/LeadFields.vue';
import ConversationAction from 'dashboard/routes/dashboard/conversation/ConversationAction.vue';
import MacrosList from 'dashboard/routes/dashboard/conversation/Macros/List.vue';
import ResolveAction from 'dashboard/components/buttons/ResolveAction.vue';
import LeadHistory from 'dashboard/routes/dashboard/ramon/components/conversation/LeadHistory.vue';
import LeadPlaybook from 'dashboard/routes/dashboard/ramon/components/conversation/LeadPlaybook.vue';
import LeadTriage from 'dashboard/routes/dashboard/ramon/components/conversation/LeadTriage.vue';
import LeadKit from 'dashboard/routes/dashboard/ramon/components/conversation/LeadKit.vue';
import LeadCopilot from 'dashboard/routes/dashboard/ramon/components/conversation/LeadCopilot.vue';
import LeadSimulador from 'dashboard/routes/dashboard/ramon/components/conversation/LeadSimulador.vue';
import { useLeadPanelSections } from 'dashboard/routes/dashboard/ramon/composables/useLeadPanelSections';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
const emit = defineEmits(['discarded', 'close']);

defineOptions({ name: 'LeadConversationPanel' });
const store = useStore();
const leadByConv = useMapGetter('leads/getLeadByConversationId');
const theses = useMapGetter('theses/getTheses');
const lead = computed(() => leadByConv.value(Number(props.conversationId)));

// Persistência do aberto/recolhido por seção (compartilhada com a gaveta).
const { openSections, toggleSection } = useLeadPanelSections();

const ensureFailed = ref(false);
const ensure = async () => {
  ensureFailed.value = false;
  try {
    await store.dispatch('leads/ensureForConversation', {
      conversationId: Number(props.conversationId),
    });
  } catch (e) {
    ensureFailed.value = true;
  }
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
  <!-- overflow-x-hidden + min-w-0: o painel NUNCA rola na horizontal; conteúdo
       largo (tabelas) rola dentro do próprio bloco, que já tem overflow-x-auto -->
  <div
    class="flex flex-col h-full min-w-0 max-w-full overflow-x-hidden"
    data-testid="lead-conversation-panel"
  >
    <div class="flex items-center gap-2 border-b border-n-weak px-3 py-2">
      <span class="text-sm font-semibold text-n-slate-12">
        {{ $t('RAMON.LEAD_PANEL.TITLE') }}
      </span>
      <button
        class="ml-auto text-n-slate-10 hover:text-n-slate-12"
        data-testid="lead-panel-close"
        :aria-label="$t('RAMON.LEAD_PANEL.CLOSE')"
        :title="$t('RAMON.LEAD_PANEL.CLOSE')"
        @click="emit('close')"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </div>
    <div
      v-if="lead"
      class="flex flex-col gap-2 flex-1 min-w-0 overflow-y-auto overflow-x-hidden p-3"
    >
      <AccordionItem
        :title="$t('RAMON.LEAD_PANEL.TABS.SUMMARY')"
        :is-open="openSections.resumo"
        data-testid="section-resumo"
        @toggle="toggleSection('resumo')"
      >
        <div class="mb-4 flex flex-col gap-2 min-w-0">
          <ConversationAction :conversation-id="conversationId" />
          <MacrosList :conversation-id="conversationId" />
          <ResolveAction />
        </div>
        <LeadCopilot
          :conversation-id="conversationId"
          class="pt-3 mb-4 border-t border-n-weak"
        />
        <div class="pt-3 border-t border-n-weak">
          <LeadFields :lead="lead" />
        </div>
        <div class="mt-6 pt-3 border-t border-n-weak">
          <button
            class="text-xs text-n-ruby-11 hover:underline"
            data-testid="lead-discard"
            @click="discard"
          >
            {{ $t('RAMON.LEAD_PANEL.DISCARD') }}
          </button>
        </div>
      </AccordionItem>
      <AccordionItem
        :title="$t('RAMON.LEAD_PANEL.TABS.HISTORY')"
        :is-open="openSections.historico"
        data-testid="section-historico"
        @toggle="toggleSection('historico')"
      >
        <LeadHistory :lead-id="lead.id" />
      </AccordionItem>
      <AccordionItem
        :title="$t('RAMON.LEAD_PANEL.TABS.PLAYBOOK')"
        :is-open="openSections.playbook"
        data-testid="section-playbook"
        @toggle="toggleSection('playbook')"
      >
        <LeadPlaybook :lead="lead" />
      </AccordionItem>
      <AccordionItem
        :title="$t('RAMON.TRIAGE.TAB')"
        :is-open="openSections.triagem"
        data-testid="section-triagem"
        @toggle="toggleSection('triagem')"
      >
        <LeadTriage :lead="lead" />
      </AccordionItem>
      <AccordionItem
        :title="$t('RAMON.KIT.TAB')"
        :is-open="openSections.kit"
        data-testid="section-kit"
        @toggle="toggleSection('kit')"
      >
        <LeadKit :lead="lead" />
      </AccordionItem>
      <AccordionItem
        :title="$t('RAMON.SIMULADOR.TAB')"
        :is-open="openSections.simulador"
        data-testid="section-simulador"
        @toggle="toggleSection('simulador')"
      >
        <LeadSimulador :lead="lead" />
      </AccordionItem>
    </div>
    <div v-else-if="ensureFailed" class="flex-1 p-3 text-sm">
      <p class="text-n-ruby-11">{{ $t('RAMON.LEAD_PANEL.LOAD_ERROR') }}</p>
      <button
        class="mt-2 text-xs text-n-iris-11 hover:underline"
        data-testid="lead-panel-retry"
        @click="ensure"
      >
        {{ $t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>
    <div v-else class="flex-1 p-3 text-sm text-n-slate-10">
      {{ $t('RAMON.LEAD_PANEL.LOADING') }}
    </div>
  </div>
</template>

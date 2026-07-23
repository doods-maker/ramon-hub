<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import LeadPanelBody from 'dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
const emit = defineEmits(['discarded', 'close']);

defineOptions({ name: 'LeadConversationPanel' });
const store = useStore();
const leadByConv = useMapGetter('leads/getLeadByConversationId');
const theses = useMapGetter('theses/getTheses');
const lead = computed(() => leadByConv.value(Number(props.conversationId)));

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
    <LeadPanelBody
      v-if="lead"
      :lead="lead"
      context="conversation"
      :conversation-id="conversationId"
      @discarded="emit('discarded')"
    />
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
    <div
      v-else
      class="flex items-center gap-2 flex-1 p-3 text-sm text-n-slate-10"
    >
      <span class="i-lucide-loader-2 animate-spin size-4" />
      {{ $t('RAMON.LEAD_PANEL.LOADING') }}
    </div>
  </div>
</template>

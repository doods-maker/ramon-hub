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
const currentChat = useMapGetter('getSelectedChat');
const lead = computed(() => leadByConv.value(Number(props.conversationId)));

// Portaria: conversa fora do funil (caixa do escritório). O botão de
// encaminhar só aparece no Setor Recepção — decisão do Eduardo 28/08/2026.
const semLead = ref(false);
const encaminhando = ref(false);
const naRecepcao = computed(
  () => currentChat.value?.meta?.team?.name === 'recepção'
);

const ensureFailed = ref(false);
const ensure = async () => {
  ensureFailed.value = false;
  semLead.value = false;
  try {
    const found = await store.dispatch('leads/ensureForConversation', {
      conversationId: Number(props.conversationId),
    });
    semLead.value = !found;
  } catch (e) {
    ensureFailed.value = true;
  }
};
watch(() => props.conversationId, ensure, { immediate: true });

const encaminhar = async () => {
  encaminhando.value = true;
  try {
    await store.dispatch('leads/encaminharComercial', {
      conversationId: Number(props.conversationId),
    });
    semLead.value = false;
  } catch (e) {
    ensureFailed.value = true;
  } finally {
    encaminhando.value = false;
  }
};

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
    <div v-else-if="semLead" class="flex-1 p-3 text-sm text-n-slate-11">
      <p>{{ $t('RAMON.LEAD_PANEL.SEM_LEAD') }}</p>
      <button
        v-if="naRecepcao"
        class="mt-2 rounded-md bg-n-iris-9 px-3 py-1.5 text-xs font-medium text-white hover:bg-n-iris-10 disabled:opacity-50"
        data-testid="lead-panel-encaminhar-comercial"
        :disabled="encaminhando"
        @click="encaminhar"
      >
        {{ $t('RAMON.LEAD_PANEL.ENCAMINHAR_COMERCIAL') }}
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

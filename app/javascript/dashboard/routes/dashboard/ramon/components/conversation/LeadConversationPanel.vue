<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import LeadPanelBody from 'dashboard/routes/dashboard/ramon/components/lead/LeadPanelBody.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

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

// Caixa do escritório: conversa fora do funil. O botão de encaminhar só
// aparece enquanto a conversa está na triagem da Recepção (sem dono e sem
// time) — decisões do Eduardo 28/08 e 02/10/2026 (ADR 0004).
const semLead = ref(false);
const encaminhando = ref(false);
const naRecepcao = computed(() => {
  const meta = currentChat.value?.meta || {};
  return !meta.team && !meta.assignee;
});

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
      <Button
        data-testid="lead-panel-close"
        sm
        ghost
        slate
        icon="i-lucide-x"
        class="ml-auto"
        :aria-label="$t('RAMON.LEAD_PANEL.CLOSE')"
        :title="$t('RAMON.LEAD_PANEL.CLOSE')"
        @click="emit('close')"
      />
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
      <Button
        data-testid="lead-panel-retry"
        link
        xs
        class="mt-2"
        :label="$t('RAMON.LEAD_PANEL.RETRY')"
        @click="ensure"
      />
    </div>
    <div v-else-if="semLead" class="flex-1 p-3 text-sm text-n-slate-11">
      <p>{{ $t('RAMON.LEAD_PANEL.SEM_LEAD') }}</p>
      <Button
        v-if="naRecepcao"
        data-testid="lead-panel-encaminhar-comercial"
        sm
        class="mt-2"
        :label="$t('RAMON.LEAD_PANEL.ENCAMINHAR_COMERCIAL')"
        :disabled="encaminhando"
        @click="encaminhar"
      />
    </div>
    <div
      v-else
      class="flex items-center gap-2 flex-1 p-3 text-sm text-n-slate-10"
    >
      <Spinner :size="16" />
      {{ $t('RAMON.LEAD_PANEL.LOADING') }}
    </div>
  </div>
</template>

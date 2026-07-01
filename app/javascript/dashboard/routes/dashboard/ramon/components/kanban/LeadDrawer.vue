<script setup>
import { computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import LeadFields from '../lead/LeadFields.vue';

const emit = defineEmits(['open-conversation']);
const store = useStore();
const getters = useStoreGetters();

const lead = computed(() => getters['leads/getSelectedLead'].value);

const close = () => store.dispatch('leads/select', null);

const onDocKeydown = e => {
  if (e.key === 'Escape') close();
};
onMounted(() => document.addEventListener('keydown', onDocKeydown));
onBeforeUnmount(() => document.removeEventListener('keydown', onDocKeydown));
</script>

<template>
  <div v-if="lead" class="fixed inset-0 z-40 flex justify-end">
    <div
      class="absolute inset-0 bg-black/40"
      data-testid="drawer-overlay"
      @click="close"
    />
    <aside
      class="relative z-10 w-96 h-full overflow-y-auto bg-n-solid-1 border-l border-n-weak p-5"
    >
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-cormorant text-n-slate-12">{{ lead.name }}</h2>
        <button
          data-testid="drawer-close"
          class="text-n-slate-10 hover:text-n-slate-12"
          @click="close"
        >
          <span class="i-lucide-x size-5" />
        </button>
      </div>

      <LeadFields :lead="lead" />

      <button
        v-if="lead.conversation_id"
        data-testid="drawer-open-conversation"
        class="flex items-center gap-1 mt-3 px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
        @click="emit('open-conversation', lead.conversation_id)"
      >
        <span class="i-lucide-message-square size-4" />{{
          $t('RAMON.FUNIL.OPEN_CONVERSATION')
        }}
      </button>
    </aside>
  </div>
</template>

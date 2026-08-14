<script setup>
import { ref, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import KanbanBoard from '../components/kanban/KanbanBoard.vue';
import NewLeadModal from '../components/kanban/NewLeadModal.vue';

const showModal = ref(false);

// Só busca a conversão se ainda não tiver dado (ex.: já veio do Cockpit) —
// coluna funciona sem ela, então não bloqueia o render do board.
const store = useStore();
const getters = useStoreGetters();
onMounted(() => {
  if (!getters['ramonDashboard/getData']?.value) {
    store.dispatch('ramonDashboard/fetch');
  }
});
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <KanbanBoard @new-lead="showModal = true" />
    <NewLeadModal v-if="showModal" @close="showModal = false" />
  </div>
</template>

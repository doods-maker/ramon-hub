<script setup>
import { ref, onMounted, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import KanbanBoard from '../components/kanban/KanbanBoard.vue';
import NewLeadModal from '../components/kanban/NewLeadModal.vue';

// "Novo lead" da paleta Ctrl K chega como ?novo=1.
const route = useRoute();
const showModal = ref(false);
watch(
  () => route.query.novo,
  novo => {
    if (novo) showModal.value = true;
  },
  { immediate: true }
);
// fechar tira o ?novo da URL (senão recarregar reabre o modal)
const router = useRouter();
const fecharModal = () => {
  showModal.value = false;
  if (route.query.novo)
    router.replace({ query: { ...route.query, novo: undefined } });
};

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
    <NewLeadModal v-if="showModal" @close="fecharModal" />
  </div>
</template>

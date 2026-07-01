<script setup>
import { ref } from 'vue';
import KanbanBoard from '../components/kanban/KanbanBoard.vue';
import NewLeadModal from '../components/kanban/NewLeadModal.vue';

const showModal = ref(false);
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <KanbanBoard @new-lead="showModal = true" />
    <NewLeadModal v-if="showModal" @close="showModal = false" />
  </div>
</template>

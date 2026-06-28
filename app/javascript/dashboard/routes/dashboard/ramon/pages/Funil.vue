<script setup>
import { ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import KanbanBoard from '../components/kanban/KanbanBoard.vue';
import NewLeadModal from '../components/kanban/NewLeadModal.vue';

const route = useRoute();
const router = useRouter();
const showModal = ref(false);

const openConversation = conversationId => {
  router.push({
    name: 'inbox_conversation',
    params: { accountId: route.params.accountId, conversation_id: conversationId },
  });
};
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <KanbanBoard @new-lead="showModal = true" @open-conversation="openConversation" />
    <NewLeadModal v-if="showModal" @close="showModal = false" />
  </div>
</template>

<script setup>
import { useRoute, useRouter } from 'vue-router';
import KanbanBoard from '../ramon/components/kanban/KanbanBoard.vue';
const route = useRoute();
const router = useRouter();
const openConversation = conversationId => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: conversationId,
    },
  });
};
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <KanbanBoard @open-conversation="openConversation" />
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import AssistantPlayground from 'dashboard/components-next/captain/assistant/AssistantPlayground.vue';
import AbasTestar from '../../casos/AbasTestar.vue';

const route = useRoute();
const assistantId = computed(() => Number(route.params.assistantId));
</script>

<template>
  <PageLayout
    show-assistant-switcher
    :show-pagination-footer="false"
    class="h-full"
  >
    <template #subHeader>
      <AbasTestar ativa="conversa" />
    </template>
    <template #body>
      <div class="flex flex-col h-full">
        <AssistantPlayground :assistant-id="assistantId" class="bg-n-solid-1" />
      </div>
    </template>
  </PageLayout>
</template>

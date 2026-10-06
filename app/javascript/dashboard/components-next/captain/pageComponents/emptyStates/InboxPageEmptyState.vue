<script setup>
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['click']);
</script>

<template>
  <EmptyStateLayout
    :title="$t('CAPTAIN.INBOXES.EMPTY_STATE.TITLE')"
    :subtitle="$t('CAPTAIN.INBOXES.EMPTY_STATE.SUBTITLE')"
    :action-perms="['administrator']"
    :show-backdrop="false"
  >
    <template #actions>
      <Button
        :label="$t('CAPTAIN.INBOXES.ADD_NEW')"
        icon="i-lucide-plus"
        @click="emit('click')"
      />
    </template>
  </EmptyStateLayout>
</template>

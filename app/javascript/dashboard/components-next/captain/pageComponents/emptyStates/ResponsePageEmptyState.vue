<script setup>
import { computed } from 'vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  variant: {
    type: String,
    default: 'approved',
    validator: value => ['approved', 'pending'].includes(value),
  },
  hasActiveFilters: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['click', 'clearFilters']);

const isApproved = computed(() => props.variant === 'approved');
const isPending = computed(() => props.variant === 'pending');
</script>

<template>
  <EmptyStateLayout
    :title="
      isPending
        ? $t('CAPTAIN.RESPONSES.EMPTY_STATE.NO_PENDING_TITLE')
        : $t('CAPTAIN.RESPONSES.EMPTY_STATE.TITLE')
    "
    :subtitle="isApproved ? $t('CAPTAIN.RESPONSES.EMPTY_STATE.SUBTITLE') : ''"
    :action-perms="['administrator']"
    :show-backdrop="false"
  >
    <template #actions>
      <div class="flex flex-col items-center gap-3">
        <Button
          v-if="isApproved"
          :label="$t('CAPTAIN.RESPONSES.ADD_NEW')"
          icon="i-lucide-plus"
          @click="emit('click')"
        />
        <Button
          v-else-if="isPending && hasActiveFilters"
          :label="$t('CAPTAIN.RESPONSES.EMPTY_STATE.CLEAR_SEARCH')"
          variant="link"
          size="sm"
          @click="emit('clearFilters')"
        />
      </div>
    </template>
  </EmptyStateLayout>
</template>

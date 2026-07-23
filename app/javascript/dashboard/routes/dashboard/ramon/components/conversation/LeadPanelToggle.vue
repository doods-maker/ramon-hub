<script setup>
import { computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import LeadFollowUpBanner from './LeadFollowUpBanner.vue';

defineOptions({ name: 'LeadPanelToggle' });

const { uiSettings, updateUISettings } = useUISettings();

const isOpen = computed(() =>
  Boolean(uiSettings.value.is_contact_sidebar_open)
);

const toggle = () => {
  updateUISettings({
    is_contact_sidebar_open: !isOpen.value,
    is_copilot_panel_open: false,
  });
};
</script>

<template>
  <LeadFollowUpBanner />
  <Button
    ghost
    slate
    sm
    data-testid="lead-panel-toggle"
    icon="i-ph-user-bold"
    :label="$t('CONVERSATION.SIDEBAR.CONTACT')"
    :class="{ 'bg-n-alpha-2 !text-n-slate-12': isOpen }"
    @click="toggle"
  />
</template>

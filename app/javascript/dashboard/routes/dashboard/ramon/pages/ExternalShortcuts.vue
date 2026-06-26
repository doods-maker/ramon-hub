<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { DEFAULT_EXTERNAL_SHORTCUTS } from '../externalShortcutsDefaults';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const shortcuts = ref([]);
watch(
  uiSettings,
  v => {
    shortcuts.value = v.external_shortcuts ?? DEFAULT_EXTERNAL_SHORTCUTS.slice();
  },
  { immediate: true }
);

const draft = ref({ label: '', url: '', icon: 'i-lucide-external-link' });

const persist = () => updateUISettings({ external_shortcuts: shortcuts.value });

const add = () => {
  if (!draft.value.label || !draft.value.url) return;
  shortcuts.value.push({ ...draft.value });
  draft.value = { label: '', url: '', icon: 'i-lucide-external-link' };
  persist();
};
const remove = i => { shortcuts.value.splice(i, 1); persist(); };
</script>

<template>
  <div class="flex flex-col w-full h-full p-8 overflow-auto bg-n-background">
    <h1 class="mb-6 text-2xl font-cormorant text-n-slate-12">{{ t('RAMON.SHORTCUTS.TITLE') }}</h1>

    <ul class="flex flex-col gap-2 mb-6 max-w-xl">
      <li v-for="(s, i) in shortcuts" :key="i" class="flex items-center gap-3 p-3 border rounded-lg border-n-weak bg-n-solid-1">
        <span :class="s.icon || 'i-lucide-external-link'" class="size-4 text-n-slate-11" />
        <span class="font-medium text-n-slate-12">{{ s.label }}</span>
        <span class="text-sm truncate text-n-slate-9">{{ s.url }}</span>
        <Button class="ml-auto" icon="Trash2" color="ruby" variant="ghost" size="sm" @click="remove(i)" />
      </li>
    </ul>

    <div class="flex flex-col gap-3 max-w-xl p-4 border rounded-lg border-n-weak">
      <Input v-model="draft.label" :label="t('RAMON.SHORTCUTS.LABEL')" :placeholder="t('RAMON.SHORTCUTS.LABEL_PH')" />
      <Input v-model="draft.url" :label="t('RAMON.SHORTCUTS.URL')" placeholder="https://..." />
      <Input v-model="draft.icon" :label="t('RAMON.SHORTCUTS.ICON')" placeholder="i-lucide-..." />
      <Button :label="t('RAMON.SHORTCUTS.ADD')" icon="Plus" class="self-start" @click="add" />
    </div>
  </div>
</template>

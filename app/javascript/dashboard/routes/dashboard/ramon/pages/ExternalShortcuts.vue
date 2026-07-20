<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { DEFAULT_EXTERNAL_SHORTCUTS } from '../externalShortcutsDefaults';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import ConfirmModal from '../components/ConfirmModal.vue';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

const shortcuts = ref([]);
watch(
  uiSettings,
  v => {
    // Clone raso: edição inline não pode mutar o objeto do store direto.
    shortcuts.value = (v.external_shortcuts ?? DEFAULT_EXTERNAL_SHORTCUTS).map(
      s => ({ ...s })
    );
  },
  { immediate: true }
);

const draft = ref({ label: '', url: '', icon: 'i-lucide-external-link' });
const urlError = ref(false);

const persist = () => updateUISettings({ external_shortcuts: shortcuts.value });

// Sem esquema → prefixa https://; inválida de vez (ou não-http) → null.
const parseHttpUrl = candidate => {
  try {
    const parsed = new URL(candidate);
    return ['http:', 'https:'].includes(parsed.protocol) ? candidate : null;
  } catch {
    return null;
  }
};
const normalizeUrl = raw => {
  const url = raw.trim();
  return parseHttpUrl(url) || parseHttpUrl(`https://${url}`);
};

const add = () => {
  if (!draft.value.label || !draft.value.url) return;
  const url = normalizeUrl(draft.value.url);
  urlError.value = !url;
  if (!url) return;
  shortcuts.value.push({ ...draft.value, url });
  draft.value = { label: '', url: '', icon: 'i-lucide-external-link' };
  persist();
};

const toRemove = ref(null);
const remove = i => {
  toRemove.value = i;
};
const confirmRemove = () => {
  shortcuts.value.splice(toRemove.value, 1);
  toRemove.value = null;
  persist();
};
</script>

<template>
  <div class="flex flex-col w-full h-full p-8 overflow-auto bg-n-background">
    <RamonPageHeader :title="t('RAMON.SHORTCUTS.TITLE')" />

    <ul class="flex flex-col gap-2 mb-6 max-w-xl">
      <li
        v-for="(s, i) in shortcuts"
        :key="i"
        class="flex items-center gap-3 p-3 border rounded-lg border-n-weak bg-n-solid-1"
      >
        <span
          :class="s.icon || 'i-lucide-external-link'"
          class="size-4 shrink-0 text-n-slate-11"
        />
        <input
          v-model="s.label"
          data-testid="shortcut-label-input"
          class="w-32 px-2 py-1 text-sm font-medium rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          :placeholder="t('RAMON.SHORTCUTS.LABEL')"
          @blur="persist"
        />
        <input
          v-model="s.url"
          data-testid="shortcut-url-input"
          class="flex-1 min-w-0 px-2 py-1 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          :placeholder="t('RAMON.SHORTCUTS.URL')"
          @blur="persist"
        />
        <button
          data-testid="shortcut-remove"
          class="ml-auto shrink-0 text-n-slate-9 hover:text-n-ruby-11"
          :title="t('RAMON.FUNIL_CONFIG.REMOVE')"
          @click="remove(i)"
        >
          <span class="i-lucide-trash-2 size-4" />
        </button>
      </li>
    </ul>

    <div
      class="flex flex-col gap-3 max-w-xl p-4 border rounded-lg border-n-weak"
    >
      <label class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-10">
          {{ t('RAMON.SHORTCUTS.LABEL') }}
        </span>
        <input
          v-model="draft.label"
          data-testid="shortcut-new-label"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          :placeholder="t('RAMON.SHORTCUTS.LABEL_PH')"
        />
      </label>
      <label class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-10">
          {{ t('RAMON.SHORTCUTS.URL') }}
        </span>
        <input
          v-model="draft.url"
          data-testid="shortcut-new-url"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          :placeholder="t('RAMON.SHORTCUTS.URL_PH')"
          @input="urlError = false"
        />
        <span
          v-if="urlError"
          data-testid="shortcut-url-error"
          class="text-xs text-n-ruby-11"
        >
          {{ t('RAMON.SHORTCUTS.URL_INVALID') }}
        </span>
      </label>
      <label class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-10">
          {{ t('RAMON.SHORTCUTS.ICON') }}
        </span>
        <input
          v-model="draft.icon"
          data-testid="shortcut-new-icon"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          :placeholder="t('RAMON.SHORTCUTS.ICON_PH')"
        />
      </label>
      <button
        data-testid="shortcut-add"
        class="self-start px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
        :disabled="!draft.label || !draft.url"
        @click="add"
      >
        {{ t('RAMON.SHORTCUTS.ADD') }}
      </button>
    </div>
    <ConfirmModal
      v-if="toRemove !== null"
      :title="t('RAMON.SHORTCUTS.REMOVE_CONFIRM')"
      :message="shortcuts[toRemove]?.label || ''"
      :confirm-label="t('RAMON.FUNIL_CONFIG.REMOVE')"
      @confirm="confirmRemove"
      @cancel="toRemove = null"
    />
  </div>
</template>

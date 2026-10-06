<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { DEFAULT_EXTERNAL_SHORTCUTS } from '../externalShortcutsDefaults';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { CAMPO, CARTAO, ROTULO } from '../helpers/ui';

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

// Blur da URL inline passa pela MESMA validação do add (bloqueia javascript:
// e URL vazia/inválida — senão o rail renderizava href cru).
const persistUrl = s => {
  const url = normalizeUrl(s.url || '');
  if (!url) {
    urlError.value = true;
    return;
  }
  s.url = url;
  persist();
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
  <div class="h-full w-full overflow-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-xl flex-col gap-4">
      <RamonPageHeader class="!mb-0" :title="t('RAMON.SHORTCUTS.TITLE')" />

      <ul class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="(s, i) in shortcuts"
          :key="i"
          :class="CARTAO"
          class="flex items-center gap-3"
        >
          <span
            :class="s.icon || 'i-lucide-external-link'"
            class="size-4 shrink-0 text-n-slate-11"
          />
          <input
            v-model="s.label"
            data-testid="shortcut-label-input"
            :class="CAMPO"
            class="!w-32 font-medium"
            :placeholder="t('RAMON.SHORTCUTS.LABEL')"
            @blur="persist"
          />
          <input
            v-model="s.url"
            data-testid="shortcut-url-input"
            :class="CAMPO"
            class="min-w-0 flex-1"
            :placeholder="t('RAMON.SHORTCUTS.URL')"
            @blur="persistUrl(s)"
            @input="urlError = false"
          />
          <Button
            data-testid="shortcut-remove"
            ghost
            slate
            sm
            icon="i-lucide-trash-2"
            class="shrink-0"
            :title="t('RAMON.FUNIL_CONFIG.REMOVE')"
            @click="remove(i)"
          />
        </li>
      </ul>

      <div :class="CARTAO" class="flex flex-col gap-3">
        <label :class="ROTULO">
          {{ t('RAMON.SHORTCUTS.LABEL') }}
          <input
            v-model="draft.label"
            data-testid="shortcut-new-label"
            :class="CAMPO"
            :placeholder="t('RAMON.SHORTCUTS.LABEL_PH')"
          />
        </label>
        <label :class="ROTULO">
          {{ t('RAMON.SHORTCUTS.URL') }}
          <input
            v-model="draft.url"
            data-testid="shortcut-new-url"
            :class="CAMPO"
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
        <label :class="ROTULO">
          {{ t('RAMON.SHORTCUTS.ICON') }}
          <input
            v-model="draft.icon"
            data-testid="shortcut-new-icon"
            :class="CAMPO"
            class="font-mono"
            :placeholder="t('RAMON.SHORTCUTS.ICON_PH')"
          />
        </label>
        <Button
          data-testid="shortcut-add"
          sm
          class="self-start"
          :label="t('RAMON.SHORTCUTS.ADD')"
          :disabled="!draft.label || !draft.url"
          @click="add"
        />
      </div>
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

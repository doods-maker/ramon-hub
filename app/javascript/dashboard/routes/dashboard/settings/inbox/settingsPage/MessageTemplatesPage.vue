<script setup>
import { ref, reactive, computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const store = useStore();
const { t } = useI18n();

// ponytail: idioma fixo pt_BR (a banca só atende em português); abrir seletor se precisar
const LANGUAGE = 'pt_BR';
const form = reactive({ name: '', category: 'UTILITY', body: '' });
const examples = reactive({});
const isCreating = ref(false);
const isSyncing = ref(false);

const categoryOptions = computed(() => [
  { value: 'UTILITY', label: t('RAMON.MESSAGE_TEMPLATES.CATEGORY.UTILITY') },
  {
    value: 'MARKETING',
    label: t('RAMON.MESSAGE_TEMPLATES.CATEGORY.MARKETING'),
  },
]);

const templates = computed(() => props.inbox.message_templates || []);
const normalizedName = computed(() =>
  form.name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, '_')
);
const variableCount = computed(() =>
  Math.max(
    0,
    ...[...form.body.matchAll(/\{\{(\d+)\}\}/g)].map(match => Number(match[1]))
  )
);
const exampleList = computed(() =>
  Array.from({ length: variableCount.value }, (_, i) => examples[i + 1] || '')
);
const canSubmit = computed(
  () =>
    normalizedName.value &&
    form.body.trim() &&
    exampleList.value.every(example => example.trim())
);

const bodyText = template =>
  template.components?.find(component => component.type === 'BODY')?.text || '';
// Rótulos traduzidos de categoria/status; valor desconhecido da Meta aparece cru.
const translatedLabel = (labels, value) => labels[value] || value;
const categoryLabels = computed(() => ({
  UTILITY: t('RAMON.MESSAGE_TEMPLATES.CATEGORY.UTILITY'),
  MARKETING: t('RAMON.MESSAGE_TEMPLATES.CATEGORY.MARKETING'),
  AUTHENTICATION: t('RAMON.MESSAGE_TEMPLATES.CATEGORY.AUTHENTICATION'),
}));
const statusLabels = computed(() => ({
  APPROVED: t('RAMON.MESSAGE_TEMPLATES.STATUS.APPROVED'),
  PENDING: t('RAMON.MESSAGE_TEMPLATES.STATUS.PENDING'),
  REJECTED: t('RAMON.MESSAGE_TEMPLATES.STATUS.REJECTED'),
  PAUSED: t('RAMON.MESSAGE_TEMPLATES.STATUS.PAUSED'),
  DISABLED: t('RAMON.MESSAGE_TEMPLATES.STATUS.DISABLED'),
}));
const refreshInboxes = () => store.dispatch('inboxes/get');

const syncTemplates = async () => {
  isSyncing.value = true;
  try {
    await InboxesAPI.syncTemplates(props.inbox.id);
    // ponytail: a sincronização roda em job; 3s cobre o caso normal — botão pode ser clicado de novo
    await new Promise(resolve => {
      setTimeout(resolve, 3000);
    });
    await refreshInboxes();
  } catch (_) {
    useAlert(t('RAMON.MESSAGE_TEMPLATES.SYNC_ERROR'));
  } finally {
    isSyncing.value = false;
  }
};

const createTemplate = async () => {
  isCreating.value = true;
  try {
    await InboxesAPI.createMessageTemplate(props.inbox.id, {
      name: normalizedName.value,
      category: form.category,
      language: LANGUAGE,
      body: form.body.trim(),
      examples: exampleList.value,
    });
    await refreshInboxes();
    form.name = '';
    form.body = '';
    Object.keys(examples).forEach(key => delete examples[key]);
    useAlert(t('RAMON.MESSAGE_TEMPLATES.CREATE_SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('RAMON.MESSAGE_TEMPLATES.CREATE_ERROR')
    );
  } finally {
    isCreating.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col gap-8 mx-6 max-w-4xl">
    <section class="flex flex-col gap-4">
      <div>
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('RAMON.MESSAGE_TEMPLATES.NEW_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ t('RAMON.MESSAGE_TEMPLATES.NEW_DESCRIPTION') }}
        </p>
      </div>
      <Input
        v-model="form.name"
        :label="t('RAMON.MESSAGE_TEMPLATES.NAME')"
        :placeholder="t('RAMON.MESSAGE_TEMPLATES.NAME_PLACEHOLDER')"
        :message="
          normalizedName
            ? t('RAMON.MESSAGE_TEMPLATES.NAME_PREVIEW', {
                name: normalizedName,
              })
            : ''
        "
      />
      <div class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('RAMON.MESSAGE_TEMPLATES.CATEGORY.LABEL') }}
        </span>
        <Select v-model="form.category" :options="categoryOptions" />
      </div>
      <TextArea
        v-model="form.body"
        :label="t('RAMON.MESSAGE_TEMPLATES.BODY')"
        :placeholder="t('RAMON.MESSAGE_TEMPLATES.BODY_PLACEHOLDER')"
        :max-length="1024"
        show-character-count
        auto-height
      />
      <div v-if="variableCount" class="flex flex-col gap-2">
        <span class="text-sm text-n-slate-11">
          {{ t('RAMON.MESSAGE_TEMPLATES.EXAMPLES_HINT') }}
        </span>
        <Input
          v-for="n in variableCount"
          :key="n"
          v-model="examples[n]"
          :label="`{{${n}}}`"
        />
      </div>
      <div>
        <NextButton
          :label="t('RAMON.MESSAGE_TEMPLATES.SUBMIT')"
          :is-loading="isCreating"
          :disabled="!canSubmit"
          @click="createTemplate"
        />
      </div>
    </section>

    <section class="flex flex-col gap-3">
      <div class="flex items-center justify-between gap-4">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ t('RAMON.MESSAGE_TEMPLATES.LIST_TITLE') }}
        </h3>
        <NextButton
          :label="t('RAMON.MESSAGE_TEMPLATES.SYNC')"
          :is-loading="isSyncing"
          slate
          faded
          sm
          @click="syncTemplates"
        />
      </div>
      <p v-if="!templates.length" class="text-sm text-n-slate-11">
        {{ t('RAMON.MESSAGE_TEMPLATES.EMPTY') }}
      </p>
      <div
        v-for="template in templates"
        :key="`${template.name}-${template.language}`"
        class="flex flex-col gap-1 p-3 rounded-lg outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <div class="flex flex-wrap items-center gap-2 text-sm">
          <span class="font-medium text-n-slate-12">{{ template.name }}</span>
          <span class="text-n-slate-11">
            {{ translatedLabel(categoryLabels, template.category) }}
          </span>
          <span class="text-n-slate-11">{{ template.language }}</span>
          <span
            class="px-2 py-0.5 text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
          >
            {{ translatedLabel(statusLabels, template.status) }}
          </span>
        </div>
        <p class="text-sm whitespace-pre-line text-n-slate-11">
          {{ bodyText(template) }}
        </p>
      </div>
    </section>
  </div>
</template>

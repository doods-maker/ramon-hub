<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, url } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  assistantId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();
const uiFlags = useMapGetter('captainDocuments/getUIFlags');

// ponytail: só URL. O PDF ia para a OpenAI (pdf_processing_service) e aqui só
// há DeepSeek; "Colar texto" entra no I-DO1.
const state = reactive({ name: '', url: '' });
const v$ = useVuelidate({ url: { required, url } }, state);

const isLoading = computed(() => uiFlags.value.creatingItem);
const urlError = computed(() =>
  v$.value.url.$error ? t('CAPTAIN.DOCUMENTS.FORM.URL.ERROR') : ''
);

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  const formData = new FormData();
  formData.append('document[assistant_id]', props.assistantId);
  formData.append('document[external_link]', state.url);
  formData.append('document[name]', state.name || state.url);
  emit('submit', formData);
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <Input
      v-model="state.url"
      :label="t('CAPTAIN.DOCUMENTS.FORM.URL.LABEL')"
      :placeholder="t('CAPTAIN.DOCUMENTS.FORM.URL.PLACEHOLDER')"
      :message="urlError"
      :message-type="urlError ? 'error' : 'info'"
    />

    <Input
      v-model="state.name"
      :label="t('CAPTAIN.DOCUMENTS.FORM.NAME.LABEL')"
      :placeholder="t('CAPTAIN.DOCUMENTS.FORM.NAME.PLACEHOLDER')"
    />

    <div class="flex gap-3 justify-between items-center w-full">
      <Button
        type="button"
        variant="faded"
        color="slate"
        :label="t('CAPTAIN.FORM.CANCEL')"
        class="w-full bg-n-alpha-2 text-n-blue-11 hover:bg-n-alpha-3"
        @click="emit('cancel')"
      />
      <Button
        type="submit"
        :label="t('CAPTAIN.FORM.CREATE')"
        class="w-full"
        :is-loading="isLoading"
        :disabled="isLoading"
      />
    </div>
  </form>
</template>

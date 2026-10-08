<script setup>
import { reactive, ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, url, maxLength } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';

import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
  AVISO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  assistantId: {
    type: Number,
    required: true,
  },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();
const uiFlags = useMapGetter('captainDocuments/getUIFlags');

// ponytail: sem PDF — ia para a OpenAI (pdf_processing_service) e aqui só há
// DeepSeek. "Colar texto" (I-DO1) cobre o caso: copie o texto do PDF e cole.
// Mesmo teto do modelo (Captain::Document validates :content, maximum: 200_000).
const MAX_TEXTO = 200000;
const MODOS = ['link', 'texto'];

const modo = ref('link');
const state = reactive({ name: '', url: '', texto: '' });
const ehTexto = computed(() => modo.value === 'texto');
const rules = computed(() =>
  ehTexto.value
    ? {
        name: { required },
        texto: { required, maxLength: maxLength(MAX_TEXTO) },
      }
    : { url: { required, url } }
);
const v$ = useVuelidate(rules, state);

const isLoading = computed(() => uiFlags.value.creatingItem);
const urlError = computed(() =>
  v$.value.url?.$error ? t('CAPTAIN.DOCUMENTS.FORM.URL.ERROR') : ''
);
const tituloError = computed(() =>
  v$.value.name?.$error ? t('INTEL.DOCUMENTOS.TITULO_ERRO') : ''
);
const textoError = computed(() =>
  v$.value.texto?.$error ? t('INTEL.DOCUMENTOS.TEXTO_ERRO') : ''
);
const rotuloModo = item =>
  item === 'texto'
    ? t('INTEL.DOCUMENTOS.MODO_TEXTO')
    : t('INTEL.DOCUMENTOS.MODO_LINK');

const trocarModo = novo => {
  modo.value = novo;
  v$.value.$reset();
};

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  const formData = new FormData();
  formData.append('document[assistant_id]', props.assistantId);
  if (ehTexto.value) {
    formData.append('document[name]', state.name.trim());
    formData.append('document[content]', state.texto);
  } else {
    formData.append('document[external_link]', state.url);
    formData.append('document[name]', state.name || state.url);
  }
  emit('submit', formData);
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <nav class="flex gap-1 border-b border-n-weak">
      <button
        v-for="item in MODOS"
        :key="item"
        type="button"
        :data-testid="`documento-modo-${item}`"
        :class="[ABA, modo === item ? ABA_ATIVA : ABA_INATIVA]"
        @click="trocarModo(item)"
      >
        {{ rotuloModo(item) }}
      </button>
    </nav>

    <template v-if="ehTexto">
      <Input
        v-model="state.name"
        :label="t('INTEL.DOCUMENTOS.TITULO_LABEL')"
        :placeholder="t('INTEL.DOCUMENTOS.TITULO_PLACEHOLDER')"
        :message="tituloError"
        :message-type="tituloError ? 'error' : 'info'"
      />
      <TextArea
        v-model="state.texto"
        :label="t('INTEL.DOCUMENTOS.TEXTO_LABEL')"
        :placeholder="t('INTEL.DOCUMENTOS.TEXTO_PLACEHOLDER')"
        :max-length="MAX_TEXTO"
        show-character-count
        resize
        min-height="12rem"
        max-height="20rem"
        :message="textoError"
        :message-type="textoError ? 'error' : 'info'"
      />
    </template>
    <template v-else>
      <Input
        v-model="state.url"
        :label="t('CAPTAIN.DOCUMENTS.FORM.URL.LABEL')"
        :placeholder="t('CAPTAIN.DOCUMENTS.FORM.URL.PLACEHOLDER')"
        :message="urlError"
        :message-type="urlError ? 'error' : 'info'"
      />
      <p data-testid="documento-link-aviso" :class="[AVISO, TOM.amber]">
        {{ t('INTEL.DOCUMENTOS.LINK_AVISO') }}
      </p>
      <Input
        v-model="state.name"
        :label="t('CAPTAIN.DOCUMENTS.FORM.NAME.LABEL')"
        :placeholder="t('CAPTAIN.DOCUMENTS.FORM.NAME.PLACEHOLDER')"
      />
    </template>

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

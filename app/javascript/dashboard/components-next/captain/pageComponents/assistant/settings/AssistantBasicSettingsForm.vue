<script setup>
import { reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Editor from 'dashboard/components-next/Editor/Editor.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import { AVISO, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  assistant: {
    type: Object,
    default: () => ({}),
  },
  // 'lead' (tem caixa conectada) | 'equipe' (só Testar e painel do Copiloto)
  publico: {
    type: String,
    default: 'lead',
  },
});
const emit = defineEmits(['submit']);
// ramon (I-CF3): o nome do escritório já vem preenchido quando o assistente não tem.
const ESCRITORIO = 'Ramon Antonio Advogados';
// ramon (I-CF4): chaves que só valem em conversa com lead. "Citações" sai da tela: no modo do agente não muda
// nada e citação numerada não cabe em WhatsApp — é salva desligada.
const CHAVES_DO_LEAD = [
  {
    campo: 'conversationFaqs',
    rotulo: 'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONVERSATION_FAQS',
  },
  {
    campo: 'memories',
    rotulo: 'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_MEMORIES',
    ajuda: 'INTEL.CONFIG.MEMORIA_AJUDA',
  },
  {
    campo: 'contactAttributes',
    rotulo: 'CAPTAIN.ASSISTANTS.FORM.FEATURES.ALLOW_CONTACT_ATTRIBUTES',
  },
];

const { t } = useI18n();

const state = reactive({
  name: '',
  description: '',
  productName: '',
  features: {
    conversationFaqs: false,
    memories: false,
    contactAttributes: false,
  },
});

const validationRules = {
  name: { required, minLength: minLength(1) },
  description: { required, minLength: minLength(1) },
  productName: { required, minLength: minLength(1) },
};

const v$ = useVuelidate(validationRules, state);

const getErrorMessage = field => {
  return v$.value[field].$error ? v$.value[field].$errors[0].$message : '';
};

const formErrors = computed(() => ({
  name: getErrorMessage('name'),
  description: getErrorMessage('description'),
  productName: getErrorMessage('productName'),
}));

const updateStateFromAssistant = assistant => {
  const { config = {} } = assistant;
  state.name = assistant.name;
  state.description = assistant.description;
  state.productName = config.product_name || ESCRITORIO;
  state.features = {
    conversationFaqs: config.feature_faq || false,
    memories: config.feature_memory || false,
    contactAttributes: config.feature_contact_attributes || false,
  };
};

const handleBasicInfoUpdate = async () => {
  const result = await Promise.all([
    v$.value.name.$validate(),
    v$.value.description.$validate(),
    v$.value.productName.$validate(),
  ]).then(results => results.every(Boolean));
  if (!result) return;

  emit('submit', {
    name: state.name,
    description: state.description,
    config: {
      ...props.assistant.config,
      product_name: state.productName,
      feature_faq: state.features.conversationFaqs,
      feature_memory: state.features.memories,
      feature_citation: false,
      feature_contact_attributes: state.features.contactAttributes,
    },
  });
};

watch(
  () => props.assistant,
  newAssistant => {
    if (newAssistant) updateStateFromAssistant(newAssistant);
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <Input
      v-model="state.name"
      :label="t('CAPTAIN.ASSISTANTS.FORM.NAME.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.NAME.PLACEHOLDER')"
      :message="formErrors.name"
      :message-type="formErrors.name ? 'error' : 'info'"
    />

    <Input
      v-model="state.productName"
      :label="t('CAPTAIN.ASSISTANTS.FORM.PRODUCT_NAME.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.PRODUCT_NAME.PLACEHOLDER')"
      :message="formErrors.productName"
      :message-type="formErrors.productName ? 'error' : 'info'"
    />

    <Editor
      v-model="state.description"
      :label="t('CAPTAIN.ASSISTANTS.FORM.DESCRIPTION.LABEL')"
      :placeholder="t('CAPTAIN.ASSISTANTS.FORM.DESCRIPTION.PLACEHOLDER')"
      :message="formErrors.description"
      :message-type="formErrors.description ? 'error' : 'info'"
      class="z-0"
    />

    <div class="flex flex-col gap-3">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.ASSISTANTS.FORM.FEATURES.TITLE') }}
      </span>
      <template v-if="publico === 'lead'">
        <div
          v-for="chave in CHAVES_DO_LEAD"
          :key="chave.campo"
          data-testid="config-chave"
          class="flex items-start gap-3"
        >
          <Switch v-model="state.features[chave.campo]" class="mt-0.5" />
          <div class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-12">{{ t(chave.rotulo) }}</span>
            <span v-if="chave.ajuda" class="text-xs text-n-slate-10">
              {{ t(chave.ajuda) }}
            </span>
          </div>
        </div>
      </template>
      <p v-else :class="[AVISO, TOM.slate]">
        {{ t('INTEL.CONFIG.SO_EQUIPE') }}
      </p>
    </div>

    <div>
      <Button
        :label="t('CAPTAIN.ASSISTANTS.FORM.UPDATE')"
        @click="handleBasicInfoUpdate"
      />
    </div>
  </div>
</template>

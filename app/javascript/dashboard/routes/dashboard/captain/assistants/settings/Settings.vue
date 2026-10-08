<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAccount } from 'dashboard/composables/useAccount';
import Policy from 'dashboard/components/policy.vue';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import Button from 'dashboard/components-next/button/Button.vue';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import SettingsHeader from 'dashboard/components-next/captain/pageComponents/settings/SettingsHeader.vue';
import AssistantBasicSettingsForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantBasicSettingsForm.vue';
import AssistantSystemSettingsForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantSystemSettingsForm.vue';
import AssistantControlItems from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantControlItems.vue';
import DeleteDialog from 'dashboard/components-next/captain/pageComponents/DeleteDialog.vue';
import TextoFinal from 'dashboard/components-next/captain/pageComponents/assistant/settings/TextoFinal.vue';
import {
  CAMPO,
  CARTAO_STATUS,
  FILETE,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const { t } = useI18n();
const { isCloudFeatureEnabled } = useAccount();

const isCaptainV2Enabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN_V2)
);
const route = useRoute();
const router = useRouter();
const store = useStore();

const deleteAssistantDialog = ref(null);

const uiFlags = useMapGetter('captainAssistants/getUIFlags');
const assistants = useMapGetter('captainAssistants/getRecords');
const isFetching = computed(() => uiFlags.value.fetchingItem);
const assistantId = computed(() => Number(route.params.assistantId));
const assistant = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

// I-CF4: público de cada assistente (lead = tem caixa conectada) — muda o que os formulários mostram.
const cartoes = ref([]);
onMounted(async () => {
  try {
    const { data } = await CaptainAssistantAPI.stats();
    cartoes.value = data.payload;
  } catch (e) {
    cartoes.value = [];
  }
});
const publico = computed(
  () =>
    cartoes.value.find(item => item.id === assistantId.value)?.publico || 'lead'
);

// I-CF5: excluir só depois de digitar o nome exato (zona de risco recolhida, só administrador).
const confirmaNome = ref('');
watch(assistantId, () => {
  confirmaNome.value = '';
});
const podeExcluir = computed(
  () =>
    !!assistant.value?.name &&
    confirmaNome.value.trim() === assistant.value.name
);

// I-CF6
const textoFinalAberto = ref(false);

const controlItems = computed(() => {
  return [
    {
      name: t(
        'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.GUARDRAILS.TITLE'
      ),
      description: t(
        'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.GUARDRAILS.DESCRIPTION'
      ),
      routeName: 'captain_assistants_guardrails_index',
    },
    {
      name: t(
        'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.RESPONSE_GUIDELINES.TITLE'
      ),
      description: t(
        'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.RESPONSE_GUIDELINES.DESCRIPTION'
      ),
      routeName: 'captain_assistants_guidelines_index',
    },
  ];
});

const handleSubmit = async updatedAssistant => {
  try {
    await store.dispatch('captainAssistants/update', {
      id: assistantId.value,
      ...updatedAssistant,
    });
    useAlert(t('CAPTAIN.ASSISTANTS.EDIT.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('CAPTAIN.ASSISTANTS.EDIT.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

const handleDelete = () => {
  deleteAssistantDialog.value.dialogRef.open();
};

const handleDeleteSuccess = () => {
  // Get remaining assistants after deletion
  const remainingAssistants = assistants.value.filter(
    a => a.id !== assistantId.value
  );

  if (remainingAssistants.length > 0) {
    // Navigate to the first available assistant's settings
    const nextAssistant = remainingAssistants[0];
    router.push({
      name: 'captain_assistants_settings_index',
      params: {
        accountId: route.params.accountId,
        assistantId: nextAssistant.id,
      },
    });
  } else {
    // No assistants left, redirect to create assistant page
    router.push({
      name: 'captain_assistants_create_index',
      params: { accountId: route.params.accountId },
    });
  }
};
</script>

<template>
  <PageLayout
    :is-fetching="isFetching"
    :show-pagination-footer="false"
    show-assistant-switcher
    :class="{
      '[&>header>div]:max-w-[80rem] [&>main>div]:max-w-[80rem]':
        isCaptainV2Enabled,
    }"
  >
    <template #body>
      <div
        class="gap-6 lg:gap-16 pb-8"
        :class="{ 'grid grid-cols-2': isCaptainV2Enabled }"
      >
        <div class="flex flex-col gap-6">
          <div class="flex flex-col gap-6">
            <SettingsHeader
              :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.BASIC_SETTINGS.TITLE')"
              :description="
                t('CAPTAIN.ASSISTANTS.SETTINGS.BASIC_SETTINGS.DESCRIPTION')
              "
            />
            <AssistantBasicSettingsForm
              :assistant="assistant"
              :publico="publico"
              @submit="handleSubmit"
            />
          </div>
          <span class="h-px w-full bg-n-weak mt-2" />
          <div class="flex flex-col gap-6">
            <SettingsHeader
              :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.SYSTEM_SETTINGS.TITLE')"
              :description="
                t('CAPTAIN.ASSISTANTS.SETTINGS.SYSTEM_SETTINGS.DESCRIPTION')
              "
            />
            <AssistantSystemSettingsForm
              :assistant="assistant"
              :publico="publico"
              @submit="handleSubmit"
            />
          </div>
          <span class="h-px w-full bg-n-weak mt-2" />
          <Policy :permissions="['administrator']">
            <details
              data-testid="zona-de-risco"
              :class="[CARTAO_STATUS, FILETE.ruby]"
            >
              <summary
                class="text-sm font-medium cursor-pointer text-n-ruby-11"
              >
                {{ t('INTEL.CONFIG.ZONA_RISCO') }}
              </summary>
              <p class="mt-2 text-sm text-n-slate-11">
                {{ t('CAPTAIN.ASSISTANTS.SETTINGS.DELETE.DESCRIPTION') }}
              </p>
              <input
                v-model="confirmaNome"
                data-testid="zona-de-risco-nome"
                class="mt-3"
                :class="CAMPO"
                :placeholder="
                  t('INTEL.CONFIG.DIGITE_NOME', { nome: assistant?.name })
                "
              />
              <Button
                data-testid="zona-de-risco-excluir"
                class="mt-3 max-w-56 !w-fit"
                color="ruby"
                size="sm"
                :disabled="!podeExcluir"
                :label="
                  t('CAPTAIN.ASSISTANTS.SETTINGS.DELETE.BUTTON_TEXT', {
                    assistantName: assistant?.name,
                  })
                "
                @click="handleDelete"
              />
            </details>
          </Policy>
        </div>
        <div v-if="isCaptainV2Enabled" class="flex flex-col gap-6">
          <SettingsHeader
            :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.TITLE')"
            :description="
              t('CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.DESCRIPTION')
            "
          />
          <div class="flex flex-col gap-6">
            <AssistantControlItems
              v-for="item in controlItems"
              :key="item.name"
              :control-item="item"
            />
          </div>
          <Button
            variant="link"
            size="sm"
            icon="i-lucide-file-text"
            class="self-start"
            data-testid="ver-texto-final"
            :label="t('INTEL.CONFIG.TEXTO_FINAL')"
            @click="textoFinalAberto = true"
          />
        </div>
      </div>
    </template>
    <TextoFinal
      v-if="textoFinalAberto"
      :assistant-id="assistantId"
      @fechar="textoFinalAberto = false"
    />
    <DeleteDialog
      v-if="assistant"
      ref="deleteAssistantDialog"
      :entity="assistant"
      type="Assistants"
      translation-key="ASSISTANTS"
      @delete-success="handleDeleteSuccess"
    />
  </PageLayout>
</template>

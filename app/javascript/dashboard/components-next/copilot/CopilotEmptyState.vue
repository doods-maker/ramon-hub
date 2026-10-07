<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui.js';
import Icon from '../icon/Icon.vue';

const props = defineProps({
  hasAssistants: { type: Boolean, default: false },
  // ramon (A4): assistente da equipe → atalhos da banca (rodam as skills do Copiloto do Escritório)
  equipe: { type: Boolean, default: false },
  naConversa: { type: Boolean, default: false },
});

const emit = defineEmits(['useSuggestion']);
const { t } = useI18n();
const route = useRoute();

const routePromptMap = {
  conversations: [
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.LABEL',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.SUMMARIZE.CONTENT',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.SUGGEST.LABEL',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.SUGGEST.CONTENT',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.RATE.LABEL',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.RATE.CONTENT',
    },
  ],
  dashboard: [
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.HIGH_PRIORITY.LABEL',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.HIGH_PRIORITY.CONTENT',
    },
    {
      label: 'CAPTAIN.COPILOT.PROMPTS.LIST_CONTACTS.LABEL',
      prompt: 'CAPTAIN.COPILOT.PROMPTS.LIST_CONTACTS.CONTENT',
    },
  ],
};

const K = 'CAPTAIN_RAMON.COPILOTO_ATALHOS';
const ATALHOS_EQUIPE = {
  conversa: [
    { chave: 'SITUACAO', icone: 'i-lucide-scale' },
    { chave: 'DOCUMENTOS', icone: 'i-lucide-file-check' },
    { chave: 'REUNIAO', icone: 'i-lucide-calendar-check' },
  ],
  geral: [
    { chave: 'AGENDA', icone: 'i-lucide-calendar-days' },
    { chave: 'FUNIL', icone: 'i-lucide-filter' },
    { chave: 'PRAZOS', icone: 'i-lucide-alarm-clock' },
  ],
};

const promptOptions = computed(() => {
  if (props.equipe) {
    return ATALHOS_EQUIPE[props.naConversa ? 'conversa' : 'geral'].map(
      ({ chave, icone }) => ({
        label: `${K}.${chave}.LABEL`,
        prompt: `${K}.${chave}.CONTENT`,
        icone,
      })
    );
  }
  return routePromptMap[props.naConversa ? 'conversations' : 'dashboard'];
});

// fora da conversa não há caso aberto: frase própria
const kickoff = computed(() => {
  if (!props.equipe) return t('CAPTAIN.COPILOT.KICK_OFF_MESSAGE');
  return t(`${K}.${props.naConversa ? 'KICKOFF' : 'KICKOFF_GERAL'}`);
});

const handleSuggestion = opt => {
  emit('useSuggestion', t(opt.prompt));
};
</script>

<template>
  <div class="flex-1 flex flex-col gap-6 px-2">
    <div class="flex flex-col space-y-4 py-4">
      <Icon icon="i-woot-captain" class="text-n-slate-9 text-4xl" />
      <div class="space-y-1">
        <h3 class="text-base font-medium text-n-slate-12 leading-8">
          {{ $t('CAPTAIN.COPILOT.PANEL_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11 leading-6">
          {{ kickoff }}
        </p>
      </div>
    </div>
    <div v-if="!hasAssistants" class="w-full space-y-2">
      <p class="text-sm text-n-slate-11 leading-6">
        {{ $t('CAPTAIN.ASSISTANTS.NO_ASSISTANTS_AVAILABLE') }}
      </p>
      <router-link
        :to="{
          name: 'captain_assistants_create_index',
          params: {
            accountId: route.params.accountId,
          },
        }"
        class="text-n-slate-11 underline hover:text-n-slate-12"
      >
        {{ $t('CAPTAIN.ASSISTANTS.ADD_NEW') }}
      </router-link>
    </div>
    <div v-else class="w-full space-y-2">
      <span class="text-xs text-n-slate-10 block">
        {{ $t('CAPTAIN.COPILOT.TRY_THESE_PROMPTS') }}
      </span>
      <div class="space-y-1">
        <button
          v-for="prompt in promptOptions"
          :key="prompt.label"
          class="w-full flex items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-left text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-2"
          @click="handleSuggestion(prompt)"
        >
          <span class="flex min-w-0 items-center gap-2">
            <span
              v-if="prompt.icone"
              class="flex size-6 shrink-0 items-center justify-center rounded-md"
              :class="TOM.blue"
            >
              <Icon :icon="prompt.icone" class="size-3.5" />
            </span>
            <span class="truncate">{{ t(prompt.label) }}</span>
          </span>
          <Icon
            icon="i-lucide-chevron-right"
            class="shrink-0 text-n-slate-10"
          />
        </button>
      </div>
    </div>
  </div>
</template>

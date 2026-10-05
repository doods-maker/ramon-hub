<script>
import { reactive } from 'vue';

// Resumo da IA por conversa, no escopo do módulo: sobrevive à troca de aba
// e ao remount do painel (antes sumia e o usuário pagava outra geração).
// ponytail: só na memória da página — F5 limpa; persistir se pedirem.
const summaries = reactive(new Map()); // conversationId → { summary, generatedAt }
</script>

<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import RamonCopilotAPI from 'dashboard/api/ramonCopilot';
import Button from 'dashboard/components-next/button/Button.vue';
import { CARTAO, TITULO } from '../../helpers/ui';

// Linha "Resumo da IA" do Resumo (o "Sugerir resposta" fica no cabeçalho).
const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});
defineOptions({ name: 'LeadCopilot' });

const { t } = useI18n();
const cached = computed(() => summaries.get(String(props.conversationId)));
const summary = computed(() => cached.value?.summary || '');
const generatedAt = computed(() => cached.value?.generatedAt ?? null);
const loading = ref(false);
const expanded = ref(false);
watch(
  () => props.conversationId,
  () => {
    expanded.value = false;
  }
);

const generatedAgo = computed(() =>
  generatedAt.value ? dynamicTime(generatedAt.value / 1000) : null
);
// ponytail: "longo" por tamanho (~60 caracteres por linha nos 400px), sem
// medir o DOM; medir o scrollHeight se o "ver tudo" sobrar ou faltar.
const longo = computed(
  () => summary.value.length > 180 || summary.value.split('\n').length > 3
);

const generate = async () => {
  if (loading.value) return;
  loading.value = true;
  // id capturado antes do await: trocar de conversa no meio não troca o dono
  const id = props.conversationId;
  try {
    const { data } = await RamonCopilotAPI.generate(id, 'summary');
    summaries.set(String(id), {
      summary: data.content,
      generatedAt: Date.now(),
    });
  } catch (error) {
    useAlert(error?.response?.data?.error || t('RAMON.COPILOT.ERROR'));
  } finally {
    loading.value = false;
  }
};
</script>

<template>
  <div data-testid="lead-copilot" :class="CARTAO">
    <!-- sem resumo: uma linha só, clicar gera -->
    <button
      v-if="!summary"
      type="button"
      data-testid="copilot-summarize"
      class="flex items-center w-full gap-1.5 p-0 text-left text-xs text-n-slate-11 hover:text-n-slate-12 disabled:opacity-60"
      :disabled="loading"
      @click="generate"
    >
      <span class="i-lucide-sparkles size-3.5 shrink-0 text-n-blue-11" />
      <span class="font-medium text-n-slate-12">
        {{ $t('RAMON.COPILOT.SUMMARY_TITLE') }}
      </span>
      <span>·</span>
      <span class="text-n-blue-11">
        {{
          loading ? $t('RAMON.COPILOT.WORKING') : $t('RAMON.COPILOT.GENERATE')
        }}
      </span>
    </button>
    <template v-else>
      <div class="flex items-center gap-2">
        <p :class="TITULO">
          {{ $t('RAMON.COPILOT.SUMMARY_TITLE') }}
          <span
            data-testid="copilot-summary-time"
            class="normal-case tracking-normal font-normal text-n-slate-9"
          >
            {{ `· ${generatedAgo}` }}
          </span>
        </p>
        <Button
          data-testid="copilot-summarize"
          xs
          ghost
          slate
          icon="i-lucide-refresh-cw"
          class="ml-auto"
          :class="{ 'animate-spin': loading }"
          :disabled="loading"
          :aria-label="$t('RAMON.COPILOT.REFRESH')"
          :title="$t('RAMON.COPILOT.REFRESH')"
          @click="generate"
        />
      </div>
      <!-- resumo num quadro cinza com filete à esquerda (como na referência) -->
      <div class="mt-2 rounded-lg bg-n-alpha-1 px-3 py-2">
        <p
          data-testid="copilot-summary"
          class="border-l-2 border-n-slate-6 pl-2.5 text-[12.5px] leading-[1.55] text-n-slate-11 whitespace-pre-wrap break-words"
          :class="{ 'line-clamp-3': !expanded }"
        >
          {{ summary }}
        </p>
        <Button
          v-if="longo"
          data-testid="copilot-toggle"
          link
          xs
          class="mt-1"
          :label="
            expanded
              ? $t('RAMON.COPILOT.SEE_LESS')
              : $t('RAMON.COPILOT.SEE_ALL')
          "
          @click="expanded = !expanded"
        />
      </div>
    </template>
  </div>
</template>

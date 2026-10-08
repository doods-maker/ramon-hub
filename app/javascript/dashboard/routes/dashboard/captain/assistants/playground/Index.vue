<script setup>
// Testar: a conversa avulsa com o assistente (AssistantPlayground) + atalhos da A5 — falas das skills
// (as do seu papel primeiro, I-X5), "Testar com o caso…" (I-PG4) e a fala vinda de "Testar esta skill"
// (?fala=, I-SK6). Nada é enviado sozinho: os atalhos só escrevem no campo (N7).
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import AssistantPlayground from 'dashboard/components-next/captain/assistant/AssistantPlayground.vue';
import AbasTestar from '../../casos/AbasTestar.vue';
import TestarComCaso from './TestarComCaso.vue';
import { referenciaCaso, skillsDoPapel } from './testar';
import { CHIP, TITULO, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';

const VISIVEIS = 8;

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const assistantId = computed(() => Number(route.params.assistantId));
const playground = ref(null);

const skills = useMapGetter('captainScenarios/getRecords');
const meusTimes = useMapGetter('teams/getMyTeams');
const sugestoes = computed(() =>
  skillsDoPapel(skills.value, meusTimes.value).slice(0, VISIVEIS)
);

watch(
  assistantId,
  id => store.dispatch('captainScenarios/get', { assistantId: id }),
  { immediate: true }
);

onMounted(async () => {
  store.dispatch('teams/get');
  await nextTick();
  if (route.query?.fala) playground.value?.escrever(String(route.query.fala));
});

const usarCaso = lead => playground.value?.anexar(referenciaCaso(lead));
</script>

<template>
  <PageLayout
    show-assistant-switcher
    :show-pagination-footer="false"
    class="h-full"
  >
    <template #subHeader>
      <AbasTestar ativa="conversa" />
    </template>
    <template #body>
      <div class="flex flex-col h-full gap-3">
        <div class="flex flex-wrap items-start gap-3">
          <TestarComCaso class="w-72 shrink-0" @escolher="usarCaso" />
          <div
            v-if="sugestoes.length"
            data-testid="testar-sugestoes"
            class="flex flex-wrap items-center flex-1 min-w-0 gap-1.5"
          >
            <span :class="TITULO">{{ t('INTEL.TESTAR.SUGESTOES') }}</span>
            <button
              v-for="skill in sugestoes"
              :key="skill.id"
              type="button"
              data-testid="testar-sugestao"
              class="hover:brightness-110"
              :class="[CHIP, skill.meu ? TOM.blue : TOM.slate]"
              :title="skill.exemplo"
              @click="playground?.escrever(skill.exemplo)"
            >
              {{ skill.title }}
            </button>
          </div>
        </div>
        <AssistantPlayground
          ref="playground"
          :assistant-id="assistantId"
          class="flex-1 min-h-0 bg-n-solid-1"
        />
      </div>
    </template>
  </PageLayout>
</template>

<script setup>
// Testar: a conversa avulsa com o assistente (AssistantPlayground) + atalhos da A5 — falas das skills
// (as do seu papel primeiro, I-X5), "Testar com o caso…" (I-PG4) e a fala vinda de "Testar esta skill"
// (?fala=, I-SK6). Nada é enviado sozinho: os atalhos só escrevem no campo (N7).
// Roteiro da tese (F2): escolher a tese faz a IA seguir o roteiro dela; o roteiro roda de verdade, nada é
// gravado, e o passo a passo aparece ao lado da conversa.
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import AssistantPlayground from 'dashboard/components-next/captain/assistant/AssistantPlayground.vue';
import {
  garantirConversa,
  roteiroDe,
} from 'dashboard/components-next/captain/assistant/testarConversas';
import RoteiroDoLead from 'dashboard/routes/dashboard/ramon/components/lead/RoteiroDoLead.vue';
import AbasTestar from '../../casos/AbasTestar.vue';
import TestarComCaso from './TestarComCaso.vue';
import { referenciaCaso, skillsDoPapel } from './testar';
import {
  CHIP,
  SELECT,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const VISIVEIS = 8;

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const assistantId = computed(() => Number(route.params.assistantId));
const playground = ref(null);

const skills = useMapGetter('captainScenarios/getRecords');
const meusTimes = useMapGetter('teams/getMyTeams');
const teses = useMapGetter('theses/getTheses');
const sugestoes = computed(() =>
  skillsDoPapel(skills.value, meusTimes.value).slice(0, VISIVEIS)
);
const roteiro = computed(() => roteiroDe(assistantId.value));

watch(
  assistantId,
  id => {
    garantirConversa(id);
    store.dispatch('captainScenarios/get', { assistantId: id });
  },
  { immediate: true }
);

onMounted(async () => {
  store.dispatch('teams/get');
  store.dispatch('theses/get');
  await nextTick();
  if (route.query?.fala) playground.value?.escrever(String(route.query.fala));
});

const usarCaso = lead => playground.value?.anexar(referenciaCaso(lead));

// Trocar a tese recomeça o roteiro do teste (a conversa fica — limpe-a para começar do zero).
const escolherTese = evento => {
  Object.assign(roteiro.value, {
    thesisId: Number(evento.target.value) || null,
    estado: null,
    painel: null,
  });
};
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
          <select
            data-testid="testar-roteiro-tese"
            class="!w-60 shrink-0"
            :class="SELECT"
            :value="roteiro?.thesisId || ''"
            :title="t('RAMON.ROTEIRO_IA.TESTAR.AJUDA')"
            :aria-label="t('RAMON.ROTEIRO_IA.TESTAR.AJUDA')"
            @change="escolherTese"
          >
            <option value="">
              {{ t('RAMON.ROTEIRO_IA.TESTAR.SEM_TESE') }}
            </option>
            <option v-for="tese in teses" :key="tese.id" :value="tese.id">
              {{ tese.name }}
            </option>
          </select>
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
        <div class="flex flex-1 min-h-0 gap-3">
          <AssistantPlayground
            ref="playground"
            :assistant-id="assistantId"
            class="flex-1 min-w-0 min-h-0 bg-n-solid-1"
          />
          <RoteiroDoLead
            v-if="roteiro?.painel"
            class="w-72 shrink-0 self-start"
            :roteiro="roteiro.painel"
          />
        </div>
      </div>
    </template>
  </PageLayout>
</template>

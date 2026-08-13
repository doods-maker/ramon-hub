<script setup>
import { computed } from 'vue';

const props = defineProps({
  lead: { type: Object, required: true },
});

defineOptions({ name: 'LeadQuizResumo' });

const quiz = computed(() => props.lead?.custom_attributes?.quiz || null);
const respostas = computed(() => quiz.value?.respostas || []);
const duvidas = computed(() => quiz.value?.duvidas || []);
</script>

<template>
  <div
    v-if="quiz"
    data-testid="lead-quiz-resumo"
    class="pt-3 border-t border-n-weak"
  >
    <div class="flex items-center gap-2 mb-2">
      <p
        class="text-[10.5px] font-semibold uppercase tracking-[.1em] text-n-slate-10"
      >
        {{ $t('RAMON.LEAD_PANEL.QUIZ.TITLE') }}
      </p>
      <span
        class="rounded-full px-2 py-0.5 text-[10.5px]"
        :class="
          quiz.qualificado
            ? 'bg-n-teal-9/10 text-n-teal-11'
            : 'bg-n-ruby-9/10 text-n-ruby-11'
        "
      >
        {{
          quiz.qualificado
            ? $t('RAMON.LEAD_PANEL.QUIZ.QUALIFIED')
            : $t('RAMON.LEAD_PANEL.QUIZ.DISQUALIFIED')
        }}
      </span>
    </div>
    <dl class="flex flex-col gap-1">
      <div
        v-for="r in respostas"
        :key="r.id"
        class="flex justify-between gap-2 text-[12px]"
      >
        <dt class="text-n-slate-10">{{ r.pergunta }}</dt>
        <dd
          class="text-right text-n-slate-12"
          :class="{ 'text-n-ruby-11': r.reprova, 'text-n-amber-11': r.duvida }"
        >
          {{ r.resposta }}
        </dd>
      </div>
    </dl>
    <p v-for="d in duvidas" :key="d" class="mt-1 text-[11px] text-n-amber-11">
      {{ $t('RAMON.LEAD_PANEL.QUIZ.DOUBT', { doubt: d }) }}
    </p>
  </div>
</template>

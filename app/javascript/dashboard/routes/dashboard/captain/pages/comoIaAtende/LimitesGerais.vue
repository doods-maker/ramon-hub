<script setup>
// "Limites gerais do escritório" (só no Padrão do escritório): horário de atendimento, atraso da resposta da IA,
// tetos diários e intervalo da retomada. Emite o objeto inteiro de limites; quem salva é a página.
import { useI18n } from 'vue-i18n';
import { CAMPO, ROTULO } from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  // corpo.limites do GET: horario, atraso, fluxo_ia_dia, retomadas_dia, retomada_intervalo_dias, teto_usd, agente_dia
  modelValue: { type: Object, required: true },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const K = 'RAMON.COMO_IA.GERAIS';

// Date#wday do servidor: 0 = domingo; a semana na tela começa na segunda.
const DIAS = [1, 2, 3, 4, 5, 6, 0];
const ATRASO_MAXIMO = 180;
const INTEIROS = [
  { chave: 'fluxo_ia_dia', max: 1000 },
  { chave: 'retomadas_dia', max: 1000 },
  { chave: 'retomada_intervalo_dias', max: 60 },
];
const SEGUNDA_FAIXA = ['13:30', '18:00'];

const mudar = parte =>
  emit('update:modelValue', { ...props.modelValue, ...parte });
const mudarHorario = parte =>
  mudar({ horario: { ...props.modelValue.horario, ...parte } });

const alternarDia = dia => {
  const { dias } = props.modelValue.horario;
  mudarHorario({
    dias: dias.includes(dia) ? dias.filter(d => d !== dia) : [...dias, dia],
  });
};
const mudarHora = (faixa, ponta, valor) =>
  mudarHorario({
    janelas: props.modelValue.horario.janelas.map((par, i) =>
      i === faixa ? par.map((hora, p) => (p === ponta ? valor : hora)) : par
    ),
  });
const alternarSegundaFaixa = () => {
  const [primeira, segunda] = props.modelValue.horario.janelas;
  mudarHorario({ janelas: segunda ? [primeira] : [primeira, SEGUNDA_FAIXA] });
};
const mudarAtraso = (ponta, valor) =>
  mudar({ atraso: { ...props.modelValue.atraso, [ponta]: valor } });
const mudarTeto = valor => mudar({ teto_usd: valor === '' ? null : valor });
</script>

<template>
  <div data-testid="limites-gerais">
    <div class="flex flex-wrap items-baseline gap-2.5 mb-2.5">
      <h3 class="text-sm font-semibold text-n-slate-12">
        {{ t(`${K}.TITULO`) }}
      </h3>
      <span class="text-[12.5px] text-n-slate-10">{{ t(`${K}.DICA`) }}</span>
    </div>

    <div
      class="flex flex-col gap-5 p-4 border border-solid rounded-xl border-n-weak"
    >
      <div class="flex flex-col gap-2">
        <span class="text-[13px] font-medium text-n-slate-12">
          {{ t(`${K}.HORARIO`) }}
        </span>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="dia in DIAS"
            :key="dia"
            type="button"
            :data-testid="`dia-${dia}`"
            :aria-pressed="modelValue.horario.dias.includes(dia)"
            class="h-8 px-3 text-[13px] border border-solid rounded-lg"
            :class="
              modelValue.horario.dias.includes(dia)
                ? 'border-n-blue-9 bg-n-blue-9/[0.08] font-semibold text-n-slate-12'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
            "
            @click="alternarDia(dia)"
          >
            {{ t(`${K}.DIAS.${dia}`) }}
          </button>
        </div>
        <div
          v-for="(par, i) in modelValue.horario.janelas"
          :key="i"
          class="flex flex-wrap items-center gap-2 text-[13px] text-n-slate-11"
        >
          <span class="w-14">{{ t(`${K}.FAIXA`, { n: i + 1 }) }}</span>
          <input
            type="time"
            class="!w-28"
            :class="[CAMPO]"
            :data-testid="`faixa-${i}-ini`"
            :value="par[0]"
            @input="mudarHora(i, 0, $event.target.value)"
          />
          <span>{{ t(`${K}.ATE`) }}</span>
          <input
            type="time"
            class="!w-28"
            :class="[CAMPO]"
            :data-testid="`faixa-${i}-fim`"
            :value="par[1]"
            @input="mudarHora(i, 1, $event.target.value)"
          />
        </div>
        <button
          type="button"
          data-testid="segunda-faixa"
          class="self-start text-xs font-medium text-n-blue-11 hover:underline"
          @click="alternarSegundaFaixa"
        >
          {{
            modelValue.horario.janelas.length > 1
              ? t(`${K}.REMOVER_FAIXA`)
              : t(`${K}.ADICIONAR_FAIXA`)
          }}
        </button>
        <p class="text-xs text-n-slate-10">{{ t(`${K}.HORARIO_NOTA`) }}</p>
      </div>

      <div class="flex flex-col gap-2">
        <span class="text-[13px] font-medium text-n-slate-12">
          {{ t(`${K}.ATRASO`) }}
        </span>
        <div
          class="flex flex-wrap items-center gap-2 text-[13px] text-n-slate-11"
        >
          <input
            type="number"
            min="0"
            :max="ATRASO_MAXIMO"
            class="!w-24"
            :class="[CAMPO]"
            data-testid="atraso-min"
            :value="modelValue.atraso.min"
            @input="mudarAtraso('min', $event.target.valueAsNumber)"
          />
          <span>{{ t(`${K}.ATE`) }}</span>
          <input
            type="number"
            min="0"
            :max="ATRASO_MAXIMO"
            class="!w-24"
            :class="[CAMPO]"
            data-testid="atraso-max"
            :value="modelValue.atraso.max"
            @input="mudarAtraso('max', $event.target.valueAsNumber)"
          />
          <span>{{ t(`${K}.SEGUNDOS`) }}</span>
        </div>
        <p class="text-xs text-n-slate-10">
          {{ t(`${K}.ATRASO_NOTA`, { max: ATRASO_MAXIMO }) }}
        </p>
      </div>

      <div class="grid gap-4 md:grid-cols-3">
        <label v-for="item in INTEIROS" :key="item.chave" :class="ROTULO">
          {{ t(`${K}.${item.chave}`) }}
          <input
            type="number"
            min="1"
            :max="item.max"
            :class="CAMPO"
            :data-testid="`lim-${item.chave}`"
            :value="modelValue[item.chave]"
            @input="mudar({ [item.chave]: $event.target.valueAsNumber })"
          />
        </label>
      </div>

      <div class="grid gap-4 md:grid-cols-3">
        <label :class="ROTULO">
          {{ t(`${K}.TETO_USD`) }}
          <input
            type="number"
            min="0"
            step="0.01"
            :class="CAMPO"
            data-testid="lim-teto_usd"
            :value="modelValue.teto_usd ?? ''"
            @input="mudarTeto($event.target.value)"
          />
          <span class="text-n-slate-10">{{ t(`${K}.TETO_USD_NOTA`) }}</span>
        </label>
        <div :class="ROTULO">
          {{ t(`${K}.AGENTE`) }}
          <span
            data-testid="agente-dia"
            class="flex items-center h-8 px-3 text-sm rounded-lg text-n-slate-11 bg-n-alpha-2"
          >
            {{ modelValue.agente_dia }}
          </span>
          <span class="text-n-slate-10">{{ t(`${K}.AGENTE_NOTA`) }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

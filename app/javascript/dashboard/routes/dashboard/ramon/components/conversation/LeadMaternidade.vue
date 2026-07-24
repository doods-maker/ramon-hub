<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/leads';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'LeadMaternidade' });

const { t } = useI18n();

const isLoading = ref(false);
const hasError = ref(false);
const errorMessage = ref('');
const resultado = ref(null);

const dataEvento = ref('');
const categoria = ref('empregada');

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const money = value => brl.format(Number(value || 0));

const calcular = async () => {
  isLoading.value = true;
  hasError.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.maternidade(props.lead.id, {
      data_evento: dataEvento.value,
      categoria: categoria.value,
    });
    resultado.value = data;
  } catch (error) {
    hasError.value = true;
    errorMessage.value =
      error?.response?.data?.error || t('RAMON.SIMULADOR.MATERNIDADE_ERRO');
  } finally {
    isLoading.value = false;
  }
};

// erro nunca se mascara de vazio: retry refaz a mesma ação que falhou.
const retry = () => calcular();
</script>

<template>
  <div class="flex flex-col gap-3 p-1" data-testid="lead-maternidade">
    <div class="grid grid-cols-2 gap-2">
      <label class="flex flex-col gap-1 text-xs text-n-slate-10">
        {{ $t('RAMON.SIMULADOR.MATERNIDADE_DATA_EVENTO') }}
        <input
          v-model="dataEvento"
          type="date"
          data-testid="maternidade-data-evento"
          class="w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 outline-none focus:border-n-slate-8"
        />
      </label>
      <label class="flex flex-col gap-1 text-xs text-n-slate-10">
        {{ $t('RAMON.SIMULADOR.MATERNIDADE_CATEGORIA') }}
        <select
          v-model="categoria"
          data-testid="maternidade-categoria"
          class="w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12"
        >
          <option value="empregada">
            {{ $t('RAMON.SIMULADOR.MATERNIDADE_CATEGORIA_EMPREGADA') }}
          </option>
          <option value="ci_facultativa">
            {{ $t('RAMON.SIMULADOR.MATERNIDADE_CATEGORIA_CI_FACULTATIVA') }}
          </option>
          <option value="especial">
            {{ $t('RAMON.SIMULADOR.MATERNIDADE_CATEGORIA_ESPECIAL') }}
          </option>
        </select>
      </label>
    </div>

    <button
      type="button"
      data-testid="maternidade-calcular"
      class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-40 disabled:cursor-not-allowed"
      :disabled="!dataEvento || isLoading"
      @click="calcular"
    >
      {{
        isLoading
          ? $t('RAMON.SIMULADOR.MATERNIDADE_CALCULANDO')
          : $t('RAMON.SIMULADOR.MATERNIDADE_CALCULAR')
      }}
    </button>

    <div v-if="hasError" data-testid="maternidade-error">
      <p class="text-sm text-n-ruby-11">{{ errorMessage }}</p>
      <button
        type="button"
        data-testid="maternidade-retry"
        class="mt-1 text-xs text-n-iris-11 hover:underline"
        @click="retry"
      >
        {{ $t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <div
      v-if="resultado"
      class="flex flex-col gap-2 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
      data-testid="maternidade-resultado"
    >
      <p class="text-sm text-n-slate-12">
        <span class="text-n-slate-10"
          >{{ $t('RAMON.SIMULADOR.MATERNIDADE_RMI') }}:</span
        >
        <span class="font-semibold" data-testid="maternidade-rmi">
          {{ money(resultado.rmi) }}
        </span>
      </p>
      <p class="text-sm text-n-slate-12" data-testid="maternidade-carencia">
        <span class="text-n-slate-10"
          >{{ $t('RAMON.SIMULADOR.MATERNIDADE_CARENCIA') }}:</span
        >
        {{ resultado.carencia?.exigida }}
        <span class="text-xs text-n-slate-10">
          ({{ resultado.carencia?.fundamento }})
        </span>
      </p>
      <p class="text-sm text-n-slate-12" data-testid="maternidade-duracao">
        {{
          $t('RAMON.SIMULADOR.MATERNIDADE_DURACAO', {
            dias: resultado.duracao_dias,
          })
        }}
      </p>
      <ul
        v-if="resultado.avisos && resultado.avisos.length"
        class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4"
        data-testid="maternidade-avisos"
      >
        <li v-for="(aviso, i) in resultado.avisos" :key="i">{{ aviso }}</li>
      </ul>
    </div>
  </div>
</template>

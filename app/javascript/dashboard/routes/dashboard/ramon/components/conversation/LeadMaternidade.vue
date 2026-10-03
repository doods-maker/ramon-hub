<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import { ACAO, CAMPO, CARTAO, ROTULO, SELECT } from '../../helpers/ui';

const props = defineProps({
  lead: { type: Object, required: true },
  seguradoNome: { type: String, default: '' },
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
      segurado_nome: props.seguradoNome || undefined,
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
      <label :class="ROTULO">
        {{ $t('RAMON.SIMULADOR.MATERNIDADE_DATA_EVENTO') }}
        <input
          v-model="dataEvento"
          type="date"
          data-testid="maternidade-data-evento"
          class="font-mono"
          :class="[CAMPO]"
        />
      </label>
      <label :class="ROTULO">
        {{ $t('RAMON.SIMULADOR.MATERNIDADE_CATEGORIA') }}
        <select
          v-model="categoria"
          data-testid="maternidade-categoria"
          :class="SELECT"
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

    <Button
      data-testid="maternidade-calcular"
      :disabled="!dataEvento || isLoading"
      sm
      :class="ACAO"
      class="self-start"
      :label="
        isLoading
          ? $t('RAMON.SIMULADOR.MATERNIDADE_CALCULANDO')
          : $t('RAMON.SIMULADOR.MATERNIDADE_CALCULAR')
      "
      @click="calcular"
    />

    <div v-if="hasError" data-testid="maternidade-error">
      <p class="text-sm text-n-ruby-11">{{ errorMessage }}</p>
      <Button
        data-testid="maternidade-retry"
        link
        xs
        class="mt-1"
        :label="$t('RAMON.LEAD_PANEL.RETRY')"
        @click="retry"
      />
    </div>

    <div
      v-if="resultado"
      class="flex flex-col gap-2"
      :class="CARTAO"
      data-testid="maternidade-resultado"
    >
      <p class="text-sm text-n-slate-12">
        <span class="text-n-slate-10"
          >{{ $t('RAMON.SIMULADOR.MATERNIDADE_RMI') }}:</span
        >
        <span class="font-semibold" data-testid="maternidade-rmi">
          <span class="font-mono">{{ money(resultado.rmi) }}</span>
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

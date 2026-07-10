<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/leads';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'LeadSimulador' });

const { t } = useI18n();

// Default do benefício pela tese do lead (heurística sobre os nomes seedados).
const guessBeneficio = name => {
  const n = (name || '').toLowerCase();
  if (n.includes('acidente')) return 'acidente';
  if (n.includes('permanente') || n.includes('invalidez')) return 'permanente';
  return 'temporaria';
};

const form = ref({
  nascimento: props.lead.contact_data_nascimento || '',
  sexo: props.lead.contact_sexo || 'M',
  der: '',
  salario: '',
  beneficio: guessBeneficio(props.lead.thesis_name),
  origem: 'previdenciaria',
  acrescimo_25: (props.lead.thesis_name || '').includes('25%'),
});

const isLoading = ref(false);
const resultado = ref(null);
const motorDown = ref(false);
const errorMessage = ref('');

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const money = value => brl.format(Number(value || 0));

const canSimulate = computed(
  () => form.value.nascimento && form.value.der && form.value.salario
);

const honorario = computed(() => resultado.value?.honorario || null);

const simulate = async () => {
  isLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  resultado.value = null;
  try {
    const { data } = await LeadsAPI.simulate(props.lead.id, {
      ...form.value,
    });
    resultado.value = data;
  } catch (error) {
    if (error?.response?.status === 503) {
      motorDown.value = true;
    } else {
      errorMessage.value =
        error?.response?.data?.error || t('RAMON.SIMULADOR.GENERIC_ERROR');
    }
  } finally {
    isLoading.value = false;
  }
};

const fieldClass =
  'w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 outline-none focus:border-n-slate-8';
const labelClass = 'flex flex-col gap-1 text-xs text-n-slate-10';
</script>

<template>
  <div class="flex flex-col gap-3 p-1" data-testid="lead-simulador">
    <div class="grid grid-cols-2 gap-2">
      <label :class="labelClass">
        {{ $t('RAMON.SIMULADOR.NASCIMENTO') }}
        <input
          v-model="form.nascimento"
          type="date"
          data-testid="sim-nascimento"
          :class="fieldClass"
        />
      </label>
      <label :class="labelClass">
        {{ $t('RAMON.SIMULADOR.SEXO') }}
        <select v-model="form.sexo" data-testid="sim-sexo" :class="fieldClass">
          <option value="M">{{ $t('RAMON.SIMULADOR.SEXO_M') }}</option>
          <option value="F">{{ $t('RAMON.SIMULADOR.SEXO_F') }}</option>
        </select>
      </label>
      <label :class="labelClass">
        {{ $t('RAMON.SIMULADOR.DER') }}
        <input
          v-model="form.der"
          type="date"
          data-testid="sim-der"
          :class="fieldClass"
        />
      </label>
      <label :class="labelClass">
        {{ $t('RAMON.SIMULADOR.SALARIO') }}
        <input
          v-model="form.salario"
          type="number"
          min="0"
          step="0.01"
          data-testid="sim-salario"
          :class="fieldClass"
        />
      </label>
      <label :class="labelClass">
        {{ $t('RAMON.SIMULADOR.BENEFICIO') }}
        <select
          v-model="form.beneficio"
          data-testid="sim-beneficio"
          :class="fieldClass"
        >
          <option value="temporaria">
            {{ $t('RAMON.SIMULADOR.BENEFICIO_TEMPORARIA') }}
          </option>
          <option value="permanente">
            {{ $t('RAMON.SIMULADOR.BENEFICIO_PERMANENTE') }}
          </option>
          <option value="acidente">
            {{ $t('RAMON.SIMULADOR.BENEFICIO_ACIDENTE') }}
          </option>
        </select>
      </label>
      <label :class="labelClass">
        {{ $t('RAMON.SIMULADOR.ORIGEM') }}
        <select
          v-model="form.origem"
          data-testid="sim-origem"
          :class="fieldClass"
        >
          <option value="previdenciaria">
            {{ $t('RAMON.SIMULADOR.ORIGEM_PREVIDENCIARIA') }}
          </option>
          <option value="acidentaria">
            {{ $t('RAMON.SIMULADOR.ORIGEM_ACIDENTARIA') }}
          </option>
        </select>
      </label>
    </div>

    <label class="flex items-center gap-2 text-xs text-n-slate-11">
      <input
        v-model="form.acrescimo_25"
        type="checkbox"
        data-testid="sim-acrescimo"
      />
      {{ $t('RAMON.SIMULADOR.ACRESCIMO') }}
    </label>

    <button
      type="button"
      data-testid="sim-run"
      class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
      :disabled="!canSimulate || isLoading"
      @click="simulate"
    >
      {{
        isLoading
          ? $t('RAMON.SIMULADOR.SIMULANDO')
          : $t('RAMON.SIMULADOR.SIMULAR')
      }}
    </button>

    <p
      v-if="motorDown"
      class="text-sm text-n-amber-11"
      data-testid="sim-motor-down"
    >
      {{ $t('RAMON.SIMULADOR.MOTOR_DOWN') }}
    </p>
    <p
      v-else-if="errorMessage"
      class="text-sm text-n-ruby-11"
      data-testid="sim-error"
    >
      {{ errorMessage }}
    </p>

    <div
      v-if="resultado"
      class="flex flex-col gap-2 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
      data-testid="sim-resultado"
    >
      <p class="text-sm text-n-slate-12">
        <span class="text-n-slate-10">
          {{ $t('RAMON.SIMULADOR.ATRASADOS') }}:
        </span>
        <span class="font-semibold" data-testid="sim-atrasados">
          {{ `~${money(resultado.atrasados)}` }}
        </span>
      </p>
      <p class="text-sm text-n-slate-12" data-testid="sim-perda-mensal">
        {{
          $t('RAMON.SIMULADOR.PERDA_MENSAL', {
            value: money(resultado.perda_mensal),
          })
        }}
      </p>
      <p
        v-if="honorario && honorario.valor"
        class="text-sm text-n-slate-12"
        data-testid="sim-honorario"
      >
        <span class="text-n-slate-10">
          {{ $t('RAMON.SIMULADOR.HONORARIO') }}:
        </span>
        <span class="font-semibold">{{ `~${money(honorario.valor)}` }}</span>
        <span class="text-xs text-n-slate-10">
          ({{
            $t('RAMON.SIMULADOR.HONORARIO_FORMULA', {
              percentual: honorario.percentual,
              n: honorario.n_mensalidades,
              tese: honorario.tese,
            })
          }})
        </span>
      </p>
      <p v-else class="text-xs text-n-amber-11" data-testid="sim-sem-honorario">
        {{ $t('RAMON.SIMULADOR.NO_FEE_CONFIG') }}
      </p>
      <p class="text-xs text-n-slate-10">
        {{
          $t('RAMON.SIMULADOR.ESTIMATIVA_BASE', {
            meses: resultado.atrasados_estimativa?.meses || 0,
          })
        }}
      </p>
      <ul
        v-if="resultado.avisos && resultado.avisos.length"
        class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4"
        data-testid="sim-avisos"
      >
        <li v-for="(aviso, i) in resultado.avisos" :key="i">{{ aviso }}</li>
      </ul>
    </div>

    <p
      class="text-xs italic text-n-amber-11 border-t border-n-weak pt-2"
      data-testid="sim-disclaimer"
    >
      {{ $t('RAMON.SIMULADOR.DISCLAIMER') }}
    </p>
  </div>
</template>

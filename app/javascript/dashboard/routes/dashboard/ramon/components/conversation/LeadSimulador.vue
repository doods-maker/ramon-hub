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
const cnis = ref(props.lead.cnis_resumo || null);
const cnisLoading = ref(false);
// PDF fica só na memória do browser (LGPD): reprocessar com ajustes reenvia
// o mesmo arquivo; depois de F5 é preciso selecionar o PDF de novo.
const cnisFile = ref(null);
const vinculos = ref([]);
const excluidos = ref([]);
const mensalidades = ref({});
const ajustesOpen = ref(false);
const memoria = ref(null);
const memoriaLoading = ref(false);

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const money = value => brl.format(Number(value || 0));

// Com CNIS anexado, nascimento/sexo/salário vêm do histórico real.
const canSimulate = computed(() =>
  cnis.value
    ? Boolean(form.value.der)
    : Boolean(form.value.nascimento && form.value.der && form.value.salario)
);

const honorario = computed(() => resultado.value?.honorario || null);
const motorInfo = computed(() => resultado.value?.motor || {});

const handleMotorError = error => {
  if (error?.response?.status === 503) {
    motorDown.value = true;
  } else {
    errorMessage.value =
      error?.response?.data?.error || t('RAMON.SIMULADOR.GENERIC_ERROR');
  }
};

const applyCnis = data => {
  cnis.value = data;
  vinculos.value = data.vinculos_detalhe || [];
  const parametros = data.parametros || {};
  excluidos.value = parametros.excluir_seqs
    ? parametros.excluir_seqs.split(',').map(Number)
    : [];
  mensalidades.value = parametros.mensalidades
    ? JSON.parse(parametros.mensalidades)
    : {};
};

const mensalidadesJson = () => {
  // valores como string: o motor converte pra Decimal sem artefato de float
  const entries = Object.entries(mensalidades.value)
    .filter(([, v]) => v)
    .map(([k, v]) => [k, String(v)]);
  return entries.length ? JSON.stringify(Object.fromEntries(entries)) : '';
};

const tituloDe = v => [v.seq, v.tipo, v.origem].filter(Boolean).join(' · ');
const periodoDe = v => (v.inicio ? `${v.inicio} → ${v.fim || '…'}` : '');

const uploadCnis = async opts => {
  cnisLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.uploadCnis(
      props.lead.id,
      cnisFile.value,
      form.value.sexo,
      opts
    );
    applyCnis(data);
    resultado.value = null;
    memoria.value = null;
  } catch (error) {
    handleMotorError(error);
  } finally {
    cnisLoading.value = false;
  }
};

const onCnisFile = async event => {
  const file = event.target.files[0];
  if (!file) return;
  cnisFile.value = file;
  await uploadCnis({});
  event.target.value = '';
};

// Depois de F5 o PDF não está mais na memória — reanexar para poder reaplicar.
const onRefile = event => {
  cnisFile.value = event.target.files[0] || null;
};

const reaplicar = () =>
  uploadCnis({
    excluirSeqs: excluidos.value.join(','),
    mensalidades: mensalidadesJson(),
  });

const toggleAjustes = async () => {
  ajustesOpen.value = !ajustesOpen.value;
  if (ajustesOpen.value && !vinculos.value.length) {
    try {
      const { data } = await LeadsAPI.getCnis(props.lead.id);
      applyCnis(data);
    } catch {
      errorMessage.value = t('RAMON.SIMULADOR.GENERIC_ERROR');
    }
  }
};

const removeCnis = async () => {
  errorMessage.value = '';
  try {
    await LeadsAPI.deleteCnis(props.lead.id);
    cnis.value = null;
    cnisFile.value = null;
    vinculos.value = [];
    excluidos.value = [];
    mensalidades.value = {};
    ajustesOpen.value = false;
    resultado.value = null;
    memoria.value = null;
  } catch {
    errorMessage.value = t('RAMON.SIMULADOR.GENERIC_ERROR');
  }
};

const simulate = async () => {
  isLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  resultado.value = null;
  memoria.value = null;
  try {
    const { data } = await LeadsAPI.simulate(props.lead.id, {
      ...form.value,
      usar_cnis: Boolean(cnis.value),
    });
    resultado.value = data;
  } catch (error) {
    handleMotorError(error);
  } finally {
    isLoading.value = false;
  }
};

// Memória de cálculo do motor (competência/índice/corrigido): re-simula com o
// flag opt-in — payload grande, só quando o advogado pede.
const verMemoria = async () => {
  if (memoria.value) {
    memoria.value = null;
    return;
  }
  memoriaLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.simulate(props.lead.id, {
      ...form.value,
      usar_cnis: Boolean(cnis.value),
      memoria_calculo: true,
    });
    resultado.value = data;
    memoria.value = data.motor?.memoria_calculo || null;
  } catch (error) {
    handleMotorError(error);
  } finally {
    memoriaLoading.value = false;
  }
};

const fieldClass =
  'w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 outline-none focus:border-n-slate-8';
const labelClass = 'flex flex-col gap-1 text-xs text-n-slate-10';
</script>

<template>
  <div class="flex flex-col gap-3 p-1" data-testid="lead-simulador">
    <div
      v-if="cnis"
      class="flex flex-col gap-1 p-2 rounded-lg bg-n-alpha-1 border border-n-weak"
      data-testid="sim-cnis-chip"
    >
      <div class="flex items-center justify-between gap-2">
        <span class="text-xs font-medium text-n-slate-12">
          {{ cnis.filename }}
        </span>
        <button
          type="button"
          data-testid="sim-cnis-remove"
          class="text-xs text-n-ruby-11"
          @click="removeCnis"
        >
          {{ $t('RAMON.SIMULADOR.CNIS_REMOVE') }}
        </button>
      </div>
      <span class="text-xs text-n-slate-10">
        {{
          $t('RAMON.SIMULADOR.CNIS_LOADED', {
            competencias: cnis.competencias,
            vinculos: cnis.vinculos,
          })
        }}
      </span>
      <ul
        v-if="cnis.avisos && cnis.avisos.length"
        class="flex flex-col gap-1 text-xs text-n-amber-11 list-disc ps-4"
        data-testid="sim-cnis-avisos"
      >
        <li v-for="(aviso, i) in cnis.avisos" :key="i">{{ aviso }}</li>
      </ul>
      <button
        type="button"
        data-testid="sim-cnis-ajustes-toggle"
        class="self-start text-xs underline text-n-slate-11"
        @click="toggleAjustes"
      >
        {{ $t('RAMON.SIMULADOR.VINCULOS_TOGGLE') }}
      </button>
      <div
        v-if="ajustesOpen"
        class="flex flex-col gap-2 pt-1"
        data-testid="sim-cnis-vinculos"
      >
        <div
          v-for="v in vinculos"
          :key="v.seq"
          class="flex flex-col gap-1 p-1.5 rounded-lg border border-n-weak"
        >
          <span class="text-xs text-n-slate-12 truncate">
            {{ tituloDe(v) }}
          </span>
          <span v-if="v.inicio" class="text-xs text-n-slate-10">
            {{ periodoDe(v) }}
          </span>
          <label class="flex items-center gap-2 text-xs text-n-slate-11">
            <input
              v-model="excluidos"
              type="checkbox"
              :value="v.seq"
              :data-testid="`sim-vinculo-excluir-${v.seq}`"
            />
            {{ $t('RAMON.SIMULADOR.VINCULO_EXCLUIR') }}
          </label>
          <label v-if="v.tipo === 'BENEFICIO'" :class="labelClass">
            {{ $t('RAMON.SIMULADOR.VINCULO_MENSALIDADE') }}
            <input
              v-model="mensalidades[v.seq]"
              type="number"
              min="0"
              step="0.01"
              :class="fieldClass"
              :data-testid="`sim-vinculo-mensalidade-${v.seq}`"
            />
          </label>
        </div>
        <label v-if="!cnisFile" :class="labelClass">
          {{ $t('RAMON.SIMULADOR.VINCULOS_REUPLOAD_HINT') }}
          <input
            type="file"
            accept="application/pdf"
            data-testid="sim-cnis-refile"
            :class="fieldClass"
            @change="onRefile"
          />
        </label>
        <button
          type="button"
          data-testid="sim-cnis-reaplicar"
          class="px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
          :disabled="!cnisFile || cnisLoading"
          @click="reaplicar"
        >
          {{
            cnisLoading
              ? $t('RAMON.SIMULADOR.CNIS_LOADING')
              : $t('RAMON.SIMULADOR.VINCULOS_REAPLICAR')
          }}
        </button>
      </div>
    </div>
    <label v-else :class="labelClass">
      {{
        cnisLoading
          ? $t('RAMON.SIMULADOR.CNIS_LOADING')
          : $t('RAMON.SIMULADOR.CNIS_LABEL')
      }}
      <input
        type="file"
        accept="application/pdf"
        data-testid="sim-cnis-file"
        :disabled="cnisLoading"
        :class="fieldClass"
        @change="onCnisFile"
      />
      <span class="text-n-slate-10">
        {{ $t('RAMON.SIMULADOR.CNIS_HINT') }}
      </span>
    </label>

    <div class="grid grid-cols-2 gap-2">
      <label v-if="!cnis" :class="labelClass">
        {{ $t('RAMON.SIMULADOR.NASCIMENTO') }}
        <input
          v-model="form.nascimento"
          type="date"
          data-testid="sim-nascimento"
          :class="fieldClass"
        />
      </label>
      <label v-if="!cnis" :class="labelClass">
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
      <label v-if="!cnis" :class="labelClass">
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
      <p
        v-if="motorInfo.rmi_com_descartes"
        class="text-xs text-n-slate-10"
        data-testid="sim-duas-medias"
      >
        {{
          $t('RAMON.SIMULADOR.DUAS_MEDIAS', {
            rmi: money(motorInfo.rmi),
            descartes: money(motorInfo.rmi_com_descartes),
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
      <button
        type="button"
        data-testid="sim-memoria-toggle"
        class="self-start text-xs underline text-n-slate-11 disabled:opacity-40"
        :disabled="memoriaLoading"
        @click="verMemoria"
      >
        {{
          memoriaLoading
            ? $t('RAMON.SIMULADOR.MEMORIA_LOADING')
            : memoria
              ? $t('RAMON.SIMULADOR.MEMORIA_HIDE')
              : $t('RAMON.SIMULADOR.MEMORIA_SHOW')
        }}
      </button>
      <div v-if="memoria" class="flex flex-col gap-1" data-testid="sim-memoria">
        <div class="max-h-64 overflow-y-auto rounded-lg border border-n-weak">
          <table class="w-full text-xs text-n-slate-11">
            <thead class="sticky top-0 bg-n-solid-2">
              <tr class="text-n-slate-10">
                <th class="p-1 text-start font-medium">
                  {{ $t('RAMON.SIMULADOR.MEMORIA_COMPETENCIA') }}
                </th>
                <th class="p-1 text-end font-medium">
                  {{ $t('RAMON.SIMULADOR.MEMORIA_SALARIO') }}
                </th>
                <th class="p-1 text-end font-medium">
                  {{ $t('RAMON.SIMULADOR.MEMORIA_INDICE') }}
                </th>
                <th class="p-1 text-end font-medium">
                  {{ $t('RAMON.SIMULADOR.MEMORIA_CORRIGIDO') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="linha in memoria.salarios" :key="linha.competencia">
                <td class="p-1">{{ linha.competencia }}</td>
                <td class="p-1 text-end">{{ money(linha.salario) }}</td>
                <td class="p-1 text-end">{{ linha.indice }}</td>
                <td class="p-1 text-end">{{ money(linha.corrigido) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="text-xs text-n-slate-10" data-testid="sim-memoria-resumo">
          {{
            $t('RAMON.SIMULADOR.MEMORIA_RESUMO', {
              soma: money(memoria.soma),
              divisor: memoria.divisor,
              media: money(memoria.media),
            })
          }}
        </p>
      </div>
    </div>

    <p
      class="text-xs italic text-n-amber-11 border-t border-n-weak pt-2"
      data-testid="sim-disclaimer"
    >
      {{ $t('RAMON.SIMULADOR.DISCLAIMER') }}
    </p>
  </div>
</template>

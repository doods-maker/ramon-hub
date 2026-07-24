<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/leads';
import LeadLiquidacao from './LeadLiquidacao.vue';
import LeadElegibilidade from './LeadElegibilidade.vue';
import LeadPensao from './LeadPensao.vue';
import LeadMaternidade from './LeadMaternidade.vue';
import LeadPlanejamento from './LeadPlanejamento.vue';

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
const especiaisGrau = ref({});
const especiaisInicio = ref({});
const especiaisFim = ref({});
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
const avisosQualidade = computed(() =>
  (resultado.value?.avisos || []).filter(a =>
    /qualidade de segurado|27-A|Tema 1360/i.test(a)
  )
);
const avisosGerais = computed(() =>
  (resultado.value?.avisos || []).filter(
    a => !avisosQualidade.value.includes(a)
  )
);

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
  const especiais = parametros.especiais
    ? JSON.parse(parametros.especiais)
    : {};
  especiaisGrau.value = {};
  especiaisInicio.value = {};
  especiaisFim.value = {};
  Object.entries(especiais).forEach(([seq, v]) => {
    especiaisGrau.value[seq] = v.grau;
    if (v.inicio) especiaisInicio.value[seq] = v.inicio;
    if (v.fim) especiaisFim.value[seq] = v.fim;
  });
};

const mensalidadesJson = () => {
  // valores como string: o motor converte pra Decimal sem artefato de float
  const entries = Object.entries(mensalidades.value)
    .filter(([, v]) => v)
    .map(([k, v]) => [k, String(v)]);
  return entries.length ? JSON.stringify(Object.fromEntries(entries)) : '';
};

// Espelha mensalidadesJson: filtra vínculos sem grau marcado; trecho
// (inicio/fim) é opcional — vazio vira null (motor aceita ausência de trecho
// = período todo).
const especiaisJson = () => {
  const entries = Object.entries(especiaisGrau.value)
    .filter(([, grau]) => grau)
    .map(([seq, grau]) => [
      seq,
      {
        grau: Number(grau),
        inicio: especiaisInicio.value[seq] || null,
        fim: especiaisFim.value[seq] || null,
      },
    ]);
  return entries.length ? JSON.stringify(Object.fromEntries(entries)) : '';
};

const GRAUS_ESPECIAIS = [15, 20, 25];

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
    especiaisGrau.value = {};
    especiaisInicio.value = {};
    especiaisFim.value = {};
    ajustesOpen.value = false;
    resultado.value = null;
    memoria.value = null;
  } catch {
    errorMessage.value = t('RAMON.SIMULADOR.GENERIC_ERROR');
  }
};

// Persiste o essencial da última simulação no lead (o Modo Foco da Esteira
// lê custom_attributes.ultima_simulacao; o PATCH faz deep_merge no server).
// Best-effort: falha do PATCH nunca esconde o resultado já exibido.
const persistirUltimaSimulacao = async data => {
  try {
    await LeadsAPI.update(props.lead.id, {
      custom_attributes: {
        ultima_simulacao: {
          mensal: data.mensal,
          atrasados: data.atrasados,
          honorario_valor: data.honorario?.valor || null,
          tese: data.honorario?.tese || props.lead.thesis_name || null,
          em: new Date().toISOString(),
          parametros: {
            der: form.value.der,
            salario: form.value.salario,
            beneficio: form.value.beneficio,
            origem: form.value.origem,
            acrescimo_25: form.value.acrescimo_25,
            usar_cnis: Boolean(cnis.value),
          },
        },
      },
    });
  } catch {
    // silêncio: persistência é conveniência, o resultado na tela é a fonte
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
    await persistirUltimaSimulacao(data);
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

// Painel de possibilidades (todas as regras, estilo Previdenciarista):
// CNIS e/ou vínculos manuais (ex.: atividade rural que não está no CNIS).
const painelLoading = ref(false);
const painel = ref(null);
const vinculosExtras = ref([]);

const addVinculoExtra = () =>
  vinculosExtras.value.push({
    inicio: '',
    fim: '',
    tipo: 'EMPREGO',
    salario: '',
    especialGrau: undefined,
    especialInicio: '',
    especialFim: '',
  });
const removeVinculoExtra = index => vinculosExtras.value.splice(index, 1);

const vinculosExtrasJson = () =>
  vinculosExtras.value
    .filter(v => v.inicio && v.fim)
    .map(({ especialGrau, especialInicio, especialFim, ...v }) => ({
      ...v,
      ...(especialGrau
        ? {
            especial: {
              grau: Number(especialGrau),
              inicio: especialInicio || null,
              fim: especialFim || null,
            },
          }
        : {}),
    }));

const canPainel = computed(() =>
  Boolean(
    form.value.der &&
      (cnis.value ||
        (form.value.nascimento &&
          vinculosExtras.value.some(v => v.inicio && v.fim)))
  )
);

// A elegibilidade não aceita vínculos manuais (sem suporte no motor ainda) —
// CNIS é obrigatório, diferente do canPainel (que aceita vínculos avulsos).
const canElegibilidade = computed(() => Boolean(form.value.der && cnis.value));

// Pensão e maternidade usam data própria (data_obito/data_evento) dentro do
// componente filho — o gate da aba é só o CNIS, igual à elegibilidade.
const canPensao = computed(() => Boolean(cnis.value));
const canMaternidade = computed(() => Boolean(cnis.value));
const canPlanejamento = computed(() => Boolean(cnis.value));

const calcularPainel = async () => {
  painelLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.painel(props.lead.id, {
      der: form.value.der,
      nascimento: form.value.nascimento,
      sexo: form.value.sexo,
      vinculos_extras: vinculosExtrasJson(),
      especiais: especiaisJson(),
    });
    painel.value = data;
  } catch (error) {
    handleMotorError(error);
  } finally {
    painelLoading.value = false;
  }
};

const liquidacaoRef = ref(null);

// RMI com descartes é a que o advogado usa na conta quando existe (é a maior).
const liquidarCartao = cartao => {
  liquidacaoRef.value?.preencher(cartao.rmi_com_descartes || cartao.rmi);
};

const bordaDe = cartao => {
  if (cartao.elegivel === true) return 'border-s-4 border-n-teal-9';
  if (cartao.elegivel === false) return 'border-s-4 border-n-ruby-9';
  return 'border-s-4 border-n-amber-9';
};

const dataBr = iso => (iso ? iso.split('-').reverse().join('/') : '');

const fieldClass =
  'w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 outline-none focus:border-n-slate-8';
const labelClass = 'flex flex-col gap-1 text-xs text-n-slate-10';

// Aba padrão = Possibilidades (uso "hub = Previdenciarista"); o fluxo de
// honorário do auxílio-acidente vive na 2ª aba, intacto.
const aba = ref('painel');
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
          <div
            v-if="v.tipo !== 'BENEFICIO'"
            class="flex flex-wrap items-center gap-2"
          >
            <label class="text-xs text-n-slate-11">
              {{ $t('RAMON.SIMULADOR.ESPECIAL_LABEL') }}
            </label>
            <select
              v-model="especiaisGrau[v.seq]"
              :data-testid="`sim-especial-grau-${v.seq}`"
              :class="fieldClass"
            >
              <option :value="undefined">
                {{ $t('RAMON.SIMULADOR.ESPECIAL_NAO') }}
              </option>
              <option v-for="g in GRAUS_ESPECIAIS" :key="g" :value="g">
                {{ g }}
              </option>
            </select>
            <template v-if="especiaisGrau[v.seq]">
              <input
                v-model="especiaisInicio[v.seq]"
                type="date"
                :data-testid="`sim-especial-inicio-${v.seq}`"
                :class="fieldClass"
              />
              <input
                v-model="especiaisFim[v.seq]"
                type="date"
                :data-testid="`sim-especial-fim-${v.seq}`"
                :class="fieldClass"
              />
            </template>
          </div>
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
    </div>

    <div
      class="flex flex-wrap gap-1 border-b border-n-weak"
      role="tablist"
      data-testid="sim-abas"
    >
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'painel'"
        data-testid="sim-aba-painel"
        class="px-3 py-1.5 text-xs rounded-t-lg"
        :class="
          aba === 'painel'
            ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
            : 'text-n-slate-10'
        "
        @click="aba = 'painel'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_POSSIBILIDADES') }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'honorario'"
        data-testid="sim-aba-honorario"
        class="px-3 py-1.5 text-xs rounded-t-lg"
        :class="
          aba === 'honorario'
            ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
            : 'text-n-slate-10'
        "
        @click="aba = 'honorario'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_HONORARIO') }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'elegibilidade'"
        data-testid="sim-aba-elegibilidade"
        class="px-3 py-1.5 text-xs rounded-t-lg"
        :class="
          aba === 'elegibilidade'
            ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
            : 'text-n-slate-10'
        "
        @click="aba = 'elegibilidade'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_ELEGIBILIDADE') }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'pensao'"
        data-testid="sim-aba-pensao"
        class="px-3 py-1.5 text-xs rounded-t-lg"
        :class="
          aba === 'pensao'
            ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
            : 'text-n-slate-10'
        "
        @click="aba = 'pensao'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_PENSAO') }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'maternidade'"
        data-testid="sim-aba-maternidade"
        class="px-3 py-1.5 text-xs rounded-t-lg"
        :class="
          aba === 'maternidade'
            ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
            : 'text-n-slate-10'
        "
        @click="aba = 'maternidade'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_MATERNIDADE') }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'planejamento'"
        data-testid="sim-aba-planejamento"
        class="px-3 py-1.5 text-xs rounded-t-lg"
        :class="
          aba === 'planejamento'
            ? 'bg-n-alpha-2 text-n-slate-12 font-medium'
            : 'text-n-slate-10'
        "
        @click="aba = 'planejamento'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_PLANEJAMENTO') }}
      </button>
    </div>

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
      v-show="aba === 'honorario'"
      class="flex flex-col gap-3"
      data-testid="sim-secao-honorario"
    >
      <div class="grid grid-cols-2 gap-2">
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
        class="px-3 py-1.5 text-xs rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-40 disabled:cursor-not-allowed"
        :disabled="!canSimulate || isLoading"
        @click="simulate"
      >
        {{
          isLoading
            ? $t('RAMON.SIMULADOR.SIMULANDO')
            : $t('RAMON.SIMULADOR.SIMULAR')
        }}
      </button>

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
        <div
          v-if="avisosQualidade.length"
          class="flex flex-col gap-1 p-2 rounded-lg border border-n-ruby-9 bg-n-ruby-3 text-xs text-n-ruby-11"
          data-testid="sim-aviso-qualidade"
        >
          <p v-for="(aviso, i) in avisosQualidade" :key="i">{{ aviso }}</p>
          <p class="font-medium">
            {{ $t('RAMON.SIMULADOR.ELEG_VER_ABA') }}
          </p>
        </div>
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
        <p
          v-else
          class="text-xs text-n-amber-11"
          data-testid="sim-sem-honorario"
        >
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
          v-if="avisosGerais.length"
          class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4"
          data-testid="sim-avisos"
        >
          <li v-for="(aviso, i) in avisosGerais" :key="i">{{ aviso }}</li>
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
        <div
          v-if="memoria"
          class="flex flex-col gap-1"
          data-testid="sim-memoria"
        >
          <div
            class="max-h-64 overflow-y-auto overflow-x-auto rounded-lg border border-n-weak"
          >
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
                  <td class="p-1 whitespace-nowrap">{{ linha.competencia }}</td>
                  <td class="p-1 text-end whitespace-nowrap">
                    {{ money(linha.salario) }}
                  </td>
                  <td class="p-1 text-end whitespace-nowrap">
                    {{ linha.indice }}
                  </td>
                  <td class="p-1 text-end whitespace-nowrap">
                    {{ money(linha.corrigido) }}
                  </td>
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
    </div>

    <div
      v-show="aba === 'painel'"
      class="flex flex-col gap-2"
      data-testid="sim-painel-secao"
    >
      <span class="text-xs font-medium text-n-slate-12">
        {{ $t('RAMON.SIMULADOR.PAINEL_TITULO') }}
      </span>
      <div
        v-for="(v, i) in vinculosExtras"
        :key="i"
        class="flex flex-col gap-1 p-1.5 rounded-lg border border-n-weak"
        :data-testid="`sim-vinculo-extra-${i}`"
      >
        <div class="grid grid-cols-2 gap-1">
          <label :class="labelClass">
            {{ $t('RAMON.SIMULADOR.VINCULO_INICIO') }}
            <input v-model="v.inicio" type="date" :class="fieldClass" />
          </label>
          <label :class="labelClass">
            {{ $t('RAMON.SIMULADOR.VINCULO_FIM') }}
            <input v-model="v.fim" type="date" :class="fieldClass" />
          </label>
          <label :class="labelClass">
            {{ $t('RAMON.SIMULADOR.VINCULO_TIPO') }}
            <select v-model="v.tipo" :class="fieldClass">
              <option value="EMPREGO">
                {{ $t('RAMON.SIMULADOR.VINCULO_TIPO_EMPREGO') }}
              </option>
              <option value="RECOLHIMENTO">
                {{ $t('RAMON.SIMULADOR.VINCULO_TIPO_RECOLHIMENTO') }}
              </option>
            </select>
          </label>
          <label :class="labelClass">
            {{ $t('RAMON.SIMULADOR.VINCULO_SALARIO') }}
            <input
              v-model="v.salario"
              type="number"
              min="0"
              step="0.01"
              :class="fieldClass"
            />
          </label>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <label class="text-xs text-n-slate-11">
            {{ $t('RAMON.SIMULADOR.ESPECIAL_LABEL') }}
          </label>
          <select
            v-model="v.especialGrau"
            :data-testid="`sim-vinculo-extra-especial-grau-${i}`"
            :class="fieldClass"
          >
            <option :value="undefined">
              {{ $t('RAMON.SIMULADOR.ESPECIAL_NAO') }}
            </option>
            <option v-for="g in GRAUS_ESPECIAIS" :key="g" :value="g">
              {{ g }}
            </option>
          </select>
          <template v-if="v.especialGrau">
            <input
              v-model="v.especialInicio"
              type="date"
              :data-testid="`sim-vinculo-extra-especial-inicio-${i}`"
              :class="fieldClass"
            />
            <input
              v-model="v.especialFim"
              type="date"
              :data-testid="`sim-vinculo-extra-especial-fim-${i}`"
              :class="fieldClass"
            />
          </template>
        </div>
        <button
          type="button"
          class="self-start text-xs text-n-ruby-11"
          @click="removeVinculoExtra(i)"
        >
          {{ $t('RAMON.SIMULADOR.VINCULO_REMOVER') }}
        </button>
      </div>
      <button
        type="button"
        data-testid="sim-vinculo-extra-add"
        class="self-start text-xs underline text-n-slate-11"
        @click="addVinculoExtra"
      >
        {{ $t('RAMON.SIMULADOR.VINCULO_ADICIONAR') }}
      </button>
      <button
        type="button"
        data-testid="sim-painel-run"
        class="px-3 py-1.5 text-xs rounded-lg bg-n-teal-9 text-white hover:bg-n-teal-10 disabled:opacity-40 disabled:cursor-not-allowed"
        :disabled="!canPainel || painelLoading"
        @click="calcularPainel"
      >
        {{
          painelLoading
            ? $t('RAMON.SIMULADOR.PAINEL_CALCULANDO')
            : $t('RAMON.SIMULADOR.PAINEL_CALCULAR')
        }}
      </button>

      <div
        v-if="painel"
        class="flex flex-col gap-2"
        data-testid="sim-painel-resultado"
      >
        <p class="text-xs text-n-slate-11" data-testid="sim-painel-resumo">
          {{
            $t('RAMON.SIMULADOR.PAINEL_RESUMO', {
              idade: painel.resumo.idade,
              tempo: painel.resumo.tempo_contribuicao,
              tempoReforma: painel.resumo.tempo_na_reforma,
              carencia: painel.resumo.carencia,
              media: money(painel.resumo.media),
            })
          }}
        </p>
        <div
          v-for="cartao in painel.cartoes"
          :key="cartao.id"
          class="flex flex-col gap-1 p-2 rounded-lg bg-n-alpha-1 border border-n-weak"
          :class="bordaDe(cartao)"
          :data-testid="`sim-cartao-${cartao.id}`"
        >
          <div class="flex items-start justify-between gap-2">
            <span class="text-xs font-medium text-n-slate-12">
              {{ cartao.titulo }}
            </span>
            <span
              class="text-sm font-semibold text-n-slate-12 whitespace-nowrap"
            >
              {{ money(cartao.rmi) }}
            </span>
          </div>
          <span class="text-xs text-n-slate-10">{{ cartao.subtitulo }}</span>
          <span
            v-if="cartao.elegivel === true"
            class="text-xs text-n-teal-11 font-medium"
          >
            {{ $t('RAMON.SIMULADOR.PAINEL_ELEGIVEL') }}
          </span>
          <span
            v-else-if="cartao.elegivel === null && cartao.depende_de"
            class="text-xs text-n-amber-11"
          >
            {{
              $t('RAMON.SIMULADOR.PAINEL_DEPENDE', { de: cartao.depende_de })
            }}
          </span>
          <template v-for="req in cartao.requisitos || []" :key="req.nome">
            <span v-if="req.faltou" class="text-xs text-n-ruby-11">
              {{
                $t('RAMON.SIMULADOR.PAINEL_FALTOU', {
                  requisito: $t(
                    `RAMON.SIMULADOR.REQ_${req.nome.toUpperCase()}`
                  ),
                  atual: req.atual,
                  faltou: req.faltou,
                })
              }}
            </span>
          </template>
          <span v-if="cartao.rmi_com_descartes" class="text-xs text-n-slate-10">
            {{
              $t('RAMON.SIMULADOR.PAINEL_DESCARTES', {
                valor: money(cartao.rmi_com_descartes),
              })
            }}
          </span>
          <span v-if="cartao.previsao" class="text-xs text-n-slate-10">
            {{
              $t('RAMON.SIMULADOR.PAINEL_PREVISAO', {
                data: dataBr(cartao.previsao),
              })
            }}
          </span>
          <button
            v-if="cartao.rmi"
            type="button"
            class="self-start text-xs underline text-n-slate-11"
            :data-testid="`sim-cartao-liquidar-${cartao.id}`"
            @click="liquidarCartao(cartao)"
          >
            {{ $t('RAMON.SIMULADOR.PAINEL_LIQUIDAR') }}
          </button>
        </div>
        <ul
          v-if="painel.avisos && painel.avisos.length"
          class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4"
        >
          <li v-for="(aviso, i) in painel.avisos" :key="i">{{ aviso }}</li>
        </ul>
      </div>
      <LeadLiquidacao ref="liquidacaoRef" :lead="lead" />
    </div>

    <div
      v-show="aba === 'elegibilidade'"
      class="flex flex-col gap-2"
      data-testid="sim-elegibilidade-secao"
    >
      <p
        v-if="!canElegibilidade"
        class="text-xs text-n-amber-11"
        data-testid="sim-elegibilidade-hint"
      >
        {{ $t('RAMON.SIMULADOR.ELEG_PRECISA_CNIS') }}
      </p>
      <LeadElegibilidade v-else :lead="lead" :der="form.der" />
    </div>

    <div
      v-show="aba === 'pensao'"
      class="flex flex-col gap-2"
      data-testid="sim-pensao-secao"
    >
      <p
        v-if="!canPensao"
        class="text-xs text-n-amber-11"
        data-testid="sim-pensao-hint"
      >
        {{ $t('RAMON.SIMULADOR.PENSAO_PRECISA_CNIS') }}
      </p>
      <LeadPensao v-else :lead="lead" />
    </div>

    <div
      v-show="aba === 'maternidade'"
      class="flex flex-col gap-2"
      data-testid="sim-maternidade-secao"
    >
      <p
        v-if="!canMaternidade"
        class="text-xs text-n-amber-11"
        data-testid="sim-maternidade-hint"
      >
        {{ $t('RAMON.SIMULADOR.MATERNIDADE_PRECISA_CNIS') }}
      </p>
      <LeadMaternidade v-else :lead="lead" />
    </div>

    <div
      v-show="aba === 'planejamento'"
      class="flex flex-col gap-2"
      data-testid="sim-planejamento-secao"
    >
      <p
        v-if="!canPlanejamento"
        class="text-xs text-n-amber-11"
        data-testid="sim-planejamento-hint"
      >
        {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_PRECISA_CNIS') }}
      </p>
      <LeadPlanejamento v-else :lead="lead" />
    </div>

    <p
      class="text-xs italic text-n-amber-11 border-t border-n-weak pt-2"
      data-testid="sim-disclaimer"
    >
      {{ $t('RAMON.SIMULADOR.DISCLAIMER') }}
    </p>
  </div>
</template>

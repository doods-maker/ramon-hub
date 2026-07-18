<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/leads';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'LeadLiquidacao' });

const { t } = useI18n();

const form = ref({
  rmi: '',
  dib: '',
  data_citacao: '',
  data_ajuizamento: '',
  data_sentenca_ou_acordao: '',
  data_fim: '',
  data_calculo: '',
  no_piso: false,
  regime_pos_ec136: 'art406',
  honorarios_sucumbenciais_pct: '',
  honorarios_contratuais_pct: '',
});
const abatimentos = ref([]);
const cabecalho = ref({
  segurado_nome: '',
  numero_processo: '',
  numero_beneficio: '',
});

const isLoading = ref(false);
const pdfLoading = ref(false);
const resultado = ref(null);
const motorDown = ref(false);
const errorMessage = ref('');

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const money = value => brl.format(Number(value || 0));

// "1518", "1518.50" ou "1518,50" — nunca "1.518" (milhar) que vira 1000x menor.
const decimalValido = v => /^\d+([.,]\d{1,2})?$/.test(v);
const normDecimal = v => String(v).replace(',', '.');

const canCalcular = computed(
  () =>
    decimalValido(form.value.rmi) &&
    Number(normDecimal(form.value.rmi)) > 0 &&
    Boolean(form.value.dib)
);

// Pré-preenche a RMI a partir de um cartão do painel (Task 5).
const preencher = rmi => {
  form.value.rmi = String(rmi);
};
defineExpose({ preencher });

const addAbatimento = () =>
  abatimentos.value.push({ ano: '', mes: '', valor: '' });
const removeAbatimento = index => abatimentos.value.splice(index, 1);

const DATAS = [
  'data_citacao',
  'data_ajuizamento',
  'data_sentenca_ou_acordao',
  'data_fim',
  'data_calculo',
];

// dinheiro/percentual como string no JSON (input number vira float)
const payload = () => {
  const f = form.value;
  const p = {
    rmi: normDecimal(f.rmi),
    dib: f.dib,
    no_piso: f.no_piso,
    regime_pos_ec136: f.regime_pos_ec136,
    abatimentos: abatimentos.value
      .filter(a => a.ano && a.mes && a.valor && decimalValido(a.valor))
      .map(a => ({
        ano: Number(a.ano),
        mes: Number(a.mes),
        valor: normDecimal(a.valor),
      })),
  };
  DATAS.forEach(k => {
    if (f[k]) p[k] = f[k];
  });
  ['honorarios_sucumbenciais_pct', 'honorarios_contratuais_pct'].forEach(k => {
    if (f[k]) p[k] = normDecimal(f[k]);
  });
  return p;
};

// jsdom (specs) não implementa Blob.text() — FileReader funciona nos dois.
const blobToText = blob =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsText(blob);
  });

// liquidacaoPdf usa responseType: 'blob', então em erro o axios entrega
// error.response.data como Blob (não JSON) — precisa ler o texto antes.
const handleError = async error => {
  if (error?.response?.status === 503) {
    motorDown.value = true;
    return;
  }
  const data = error?.response?.data;
  if (data instanceof Blob) {
    try {
      const parsed = JSON.parse(await blobToText(data));
      errorMessage.value = parsed.error || t('RAMON.SIMULADOR.GENERIC_ERROR');
    } catch {
      errorMessage.value = t('RAMON.SIMULADOR.GENERIC_ERROR');
    }
    return;
  }
  errorMessage.value = data?.error || t('RAMON.SIMULADOR.GENERIC_ERROR');
};

const calcular = async () => {
  isLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  resultado.value = null;
  try {
    const { data } = await LeadsAPI.liquidacao(props.lead.id, payload());
    resultado.value = data;
  } catch (error) {
    await handleError(error);
  } finally {
    isLoading.value = false;
  }
};

const baixarPdf = async () => {
  pdfLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.liquidacaoPdf(props.lead.id, {
      ...payload(),
      ...cabecalho.value,
    });
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = `liquidacao-lead-${props.lead.id}.pdf`;
    link.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    await handleError(error);
  } finally {
    pdfLoading.value = false;
  }
};

const fieldClass =
  'w-full px-2 py-1.5 text-sm rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-12 outline-none focus:border-n-slate-8';
const labelClass = 'flex flex-col gap-1 text-xs text-n-slate-10';
</script>

<template>
  <div
    class="flex flex-col gap-2 border-t border-n-weak pt-2"
    data-testid="liq-form"
  >
    <span class="text-xs font-medium text-n-slate-12">
      {{ $t('RAMON.LIQUIDACAO.TITULO') }}
    </span>
    <div class="grid grid-cols-2 gap-2">
      <label :class="labelClass">
        {{ $t('RAMON.LIQUIDACAO.RMI') }}
        <input
          v-model="form.rmi"
          type="text"
          inputmode="decimal"
          data-testid="liq-rmi"
          :class="fieldClass"
        />
      </label>
      <label :class="labelClass">
        {{ $t('RAMON.LIQUIDACAO.DIB') }}
        <input
          v-model="form.dib"
          type="date"
          data-testid="liq-dib"
          :class="fieldClass"
        />
      </label>
      <label :class="labelClass">
        {{ $t('RAMON.LIQUIDACAO.CITACAO') }}
        <input
          v-model="form.data_citacao"
          type="date"
          data-testid="liq-citacao"
          :class="fieldClass"
        />
      </label>
    </div>

    <details data-testid="liq-opcionais">
      <summary class="text-xs cursor-pointer text-n-slate-11">
        {{ $t('RAMON.LIQUIDACAO.OPCIONAIS') }}
      </summary>
      <div class="grid grid-cols-2 gap-2 pt-2">
        <label :class="labelClass">
          {{ $t('RAMON.LIQUIDACAO.AJUIZAMENTO') }}
          <input
            v-model="form.data_ajuizamento"
            type="date"
            data-testid="liq-ajuizamento"
            :class="fieldClass"
          />
        </label>
        <label :class="labelClass">
          {{ $t('RAMON.LIQUIDACAO.SENTENCA') }}
          <input
            v-model="form.data_sentenca_ou_acordao"
            type="date"
            data-testid="liq-sentenca"
            :class="fieldClass"
          />
        </label>
        <label :class="labelClass">
          {{ $t('RAMON.LIQUIDACAO.FIM') }}
          <input
            v-model="form.data_fim"
            type="date"
            data-testid="liq-fim"
            :class="fieldClass"
          />
        </label>
        <label :class="labelClass">
          {{ $t('RAMON.LIQUIDACAO.CALCULO_EM') }}
          <input
            v-model="form.data_calculo"
            type="date"
            data-testid="liq-calculo-em"
            :class="fieldClass"
          />
        </label>
        <label :class="labelClass">
          {{ $t('RAMON.LIQUIDACAO.HON_SUC') }}
          <input
            v-model="form.honorarios_sucumbenciais_pct"
            type="text"
            inputmode="decimal"
            data-testid="liq-hon-suc"
            :class="fieldClass"
          />
        </label>
        <label :class="labelClass">
          {{ $t('RAMON.LIQUIDACAO.HON_CONTR') }}
          <input
            v-model="form.honorarios_contratuais_pct"
            type="text"
            inputmode="decimal"
            data-testid="liq-hon-contr"
            :class="fieldClass"
          />
        </label>
        <label :class="labelClass">
          {{ $t('RAMON.LIQUIDACAO.REGIME') }}
          <select
            v-model="form.regime_pos_ec136"
            data-testid="liq-regime"
            :class="fieldClass"
          >
            <option value="art406">
              {{ $t('RAMON.LIQUIDACAO.REGIME_ART406') }}
            </option>
            <option value="selic">
              {{ $t('RAMON.LIQUIDACAO.REGIME_SELIC') }}
            </option>
          </select>
        </label>
      </div>
      <label class="flex items-center gap-2 pt-2 text-xs text-n-slate-11">
        <input
          v-model="form.no_piso"
          type="checkbox"
          data-testid="liq-no-piso"
        />
        {{ $t('RAMON.LIQUIDACAO.NO_PISO') }}
      </label>

      <div class="flex flex-col gap-1 pt-2">
        <span class="text-xs text-n-slate-10">
          {{ $t('RAMON.LIQUIDACAO.ABATIMENTOS') }}
        </span>
        <div
          v-for="(a, i) in abatimentos"
          :key="i"
          class="flex items-end gap-1"
          :data-testid="`liq-abatimento-${i}`"
        >
          <label :class="labelClass">
            {{ $t('RAMON.LIQUIDACAO.ABATIMENTO_ANO') }}
            <input
              v-model="a.ano"
              type="number"
              :data-testid="`liq-abatimento-ano-${i}`"
              :class="fieldClass"
            />
          </label>
          <label :class="labelClass">
            {{ $t('RAMON.LIQUIDACAO.ABATIMENTO_MES') }}
            <input
              v-model="a.mes"
              type="number"
              min="1"
              max="12"
              :data-testid="`liq-abatimento-mes-${i}`"
              :class="fieldClass"
            />
          </label>
          <label :class="labelClass">
            {{ $t('RAMON.LIQUIDACAO.ABATIMENTO_VALOR') }}
            <input
              v-model="a.valor"
              type="text"
              inputmode="decimal"
              :data-testid="`liq-abatimento-valor-${i}`"
              :class="fieldClass"
            />
          </label>
          <button
            type="button"
            class="pb-1.5 text-xs text-n-ruby-11"
            @click="removeAbatimento(i)"
          >
            {{ $t('RAMON.LIQUIDACAO.ABATIMENTO_REMOVER') }}
          </button>
        </div>
        <button
          type="button"
          data-testid="liq-abatimento-add"
          class="self-start text-xs underline text-n-slate-11"
          @click="addAbatimento"
        >
          {{ $t('RAMON.LIQUIDACAO.ABATIMENTO_ADD') }}
        </button>
      </div>
    </details>

    <button
      type="button"
      data-testid="liq-run"
      class="px-3 py-1.5 text-xs rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-40 disabled:cursor-not-allowed"
      :disabled="!canCalcular || isLoading"
      @click="calcular"
    >
      {{
        isLoading
          ? $t('RAMON.LIQUIDACAO.CALCULANDO')
          : $t('RAMON.LIQUIDACAO.CALCULAR')
      }}
    </button>

    <p
      v-if="motorDown"
      class="text-sm text-n-amber-11"
      data-testid="liq-motor-down"
    >
      {{ $t('RAMON.SIMULADOR.MOTOR_DOWN') }}
    </p>
    <p
      v-else-if="errorMessage"
      class="text-sm text-n-ruby-11"
      data-testid="liq-error"
    >
      {{ errorMessage }}
    </p>

    <div
      v-if="resultado"
      class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
      data-testid="liq-resultado"
    >
      <p class="text-sm text-n-slate-12">
        <span class="text-n-slate-10"
          >{{ $t('RAMON.LIQUIDACAO.TOTAL_PRINCIPAL') }}:</span
        >
        {{ money(resultado.total_principal_corrigido) }}
      </p>
      <p class="text-sm text-n-slate-12">
        <span class="text-n-slate-10"
          >{{ $t('RAMON.LIQUIDACAO.TOTAL_JUROS') }}:</span
        >
        {{ money(resultado.total_juros) }}
      </p>
      <p
        v-if="Number(resultado.total_atualizacao_selic_ec136)"
        class="text-sm text-n-slate-12"
      >
        <span class="text-n-slate-10"
          >{{ $t('RAMON.LIQUIDACAO.TOTAL_SELIC') }}:</span
        >
        {{ money(resultado.total_atualizacao_selic_ec136) }}
      </p>
      <p class="text-sm font-semibold text-n-slate-12">
        <span class="font-normal text-n-slate-10"
          >{{ $t('RAMON.LIQUIDACAO.TOTAL_GERAL') }}:</span
        >
        {{ money(resultado.total_geral) }}
      </p>
      <p
        v-if="resultado.honorarios?.sucumbenciais"
        class="text-sm text-n-slate-12"
      >
        <span class="text-n-slate-10"
          >{{ $t('RAMON.LIQUIDACAO.HONORARIOS_SUC') }}:</span
        >
        {{ money(resultado.honorarios.sucumbenciais.valor) }}
      </p>
      <p
        v-if="resultado.honorarios?.contratuais"
        class="text-sm text-n-slate-12"
      >
        <span class="text-n-slate-10"
          >{{ $t('RAMON.LIQUIDACAO.HONORARIOS_CONTR') }}:</span
        >
        {{ money(resultado.honorarios.contratuais.valor) }}
      </p>
      <p
        v-if="resultado.honorarios?.contratuais"
        class="text-sm text-n-slate-12"
      >
        <span class="text-n-slate-10"
          >{{ $t('RAMON.LIQUIDACAO.LIQUIDO_CLIENTE') }}:</span
        >
        {{ money(resultado.liquido_cliente) }}
      </p>
      <ul
        v-if="resultado.avisos && resultado.avisos.length"
        class="flex flex-col gap-1 pt-1 text-xs text-n-slate-10 list-disc ps-4"
      >
        <li v-for="(aviso, i) in resultado.avisos" :key="i">{{ aviso }}</li>
      </ul>

      <div class="grid grid-cols-3 gap-1 pt-2">
        <label :class="labelClass">
          {{ $t('RAMON.LIQUIDACAO.PDF_NOME') }}
          <input
            v-model="cabecalho.segurado_nome"
            type="text"
            data-testid="liq-pdf-nome"
            :class="fieldClass"
          />
        </label>
        <label :class="labelClass">
          {{ $t('RAMON.LIQUIDACAO.PDF_PROCESSO') }}
          <input
            v-model="cabecalho.numero_processo"
            type="text"
            data-testid="liq-pdf-processo"
            :class="fieldClass"
          />
        </label>
        <label :class="labelClass">
          {{ $t('RAMON.LIQUIDACAO.PDF_BENEFICIO') }}
          <input
            v-model="cabecalho.numero_beneficio"
            type="text"
            data-testid="liq-pdf-beneficio"
            :class="fieldClass"
          />
        </label>
      </div>
      <button
        type="button"
        data-testid="liq-pdf-run"
        class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
        :disabled="pdfLoading || !canCalcular"
        @click="baixarPdf"
      >
        {{
          pdfLoading
            ? $t('RAMON.LIQUIDACAO.PDF_BAIXANDO')
            : $t('RAMON.LIQUIDACAO.PDF_BAIXAR')
        }}
      </button>
    </div>
  </div>
</template>

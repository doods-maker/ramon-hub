<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/leads';

const props = defineProps({
  lead: { type: Object, required: true },
});
defineOptions({ name: 'LeadPlanejamento' });

const { t } = useI18n();

const isLoading = ref(false);
const pdfLoading = ref(false);
const ocupado = computed(() => isLoading.value || pdfLoading.value);
const hasError = ref(false);
const errorMessage = ref('');
const resultado = ref(null);
// erro nunca se mascara de vazio: retry refaz a mesma ação que falhou.
const ultimaAcao = ref('planejar');

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const money = value => brl.format(Number(value || 0));
const dataBr = iso => (iso ? iso.split('-').reverse().join('/') : '');
const capitalizar = s => (s ? s.charAt(0).toUpperCase() + s.slice(1) : '');

// jsdom (specs) não implementa Blob.text() — FileReader funciona nos dois.
const blobToText = blob =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsText(blob);
  });

// planejamentoPdf usa responseType: 'blob', então em erro o axios entrega
// error.response.data como Blob (não JSON) — precisa ler o texto antes.
const handleError = async error => {
  const data = error?.response?.data;
  if (data instanceof Blob) {
    try {
      const parsed = JSON.parse(await blobToText(data));
      errorMessage.value =
        parsed.error || t('RAMON.SIMULADOR.PLANEJAMENTO_ERRO');
    } catch {
      errorMessage.value = t('RAMON.SIMULADOR.PLANEJAMENTO_ERRO');
    }
  } else {
    errorMessage.value = data?.error || t('RAMON.SIMULADOR.PLANEJAMENTO_ERRO');
  }
  hasError.value = true;
};

const planejar = async () => {
  ultimaAcao.value = 'planejar';
  isLoading.value = true;
  hasError.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.planejamento(props.lead.id, {});
    resultado.value = data;
  } catch (error) {
    await handleError(error);
  } finally {
    isLoading.value = false;
  }
};

const baixarPdf = async () => {
  ultimaAcao.value = 'pdf';
  pdfLoading.value = true;
  hasError.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.planejamentoPdf(props.lead.id, {});
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = `planejamento-lead-${props.lead.id}.pdf`;
    link.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    await handleError(error);
  } finally {
    pdfLoading.value = false;
  }
};

const retry = () => (ultimaAcao.value === 'pdf' ? baixarPdf() : planejar());
</script>

<template>
  <div class="flex flex-col gap-3 p-1" data-testid="lead-planejamento">
    <button
      type="button"
      data-testid="planejamento-planejar"
      class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-40 disabled:cursor-not-allowed"
      :disabled="ocupado"
      @click="planejar"
    >
      {{
        isLoading
          ? $t('RAMON.SIMULADOR.PLANEJAMENTO_PLANEJANDO')
          : $t('RAMON.SIMULADOR.PLANEJAMENTO_PLANEJAR')
      }}
    </button>

    <div v-if="hasError" data-testid="planejamento-error">
      <p class="text-sm text-n-ruby-11">{{ errorMessage }}</p>
      <button
        type="button"
        data-testid="planejamento-retry"
        class="mt-1 text-xs text-n-iris-11 hover:underline"
        @click="retry"
      >
        {{ $t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <template v-if="resultado">
      <div
        v-if="
          resultado.decisoes_pendentes && resultado.decisoes_pendentes.length
        "
        class="flex flex-col gap-2"
        data-testid="planejamento-pendencias"
      >
        <span class="text-xs font-medium text-n-slate-12">
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_PENDENCIAS') }}
        </span>
        <div
          v-for="(pend, i) in resultado.decisoes_pendentes"
          :key="i"
          class="p-2 rounded-lg bg-n-amber-3 border border-n-amber-6"
          :data-testid="`planejamento-pendencia-${i}`"
        >
          <p class="text-xs text-n-amber-11 font-medium">
            {{ pend.pergunta }}
          </p>
        </div>
      </div>

      <div
        v-for="(cenario, i) in resultado.cenarios"
        :key="i"
        class="flex flex-col gap-2 p-2 rounded-lg border border-n-weak"
        :data-testid="`planejamento-cenario-${i}`"
      >
        <div class="flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
          <span class="text-sm font-semibold text-n-slate-12">
            {{ capitalizar(cenario.nome) }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_SALARIO') }}:
            {{ money(cenario.salario) }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_ALIQUOTA') }}:
            {{ cenario.aliquota }}%
          </span>
        </div>
        <p v-if="cenario.observacao" class="text-xs text-n-slate-10">
          {{ cenario.observacao }}
        </p>

        <div
          v-if="cenario.resultados && cenario.resultados.length"
          class="overflow-x-auto"
        >
          <table class="w-full text-xs">
            <tbody>
              <tr
                v-for="(r, j) in cenario.resultados"
                :key="j"
                :data-testid="`planejamento-cenario-${i}-resultado-${j}`"
              >
                <td class="p-1">
                  <span class="font-medium text-n-slate-12">{{
                    r.titulo
                  }}</span>
                  <span class="text-n-slate-10"> ({{ r.regra }})</span>
                </td>
                <td class="p-1 text-end whitespace-nowrap">
                  {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_FECHA_EM') }}:
                  {{ dataBr(r.fecha_em) }}
                </td>
                <td class="p-1 text-end whitespace-nowrap">
                  {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_RMI_PROJETADA') }}:
                  {{ money(r.rmi_projetada) }}
                </td>
                <td class="p-1 text-end whitespace-nowrap">
                  {{
                    $t('RAMON.SIMULADOR.PLANEJAMENTO_MESES_CONTRIB', {
                      n: r.meses_contribuindo,
                    })
                  }}
                </td>
                <td class="p-1 text-end whitespace-nowrap">
                  {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_DESEMBOLSO') }}:
                  {{ money(r.desembolso_total) }}
                </td>
                <td class="p-1 text-end whitespace-nowrap">
                  {{
                    $t('RAMON.SIMULADOR.PLANEJAMENTO_PAYBACK', {
                      n: r.payback_meses,
                    })
                  }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="cenario.regras_excluidas && cenario.regras_excluidas.length"
          class="flex flex-col gap-0.5"
          :data-testid="`planejamento-cenario-${i}-excluidas`"
        >
          <span class="text-xs font-medium text-n-slate-11">
            {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_EXCLUIDAS_TITULO') }}
          </span>
          <p
            v-for="(ex, k) in cenario.regras_excluidas"
            :key="k"
            class="text-[11px] text-n-slate-10"
          >
            {{ ex.regra }}: {{ ex.motivo }}
          </p>
        </div>

        <ul
          v-if="cenario.avisos && cenario.avisos.length"
          class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4"
        >
          <li v-for="(aviso, k) in cenario.avisos" :key="k">{{ aviso }}</li>
        </ul>
      </div>

      <ul
        v-if="resultado.avisos && resultado.avisos.length"
        class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4"
        data-testid="planejamento-avisos"
      >
        <li v-for="(aviso, i) in resultado.avisos" :key="i">{{ aviso }}</li>
      </ul>

      <button
        type="button"
        data-testid="planejamento-pdf-run"
        class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak disabled:opacity-40 disabled:cursor-not-allowed"
        :disabled="ocupado"
        @click="baixarPdf"
      >
        {{
          pdfLoading
            ? $t('RAMON.SIMULADOR.PLANEJAMENTO_PDF_BAIXANDO')
            : $t('RAMON.SIMULADOR.PLANEJAMENTO_PDF_BAIXAR')
        }}
      </button>
    </template>
  </div>
</template>

<script setup>
// Faixa acima do quadro quando o funil está filtrado por Pós-venda ou Radar
// (redesign v2, Onda 5): o que as páginas antigas mostravam continua aqui —
// resumo do Radar + campanha de resgate; resumo do Pós-venda + Concluídos.
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import RamonPrescriptionRadarAPI from 'dashboard/api/ramonPrescriptionRadar';
import RamonPosVendaAPI from 'dashboard/api/ramonPosVenda';
import { brlCompact } from '../../helpers/currency';
import { BTN_TINT } from '../hoje/hoje';
import ConfirmModal from '../ConfirmModal.vue';

const props = defineProps({
  filtro: { type: String, required: true },
  // filtros do servidor ligados junto (ex.: veio do redirect com filtro salvo)
  outrosFiltros: { type: Boolean, default: false },
});
const emit = defineEmits(['limparFiltros']);

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const data = ref(null);
const erro = ref(false);
const carregar = async () => {
  data.value = null;
  erro.value = false;
  try {
    const api =
      props.filtro === 'prescricao'
        ? RamonPrescriptionRadarAPI
        : RamonPosVendaAPI;
    data.value = (await api.get()).data;
  } catch (e) {
    erro.value = true;
  }
};
watch(() => props.filtro, carregar, { immediate: true });

// Radar
const resumo = computed(() => data.value?.summary ?? {});
const itens = computed(() => data.value?.items ?? []);
const consentidos = computed(
  () => itens.value.filter(item => item.consent_marketing).length
);
const campanhaAberta = ref(false);
const irParaCampanhas = () => {
  campanhaAberta.value = false;
  router.push(accountScopedRoute('campaigns_whatsapp_index'));
};

// Pós-venda
const pendentes = computed(() => data.value?.pendentes ?? []);
const concluidos = computed(() => data.value?.concluidos ?? []);
const verConcluidos = ref(false);
const abrirLead = id => store.dispatch('leads/select', id);

const PILULA = 'rounded-full px-2.5 py-1 text-[12.5px]';
</script>

<template>
  <div
    data-testid="faixa-filtro"
    class="flex flex-wrap items-center gap-2.5 px-7 pt-3 text-[12.5px] text-n-slate-11"
  >
    <template v-if="erro">
      <span class="text-n-ruby-11">
        {{
          filtro === 'prescricao'
            ? t('RAMON.RADAR.LOAD_ERROR')
            : t('RAMON.POS_VENDA.ERROR')
        }}
      </span>
      <button class="text-n-blue-11 hover:underline" @click="carregar">
        {{ t('RAMON.FUNIL.TENTAR_DE_NOVO') }}
      </button>
    </template>

    <template v-else-if="data && filtro === 'prescricao'">
      <span
        data-testid="faixa-sangrando"
        :class="PILULA"
        class="bg-n-ruby-9/10 text-n-ruby-11"
      >
        <b class="font-mono font-semibold">
          {{
            `${brlCompact(resumo.bleeding_monthly)}${t('RAMON.RADAR.PER_MONTH')}`
          }}
        </b>
        {{
          t('RAMON.RADAR.SUMMARY_BLEEDING', { count: resumo.bleeding_count })
        }}
      </span>
      <span :class="PILULA" class="bg-n-amber-9/15 text-n-amber-11">
        <b class="font-mono font-semibold">
          {{
            `${brlCompact(resumo.at_risk_90d_monthly)}${t('RAMON.RADAR.PER_MONTH')}`
          }}
        </b>
        {{ t('RAMON.RADAR.SUMMARY_RISK') }}
      </span>
      <span v-if="itens.length" class="flex items-center gap-2">
        <button
          data-testid="faixa-campanha"
          :class="BTN_TINT"
          @click="campanhaAberta = true"
        >
          {{ t('RAMON.RADAR.CAMPAIGN_CTA', { count: consentidos }) }}
        </button>
        <span class="text-[11.5px] text-n-slate-9">
          {{
            t('RAMON.RADAR.CAMPAIGN_TOOLTIP', {
              n: consentidos,
              m: itens.length,
            })
          }}
        </span>
      </span>
    </template>

    <template v-else-if="data">
      <span data-testid="faixa-pos-venda">
        {{ t('RAMON.POS_VENDA.RESUMO', { count: pendentes.length }) }}
      </span>
      <button
        v-if="concluidos.length"
        data-testid="faixa-concluidos"
        class="inline-flex items-center gap-1 font-medium text-n-slate-11 hover:text-n-slate-12"
        @click="verConcluidos = !verConcluidos"
      >
        <span
          class="i-lucide-chevron-right size-3.5 transition-transform"
          :class="verConcluidos ? 'rotate-90' : ''"
        />
        {{ t('RAMON.POS_VENDA.CONCLUIDOS', { count: concluidos.length }) }}
      </button>
    </template>

    <span
      v-if="outrosFiltros"
      data-testid="faixa-outros-filtros"
      class="ms-auto flex items-center gap-1.5 text-n-slate-9"
    >
      {{ t('RAMON.FUNIL.OUTROS_FILTROS') }} —
      <button
        data-testid="faixa-limpar"
        class="text-n-blue-11 hover:underline"
        @click="emit('limparFiltros')"
      >
        {{ t('RAMON.FUNIL.LIMPAR_FILTROS') }}
      </button>
    </span>

    <ul
      v-if="verConcluidos && filtro === 'pos_venda'"
      class="w-full flex flex-wrap gap-x-5 gap-y-1"
    >
      <li
        v-for="item in concluidos"
        :key="item.id"
        data-testid="faixa-concluido"
      >
        <button
          class="inline-flex items-center gap-1.5 text-n-slate-12 hover:text-n-blue-11"
          @click="abrirLead(item.id)"
        >
          <span class="i-lucide-check-circle-2 size-3.5 text-n-teal-11" />
          {{ item.name }}
          <span
            v-if="item.drive_concluido"
            data-testid="faixa-drive"
            class="rounded-full bg-n-teal-9/15 px-2 py-0.5 font-mono text-[11px] text-n-teal-11"
          >
            {{ t('RAMON.POS_VENDA.DRIVE_CHIP') }}
          </span>
        </button>
      </li>
    </ul>

    <ConfirmModal
      v-if="campanhaAberta"
      :title="t('RAMON.RADAR.CAMPAIGN_MODAL_TITLE')"
      :message="
        t('RAMON.RADAR.CAMPAIGN_MODAL_MESSAGE', {
          n: consentidos,
          m: itens.length,
        })
      "
      :confirm-label="t('RAMON.RADAR.CAMPAIGN_MODAL_CONFIRM')"
      @confirm="irParaCampanhas"
      @cancel="campanhaAberta = false"
    />
  </div>
</template>

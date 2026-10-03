<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import RamonPrescriptionRadarAPI from 'dashboard/api/ramonPrescriptionRadar';
import { brlCompact, formatBrl } from '../helpers/currency';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import ConfirmModal from '../components/ConfirmModal.vue';

defineOptions({ name: 'RamonRadarPrescricao' });

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const data = ref(null);
const loading = ref(false);
const error = ref(false);
const showCampaignModal = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await RamonPrescriptionRadarAPI.get();
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const summary = computed(() => data.value?.summary ?? {});
const items = computed(() => data.value?.items ?? []);
const consentedCount = computed(
  () => items.value.filter(item => item.consent_marketing).length
);

const isBleeding = item => item.lost_installments > 0;
const isHot = item => item.pct_consumed > 0.75;
const barWidth = item => `${Math.round(Math.min(item.pct_consumed, 1) * 100)}%`;

const fmtDcb = value =>
  new Date(`${value}T00:00:00`).toLocaleDateString('pt-BR');

// Padrão das outras páginas: abre o Funil e seleciona o lead (drawer).
const openLead = id => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', id);
};

// Nada é disparado daqui — só navega pra tela de campanhas do Chatwoot;
// o guard LGPD real (consent_marketing) já vive no envio em massa.
const goToCampaigns = () => {
  showCampaignModal.value = false;
  router.push(accountScopedRoute('campaigns_whatsapp_index'));
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-y-auto bg-n-background p-4 sm:p-8"
  >
    <RamonPageHeader
      :title="t('RAMON.RADAR.TITLE')"
      :subtitle="t('RAMON.RADAR.SUBTITLE')"
    >
      <template #actions>
        <div v-if="items.length" class="flex flex-col items-end gap-1">
          <button
            data-testid="radar-campaign-cta"
            class="h-8 px-4 text-sm font-semibold rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
            @click="showCampaignModal = true"
          >
            {{ t('RAMON.RADAR.CAMPAIGN_CTA', { count: consentedCount }) }}
          </button>
          <span class="text-[11px] text-n-slate-10">
            {{
              t('RAMON.RADAR.CAMPAIGN_TOOLTIP', {
                n: consentedCount,
                m: items.length,
              })
            }}
          </span>
        </div>
      </template>
    </RamonPageHeader>

    <!-- Linha-resumo: sangramento (ruby) · em risco 90d (âmbar) -->
    <p
      v-if="data"
      data-testid="radar-summary"
      class="-mt-5 mb-5 text-sm text-n-slate-11"
    >
      <b class="font-semibold text-n-ruby-11">
        {{ brlCompact(summary.bleeding_monthly)
        }}{{ t('RAMON.RADAR.PER_MONTH') }}
      </b>
      {{ t('RAMON.RADAR.SUMMARY_BLEEDING', { count: summary.bleeding_count }) }}
      ·
      <b class="font-semibold text-n-amber-11">
        {{ brlCompact(summary.at_risk_90d_monthly)
        }}{{ t('RAMON.RADAR.PER_MONTH') }}
      </b>
      {{ t('RAMON.RADAR.SUMMARY_RISK') }}
    </p>

    <!-- Skeleton no primeiro load -->
    <div
      v-if="loading && !data"
      data-testid="radar-skeleton"
      class="flex flex-col gap-2 animate-pulse"
    >
      <div v-for="i in 5" :key="i" class="h-14 rounded-xl bg-n-solid-2" />
    </div>

    <!-- Erro com retry explícito -->
    <div v-else-if="error && !data" data-testid="radar-error" class="text-sm">
      <p class="text-n-ruby-11">{{ t('RAMON.RADAR.LOAD_ERROR') }}</p>
      <button
        type="button"
        data-testid="radar-retry"
        class="mt-2 text-xs text-n-iris-11 hover:underline"
        @click="fetchData"
      >
        {{ t('RAMON.RADAR.RETRY') }}
      </button>
    </div>

    <!-- Vazio -->
    <p
      v-else-if="data && !items.length"
      data-testid="radar-empty"
      class="text-sm text-n-slate-10"
    >
      {{ t('RAMON.RADAR.EMPTY') }}
    </p>

    <!-- Lista ordenada por sangramento (ordem vem do backend) -->
    <div v-else-if="data" class="flex flex-col gap-1.5 max-w-3xl">
      <button
        v-for="item in items"
        :key="item.lead_id"
        data-testid="radar-row"
        class="grid grid-cols-[1fr_120px_100px] items-center gap-2.5 px-3 py-2.5 text-left rounded-xl bg-n-solid-2 border border-n-weak border-l-[3px] hover:bg-n-alpha-2"
        :class="isBleeding(item) ? 'border-l-n-ruby-9' : 'border-l-n-amber-9'"
        @click="openLead(item.lead_id)"
      >
        <div class="min-w-0">
          <p class="text-sm font-medium truncate text-n-slate-12">
            {{ item.name }}
          </p>
          <p class="text-xs truncate text-n-slate-10">
            <template v-if="item.benefit_type_name">
              {{ item.benefit_type_name }} ·
            </template>
            {{ t('RAMON.RADAR.DCB', { date: fmtDcb(item.dcb_em) }) }} ·
            <b
              v-if="item.is_lost"
              data-testid="radar-lost-chip"
              class="font-semibold text-n-amber-11"
            >
              {{ t('RAMON.RADAR.LOST_CHIP') }}
            </b>
            <template v-else>{{ item.stage_name }}</template>
          </p>
        </div>
        <div class="h-1.5 rounded-full bg-n-alpha-2">
          <span
            class="block h-full rounded-full"
            :class="isHot(item) ? 'bg-n-ruby-9' : 'bg-n-amber-9'"
            :style="{ width: barWidth(item) }"
          />
        </div>
        <span
          class="text-xs font-semibold text-right tabular-nums"
          :class="isBleeding(item) ? 'text-n-ruby-11' : 'text-n-amber-11'"
        >
          <template v-if="item.monthly_value">
            {{ formatBrl(item.monthly_value) }}{{ t('RAMON.RADAR.PER_MONTH') }}
          </template>
          <template v-else>—</template>
        </span>
      </button>
    </div>

    <ConfirmModal
      v-if="showCampaignModal"
      :title="t('RAMON.RADAR.CAMPAIGN_MODAL_TITLE')"
      :message="
        t('RAMON.RADAR.CAMPAIGN_MODAL_MESSAGE', {
          n: consentedCount,
          m: items.length,
        })
      "
      :confirm-label="t('RAMON.RADAR.CAMPAIGN_MODAL_CONFIRM')"
      @confirm="goToCampaigns"
      @cancel="showCampaignModal = false"
    />
  </div>
</template>

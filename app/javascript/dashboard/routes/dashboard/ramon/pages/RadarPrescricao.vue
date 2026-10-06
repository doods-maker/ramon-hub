<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import RamonPrescriptionRadarAPI from 'dashboard/api/ramonPrescriptionRadar';
import Button from 'dashboard/components-next/button/Button.vue';
import { brlCompact, formatBrl } from '../helpers/currency';
import { prescriptionChip } from '../helpers/prescription';
import { CARTAO_STATUS, CHIP, FILETE, TOM } from '../helpers/ui';
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
// Campanha de resgate: só o gestor (a tela de campanhas é só de admin). A
// contagem vem da API sobre o radar inteiro, não só da lista.
const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const rescueCount = computed(() => summary.value.rescue_count ?? 0);
const totalCount = computed(
  () => summary.value.total_count ?? items.value.length
);
const tagging = ref(false);

const isBleeding = item => item.lost_installments > 0;
const isHot = item => item.pct_consumed > 0.75;
const barWidth = item => `${Math.round(Math.min(item.pct_consumed, 1) * 100)}%`;

// Mesma frase do card do funil e do painel do lead (KANBAN.CARD.PRESCRIPTION_*);
// no Radar o prazo aparece sempre, por longe que esteja.
const prescriptionLabel = item =>
  prescriptionChip(
    t,
    {
      lostInstallments: item.lost_installments,
      monthlyValue: item.monthly_value,
      monthsToCliff: item.months_to_cliff,
    },
    Infinity
  ).text;

const fmtDcb = value =>
  new Date(`${value}T00:00:00`).toLocaleDateString('pt-BR');

// Padrão das outras páginas: abre o Funil e seleciona o lead (drawer).
const openLead = id => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', id);
};

// O servidor etiqueta os contatos (resgate-prescricao) e a gente abre a tela
// de campanhas — nada é criado nem enviado daqui: quem monta e envia é o gestor.
const goToCampaigns = async () => {
  if (tagging.value) return;
  tagging.value = true;
  try {
    const { data: result } = await RamonPrescriptionRadarAPI.resgate();
    showCampaignModal.value = false;
    useAlert(t('RAMON.RADAR.CAMPAIGN_DONE', { n: result.count }));
    router.push(accountScopedRoute('campaigns_whatsapp_index'));
  } catch (e) {
    useAlert(t('RAMON.RADAR.CAMPAIGN_ERROR'));
  } finally {
    tagging.value = false;
  }
};
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <RamonPageHeader
        class="!mb-0"
        :title="t('RAMON.RADAR.TITLE')"
        :subtitle="t('RAMON.RADAR.SUBTITLE')"
      >
        <template #actions>
          <div
            v-if="isAdmin && items.length"
            class="flex flex-col items-end gap-1"
          >
            <Button
              data-testid="radar-campaign-cta"
              sm
              icon="i-lucide-megaphone"
              :label="t('RAMON.RADAR.CAMPAIGN_CTA', { count: rescueCount })"
              @click="showCampaignModal = true"
            />
            <span class="text-[11px] text-n-slate-10">
              {{
                t('RAMON.RADAR.CAMPAIGN_TOOLTIP', {
                  n: rescueCount,
                  m: totalCount,
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
        class="m-0 text-sm text-n-slate-11"
      >
        <b class="font-mono font-medium tabular-nums text-n-ruby-11">
          {{ brlCompact(summary.bleeding_monthly)
          }}{{ t('RAMON.RADAR.PER_MONTH') }}
        </b>
        {{
          t('RAMON.RADAR.SUMMARY_BLEEDING', { count: summary.bleeding_count })
        }}
        ·
        <b class="font-mono font-medium tabular-nums text-n-amber-11">
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
        <div v-for="i in 5" :key="i" class="h-14 rounded-xl bg-n-alpha-2" />
      </div>

      <!-- Erro com retry explícito -->
      <div
        v-else-if="error && !data"
        data-testid="radar-error"
        class="flex flex-col items-start gap-1 text-sm"
      >
        <p class="m-0 text-n-ruby-11">{{ t('RAMON.RADAR.LOAD_ERROR') }}</p>
        <Button
          data-testid="radar-retry"
          link
          xs
          :label="t('RAMON.RADAR.RETRY')"
          @click="fetchData"
        />
      </div>

      <!-- Vazio -->
      <p
        v-else-if="data && !items.length"
        data-testid="radar-empty"
        class="m-0 text-sm text-n-slate-10"
      >
        {{ t('RAMON.RADAR.EMPTY') }}
      </p>

      <!-- Lista ordenada por sangramento (ordem vem do backend) -->
      <div v-else-if="data" class="flex flex-col gap-2">
        <button
          v-for="item in items"
          :key="item.lead_id"
          type="button"
          data-testid="radar-row"
          class="grid grid-cols-[minmax(0,1fr)_96px_210px] items-center gap-3 border-solid text-left hover:bg-n-alpha-2"
          :class="[
            CARTAO_STATUS,
            isBleeding(item) ? FILETE.ruby : FILETE.amber,
          ]"
          @click="openLead(item.lead_id)"
        >
          <div class="min-w-0">
            <p class="m-0 text-sm font-medium truncate text-n-slate-12">
              {{ item.name }}
            </p>
            <p class="m-0 mt-0.5 text-xs truncate text-n-slate-10">
              <template v-if="item.benefit_type_name">
                {{ item.benefit_type_name }} ·
              </template>
              {{ t('RAMON.RADAR.DCB', { date: fmtDcb(item.dcb_em) }) }} ·
              <span
                v-if="item.is_lost"
                data-testid="radar-lost-chip"
                :class="[CHIP, TOM.amber]"
              >
                {{ t('RAMON.RADAR.LOST_CHIP') }}
              </span>
              <span
                v-else-if="item.is_client"
                data-testid="radar-client-chip"
                :class="[CHIP, TOM.blue]"
              >
                {{ t('RAMON.RADAR.CLIENT_CHIP') }}
              </span>
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
          <div class="flex flex-col items-end gap-0.5">
            <span
              data-testid="radar-prescription"
              class="whitespace-nowrap"
              :class="[CHIP, isBleeding(item) ? TOM.ruby : TOM.amber]"
            >
              {{ prescriptionLabel(item) }}
            </span>
            <span
              v-if="!isBleeding(item) && item.monthly_value"
              class="font-mono text-[11px] tabular-nums text-n-slate-10"
            >
              {{ formatBrl(item.monthly_value)
              }}{{ t('RAMON.RADAR.PER_MONTH') }}
            </span>
          </div>
        </button>
      </div>
    </div>

    <ConfirmModal
      v-if="showCampaignModal"
      :title="t('RAMON.RADAR.CAMPAIGN_MODAL_TITLE')"
      :message="
        t('RAMON.RADAR.CAMPAIGN_MODAL_MESSAGE', {
          n: rescueCount,
          m: totalCount,
        })
      "
      :confirm-label="t('RAMON.RADAR.CAMPAIGN_MODAL_CONFIRM')"
      confirm-color="blue"
      @confirm="goToCampaigns"
      @cancel="showCampaignModal = false"
    />
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import RamonPosVendaAPI from 'dashboard/api/ramonPosVenda';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import { prescriptionChip, prescriptionInfo } from '../helpers/prescription';
import { docChargeDraft } from '../helpers/docCobranca';
import {
  CARTAO,
  CARTAO_STATUS,
  CHIP,
  FILETE,
  LINHA,
  TITULO,
  TOM,
} from '../helpers/ui';

defineOptions({ name: 'RamonPosVenda' });

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const data = ref(null);
const loading = ref(false);
const error = ref(false);
const showConcluidos = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await RamonPosVendaAPI.get();
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const pendentes = computed(() => data.value?.pendentes ?? []);
const concluidos = computed(() => data.value?.concluidos ?? []);
// Ganho sem tese: sem checklist não há docs a cobrar nem contrato limpo.
const semTese = computed(() => data.value?.sem_tese ?? []);
// A lista traz só os mais recentes; o total real vem à parte.
const concluidosTotal = computed(
  () => data.value?.concluidos_total ?? concluidos.value.length
);

// Mesma frase de prescrição do painel do lead (helpers/prescription).
const prescricao = item => prescriptionChip(t, prescriptionInfo(item));

// Padrão das outras páginas: abre o Funil e seleciona o lead (drawer).
const openLead = id => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/select', id);
};

// Abrir conversa (padrão do fork: funil + dock).
const openConversation = conversationId => {
  router.push(accountScopedRoute('ramon_funil'));
  store.dispatch('leads/toggleDock', conversationId);
};

// "Cobrar pendentes" — o mesmo do painel do lead (DocChecklist): monta o
// rascunho e marca os pendentes como solicitados. Com conversa, o texto cai no
// campo de resposta (rascunho do ReplyBox, como o "Rascunho da IA" do Centro) e
// abre o dock; sem conversa, vai pra área de transferência. Nada é enviado.
const cobrando = ref(null);
const statusChip = doc => (doc.status === 'solicitado' ? TOM.blue : TOM.amber);
const cobrar = async item => {
  const docs = item.docs_pendentes || [];
  if (!docs.length || cobrando.value) return;
  cobrando.value = item.id;
  const draft = docChargeDraft(
    t,
    item.lead_name,
    docs.map(doc => doc.title)
  );
  try {
    if (item.conversation_id) {
      await store.dispatch('draftMessages/set', {
        key: `draft-${item.conversation_id}-REPLY`,
        message: draft,
      });
      openConversation(item.conversation_id);
      useAlert(t('RAMON.DOCS.DRAFT_READY'));
    } else {
      try {
        await copyTextToClipboard(draft);
      } catch (e) {
        useAlert(t('RAMON.DOCS.COPY_FAILED'));
        return;
      }
      useAlert(t('RAMON.DOCS.COPIED'));
    }
    const pendentesAgora = docs.filter(doc => doc.status === 'pendente');
    if (!pendentesAgora.length) return;
    try {
      await LeadsAPI.update(item.id, {
        custom_attributes: {
          doc_status: Object.fromEntries(
            pendentesAgora.map(doc => [doc.id, 'solicitado'])
          ),
        },
      });
      fetchData();
    } catch (e) {
      useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    }
  } finally {
    cobrando.value = null;
  }
};
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <RamonPageHeader
        class="!mb-0"
        :title="t('RAMON.POS_VENDA.TITLE')"
        :subtitle="t('RAMON.POS_VENDA.SUBTITLE')"
      />

      <!-- Skeleton no primeiro load -->
      <div
        v-if="loading && !data"
        data-testid="pos-venda-skeleton"
        class="flex flex-col gap-2 animate-pulse"
      >
        <div v-for="i in 5" :key="i" class="h-14 rounded-xl bg-n-alpha-2" />
      </div>

      <!-- Erro com retry explícito -->
      <div
        v-else-if="error && !data"
        data-testid="pos-venda-error"
        class="flex flex-col items-start gap-1 text-sm"
      >
        <p class="m-0 text-n-ruby-11">{{ t('RAMON.POS_VENDA.ERROR') }}</p>
        <Button
          data-testid="pos-venda-retry"
          link
          xs
          :label="t('RAMON.POS_VENDA.RETRY')"
          @click="fetchData"
        />
      </div>

      <template v-else-if="data">
        <!-- Ganhos sem tese: pedem a tese antes de tudo -->
        <section
          v-if="semTese.length"
          data-testid="pos-venda-sem-tese"
          class="flex flex-col gap-2"
          :class="[CARTAO_STATUS, FILETE.amber]"
        >
          <div>
            <p class="m-0" :class="TITULO">
              {{ t('RAMON.POS_VENDA.SEM_TESE', { count: semTese.length }) }}
            </p>
            <p class="m-0 mt-0.5 text-xs text-n-slate-10">
              {{ t('RAMON.POS_VENDA.SEM_TESE_HINT') }}
            </p>
          </div>
          <ul class="m-0 flex list-none flex-col p-0">
            <li v-for="item in semTese" :key="item.id">
              <button
                type="button"
                data-testid="pos-venda-sem-tese-row"
                class="flex items-center justify-between gap-3"
                :class="LINHA"
                @click="openLead(item.id)"
              >
                <span class="truncate text-n-slate-12">{{ item.name }}</span>
                <span class="shrink-0 text-xs text-n-slate-10">
                  {{ t('RAMON.POS_VENDA.DIAS', { dias: item.dias }) }}
                </span>
              </button>
            </li>
          </ul>
        </section>

        <!-- Vazio -->
        <p
          v-if="!pendentes.length"
          data-testid="pos-venda-empty"
          class="m-0 text-sm text-n-slate-10"
        >
          {{ t('RAMON.POS_VENDA.EMPTY') }}
        </p>

        <!-- Pendentes: mais urgentes na prescrição primeiro (ordem do backend) -->
        <div v-else class="flex flex-col gap-2">
          <div
            v-for="item in pendentes"
            :key="item.id"
            data-testid="pos-venda-row"
            class="flex items-center justify-between gap-3 cursor-pointer hover:bg-n-alpha-2"
            :class="[
              CARTAO_STATUS,
              item.dias > 7 ? FILETE.amber : 'border-l-n-weak',
            ]"
            @click="openLead(item.id)"
          >
            <div class="min-w-0 flex-1">
              <p class="m-0 text-sm font-medium truncate text-n-slate-12">
                {{ item.name }}
              </p>
              <p class="m-0 mt-0.5 text-xs truncate text-n-slate-10">
                {{ t('RAMON.POS_VENDA.DIAS', { dias: item.dias }) }} ·
                {{
                  t('RAMON.POS_VENDA.DOCS', {
                    received: item.docs_received,
                    total: item.docs_total,
                  })
                }}
              </p>
              <!-- O que falta: mesmas cores do checklist do painel -->
              <ul
                v-if="item.docs_pendentes?.length"
                data-testid="pos-venda-docs-pendentes"
                class="m-0 mt-1.5 flex list-none flex-wrap gap-1 p-0"
              >
                <li
                  v-for="doc in item.docs_pendentes"
                  :key="doc.id"
                  :class="[CHIP, statusChip(doc)]"
                  :title="t(`RAMON.DOCS.STATUS.${doc.status.toUpperCase()}`)"
                >
                  {{ doc.title }}
                </li>
              </ul>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <span
                v-if="prescricao(item)"
                data-testid="pos-venda-prescription"
                class="whitespace-nowrap"
                :class="[
                  CHIP,
                  prescricao(item).bleeding ? TOM.ruby : TOM.amber,
                ]"
              >
                {{ prescricao(item).text }}
              </span>
              <Button
                v-if="item.docs_pendentes?.length"
                data-testid="pos-venda-cobrar"
                xs
                faded
                slate
                icon="i-lucide-file-text"
                :label="t('RAMON.DOCS.CHARGE')"
                :is-loading="cobrando === item.id"
                @click.stop="cobrar(item)"
              />
              <Button
                v-if="item.conversation_id"
                data-testid="pos-venda-open-conversation"
                xs
                faded
                slate
                icon="i-lucide-message-circle"
                :label="t('RAMON.POS_VENDA.OPEN_CONVERSATION')"
                @click.stop="openConversation(item.conversation_id)"
              />
            </div>
          </div>
        </div>

        <!-- Concluídos: colapsado por padrão -->
        <div v-if="concluidos.length" class="flex flex-col gap-2">
          <button
            type="button"
            data-testid="pos-venda-toggle-concluidos"
            class="flex items-center gap-1.5 self-start text-sm font-medium text-n-slate-11 hover:text-n-slate-12"
            @click="showConcluidos = !showConcluidos"
          >
            <span
              class="i-lucide-chevron-right size-4 transition-transform"
              :class="showConcluidos ? 'rotate-90' : ''"
            />
            {{ t('RAMON.POS_VENDA.CONCLUIDOS', { count: concluidosTotal }) }}
          </button>
          <p
            v-if="showConcluidos && concluidosTotal > concluidos.length"
            data-testid="pos-venda-concluidos-recentes"
            class="m-0 text-xs text-n-slate-10"
          >
            {{
              t('RAMON.POS_VENDA.CONCLUIDOS_RECENTES', {
                count: concluidos.length,
              })
            }}
          </p>

          <template v-if="showConcluidos">
            <div
              v-for="item in concluidos"
              :key="item.id"
              data-testid="pos-venda-row-concluido"
              class="flex items-center justify-between gap-3 cursor-pointer hover:bg-n-alpha-2"
              :class="CARTAO"
              @click="openLead(item.id)"
            >
              <div class="flex items-center gap-2 min-w-0">
                <span
                  class="i-lucide-check-circle-2 size-4 shrink-0 text-n-teal-11"
                />
                <p class="m-0 text-sm font-medium truncate text-n-slate-12">
                  {{ item.name }}
                </p>
              </div>
              <span
                v-if="item.drive_concluido"
                data-testid="pos-venda-drive-chip"
                class="shrink-0"
                :class="[CHIP, TOM.teal]"
              >
                {{ t('RAMON.POS_VENDA.DRIVE_CHIP') }}
              </span>
            </div>
          </template>
        </div>
      </template>
    </div>
  </div>
</template>

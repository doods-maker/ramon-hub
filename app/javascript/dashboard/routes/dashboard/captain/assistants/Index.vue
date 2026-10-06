<script setup>
// Tela Assistentes (I-AS1/I-AS2/I-AS3): um cartão por assistente real — pra
// quem fala, skills, FAQs, caixas conectadas (antes item do menu) e, pra quem
// fala com o lead, o modo das conversas (só leitura). Atalhos levam às telas.
import { computed, nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import Button from 'dashboard/components-next/button/Button.vue';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import CaptainPaywall from 'dashboard/components-next/captain/pageComponents/Paywall.vue';
import CreateAssistantDialog from 'dashboard/components-next/captain/pageComponents/assistant/CreateAssistantDialog.vue';
import AssistantPageEmptyState from 'dashboard/components-next/captain/pageComponents/emptyStates/AssistantPageEmptyState.vue';
import {
  AVISO,
  CARTAO,
  CHIP,
  SECAO,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import {
  MODOS,
  modoDefault,
} from 'dashboard/routes/dashboard/ramon/helpers/copilotoModo';

const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();

const cartoes = ref([]);
const loading = ref(true);
const error = ref(false);
const dialogType = ref('');
const createAssistantDialog = ref(null);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await CaptainAssistantAPI.stats();
    cartoes.value = response.data.payload;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const isEmpty = computed(
  () => !loading.value && !error.value && !cartoes.value.length
);

// rascunho = azul (nada sai sem humano); piloto = âmbar/vermelho (a IA envia).
const MODO_TOM = {
  manual: TOM.slate,
  rascunho: TOM.blue,
  piloto_limitado: TOM.amber,
  piloto_total: TOM.ruby,
};
const modoNome = modo => t(`RAMON.COPILOTO.MODOS.${modo}.NOME`);
const modosDe = cartao =>
  MODOS.filter(modo => cartao.conversas_por_modo[modo]).map(modo => ({
    modo,
    n: cartao.conversas_por_modo[modo],
  }));

const ATALHOS = [
  {
    rota: 'captain_assistants_scenarios_index',
    rotulo: 'SKILLS',
    icone: 'i-lucide-list-checks',
  },
  {
    rota: 'captain_assistants_responses_index',
    rotulo: 'FAQS',
    icone: 'i-lucide-messages-square',
  },
  {
    rota: 'captain_assistants_playground_index',
    rotulo: 'TESTAR',
    icone: 'i-lucide-play',
  },
  {
    rota: 'captain_assistants_settings_index',
    rotulo: 'CONFIGURAR',
    icone: 'i-lucide-settings',
  },
];
const abrir = (name, assistantId) =>
  router.push(accountScopedRoute(name, { assistantId }));

const handleCreate = () => {
  dialogType.value = 'create';
  nextTick(() => createAssistantDialog.value.dialogRef.open());
};
const handleCreateClose = () => {
  dialogType.value = '';
};
const handleAfterCreate = newAssistant => {
  if (newAssistant?.id)
    abrir('captain_assistants_responses_index', newAssistant.id);
};
</script>

<template>
  <PageLayout
    :header-title="$t('CAPTAIN.ASSISTANTS.HEADER')"
    :button-label="$t('CAPTAIN.ASSISTANTS.ADD_NEW')"
    :button-policy="['administrator']"
    :show-assistant-switcher="false"
    :show-pagination-footer="false"
    :is-fetching="loading"
    :is-empty="isEmpty"
    :feature-flag="FEATURE_FLAGS.CAPTAIN"
    @click="handleCreate"
  >
    <template #emptyState>
      <AssistantPageEmptyState @click="handleCreate" />
    </template>

    <template #paywall>
      <CaptainPaywall />
    </template>

    <template #body>
      <div
        v-if="error"
        data-testid="assistentes-error"
        :class="[AVISO, TOM.ruby]"
      >
        {{ t('CAPTAIN_RAMON.LOAD_ERROR') }}
        <button type="button" class="ml-1 underline" @click="fetchData">
          {{ t('CAPTAIN_RAMON.RETRY') }}
        </button>
      </div>
      <div v-else class="grid gap-3 lg:grid-cols-2">
        <article
          v-for="cartao in cartoes"
          :key="cartao.id"
          data-testid="assistente-cartao"
          :class="CARTAO"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <h2 class="text-base font-medium text-n-slate-12">
                {{ cartao.name }}
              </h2>
              <p class="mt-0.5 text-sm text-n-slate-11">
                {{ cartao.description }}
              </p>
            </div>
            <span
              :class="[CHIP, cartao.publico === 'lead' ? TOM.blue : TOM.slate]"
            >
              {{ t(`CAPTAIN_RAMON.ASSISTENTES.PUBLICO.${cartao.publico}`) }}
            </span>
          </div>

          <div class="flex flex-wrap gap-1.5 mt-3">
            <span :class="[CHIP, TOM.slate]">
              {{
                t('CAPTAIN_RAMON.ASSISTENTES.SKILLS', {
                  n: cartao.skills_ativas,
                })
              }}
            </span>
            <span :class="[CHIP, TOM.slate]">
              {{
                t('CAPTAIN_RAMON.ASSISTENTES.FAQS', {
                  n: cartao.faqs_aprovadas,
                })
              }}
            </span>
            <span v-if="cartao.faqs_pendentes" :class="[CHIP, TOM.amber]">
              {{
                t('CAPTAIN_RAMON.ASSISTENTES.FAQS_PENDENTES', {
                  n: cartao.faqs_pendentes,
                })
              }}
            </span>
            <span :class="[CHIP, TOM.slate]">
              {{
                t('CAPTAIN_RAMON.ASSISTENTES.CAIXAS_N', {
                  n: cartao.caixas.length,
                })
              }}
            </span>
          </div>

          <div v-if="cartao.publico === 'lead'" class="mt-3" :class="[SECAO]">
            <p :class="TITULO">
              {{ t('CAPTAIN_RAMON.ASSISTENTES.MODO.TITULO') }}
            </p>
            <p class="mt-1 text-sm text-n-slate-12">
              {{
                t('CAPTAIN_RAMON.ASSISTENTES.MODO.PADRAO', {
                  modo: modoNome(modoDefault()),
                })
              }}
            </p>
            <div class="flex flex-wrap gap-1.5 mt-2">
              <span
                v-for="item in modosDe(cartao)"
                :key="item.modo"
                :class="[CHIP, MODO_TOM[item.modo]]"
              >
                {{
                  t('CAPTAIN_RAMON.ASSISTENTES.MODO.CONTAGEM', {
                    modo: modoNome(item.modo),
                    n: item.n,
                  })
                }}
              </span>
              <span
                v-if="!modosDe(cartao).length"
                class="text-xs text-n-slate-10"
              >
                {{ t('CAPTAIN_RAMON.ASSISTENTES.MODO.SEM_CONVERSAS') }}
              </span>
            </div>
            <p class="mt-2 text-xs text-n-slate-10">
              {{ t('CAPTAIN_RAMON.ASSISTENTES.MODO.SO_LEITURA') }}
            </p>
          </div>

          <div class="mt-3" :class="[SECAO]" data-testid="assistente-caixas">
            <p :class="TITULO">
              {{ t('CAPTAIN_RAMON.ASSISTENTES.CAIXAS.TITULO') }}
            </p>
            <div
              v-if="cartao.caixas.length"
              class="flex flex-wrap gap-1.5 mt-1"
            >
              <span
                v-for="caixa in cartao.caixas"
                :key="caixa.id"
                :class="[CHIP, TOM.blue]"
              >
                {{ caixa.name }}
              </span>
            </div>
            <p v-else class="mt-1 text-xs text-n-slate-10">
              {{ t('CAPTAIN_RAMON.ASSISTENTES.CAIXAS.NENHUMA') }}
            </p>
            <Button
              class="mt-2"
              size="xs"
              variant="ghost"
              color="slate"
              icon="i-lucide-inbox"
              :label="t('CAPTAIN_RAMON.ASSISTENTES.CAIXAS.GERENCIAR')"
              @click="abrir('captain_assistants_inboxes_index', cartao.id)"
            />
          </div>

          <div class="mt-3 flex flex-wrap gap-2" :class="[SECAO]">
            <Button
              v-for="atalho in ATALHOS"
              :key="atalho.rota"
              size="xs"
              variant="faded"
              color="slate"
              :icon="atalho.icone"
              :label="t(`CAPTAIN_RAMON.ASSISTENTES.ATALHOS.${atalho.rotulo}`)"
              @click="abrir(atalho.rota, cartao.id)"
            />
          </div>
        </article>
      </div>
    </template>

    <CreateAssistantDialog
      v-if="dialogType"
      ref="createAssistantDialog"
      :type="dialogType"
      @close="handleCreateClose"
      @created="handleAfterCreate"
    />
  </PageLayout>
</template>

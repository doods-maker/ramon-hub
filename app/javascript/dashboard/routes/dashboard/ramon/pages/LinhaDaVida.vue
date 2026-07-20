<script setup>
import { ref, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import LinhaDaVidaAPI from 'dashboard/api/linhaDaVida';
import ContactAPI from 'dashboard/api/contacts';
import { formatCpf } from '../helpers/cpf';
import { formatBrl } from '../helpers/currency';
import { frontendURL } from '../../../../helper/URLHelper';
import RamonPageHeader from '../components/RamonPageHeader.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const data = ref(null);
const loading = ref(false);
const error = ref(false);

const fetchData = async () => {
  // Sem contactId a página está no modo busca (entrada pelo menu).
  if (!route.params.contactId) {
    data.value = null;
    return;
  }
  loading.value = true;
  error.value = false;
  try {
    const response = await LinhaDaVidaAPI.show(route.params.contactId);
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

watch(() => route.params.contactId, fetchData, { immediate: true });

// ---- modo busca (rota sem contactId): achar a pessoa pela busca de contatos
const query = ref('');
const results = ref([]);
const searching = ref(false);
let searchTimer = null;
let searchAbort = null;
watch(query, value => {
  clearTimeout(searchTimer);
  const term = value.trim();
  if (term.length < 2) {
    searchAbort?.abort();
    results.value = [];
    searching.value = false;
    return;
  }
  searchTimer = setTimeout(async () => {
    // Aborta a request anterior: resposta velha não sobrescreve a atual.
    searchAbort?.abort();
    const controller = new AbortController();
    searchAbort = controller;
    searching.value = true;
    try {
      // encodeURIComponent: telefone com "+" (e termos com &/#) chegam
      // intactos na query — o endpoint recebe o termo cru interpolado.
      const { data: resp } = await ContactAPI.search(
        encodeURIComponent(term),
        1,
        'name',
        '',
        { signal: controller.signal }
      );
      results.value = resp.payload || [];
    } catch (e) {
      if (!controller.signal.aborted) results.value = [];
    } finally {
      if (searchAbort === controller) searching.value = false;
    }
  }, 300);
});

const openPessoa = contact =>
  router.push({
    name: 'ramon_linha_da_vida',
    params: { contactId: contact.id },
  });

const contact = computed(() => data.value?.contact ?? null);
const leads = computed(() => data.value?.leads ?? []);

const fmtDate = value => {
  if (!value) return '';
  // Prescrição chega como Date (addMonths); marcos/DCB chegam string ISO.
  if (value instanceof Date) return value.toLocaleDateString('pt-BR');
  return new Date(`${String(value).slice(0, 10)}T12:00:00`).toLocaleDateString(
    'pt-BR'
  );
};

// Subtítulo do cabeçalho: CPF · nascimento · telefone (só o que existir).
const headerSubtitle = computed(() => {
  const c = contact.value;
  if (!c) return '';
  const parts = [];
  if (c.cpf) parts.push(formatCpf(c.cpf));
  if (c.data_nascimento)
    parts.push(
      `${t('RAMON.LINHA_DA_VIDA.BORN_AT')} ${fmtDate(c.data_nascimento)}`
    );
  if (c.phone_number) parts.push(c.phone_number);
  return parts.join(' · ');
});

// Presente = casos vivos no funil; passado = fechados (ganhos e perdidos).
const openLeads = computed(() =>
  leads.value.filter(l => !l.is_won && !l.is_lost)
);
const closedLeads = computed(() =>
  leads.value
    .filter(l => l.is_won || l.is_lost)
    .sort(
      (a, b) =>
        new Date(b.won_at || b.lost_at) - new Date(a.won_at || a.lost_at)
    )
);

// Futuro = marcos etários não atingidos + DCBs futuras + início da prescrição
// (DCB + 60 meses: quando a pessoa começa a perder parcelas), ordenado por data.
const addMonths = (dateStr, months) => {
  const d = new Date(`${String(dateStr).slice(0, 10)}T12:00:00`);
  d.setMonth(d.getMonth() + months);
  return d;
};

const futureItems = computed(() => {
  const now = new Date();
  const marcos = (data.value?.marcos ?? [])
    .filter(m => !m.atingido)
    .map(m => ({ type: 'marco', date: m.data, marco: m }));
  const dcbs = leads.value
    .filter(l => l.dcb_em && new Date(l.dcb_em) >= now)
    .map(l => ({ type: 'dcb', date: l.dcb_em, lead: l }));
  const prescricoes = leads.value
    .filter(l => l.dcb_em && addMonths(l.dcb_em, 60) >= now)
    .map(l => ({ type: 'prescricao', date: addMonths(l.dcb_em, 60), lead: l }));
  return [...marcos, ...dcbs, ...prescricoes].sort(
    (a, b) => new Date(a.date) - new Date(b.date)
  );
});

const conversationUrl = lead =>
  frontendURL(
    `accounts/${route.params.accountId}/conversations/${lead.conversation_id}`
  );
</script>

<template>
  <div class="flex-1 w-full h-full p-4 sm:p-8 overflow-y-auto bg-n-background">
    <!-- Modo busca: rota sem contactId (entrada "Linha da Vida" do menu) -->
    <template v-if="!route.params.contactId">
      <RamonPageHeader
        :title="$t('RAMON.LINHA_DA_VIDA.TITLE')"
        :subtitle="$t('RAMON.LINHA_DA_VIDA.SEARCH_HINT')"
      />
      <div class="max-w-xl">
        <input
          v-model="query"
          data-testid="pessoa-search"
          class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          :placeholder="$t('RAMON.LINHA_DA_VIDA.SEARCH_PLACEHOLDER')"
        />
        <p v-if="searching" class="mt-3 text-sm text-n-slate-10">
          {{ $t('RAMON.LINHA_DA_VIDA.SEARCHING') }}
        </p>
        <ul
          v-else-if="results.length"
          class="mt-3 rounded-lg border border-n-weak divide-y divide-n-weak"
        >
          <li v-for="c in results" :key="c.id">
            <button
              data-testid="pessoa-result"
              class="flex items-center justify-between w-full gap-3 px-3 py-2 text-left hover:bg-n-alpha-2"
              @click="openPessoa(c)"
            >
              <span class="text-sm truncate text-n-slate-12">
                {{ c.name }}
              </span>
              <span class="text-xs shrink-0 text-n-slate-10">
                {{ c.phone_number || c.email || '' }}
              </span>
            </button>
          </li>
        </ul>
        <p
          v-else-if="query.trim().length >= 2"
          class="mt-3 text-sm text-n-slate-10"
        >
          {{ $t('RAMON.LINHA_DA_VIDA.SEARCH_EMPTY') }}
        </p>
      </div>
    </template>
    <div
      v-else-if="loading"
      class="flex flex-col max-w-2xl gap-4 animate-pulse"
      data-testid="lifeline-skeleton"
    >
      <div class="w-1/3 h-8 rounded bg-n-solid-2" />
      <div class="h-24 rounded-xl bg-n-solid-2" />
      <div class="h-24 rounded-xl bg-n-solid-2" />
      <div class="h-40 rounded-xl bg-n-solid-2" />
    </div>
    <div v-else-if="error" class="flex items-center gap-3">
      <p class="text-sm text-n-ruby-11">
        {{ $t('RAMON.LINHA_DA_VIDA.ERROR') }}
      </p>
      <button
        data-testid="lifeline-retry"
        class="text-sm text-n-iris-11 hover:underline"
        @click="fetchData"
      >
        {{ $t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <template v-else-if="contact">
      <RamonPageHeader :title="contact.name" :subtitle="headerSubtitle" />
      <p
        v-if="!contact.data_nascimento"
        data-testid="lifeline-no-birthdate"
        class="-mt-4 mb-6 text-xs text-n-amber-11"
      >
        {{ $t('RAMON.LINHA_DA_VIDA.NO_BIRTHDATE_HINT') }}
      </p>

      <!-- FUTURO -->
      <section class="mb-8" data-testid="lifeline-future">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.FUTURE') }}
        </h2>
        <p v-if="!futureItems.length" class="text-sm text-n-slate-10">
          {{ $t('RAMON.LINHA_DA_VIDA.FUTURE_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-2">
          <li
            v-for="(item, i) in futureItems"
            :key="i"
            class="flex items-baseline gap-3 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <span class="text-xs tabular-nums text-n-slate-10 shrink-0">
              {{ fmtDate(item.date) }}
            </span>
            <template v-if="item.type === 'marco'">
              <span class="text-sm text-n-slate-12">
                {{ $t(`RAMON.LINHA_DA_VIDA.MARCOS.${item.marco.key}`) }}
                ({{ item.marco.idade }}
                <template v-if="item.marco.sexo">
                  ·
                  {{
                    item.marco.sexo === 'M'
                      ? $t('RAMON.DRAWER.PESSOA.SEX_M')
                      : $t('RAMON.DRAWER.PESSOA.SEX_F')
                  }}</template
                >)
              </span>
            </template>
            <template v-else-if="item.type === 'dcb'">
              <span class="text-sm text-n-slate-12">
                {{ $t('RAMON.LINHA_DA_VIDA.DCB_OF', { name: item.lead.name }) }}
              </span>
            </template>
            <template v-else>
              <span class="text-sm text-n-slate-12">
                {{
                  $t('RAMON.LINHA_DA_VIDA.PRESCRIPTION_OF', {
                    name: item.lead.name,
                  })
                }}
              </span>
            </template>
          </li>
        </ul>
        <p class="mt-2 text-xs text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.DISCLAIMER') }}
        </p>
      </section>

      <!-- PRESENTE -->
      <section class="mb-8" data-testid="lifeline-present">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.PRESENT') }}
        </h2>
        <p v-if="!openLeads.length" class="text-sm text-n-slate-10">
          {{ $t('RAMON.LINHA_DA_VIDA.PRESENT_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-2">
          <li
            v-for="lead in openLeads"
            :key="lead.id"
            class="p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-sm text-n-slate-12">{{ lead.name }}</span>
              <span
                class="px-2 py-0.5 text-xs rounded-full shrink-0"
                :class="
                  lead.stage_color
                    ? 'text-white'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
                :style="
                  lead.stage_color
                    ? { backgroundColor: lead.stage_color }
                    : undefined
                "
              >
                {{ lead.stage_name }}
              </span>
            </div>
            <p class="text-xs text-n-slate-10">
              <span v-if="lead.benefit_type_name"
                >{{ lead.benefit_type_name }} ·
              </span>
              <span v-if="lead.thesis_name">{{ lead.thesis_name }} · </span>
              <span v-if="lead.value">{{ formatBrl(lead.value) }}</span>
            </p>
            <router-link
              v-if="lead.conversation_id"
              :to="conversationUrl(lead)"
              class="text-xs text-n-iris-11 hover:underline"
            >
              {{ $t('RAMON.FUNIL.OPEN_CONVERSATION') }}
            </router-link>
            <router-link
              data-testid="lifeline-dossie-link"
              :to="{ name: 'ramon_lead_dossie', params: { leadId: lead.id } }"
              class="ml-3 text-xs text-n-iris-11 hover:underline"
            >
              {{ $t('RAMON.DOSSIE.OPEN') }}
            </router-link>
          </li>
        </ul>
      </section>

      <!-- PASSADO -->
      <section class="mb-8" data-testid="lifeline-past">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.PAST') }}
        </h2>
        <p v-if="!closedLeads.length" class="text-sm text-n-slate-10">
          {{ $t('RAMON.LINHA_DA_VIDA.PAST_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-2">
          <li
            v-for="lead in closedLeads"
            :key="lead.id"
            class="flex items-baseline gap-3 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <span class="text-xs tabular-nums text-n-slate-10 shrink-0">
              {{ fmtDate(lead.won_at || lead.lost_at) }}
            </span>
            <div>
              <span class="text-sm text-n-slate-12">{{ lead.name }}</span>
              <span
                class="ml-2 text-xs"
                :class="lead.is_won ? 'text-n-teal-11' : 'text-n-ruby-11'"
              >
                {{
                  lead.is_won
                    ? $t('RAMON.LINHA_DA_VIDA.WON')
                    : $t('RAMON.LINHA_DA_VIDA.LOST')
                }}
              </span>
              <p class="text-xs text-n-slate-10">
                <span v-if="lead.benefit_type_name"
                  >{{ lead.benefit_type_name }} ·
                </span>
                <span v-if="lead.value">{{ formatBrl(lead.value) }}</span>
                <span v-if="lead.lost_reason"> · {{ lead.lost_reason }}</span>
              </p>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>

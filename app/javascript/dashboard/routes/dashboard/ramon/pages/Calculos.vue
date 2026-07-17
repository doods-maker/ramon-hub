<script setup>
import { ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ContactAPI from 'dashboard/api/contacts';
import LeadsAPI from 'dashboard/api/leads';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import LeadSimulador from '../components/conversation/LeadSimulador.vue';

const route = useRoute();
const router = useRouter();

// ---- deep-link (rota com leadId): carrega o lead direto, sem passar pela busca
const lead = ref(null);
const loadingLead = ref(false);
const errorLead = ref(false);

const fetchLead = async () => {
  if (!route.params.leadId) {
    lead.value = null;
    return;
  }
  loadingLead.value = true;
  errorLead.value = false;
  try {
    const { data } = await LeadsAPI.show(route.params.leadId);
    lead.value = data;
  } catch (e) {
    errorLead.value = true;
  } finally {
    loadingLead.value = false;
  }
};

watch(() => route.params.leadId, fetchLead, { immediate: true });

// ---- modo busca (rota sem leadId): achar a pessoa e depois o(s) lead(s) dela
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

const selectedContact = ref(null);
const contactLeads = ref([]);
const loadingLeads = ref(false);
const leadsError = ref(false);

const openPessoa = async contact => {
  selectedContact.value = contact;
  contactLeads.value = [];
  leadsError.value = false;
  loadingLeads.value = true;
  try {
    const { data } = await LeadsAPI.get({ contact_id: contact.id });
    const leads = data.payload || [];
    if (leads.length === 1) {
      router.push({
        name: 'ramon_calculos_lead',
        params: { leadId: leads[0].id },
      });
    } else {
      contactLeads.value = leads;
    }
  } catch {
    leadsError.value = true;
  } finally {
    loadingLeads.value = false;
  }
};

const openLead = leadId =>
  router.push({ name: 'ramon_calculos_lead', params: { leadId } });

const fmtDate = value => {
  if (!value) return '';
  return new Date(`${String(value).slice(0, 10)}T12:00:00`).toLocaleDateString(
    'pt-BR'
  );
};
</script>

<template>
  <div class="flex-1 w-full h-full p-6 overflow-y-auto bg-n-background">
    <!-- Deep-link: rota com leadId -->
    <template v-if="route.params.leadId">
      <div
        v-if="loadingLead"
        class="flex flex-col max-w-2xl gap-4 animate-pulse"
        data-testid="calculos-skeleton"
      >
        <div class="w-1/3 h-8 rounded bg-n-solid-2" />
        <div class="h-40 rounded-xl bg-n-solid-2" />
      </div>
      <p v-else-if="errorLead" class="text-sm text-n-ruby-11">
        {{ $t('RAMON.CALCULOS.ERROR') }}
      </p>
      <template v-else-if="lead">
        <RamonPageHeader
          compact
          :title="lead.contact_name || lead.name"
          :subtitle="lead.thesis_name || ''"
        />
        <LeadSimulador :lead="lead" />
      </template>
    </template>

    <!-- Busca de pessoa (entrada "Cálculos" do menu) -->
    <template v-else>
      <RamonPageHeader
        compact
        :title="$t('RAMON.CALCULOS.TITLE')"
        :subtitle="$t('RAMON.CALCULOS.SEARCH_HINT')"
      />
      <div class="max-w-xl">
        <input
          v-model="query"
          data-testid="pessoa-search"
          class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          :placeholder="$t('RAMON.CALCULOS.SEARCH_PLACEHOLDER')"
        />
        <p v-if="searching" class="mt-3 text-sm text-n-slate-10">
          {{ $t('RAMON.CALCULOS.SEARCHING') }}
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
          {{ $t('RAMON.CALCULOS.SEARCH_EMPTY') }}
        </p>

        <p
          v-if="loadingLeads"
          class="mt-4 text-sm text-n-slate-10"
          data-testid="calculos-loading-leads"
        >
          {{ $t('RAMON.CALCULOS.LOADING_LEADS') }}
        </p>

        <p
          v-else-if="leadsError"
          class="mt-4 text-sm text-n-ruby-11"
          data-testid="calculos-leads-error"
        >
          {{ $t('RAMON.CALCULOS.ERROR') }}
        </p>

        <template v-else-if="selectedContact">
          <ul
            v-if="contactLeads.length"
            class="mt-4 rounded-lg border border-n-weak divide-y divide-n-weak"
            data-testid="calculos-lead-list"
          >
            <li v-for="l in contactLeads" :key="l.id">
              <button
                data-testid="calculos-lead-item"
                class="flex items-center justify-between w-full gap-3 px-3 py-2 text-left hover:bg-n-alpha-2"
                @click="openLead(l.id)"
              >
                <span class="text-sm truncate text-n-slate-12">
                  {{ l.thesis_name || l.name }}
                </span>
                <span class="text-xs shrink-0 text-n-slate-10">
                  {{ fmtDate(l.stage_entered_at) }}
                </span>
              </button>
            </li>
          </ul>
          <p
            v-else
            class="mt-4 text-sm text-n-slate-10"
            data-testid="calculos-empty"
          >
            {{
              $t('RAMON.CALCULOS.EMPTY_NO_LEAD', {
                name: selectedContact.name,
              })
            }}
          </p>
        </template>
      </div>
    </template>
  </div>
</template>

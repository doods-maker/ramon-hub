<script setup>
import { ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import ContactAPI from 'dashboard/api/contacts';
import LeadsAPI from 'dashboard/api/leads';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import LeadSimulador from '../components/conversation/LeadSimulador.vue';

const route = useRoute();
const router = useRouter();

// ---- deep-link (rota com leadId): carrega o lead direto, sem passar pela busca
const lead = ref(null);
const loadingLead = ref(false);
const errorLead = ref(false);

// ---- calculadora sem cliente (padrão da tela, uso "hub = Previdenciarista"):
// abre num caso de rascunho invisível no funil; a busca de pessoa fica a um
// clique, pra quando o cálculo tem que ficar pendurado no cliente.
const modo = ref('calculadora');
const rascunho = ref(null);
const rascunhoLoading = ref(false);
const rascunhoError = ref(false);

const abrirCalculadora = async () => {
  modo.value = 'calculadora';
  if (rascunho.value || rascunhoLoading.value) return;
  rascunhoLoading.value = true;
  rascunhoError.value = false;
  try {
    const { data } = await RamonCalculosAPI.rascunho();
    rascunho.value = data;
  } catch (e) {
    rascunhoError.value = true;
  } finally {
    rascunhoLoading.value = false;
  }
};

const fetchLead = async () => {
  if (!route.params.leadId) {
    lead.value = null;
    abrirCalculadora();
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
const selectedContact = ref(null);
const contactLeads = ref([]);
const loadingLeads = ref(false);
const leadsError = ref(false);
let searchTimer = null;
let searchAbort = null;

// ---- AdvBox: busca sob demanda (teto de 500 chamadas/dia lá — nada por tecla)
const advboxResults = ref([]);
const advboxSearching = ref(false);
const advboxError = ref(false);
const advboxSearched = ref(false);
const creating = ref(false);
const createError = ref(false);

watch(query, value => {
  clearTimeout(searchTimer);
  // Nova busca limpa a seleção anterior: sem duas pessoas na tela.
  selectedContact.value = null;
  contactLeads.value = [];
  leadsError.value = false;
  advboxResults.value = [];
  advboxError.value = false;
  advboxSearched.value = false;
  createError.value = false;
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

const searchAdvbox = async () => {
  advboxSearching.value = true;
  advboxError.value = false;
  try {
    const { data } = await RamonCalculosAPI.advboxCustomers(query.value.trim());
    advboxResults.value = data.payload || [];
    advboxSearched.value = true;
  } catch (e) {
    advboxError.value = true;
  } finally {
    advboxSearching.value = false;
  }
};

const goToLeads = (contact, leads) => {
  if (leads.length === 1) {
    openLead(leads[0].id);
  } else {
    selectedContact.value = contact;
    contactLeads.value = leads;
  }
};

const criarCaso = async payload => {
  if (creating.value) return;
  creating.value = true;
  createError.value = false;
  try {
    const { data } = await RamonCalculosAPI.criarCaso(payload);
    goToLeads(data.contact, data.leads);
  } catch (e) {
    createError.value = true;
  } finally {
    creating.value = false;
  }
};

const openAdvboxCustomer = c =>
  criarCaso({
    nome: c.name,
    cpf: c.identification,
    telefone: c.cellphone,
    nascimento: c.birthdate,
    email: c.email,
  });

const criarCasoParaContato = () =>
  criarCaso({ contact_id: selectedContact.value.id });

const fmtDate = value => {
  if (!value) return '';
  return new Date(`${String(value).slice(0, 10)}T12:00:00`).toLocaleDateString(
    'pt-BR'
  );
};
</script>

<template>
  <div class="flex-1 w-full h-full p-4 sm:p-8 overflow-y-auto bg-n-background">
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
      <div v-else-if="errorLead" class="flex items-center gap-3">
        <p class="text-sm text-n-ruby-11">
          {{ $t('RAMON.CALCULOS.ERROR') }}
        </p>
        <button
          data-testid="calculos-retry"
          class="text-sm text-n-iris-11 hover:underline"
          @click="fetchLead"
        >
          {{ $t('RAMON.LEAD_PANEL.RETRY') }}
        </button>
      </div>
      <template v-else-if="lead">
        <RamonPageHeader
          :title="lead.contact_name || lead.name"
          :subtitle="lead.thesis_name || ''"
        >
          <template #actions>
            <button
              data-testid="calculos-novo-calculo"
              class="text-sm text-n-iris-11 hover:underline"
              @click="router.push({ name: 'ramon_calculos' })"
            >
              {{ $t('RAMON.CALCULOS.NOVO_CALCULO') }}
            </button>
          </template>
        </RamonPageHeader>
        <LeadSimulador :lead="lead" />
      </template>
    </template>

    <!-- Entrada "Cálculos" do menu: calculadora direto; busca a um clique -->
    <template v-else>
      <RamonPageHeader
        :title="$t('RAMON.CALCULOS.TITLE')"
        :subtitle="
          modo === 'calculadora'
            ? $t('RAMON.CALCULOS.RASCUNHO_HINT')
            : $t('RAMON.CALCULOS.SEARCH_HINT')
        "
      >
        <template #actions>
          <button
            v-if="modo === 'calculadora'"
            data-testid="calculos-modo-busca"
            class="text-sm text-n-iris-11 hover:underline"
            @click="modo = 'busca'"
          >
            {{ $t('RAMON.CALCULOS.OPEN_SEARCH') }}
          </button>
          <button
            v-else
            data-testid="calculos-modo-calculadora"
            class="text-sm text-n-iris-11 hover:underline"
            @click="abrirCalculadora"
          >
            {{ $t('RAMON.CALCULOS.OPEN_RASCUNHO') }}
          </button>
        </template>
      </RamonPageHeader>

      <template v-if="modo === 'calculadora'">
        <div
          v-if="rascunhoLoading"
          class="flex flex-col max-w-2xl gap-4 animate-pulse"
          data-testid="calculos-rascunho-skeleton"
        >
          <div class="w-1/3 h-8 rounded bg-n-solid-2" />
          <div class="h-40 rounded-xl bg-n-solid-2" />
        </div>
        <div v-else-if="rascunhoError" class="flex items-center gap-3">
          <p
            class="text-sm text-n-ruby-11"
            data-testid="calculos-rascunho-error"
          >
            {{ $t('RAMON.CALCULOS.RASCUNHO_ERROR') }}
          </p>
          <button
            data-testid="calculos-rascunho-retry"
            class="text-sm text-n-iris-11 hover:underline"
            @click="abrirCalculadora"
          >
            {{ $t('RAMON.LEAD_PANEL.RETRY') }}
          </button>
        </div>
        <LeadSimulador v-else-if="rascunho" :lead="rascunho" />
      </template>

      <div v-else class="max-w-xl">
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

        <!-- AdvBox: só sob demanda (1 chamada por clique) -->
        <template v-if="query.trim().length >= 2 && !searching">
          <button
            v-if="!advboxSearching"
            data-testid="advbox-search"
            class="mt-4 text-sm text-n-iris-11 hover:underline"
            @click="searchAdvbox"
          >
            {{ $t('RAMON.CALCULOS.ADVBOX_SEARCH') }}
          </button>
          <p v-else class="mt-4 text-sm text-n-slate-10">
            {{ $t('RAMON.CALCULOS.SEARCHING') }}
          </p>
          <p
            v-if="advboxError"
            class="mt-2 text-sm text-n-ruby-11"
            data-testid="advbox-error"
          >
            {{ $t('RAMON.CALCULOS.ADVBOX_ERROR') }}
          </p>
          <template v-if="advboxSearched">
            <p class="mt-4 text-xs font-medium uppercase text-n-slate-10">
              {{ $t('RAMON.CALCULOS.ADVBOX_TITLE') }}
            </p>
            <ul
              v-if="advboxResults.length"
              class="mt-2 rounded-lg border border-n-weak divide-y divide-n-weak"
            >
              <li v-for="c in advboxResults" :key="c.id">
                <button
                  data-testid="advbox-result"
                  :disabled="creating"
                  class="flex items-center justify-between w-full gap-3 px-3 py-2 text-left hover:bg-n-alpha-2 disabled:opacity-50"
                  @click="openAdvboxCustomer(c)"
                >
                  <span class="text-sm truncate text-n-slate-12">
                    {{ c.name }}
                  </span>
                  <span class="text-xs shrink-0 text-n-slate-10">
                    {{ c.identification || c.cellphone || '' }}
                  </span>
                </button>
              </li>
            </ul>
            <p
              v-else
              class="mt-2 text-sm text-n-slate-10"
              data-testid="advbox-empty"
            >
              {{ $t('RAMON.CALCULOS.ADVBOX_EMPTY') }}
            </p>
          </template>
        </template>
        <p
          v-if="createError"
          class="mt-2 text-sm text-n-ruby-11"
          data-testid="create-error"
        >
          {{ $t('RAMON.CALCULOS.CREATE_ERROR') }}
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
          <div v-else class="mt-4" data-testid="calculos-empty">
            <p class="text-sm text-n-slate-10">
              {{
                $t('RAMON.CALCULOS.EMPTY_NO_LEAD', {
                  name: selectedContact.name,
                })
              }}
            </p>
            <button
              data-testid="create-case"
              :disabled="creating"
              class="mt-2 text-sm text-n-iris-11 hover:underline disabled:opacity-50"
              @click="criarCasoParaContato"
            >
              {{ $t('RAMON.CALCULOS.CREATE_CASE') }}
            </button>
          </div>
        </template>
      </div>
    </template>
  </div>
</template>

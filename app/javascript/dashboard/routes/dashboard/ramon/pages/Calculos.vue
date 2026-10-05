<script setup>
import { ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';
import LeadsAPI from 'dashboard/api/leads';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';
import CalculosAPI from 'dashboard/api/calculos';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import LeadSimulador from '../components/conversation/LeadSimulador.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { CAMPO, CAMPO_GRANDE, CARTAO, LINHA, TITULO } from '../helpers/ui';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

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
// Nome de quem ainda não é cliente (consulta rápida): vai junto de cada
// cálculo e vira o segurado_nome do histórico — dá pra reencontrar na busca.
const seguradoNome = ref('');
// Cálculo reaberto do histórico + chave que remonta o simulador com ele.
const restaurado = ref(null);
const simuladorKey = ref(0);

// Entrar na calculadora é sempre entrada LIMPA: repete o POST (que zera o CNIS
// do rascunho no servidor — é lá que o cálculo lê o histórico) e remonta o
// simulador. Sem isso, um cálculo reaberto antes ficaria de resíduo no servidor.
const abrirCalculadora = async () => {
  modo.value = 'calculadora';
  restaurado.value = null;
  seguradoNome.value = '';
  if (rascunhoLoading.value) return;
  rascunhoLoading.value = true;
  rascunhoError.value = false;
  try {
    const { data } = await RamonCalculosAPI.rascunho();
    rascunho.value = data;
    simuladorKey.value += 1;
  } catch (e) {
    rascunhoError.value = true;
  } finally {
    rascunhoLoading.value = false;
  }
};

// ---- histórico: todo cálculo que roda fica guardado com CNIS processado,
// então reabrir volta ao estado exato sem reanexar o PDF.
const historicoOpen = ref(false);
const historico = ref([]);
const historicoQuery = ref('');
const historicoLoading = ref(false);
const historicoError = ref(false);
let historicoTimer = null;

const carregarHistorico = async () => {
  historicoLoading.value = true;
  historicoError.value = false;
  try {
    const { data } = await CalculosAPI.historico(historicoQuery.value.trim());
    historico.value = data.payload || [];
  } catch (e) {
    historicoError.value = true;
  } finally {
    historicoLoading.value = false;
  }
};

const toggleHistorico = () => {
  historicoOpen.value = !historicoOpen.value;
  if (historicoOpen.value) carregarHistorico();
};

watch(historicoQuery, () => {
  clearTimeout(historicoTimer);
  historicoTimer = setTimeout(carregarHistorico, 300);
});

// Item do histórico esperando a resposta da janela "substituir o CNIS?".
const reabrirPendente = ref(null);

// Abre o cálculo devolvido pelo servidor: no MEU rascunho fica na tela (com a
// tese que veio junto); num lead, navega pra calculadora dele.
const abrirReaberto = (data, nome) => {
  restaurado.value = data;
  simuladorKey.value += 1;
  historicoOpen.value = false;
  if (rascunho.value && data.lead_id === rascunho.value.id) {
    modo.value = 'calculadora';
    rascunho.value = {
      ...rascunho.value,
      thesis_id: data.thesis_id ?? null,
      thesis_name: data.thesis_name ?? null,
    };
    seguradoNome.value = nome || '';
  } else {
    router.push({
      name: 'ramon_calculos_lead',
      params: { leadId: data.lead_id },
    });
  }
};

// destino 'rascunho' = copia pro meu rascunho e deixa o lead intacto. Erro
// vira aviso e a lista fica onde está.
const executarReabrir = async (item, destino) => {
  reabrirPendente.value = null;
  try {
    const { data } = await CalculosAPI.reabrir(item.id, destino);
    abrirReaberto(data, item.segurado_nome);
  } catch (e) {
    useAlert(t('RAMON.CALCULOS.REABRIR_ERRO'));
  }
};

// Cálculo rápido volta sempre no meu rascunho (o servidor garante). De lead
// real que hoje tem OUTRO CNIS, pergunta antes de trocar.
const reabrirCalculo = item => {
  if (item.substitui_cnis) {
    reabrirPendente.value = item;
    return;
  }
  executarReabrir(item);
};

const diaMes = iso =>
  new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });

const apagarCalculo = async item => {
  try {
    await CalculosAPI.delete(item.id);
    historico.value = historico.value.filter(c => c.id !== item.id);
  } catch (e) {
    historicoError.value = true;
  }
};

const TIPO_LABEL = {
  painel: 'RAMON.SIMULADOR.ABA_POSSIBILIDADES',
  honorario: 'RAMON.SIMULADOR.ABA_HONORARIO',
  elegibilidade: 'RAMON.SIMULADOR.ABA_ELEGIBILIDADE',
  pensao: 'RAMON.SIMULADOR.ABA_PENSAO',
  maternidade: 'RAMON.SIMULADOR.ABA_MATERNIDADE',
  planejamento: 'RAMON.SIMULADOR.ABA_PLANEJAMENTO',
};

const fmtDateTime = iso =>
  new Date(iso).toLocaleString('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
  });

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
        class="flex flex-col max-w-4xl gap-4 animate-pulse"
        data-testid="calculos-skeleton"
      >
        <div class="w-1/3 h-8 rounded-lg bg-n-alpha-2" />
        <div class="h-40 rounded-xl bg-n-alpha-2" />
      </div>
      <div v-else-if="errorLead" class="flex items-center gap-3">
        <p class="mb-0 text-sm text-n-ruby-11">
          {{ $t('RAMON.CALCULOS.ERROR') }}
        </p>
        <Button
          data-testid="calculos-retry"
          link
          xs
          :label="$t('RAMON.LEAD_PANEL.RETRY')"
          @click="fetchLead"
        />
      </div>
      <div v-else-if="lead" class="max-w-4xl">
        <RamonPageHeader
          :title="lead.contact_name || lead.name"
          :subtitle="lead.thesis_name || ''"
        >
          <template #actions>
            <Button
              data-testid="calculos-novo-calculo"
              sm
              faded
              slate
              icon="i-lucide-plus"
              :label="$t('RAMON.CALCULOS.NOVO_CALCULO')"
              @click="router.push({ name: 'ramon_calculos' })"
            />
          </template>
        </RamonPageHeader>
        <LeadSimulador :key="simuladorKey" :lead="lead" :inicial="restaurado" />
      </div>
    </template>

    <!-- Entrada "Cálculos" do menu: calculadora direto; busca a um clique -->
    <div v-else class="max-w-4xl">
      <RamonPageHeader
        :title="$t('RAMON.CALCULOS.TITLE')"
        :subtitle="
          modo === 'calculadora'
            ? $t('RAMON.CALCULOS.RASCUNHO_HINT')
            : $t('RAMON.CALCULOS.SEARCH_HINT')
        "
      >
        <template #actions>
          <Button
            data-testid="calculos-historico-toggle"
            sm
            faded
            :color="historicoOpen ? 'blue' : 'slate'"
            icon="i-lucide-history"
            :label="$t('RAMON.CALCULOS.HIST_TOGGLE')"
            @click="toggleHistorico"
          />
          <Button
            v-if="modo === 'calculadora'"
            data-testid="calculos-modo-busca"
            sm
            faded
            slate
            icon="i-lucide-user-search"
            :label="$t('RAMON.CALCULOS.OPEN_SEARCH')"
            @click="modo = 'busca'"
          />
          <Button
            v-else
            data-testid="calculos-modo-calculadora"
            sm
            faded
            slate
            icon="i-lucide-calculator"
            :label="$t('RAMON.CALCULOS.OPEN_RASCUNHO')"
            @click="abrirCalculadora"
          />
        </template>
      </RamonPageHeader>

      <!-- Histórico: mesmo painel nos dois modos, some ao reabrir um cálculo -->
      <div
        v-if="historicoOpen"
        class="flex flex-col gap-2 mb-4"
        :class="CARTAO"
        data-testid="calculos-historico"
      >
        <input
          v-model="historicoQuery"
          data-testid="calculos-historico-busca"
          :class="CAMPO"
          :placeholder="$t('RAMON.CALCULOS.HIST_PLACEHOLDER')"
        />
        <p v-if="historicoLoading" class="mb-0 text-sm text-n-slate-10">
          {{ $t('RAMON.CALCULOS.SEARCHING') }}
        </p>
        <p
          v-else-if="historicoError"
          class="mb-0 text-sm text-n-ruby-11"
          data-testid="calculos-historico-error"
        >
          {{ $t('RAMON.CALCULOS.HIST_ERROR') }}
        </p>
        <ul
          v-else-if="historico.length"
          class="flex flex-col list-none reset-base ms-0"
        >
          <li
            v-for="item in historico"
            :key="item.id"
            class="flex items-center gap-2"
          >
            <button
              data-testid="calculos-historico-item"
              class="flex flex-col flex-1 min-w-0"
              :class="LINHA"
              @click="reabrirCalculo(item)"
            >
              <span class="truncate text-n-slate-12">
                {{ item.segurado_nome || $t('RAMON.CALCULOS.HIST_SEM_NOME') }}
              </span>
              <span v-if="item.der" class="text-xs text-n-slate-10">
                {{
                  $t('RAMON.CALCULOS.HIST_LINHA_DER', {
                    quando: fmtDateTime(item.created_at),
                    tipo: $t(TIPO_LABEL[item.tipo] || 'RAMON.CALCULOS.TITLE'),
                    der: fmtDate(item.der),
                  })
                }}
              </span>
              <span v-else class="text-xs text-n-slate-10">
                {{
                  $t('RAMON.CALCULOS.HIST_LINHA', {
                    quando: fmtDateTime(item.created_at),
                    tipo: $t(TIPO_LABEL[item.tipo] || 'RAMON.CALCULOS.TITLE'),
                  })
                }}
              </span>
            </button>
            <Button
              :data-testid="`calculos-historico-apagar-${item.id}`"
              link
              ruby
              xs
              class="shrink-0 me-2"
              :label="$t('RAMON.CALCULOS.HIST_APAGAR')"
              @click="apagarCalculo(item)"
            />
          </li>
        </ul>
        <p
          v-else
          class="mb-0 text-sm text-n-slate-10"
          data-testid="calculos-historico-vazio"
        >
          {{ $t('RAMON.CALCULOS.HIST_VAZIO') }}
        </p>
      </div>

      <template v-if="modo === 'calculadora'">
        <div
          v-if="rascunhoLoading"
          class="flex flex-col gap-4 animate-pulse"
          data-testid="calculos-rascunho-skeleton"
        >
          <div class="w-1/3 h-8 rounded-lg bg-n-alpha-2" />
          <div class="h-40 rounded-xl bg-n-alpha-2" />
        </div>
        <div v-else-if="rascunhoError" class="flex items-center gap-3">
          <p
            class="mb-0 text-sm text-n-ruby-11"
            data-testid="calculos-rascunho-error"
          >
            {{ $t('RAMON.CALCULOS.RASCUNHO_ERROR') }}
          </p>
          <Button
            data-testid="calculos-rascunho-retry"
            link
            xs
            :label="$t('RAMON.LEAD_PANEL.RETRY')"
            @click="abrirCalculadora"
          />
        </div>
        <template v-else-if="rascunho">
          <div class="px-1 mb-3">
            <input
              v-model="seguradoNome"
              data-testid="calculos-segurado-nome"
              :class="CAMPO_GRANDE"
              :placeholder="$t('RAMON.CALCULOS.NOME_PLACEHOLDER')"
            />
          </div>
          <LeadSimulador
            :key="simuladorKey"
            :lead="rascunho"
            :inicial="restaurado"
            :segurado-nome="seguradoNome"
          />
        </template>
      </template>

      <div v-else class="max-w-xl">
        <input
          v-model="query"
          data-testid="pessoa-search"
          :class="CAMPO_GRANDE"
          :placeholder="$t('RAMON.CALCULOS.SEARCH_PLACEHOLDER')"
        />
        <p v-if="searching" class="mt-3 mb-0 text-sm text-n-slate-10">
          {{ $t('RAMON.CALCULOS.SEARCHING') }}
        </p>
        <ul
          v-else-if="results.length"
          class="flex flex-col mt-3 list-none reset-base ms-0 !p-1.5"
          :class="[CARTAO]"
        >
          <li v-for="c in results" :key="c.id">
            <button
              data-testid="pessoa-result"
              class="flex items-center justify-between gap-3"
              :class="LINHA"
              @click="openPessoa(c)"
            >
              <span class="truncate text-n-slate-12">
                {{ c.name }}
              </span>
              <span class="font-mono text-xs shrink-0 text-n-slate-10">
                {{ c.phone_number || c.email || '' }}
              </span>
            </button>
          </li>
        </ul>
        <p
          v-else-if="query.trim().length >= 2"
          class="mt-3 mb-0 text-sm text-n-slate-10"
        >
          {{ $t('RAMON.CALCULOS.SEARCH_EMPTY') }}
        </p>

        <!-- AdvBox: só sob demanda (1 chamada por clique) -->
        <template v-if="query.trim().length >= 2 && !searching">
          <Button
            v-if="!advboxSearching"
            data-testid="advbox-search"
            sm
            faded
            slate
            icon="i-lucide-search"
            class="mt-4"
            :label="$t('RAMON.CALCULOS.ADVBOX_SEARCH')"
            @click="searchAdvbox"
          />
          <p v-else class="mt-4 mb-0 text-sm text-n-slate-10">
            {{ $t('RAMON.CALCULOS.SEARCHING') }}
          </p>
          <p
            v-if="advboxError"
            class="mt-2 mb-0 text-sm text-n-ruby-11"
            data-testid="advbox-error"
          >
            {{ $t('RAMON.CALCULOS.ADVBOX_ERROR') }}
          </p>
          <template v-if="advboxSearched">
            <p class="mt-4 mb-0" :class="TITULO">
              {{ $t('RAMON.CALCULOS.ADVBOX_TITLE') }}
            </p>
            <ul
              v-if="advboxResults.length"
              class="flex flex-col mt-2 list-none reset-base ms-0 !p-1.5"
              :class="[CARTAO]"
            >
              <li v-for="c in advboxResults" :key="c.id">
                <button
                  data-testid="advbox-result"
                  :disabled="creating"
                  class="flex items-center justify-between gap-3"
                  :class="LINHA"
                  @click="openAdvboxCustomer(c)"
                >
                  <span class="truncate text-n-slate-12">
                    {{ c.name }}
                  </span>
                  <span class="font-mono text-xs shrink-0 text-n-slate-10">
                    {{ c.identification || c.cellphone || '' }}
                  </span>
                </button>
              </li>
            </ul>
            <p
              v-else
              class="mt-2 mb-0 text-sm text-n-slate-10"
              data-testid="advbox-empty"
            >
              {{ $t('RAMON.CALCULOS.ADVBOX_EMPTY') }}
            </p>
          </template>
        </template>
        <p
          v-if="createError"
          class="mt-2 mb-0 text-sm text-n-ruby-11"
          data-testid="create-error"
        >
          {{ $t('RAMON.CALCULOS.CREATE_ERROR') }}
        </p>

        <p
          v-if="loadingLeads"
          class="mt-4 mb-0 text-sm text-n-slate-10"
          data-testid="calculos-loading-leads"
        >
          {{ $t('RAMON.CALCULOS.LOADING_LEADS') }}
        </p>

        <p
          v-else-if="leadsError"
          class="mt-4 mb-0 text-sm text-n-ruby-11"
          data-testid="calculos-leads-error"
        >
          {{ $t('RAMON.CALCULOS.ERROR') }}
        </p>

        <template v-else-if="selectedContact">
          <ul
            v-if="contactLeads.length"
            class="flex flex-col mt-4 list-none reset-base ms-0 !p-1.5"
            :class="[CARTAO]"
            data-testid="calculos-lead-list"
          >
            <li v-for="l in contactLeads" :key="l.id">
              <button
                data-testid="calculos-lead-item"
                class="flex items-center justify-between gap-3"
                :class="LINHA"
                @click="openLead(l.id)"
              >
                <span class="truncate text-n-slate-12">
                  {{ l.thesis_name || l.name }}
                </span>
                <span class="font-mono text-xs shrink-0 text-n-slate-10">
                  {{ fmtDate(l.stage_entered_at) }}
                </span>
              </button>
            </li>
          </ul>
          <div
            v-else
            class="flex flex-col items-start gap-2 mt-4"
            data-testid="calculos-empty"
          >
            <p class="mb-0 text-sm text-n-slate-10">
              {{
                $t('RAMON.CALCULOS.EMPTY_NO_LEAD', {
                  name: selectedContact.name,
                })
              }}
            </p>
            <Button
              data-testid="create-case"
              :disabled="creating"
              sm
              icon="i-lucide-plus"
              :label="$t('RAMON.CALCULOS.CREATE_CASE')"
              @click="criarCasoParaContato"
            />
          </div>
        </template>
      </div>
    </div>

    <ConfirmModal
      v-if="reabrirPendente"
      :title="
        $t('RAMON.CALCULOS.REABRIR_TITULO', {
          data: diaMes(reabrirPendente.created_at),
        })
      "
      :confirm-label="$t('RAMON.CALCULOS.REABRIR_SUBSTITUIR')"
      :alt-label="$t('RAMON.CALCULOS.REABRIR_RASCUNHO')"
      @confirm="executarReabrir(reabrirPendente)"
      @alt="executarReabrir(reabrirPendente, 'rascunho')"
      @cancel="reabrirPendente = null"
    />
  </div>
</template>

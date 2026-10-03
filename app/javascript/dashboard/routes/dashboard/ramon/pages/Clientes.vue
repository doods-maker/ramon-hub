<script setup>
// Lista "Clientes" (redesign v2, Onda 5): os leads do funil numa tabela, com
// filtros PRÓPRIOS (estado local + chave de storage separada) — filtrar aqui
// não mexe no funil.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import LeadsAPI from 'dashboard/api/leads';
import { DEFAULT_STAGE_COLOR } from '../helpers/stage';
import { desde } from '../components/hoje/hoje';
import FiltroChip from '../components/kanban/FiltroChip.vue';

const store = useStore();
const getters = useStoreGetters();
const router = useRouter();
const { t } = useI18n();

const STORAGE = 'ramon_clientes_filtros';
const lerFiltros = () => {
  try {
    return JSON.parse(localStorage.getItem(STORAGE) || '{}');
  } catch (e) {
    return {};
  }
};
const filters = ref({
  q: '',
  thesisId: null,
  leadStageId: null,
  agentId: null,
  ...lerFiltros(),
});

const stages = computed(() => getters['leadConfig/getStages'].value);
const stageById = computed(() => new Map(stages.value.map(s => [s.id, s])));
const asOptions = list => (list || []).map(i => ({ id: i.id, name: i.name }));
const thesisOptions = computed(() =>
  asOptions(getters['theses/getTheses'].value)
);
const agentOptions = computed(() =>
  asOptions(getters['agents/getAgents'].value)
);

const leads = ref([]);
const clientes = computed(() =>
  [...leads.value].sort((a, b) =>
    (a.name || '').localeCompare(b.name || '', 'pt-BR')
  )
);

const carregar = async () => {
  const f = filters.value;
  const params = Object.fromEntries(
    Object.entries({
      q: f.q,
      thesis_id: f.thesisId,
      lead_stage_id: f.leadStageId,
      agent_id: f.agentId,
    }).filter(([, v]) => v)
  );
  const { data } = await LeadsAPI.get(params);
  leads.value = data.payload;
};
const setFilters = partial => {
  filters.value = { ...filters.value, ...partial };
  try {
    localStorage.setItem(STORAGE, JSON.stringify(filters.value));
  } catch (e) {
    // localStorage indisponível: seguimos sem persistir
  }
  carregar();
};

// Busca com debounce de 300 ms; já nasce com o q salvo (reflete o filtro real).
const busca = ref(filters.value.q || '');
let timer = null;
watch(busca, value => {
  clearTimeout(timer);
  timer = setTimeout(() => setFilters({ q: value }), 300);
});

const ultimaMudanca = lead => {
  if (!lead.stage_entered_at) return '';
  const { key, count } = desde(lead.stage_entered_at);
  return t(`RAMON.HOJE.${key}`, { count }, count);
};
const abrir = lead =>
  router.push({ name: 'ramon_lead_dossie', params: { leadId: lead.id } });

onMounted(() => {
  carregar();
  store.dispatch('leadConfig/get');
  store.dispatch('theses/get');
  store.dispatch('agents/get');
});

const TH = 'py-1.5 text-left text-xs font-normal text-n-slate-9';
const TD = 'py-2.5 pe-4';
</script>

<template>
  <div class="flex flex-col w-full h-full bg-n-background">
    <header
      class="flex flex-wrap items-center flex-shrink-0 gap-2.5 min-h-14 px-7 py-2.5 border-b border-n-weak"
    >
      <h1 class="text-[15px] font-semibold text-n-slate-12">
        {{ t('RAMON.CLIENTES.TITLE') }}
      </h1>
      <input
        v-model="busca"
        data-testid="clientes-busca"
        class="w-64 px-3 py-1.5 text-[13px] rounded-lg border border-n-weak bg-transparent outline-none focus:border-n-strong text-n-slate-12"
        :placeholder="t('RAMON.CLIENTES.BUSCA')"
      />
      <!-- contatos sem lead (Linha da vida) continuam achados por aqui -->
      <router-link
        :to="{ name: 'ramon_pessoas' }"
        data-testid="clientes-buscar-pessoa"
        class="inline-flex items-center gap-1 text-[12.5px] text-n-blue-11 hover:underline"
      >
        <span class="i-lucide-user-search size-3.5" />
        {{ t('RAMON.CLIENTES.BUSCAR_PESSOA') }}
      </router-link>
      <FiltroChip
        :label="t('RAMON.FUNIL.CHIP.TESE')"
        :options="thesisOptions"
        :model-value="filters.thesisId"
        @update:model-value="v => setFilters({ thesisId: v })"
      />
      <FiltroChip
        :label="t('RAMON.FUNIL.FILTERS.STAGE')"
        :options="asOptions(stages)"
        :model-value="filters.leadStageId"
        @update:model-value="v => setFilters({ leadStageId: v })"
      />
      <FiltroChip
        :label="t('RAMON.FUNIL.CHIP.RESPONSAVEL')"
        :options="agentOptions"
        :model-value="filters.agentId"
        @update:model-value="v => setFilters({ agentId: v })"
      />
    </header>
    <div class="flex-1 min-h-0 overflow-auto px-7 pb-8">
      <table class="w-full text-[13px] border-collapse">
        <thead>
          <tr class="border-b border-n-weak">
            <th :class="TH">{{ t('RAMON.KANBAN.LIST.NAME') }}</th>
            <th :class="TH">{{ t('RAMON.KANBAN.LIST.STAGE') }}</th>
            <th :class="TH">{{ t('RAMON.KANBAN.LIST.THESIS') }}</th>
            <th :class="TH">{{ t('RAMON.FUNIL.CHIP.RESPONSAVEL') }}</th>
            <th :class="TH">{{ t('RAMON.KANBAN.LIST.PHONE') }}</th>
            <th :class="TH">{{ t('RAMON.CLIENTES.ULTIMA_MUDANCA') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="lead in clientes"
            :key="lead.id"
            data-testid="cliente-row"
            class="border-b border-n-weak cursor-pointer hover:bg-n-slate-3"
            @click="abrir(lead)"
          >
            <td :class="TD" class="font-medium text-n-slate-12">
              {{ lead.name }}
            </td>
            <td :class="TD">
              <span
                v-if="stageById.get(lead.lead_stage_id)"
                class="ramon-stage-pill inline-flex items-center gap-1.5 px-2 py-0.5 text-[11.5px] font-medium rounded-full border whitespace-nowrap"
                :style="{
                  '--stage':
                    stageById.get(lead.lead_stage_id).color ||
                    DEFAULT_STAGE_COLOR,
                }"
              >
                <span class="rounded-full size-1.5 shrink-0 bg-current" />
                {{ stageById.get(lead.lead_stage_id).name }}
              </span>
            </td>
            <td :class="TD" class="text-n-slate-11">
              {{ lead.thesis_name || lead.benefit_type_name }}
            </td>
            <td :class="TD" class="text-n-slate-11">
              {{ lead.closer_name || lead.sdr_name }}
            </td>
            <td :class="TD" class="font-mono text-[12.5px] text-n-slate-11">
              {{ lead.contact_phone }}
            </td>
            <td :class="TD" class="font-mono text-[12.5px] text-n-slate-9">
              {{ ultimaMudanca(lead) }}
            </td>
          </tr>
        </tbody>
      </table>
      <p
        v-if="!clientes.length"
        class="pt-6 text-xs text-center text-n-slate-9"
      >
        {{ t('RAMON.KANBAN.LIST.EMPTY') }}
      </p>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const AREAS = ['previdenciario', 'trabalhista', 'outro'];
const PROVIDERS = ['deepseek', 'anthropic', 'openai'];

const agents = computed(() => getters['triageAgents/getAgents'].value);
const uiFlags = computed(() => getters['triageAgents/getUIFlags'].value);

const selectedId = ref(null);
const selectedAgent = computed(
  () => agents.value.find(agent => agent.id === selectedId.value) || null
);

const newAgentName = ref('');

const detail = reactive({
  name: '',
  description: '',
  area: '',
  provider: '',
  model: '',
  system_prompt: '',
  kit_system_prompt: '',
  sensitive: false,
  active: true,
});

watch(
  selectedAgent,
  agent => {
    if (!agent) return;
    detail.name = agent.name || '';
    detail.description = agent.description || '';
    detail.area = agent.area || '';
    detail.provider = agent.provider || '';
    detail.model = agent.model || '';
    detail.system_prompt = agent.system_prompt || '';
    detail.kit_system_prompt = agent.kit_system_prompt || '';
    detail.sensitive = !!agent.sensitive;
    detail.active = agent.active !== false;
  },
  { immediate: true }
);

const selectAgent = agent => {
  selectedId.value = agent.id;
};

const addAgent = async () => {
  const name = newAgentName.value.trim();
  if (!name) return;
  const created = await store.dispatch('triageAgents/create', {
    name,
    system_prompt: 'Escreva aqui as instruções do agente.',
  });
  newAgentName.value = '';
  if (created?.id) {
    selectAgent(created);
  }
};

const removeAgent = async agent => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('RAMON.TRIAGE_AGENTS.DELETE_CONFIRM'))) return;
  await store.dispatch('triageAgents/delete', agent.id);
  if (selectedId.value === agent.id) selectedId.value = null;
};

const saveDetail = () => {
  if (!selectedAgent.value) return;
  store.dispatch('triageAgents/update', {
    id: selectedAgent.value.id,
    name: detail.name,
    description: detail.description,
    area: detail.area,
    provider: detail.provider,
    model: detail.model,
    system_prompt: detail.system_prompt,
    kit_system_prompt: detail.kit_system_prompt,
  });
};

const saveActive = () => {
  if (!selectedAgent.value) return;
  store.dispatch('triageAgents/update', {
    id: selectedAgent.value.id,
    active: detail.active,
  });
};

const saveSensitive = () => {
  if (!selectedAgent.value) return;
  store.dispatch('triageAgents/update', {
    id: selectedAgent.value.id,
    sensitive: detail.sensitive,
  });
};

const areaOptionKey = area =>
  `RAMON.TRIAGE_AGENTS.AREA_OPTIONS.${area.toUpperCase()}`;
const providerOptionKey = provider =>
  `RAMON.TRIAGE_AGENTS.PROVIDER_OPTIONS.${provider.toUpperCase()}`;

onMounted(() => store.dispatch('triageAgents/get'));
</script>

<template>
  <!-- w-full explícito: sem ele a página encolhe pro conteúdo (router é flex) -->
  <div class="flex w-full h-full bg-n-background">
    <div
      class="flex flex-col w-[280px] flex-shrink-0 h-full p-4 overflow-y-auto border-r border-n-weak"
    >
      <h1 class="mb-1 text-lg font-cormorant text-n-slate-12">
        {{ $t('RAMON.TRIAGE_AGENTS.TITLE') }}
      </h1>
      <p class="mb-4 text-xs text-n-slate-10">
        {{ $t('RAMON.TRIAGE_AGENTS.DESCRIPTION') }}
      </p>
      <h2 class="mb-2 text-xs uppercase tracking-widest text-n-slate-9">
        {{ $t('RAMON.TRIAGE_AGENTS.LIST_TITLE') }}
      </h2>

      <ul data-testid="triage-agents-list" class="flex flex-col mb-3 gap-0.5">
        <li
          v-for="agent in agents"
          :key="agent.id"
          data-testid="triage-agents-item"
          class="flex items-center gap-1 px-2 py-1.5 rounded-lg cursor-pointer"
          :class="
            selectedId === agent.id ? 'bg-n-iris-3' : 'hover:bg-n-alpha-2'
          "
          @click="selectAgent(agent)"
        >
          <span class="flex-1 min-w-0 truncate text-sm text-n-slate-12">
            {{ agent.name }}
          </span>
          <span
            class="px-1.5 py-0.5 text-[10px] rounded-full"
            :class="
              agent.active !== false
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-2 text-n-slate-9'
            "
          >
            {{
              agent.active !== false
                ? $t('RAMON.TRIAGE_AGENTS.ACTIVE')
                : $t('RAMON.TRIAGE_AGENTS.INACTIVE')
            }}
          </span>
          <button
            data-testid="triage-agents-item-remove"
            class="text-n-slate-9 hover:text-n-ruby-11"
            :title="$t('RAMON.TRIAGE_AGENTS.DELETE')"
            @click.stop="removeAgent(agent)"
          >
            <span class="i-lucide-trash-2 size-3.5" />
          </button>
        </li>
        <li
          v-if="!uiFlags.isFetching && !agents.length"
          class="px-2 py-1.5 text-sm text-n-slate-9"
        >
          {{ $t('RAMON.TRIAGE_AGENTS.EMPTY_LIST') }}
        </li>
      </ul>

      <div class="flex gap-2">
        <input
          v-model="newAgentName"
          data-testid="triage-agents-add-input"
          class="flex-1 min-w-0 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
          :placeholder="$t('RAMON.TRIAGE_AGENTS.ADD_PLACEHOLDER')"
          @keyup.enter="addAgent"
        />
        <button
          data-testid="triage-agents-add-button"
          class="shrink-0 whitespace-nowrap px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white"
          @click="addAgent"
        >
          {{ $t('RAMON.TRIAGE_AGENTS.ADD') }}
        </button>
      </div>
    </div>

    <div class="flex-1 h-full p-6 overflow-y-auto">
      <p
        v-if="!selectedAgent"
        data-testid="triage-agents-empty-detail"
        class="text-sm text-n-slate-9"
      >
        {{ $t('RAMON.TRIAGE_AGENTS.EMPTY_DETAIL') }}
      </p>

      <div
        v-else
        class="flex flex-col gap-3"
        data-testid="triage-agents-detail"
      >
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-10">
            {{ $t('RAMON.TRIAGE_AGENTS.NAME') }}
          </span>
          <input
            v-model="detail.name"
            data-testid="triage-agents-name-input"
            class="px-3 py-2 text-lg font-cormorant rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
            :placeholder="$t('RAMON.TRIAGE_AGENTS.NAME')"
            @blur="saveDetail"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-10">
            {{ $t('RAMON.TRIAGE_AGENTS.FIELD_DESCRIPTION') }}
          </span>
          <textarea
            v-model="detail.description"
            data-testid="triage-agents-description-input"
            rows="2"
            class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
            :placeholder="$t('RAMON.TRIAGE_AGENTS.FIELD_DESCRIPTION')"
            @blur="saveDetail"
          />
        </label>

        <div class="flex gap-3">
          <label class="flex flex-col flex-1 gap-1">
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.TRIAGE_AGENTS.AREA') }}
            </span>
            <select
              v-model="detail.area"
              data-testid="triage-agents-area-select"
              class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
              @change="saveDetail"
            >
              <option value="" disabled>
                {{ $t('RAMON.TRIAGE_AGENTS.AREA') }}
              </option>
              <option v-for="area in AREAS" :key="area" :value="area">
                {{ $t(areaOptionKey(area)) }}
              </option>
            </select>
          </label>

          <label class="flex flex-col flex-1 gap-1">
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.TRIAGE_AGENTS.PROVIDER') }}
            </span>
            <select
              v-model="detail.provider"
              data-testid="triage-agents-provider-select"
              class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
              @change="saveDetail"
            >
              <option value="" disabled>
                {{ $t('RAMON.TRIAGE_AGENTS.PROVIDER') }}
              </option>
              <option
                v-for="provider in PROVIDERS"
                :key="provider"
                :value="provider"
              >
                {{ $t(providerOptionKey(provider)) }}
              </option>
            </select>
          </label>
        </div>

        <label class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-10">
            {{ $t('RAMON.TRIAGE_AGENTS.MODEL') }}
          </span>
          <input
            v-model="detail.model"
            data-testid="triage-agents-model-input"
            class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
            :placeholder="$t('RAMON.TRIAGE_AGENTS.MODEL')"
            @blur="saveDetail"
          />
        </label>

        <!-- prompts lado a lado em tela larga: são os campos que mais pedem espaço -->
        <div class="grid gap-3 xl:grid-cols-2">
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.TRIAGE_AGENTS.SYSTEM_PROMPT') }}
            </span>
            <textarea
              v-model="detail.system_prompt"
              data-testid="triage-agents-system-prompt-input"
              rows="14"
              class="px-3 py-2 text-xs font-mono rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
              :placeholder="$t('RAMON.TRIAGE_AGENTS.SYSTEM_PROMPT')"
              @blur="saveDetail"
            />
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.TRIAGE_AGENTS.KIT_SYSTEM_PROMPT') }}
            </span>
            <textarea
              v-model="detail.kit_system_prompt"
              data-testid="triage-agents-kit-system-prompt-input"
              rows="14"
              class="px-3 py-2 text-xs font-mono rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
              :placeholder="$t('RAMON.TRIAGE_AGENTS.KIT_SYSTEM_PROMPT')"
              @blur="saveDetail"
            />
          </label>
        </div>

        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input
            v-model="detail.active"
            type="checkbox"
            data-testid="triage-agents-active-toggle"
            @change="saveActive"
          />
          {{ $t('RAMON.TRIAGE_AGENTS.ACTIVE_TOGGLE') }}
        </label>

        <label
          class="flex items-center gap-2 text-sm text-n-slate-12"
          data-testid="triage-agents-sensitive-label"
        >
          <input
            v-model="detail.sensitive"
            type="checkbox"
            data-testid="triage-agents-sensitive-toggle"
            @change="saveSensitive"
          />
          {{ $t('RAMON.TRIAGE_AGENTS.SENSITIVE') }}
        </label>
        <p class="text-xs text-n-slate-9">
          {{ $t('RAMON.TRIAGE_AGENTS.SENSITIVE_HINT') }}
        </p>
      </div>
    </div>
  </div>
</template>

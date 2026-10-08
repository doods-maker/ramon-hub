<script setup>
import { computed, h, ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { picoSearch } from '@scmmishra/pico-search';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import SettingsHeader from 'dashboard/components-next/captain/pageComponents/settings/SettingsHeader.vue';
import SuggestedScenarios from 'dashboard/components-next/captain/assistant/SuggestedRules.vue';
import ScenariosCard from 'dashboard/components-next/captain/assistant/ScenariosCard.vue';
import BulkSelectBar from 'dashboard/components-next/captain/assistant/BulkSelectBar.vue';
import AddNewScenariosDialog from 'dashboard/components-next/captain/assistant/AddNewScenariosDialog.vue';
import {
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
  CHIP,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import {
  NIVEL_TOM,
  ferramentaInfo,
} from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { uiSettings, updateUISettings } = useUISettings();
const { formatMessage } = useMessageFormatter();
const assistantId = computed(() => Number(route.params.assistantId));
const { isAdmin } = useAdmin();

const uiFlags = useMapGetter('captainScenarios/getUIFlags');
const isFetching = computed(() => uiFlags.value.fetchingList);
const scenarios = useMapGetter('captainScenarios/getRecords');
const catalogo = useMapGetter('captainTools/getRecords');

const searchQuery = ref('');

const LINK_INSTRUCTION_CLASS =
  '[&_a[href^="tool://"]]:text-n-blue-11 [&_a:not([href^="tool://"])]:text-n-slate-12 [&_a]:pointer-events-none [&_a]:cursor-default';

const renderInstruction = instruction => () =>
  h('span', {
    class: `text-sm text-n-slate-12 py-4 prose prose-sm min-w-0 break-words ${LINK_INSTRUCTION_CLASS}`,
    innerHTML: instruction,
  });

// Skill de exemplo para adicionar rápido (texto vem do i18n)
const scenariosExample = [
  {
    id: 1,
    title: t('CAPTAIN.ASSISTANTS.SCENARIOS.EXAMPLE.TITLE'),
    description: t('CAPTAIN.ASSISTANTS.SCENARIOS.EXAMPLE.DESCRIPTION'),
    instruction: t('CAPTAIN.ASSISTANTS.SCENARIOS.EXAMPLE.INSTRUCTION'),
    tools: ['playbook_da_tese'],
  },
];

// I-SK4: a API devolve ligadas e desligadas; a tela separa em abas.
const aba = ref('ligadas');
const ligadas = computed(() => scenarios.value.filter(item => item.enabled));
const desligadas = computed(() =>
  scenarios.value.filter(item => !item.enabled)
);
const daAba = computed(() =>
  aba.value === 'ligadas' ? ligadas.value : desligadas.value
);
const abas = computed(() => [
  {
    id: 'ligadas',
    label: t('INTEL.SKILLS.ABA_LIGADAS', { n: ligadas.value.length }),
  },
  {
    id: 'desligadas',
    label: t('INTEL.SKILLS.ABA_DESLIGADAS', { n: desligadas.value.length }),
  },
]);
const mensagemVazia = computed(() =>
  aba.value === 'desligadas'
    ? t('INTEL.SKILLS.NENHUMA_DESLIGADA')
    : t('CAPTAIN.ASSISTANTS.SCENARIOS.EMPTY_MESSAGE')
);

const filteredScenarios = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return daAba.value;
  return picoSearch(daAba.value, query, [
    'title',
    'description',
    'instruction',
  ]);
});

const shouldShowSuggestedRules = computed(() => {
  return uiSettings.value?.show_scenarios_suggestions !== false;
});

const closeSuggestedRules = () => {
  updateUISettings({ show_scenarios_suggestions: false });
};

// Bulk selection & hover state
const bulkSelectedIds = ref(new Set());
const hoveredCard = ref(null);

// seleção em lote só vale para a aba que se vê
watch(aba, () => {
  bulkSelectedIds.value = new Set();
});

const handleRuleSelect = id => {
  const selected = new Set(bulkSelectedIds.value);
  selected[selected.has(id) ? 'delete' : 'add'](id);
  bulkSelectedIds.value = selected;
};

const buildSelectedCountLabel = computed(() => {
  const count = daAba.value.length || 0;
  const isAllSelected = bulkSelectedIds.value.size === count && count > 0;
  return isAllSelected
    ? t('CAPTAIN.ASSISTANTS.SCENARIOS.BULK_ACTION.UNSELECT_ALL', { count })
    : t('CAPTAIN.ASSISTANTS.SCENARIOS.BULK_ACTION.SELECT_ALL', { count });
});

const selectedCountLabel = computed(() => {
  return t('CAPTAIN.ASSISTANTS.SCENARIOS.BULK_ACTION.SELECTED', {
    count: bulkSelectedIds.value.size,
  });
});

const handleRuleHover = (isHovered, id) => {
  hoveredCard.value = isHovered ? id : null;
};

const getToolsFromInstruction = instruction => [
  ...new Set(
    [...(instruction?.matchAll(/\(tool:\/\/([^)]+)\)/g) ?? [])].map(m => m[1])
  ),
];

const updateScenario = async scenario => {
  try {
    await store.dispatch('captainScenarios/update', {
      id: scenario.id,
      assistantId: assistantId.value,
      ...scenario,
      tools: getToolsFromInstruction(scenario.instruction),
    });
    useAlert(t('CAPTAIN.ASSISTANTS.SCENARIOS.API.UPDATE.SUCCESS'));
  } catch (error) {
    const errorMessage =
      error?.response?.message ||
      t('CAPTAIN.ASSISTANTS.SCENARIOS.API.UPDATE.ERROR');
    useAlert(errorMessage);
  }
};

const deleteScenario = async id => {
  try {
    await store.dispatch('captainScenarios/delete', {
      id,
      assistantId: assistantId.value,
    });
    useAlert(t('CAPTAIN.ASSISTANTS.SCENARIOS.API.DELETE.SUCCESS'));
  } catch (error) {
    const errorMessage =
      error?.response?.message ||
      t('CAPTAIN.ASSISTANTS.SCENARIOS.API.DELETE.ERROR');
    useAlert(errorMessage);
  }
};

const alternarSkill = async (scenario, ligar) => {
  try {
    await store.dispatch('captainScenarios/update', {
      id: scenario.id,
      assistantId: assistantId.value,
      enabled: ligar,
    });
    bulkSelectedIds.value = new Set(
      [...bulkSelectedIds.value].filter(id => id !== scenario.id)
    );
    useAlert(ligar ? t('INTEL.SKILLS.LIGADA') : t('INTEL.SKILLS.DESLIGADA'));
  } catch (error) {
    useAlert(
      error?.message || t('CAPTAIN.ASSISTANTS.SCENARIOS.API.UPDATE.ERROR')
    );
  }
};

// I-SK6: abre o Testar do mesmo assistente com a fala de exemplo no campo (quem envia é você — N7).
const testarSkill = scenario =>
  router.push({
    name: 'captain_assistants_playground_index',
    params: { ...route.params },
    query: { fala: scenario.exemplo },
  });

// TODO: Add bulk delete endpoint
const bulkDeleteScenarios = async ids => {
  const idsArray = ids || Array.from(bulkSelectedIds.value);
  await Promise.all(
    idsArray.map(id =>
      store.dispatch('captainScenarios/delete', {
        id,
        assistantId: assistantId.value,
      })
    )
  );
  bulkSelectedIds.value = new Set();
  useAlert(t('CAPTAIN.ASSISTANTS.SCENARIOS.API.DELETE.SUCCESS'));
};

const addScenario = async scenario => {
  try {
    await store.dispatch('captainScenarios/create', {
      assistantId: assistantId.value,
      ...scenario,
      tools: getToolsFromInstruction(scenario.instruction),
    });
    useAlert(t('CAPTAIN.ASSISTANTS.SCENARIOS.API.ADD.SUCCESS'));
  } catch (error) {
    const errorMessage =
      error?.response?.message ||
      t('CAPTAIN.ASSISTANTS.SCENARIOS.API.ADD.ERROR');
    useAlert(errorMessage);
  }
};

const addAllExampleScenarios = async () => {
  try {
    scenariosExample.forEach(async scenario => {
      await store.dispatch('captainScenarios/create', {
        assistantId: assistantId.value,
        ...scenario,
      });
    });
    useAlert(t('CAPTAIN.ASSISTANTS.SCENARIOS.API.ADD.SUCCESS'));
  } catch (error) {
    const errorMessage =
      error?.response?.message ||
      t('CAPTAIN.ASSISTANTS.SCENARIOS.API.ADD.ERROR');
    useAlert(errorMessage);
  }
};

onMounted(() => {
  store.dispatch('captainScenarios/get', {
    assistantId: assistantId.value,
  });
  store.dispatch('captainTools/getTools');
  store.dispatch('teams/get');
});
</script>

<template>
  <PageLayout
    :header-title="$t('CAPTAIN.ASSISTANTS.SCENARIOS.TITLE')"
    :is-fetching="isFetching"
    :show-pagination-footer="false"
    show-assistant-switcher
  >
    <template #body>
      <SettingsHeader
        :heading="$t('CAPTAIN.ASSISTANTS.SCENARIOS.TITLE')"
        :description="$t('CAPTAIN.ASSISTANTS.SCENARIOS.DESCRIPTION')"
      />
      <div class="flex flex-wrap items-center gap-1.5 mt-3">
        <span
          v-for="(tom, nivel) in NIVEL_TOM"
          :key="nivel"
          :class="[CHIP, tom]"
        >
          {{ t(`CAPTAIN_RAMON.NIVEL.${nivel}`) }}
        </span>
      </div>
      <div v-if="shouldShowSuggestedRules" class="flex mt-7 flex-col gap-4">
        <SuggestedScenarios
          :title="$t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.TITLE')"
          :items="scenariosExample"
          @close="closeSuggestedRules"
          @add="addAllExampleScenarios"
        >
          <template #default="{ item }">
            <div class="flex items-center gap-3 justify-between">
              <span class="text-sm text-n-slate-12">
                {{ item.title }}
              </span>
              <Button
                :label="
                  $t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.ADD_SINGLE')
                "
                ghost
                xs
                slate
                class="!text-sm !text-n-slate-11 flex-shrink-0"
                @click="addScenario(item)"
              />
            </div>
            <div class="flex flex-col">
              <span class="text-sm text-n-slate-11 mt-2">
                {{ item.description }}
              </span>
              <component
                :is="renderInstruction(formatMessage(item.instruction, false))"
              />
              <div
                v-if="item.tools?.length"
                class="flex flex-wrap items-center gap-1.5 mb-1"
              >
                <span class="text-sm text-n-slate-11 font-medium">
                  {{
                    t('CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.TOOLS_USED')
                  }}
                </span>
                <span
                  v-for="f in item.tools.map(id =>
                    ferramentaInfo(id, catalogo)
                  )"
                  :key="f.id"
                  :class="[CHIP, f.tom]"
                >
                  {{ f.title }}
                </span>
              </div>
            </div>
          </template>
        </SuggestedScenarios>
      </div>
      <div class="flex mt-7 flex-col gap-4">
        <nav
          data-testid="skills-abas"
          class="flex gap-1 border-b border-n-weak"
        >
          <button
            v-for="item in abas"
            :key="item.id"
            type="button"
            :class="[ABA, aba === item.id ? ABA_ATIVA : ABA_INATIVA]"
            @click="aba = item.id"
          >
            {{ item.label }}
          </button>
        </nav>
        <div class="flex justify-between items-center">
          <BulkSelectBar
            v-model="bulkSelectedIds"
            :all-items="daAba"
            :select-all-label="buildSelectedCountLabel"
            :selected-count-label="selectedCountLabel"
            :delete-label="
              $t('CAPTAIN.ASSISTANTS.SCENARIOS.BULK_ACTION.BULK_DELETE_BUTTON')
            "
            @bulk-delete="bulkDeleteScenarios"
          >
            <template #default-actions>
              <AddNewScenariosDialog @add="addScenario" />
            </template>
          </BulkSelectBar>
          <div
            v-if="scenarios.length && bulkSelectedIds.size === 0"
            class="max-w-[22.5rem] w-full min-w-0"
          >
            <Input
              v-model="searchQuery"
              :placeholder="
                t('CAPTAIN.ASSISTANTS.SCENARIOS.LIST.SEARCH_PLACEHOLDER')
              "
            />
          </div>
        </div>
        <div v-if="daAba.length === 0" class="mt-1 mb-2">
          <span class="text-n-slate-11 text-sm">
            {{ mensagemVazia }}
          </span>
        </div>
        <div v-else-if="filteredScenarios.length === 0" class="mt-1 mb-2">
          <span class="text-n-slate-11 text-sm">
            {{ t('CAPTAIN.ASSISTANTS.SCENARIOS.SEARCH_EMPTY_MESSAGE') }}
          </span>
        </div>
        <div v-else class="flex flex-col gap-2">
          <ScenariosCard
            v-for="scenario in filteredScenarios"
            :id="scenario.id"
            :key="scenario.id"
            :title="scenario.title"
            :description="scenario.description"
            :instruction="scenario.instruction"
            :tools="scenario.tools"
            :enabled="scenario.enabled"
            :edited="scenario.edited"
            :pode-ligar="isAdmin"
            :exemplo="scenario.exemplo || ''"
            :papeis="scenario.papeis || []"
            :uso-mes="scenario.uso_30d ?? null"
            :is-selected="bulkSelectedIds.has(scenario.id)"
            :selectable="
              hoveredCard === scenario.id || bulkSelectedIds.size > 0
            "
            @select="handleRuleSelect"
            @delete="deleteScenario(scenario.id)"
            @update="updateScenario"
            @toggle="ligar => alternarSkill(scenario, ligar)"
            @testar="testarSkill(scenario)"
            @hover="isHovered => handleRuleHover(isHovered, scenario.id)"
          />
        </div>
      </div>
    </template>
  </PageLayout>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import ConfirmModal from '../components/ConfirmModal.vue';

const store = useStore();
const getters = useStoreGetters();

const SECTIONS = [
  'abertura',
  'apresentacao',
  'qualificacao',
  'objecao',
  'documento',
  'roteiro',
];

const theses = computed(() => getters['theses/getTheses'].value);
const uiFlags = computed(() => getters['theses/getUIFlags'].value);

const selectedId = ref(null);
const selectedThesis = computed(() =>
  selectedId.value ? getters['theses/getThesis'].value(selectedId.value) : null
);

const newThesisName = ref('');

const detail = reactive({
  name: '',
  description: '',
  area: '',
  active: true,
  honorarioPercentual: '',
  honorarioNMensalidades: '',
});

watch(
  selectedThesis,
  thesis => {
    if (!thesis) return;
    detail.name = thesis.name || '';
    detail.description = thesis.description || '';
    detail.area = thesis.area || '';
    detail.active = thesis.active !== false;
    detail.honorarioPercentual = thesis.honorario_percentual ?? '';
    detail.honorarioNMensalidades = thesis.honorario_n_mensalidades ?? '';
  },
  { immediate: true }
);

const selectThesis = async thesis => {
  selectedId.value = thesis.id;
  if (!thesis.items) {
    await store.dispatch('theses/show', thesis.id);
  }
};

const addThesis = async () => {
  const name = newThesisName.value.trim();
  if (!name) return;
  const created = await store.dispatch('theses/create', { name });
  newThesisName.value = '';
  if (created?.id) {
    selectThesis(created);
  }
};

const thesisToRemove = ref(null);
const removeThesis = thesis => {
  thesisToRemove.value = thesis;
};
const confirmRemoveThesis = async () => {
  const thesis = thesisToRemove.value;
  if (!thesis) return;
  // Fecha o modal antes do await: sem janela pra duplo-clique despachar 2x.
  thesisToRemove.value = null;
  await store.dispatch('theses/delete', thesis.id);
  if (selectedId.value === thesis.id) selectedId.value = null;
};

const moveThesis = (thesis, direction) => {
  const ordered = [...theses.value];
  const index = ordered.findIndex(th => th.id === thesis.id);
  const targetIndex = index + direction;
  if (index < 0 || targetIndex < 0 || targetIndex >= ordered.length) return;
  const ids = ordered.map(th => th.id);
  [ids[index], ids[targetIndex]] = [ids[targetIndex], ids[index]];
  store.dispatch('theses/reorder', ids);
};

const saveDetail = () => {
  if (!selectedThesis.value) return;
  store.dispatch('theses/update', {
    id: selectedThesis.value.id,
    name: detail.name,
    description: detail.description,
    area: detail.area,
    honorario_percentual: detail.honorarioPercentual,
    honorario_n_mensalidades: detail.honorarioNMensalidades,
  });
};

const saveActive = () => {
  if (!selectedThesis.value) return;
  store.dispatch('theses/update', {
    id: selectedThesis.value.id,
    active: detail.active,
  });
};

const itemsBySection = computed(() => {
  const items = selectedThesis.value?.items || [];
  return SECTIONS.reduce((acc, section) => {
    acc[section] = items.filter(item => item.section === section);
    return acc;
  }, {});
});

const newItemDrafts = reactive(
  SECTIONS.reduce((acc, section) => {
    acc[section] = { title: '', content: '' };
    return acc;
  }, {})
);

const addItem = async section => {
  const draft = newItemDrafts[section];
  const content = draft.content.trim();
  if (!content) return;
  await store.dispatch('theses/createItem', {
    thesisId: selectedThesis.value.id,
    section,
    title: draft.title.trim(),
    content,
  });
  draft.title = '';
  draft.content = '';
};

const updateItem = (item, attrs) => {
  store.dispatch('theses/updateItem', {
    thesisId: selectedThesis.value.id,
    id: item.id,
    ...attrs,
  });
};

const itemToRemove = ref(null);
const removeItem = item => {
  itemToRemove.value = item;
};
const confirmRemoveItem = () => {
  store.dispatch('theses/deleteItem', {
    thesisId: selectedThesis.value.id,
    id: itemToRemove.value.id,
  });
  itemToRemove.value = null;
};

const sectionLabelKey = section =>
  `RAMON.PLAYBOOKS.SECTIONS.${section.toUpperCase()}`;

onMounted(() => store.dispatch('theses/get'));
</script>

<template>
  <!-- w-full explícito: sem ele a página encolhe pro conteúdo e sobra um
       deserto à direita (o container do router é flex) -->
  <div class="flex w-full h-full bg-n-background">
    <div
      class="flex flex-col w-[340px] flex-shrink-0 h-full p-4 overflow-y-auto border-r border-n-weak"
    >
      <h1 class="mb-4 text-lg font-cormorant text-n-slate-12">
        {{ $t('RAMON.PLAYBOOKS.TITLE') }}
      </h1>
      <h2 class="mb-2 text-xs uppercase tracking-widest text-n-slate-9">
        {{ $t('RAMON.PLAYBOOKS.LIST_TITLE') }}
      </h2>

      <ul data-testid="playbooks-list" class="flex flex-col mb-3 gap-0.5">
        <li
          v-for="(thesis, index) in theses"
          :key="thesis.id"
          data-testid="playbooks-item"
          class="flex items-center gap-1 px-2 py-1.5 rounded-lg cursor-pointer"
          :class="
            selectedId === thesis.id ? 'bg-n-iris-3' : 'hover:bg-n-alpha-2'
          "
          @click="selectThesis(thesis)"
        >
          <span class="flex-1 min-w-0 truncate text-sm text-n-slate-12">
            {{ thesis.name }}
          </span>
          <span
            class="px-1.5 py-0.5 text-[10px] rounded-full"
            :class="
              thesis.active !== false
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-alpha-2 text-n-slate-9'
            "
          >
            {{
              thesis.active !== false
                ? $t('RAMON.PLAYBOOKS.ACTIVE')
                : $t('RAMON.PLAYBOOKS.INACTIVE')
            }}
          </span>
          <button
            data-testid="playbooks-item-up"
            class="text-n-slate-9 disabled:opacity-30"
            :aria-label="$t('RAMON.PLAYBOOKS.MOVE_UP')"
            :disabled="index === 0"
            @click.stop="moveThesis(thesis, -1)"
          >
            <span class="i-lucide-chevron-up size-3.5" />
          </button>
          <button
            data-testid="playbooks-item-down"
            class="text-n-slate-9 disabled:opacity-30"
            :aria-label="$t('RAMON.PLAYBOOKS.MOVE_DOWN')"
            :disabled="index === theses.length - 1"
            @click.stop="moveThesis(thesis, 1)"
          >
            <span class="i-lucide-chevron-down size-3.5" />
          </button>
          <button
            data-testid="playbooks-item-remove"
            class="text-n-slate-9 hover:text-n-ruby-11"
            :title="$t('RAMON.PLAYBOOKS.DELETE')"
            @click.stop="removeThesis(thesis)"
          >
            <span class="i-lucide-trash-2 size-3.5" />
          </button>
        </li>
        <li
          v-if="!uiFlags.isFetching && !theses.length"
          class="px-2 py-1.5 text-sm text-n-slate-9"
        >
          {{ $t('RAMON.PLAYBOOKS.EMPTY_LIST') }}
        </li>
      </ul>

      <div class="flex gap-2">
        <input
          v-model="newThesisName"
          data-testid="playbooks-add-input"
          class="flex-1 min-w-0 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
          :placeholder="$t('RAMON.PLAYBOOKS.ADD_PLACEHOLDER')"
          @keyup.enter="addThesis"
        />
        <button
          data-testid="playbooks-add-button"
          class="shrink-0 whitespace-nowrap px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white"
          @click="addThesis"
        >
          {{ $t('RAMON.PLAYBOOKS.ADD') }}
        </button>
      </div>
    </div>

    <div class="flex-1 h-full p-6 overflow-y-auto">
      <p
        v-if="!selectedThesis"
        data-testid="playbooks-empty-detail"
        class="text-sm text-n-slate-9"
      >
        {{ $t('RAMON.PLAYBOOKS.EMPTY_DETAIL') }}
      </p>

      <template v-else>
        <div
          class="flex flex-col gap-3 p-4 mb-6 border rounded-xl border-n-weak bg-n-solid-1"
          data-testid="playbooks-detail"
        >
          <div class="flex flex-wrap items-end gap-3">
            <label class="flex flex-col flex-1 min-w-64 gap-1">
              <span class="text-xs text-n-slate-10">
                {{ $t('RAMON.PLAYBOOKS.NAME') }}
              </span>
              <input
                v-model="detail.name"
                data-testid="playbooks-name-input"
                class="px-3 py-2 text-lg font-cormorant rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
                :placeholder="$t('RAMON.PLAYBOOKS.NAME')"
                @blur="saveDetail"
              />
            </label>
            <label
              class="flex items-center gap-2 pb-2.5 text-sm text-n-slate-12 whitespace-nowrap"
            >
              <input
                v-model="detail.active"
                type="checkbox"
                data-testid="playbooks-active-toggle"
                @change="saveActive"
              />
              {{ $t('RAMON.PLAYBOOKS.ACTIVE_TOGGLE') }}
            </label>
          </div>
          <label class="flex flex-col gap-1">
            <span class="text-xs text-n-slate-10">
              {{ $t('RAMON.PLAYBOOKS.DESCRIPTION') }}
            </span>
            <textarea
              v-model="detail.description"
              data-testid="playbooks-description-input"
              rows="2"
              class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
              :placeholder="$t('RAMON.PLAYBOOKS.DESCRIPTION')"
              @blur="saveDetail"
            />
          </label>
          <div class="grid gap-3 md:grid-cols-3">
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-10">
                {{ $t('RAMON.PLAYBOOKS.AREA') }}
              </span>
              <input
                v-model="detail.area"
                data-testid="playbooks-area-input"
                class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
                :placeholder="$t('RAMON.PLAYBOOKS.AREA')"
                @blur="saveDetail"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-10">
                {{ $t('RAMON.PLAYBOOKS.HONORARIO_PERCENT') }}
              </span>
              <input
                v-model="detail.honorarioPercentual"
                type="number"
                min="0"
                max="100"
                step="0.5"
                data-testid="playbooks-honorario-percentual-input"
                class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
                :placeholder="$t('RAMON.PLAYBOOKS.HONORARIO_PERCENT')"
                @blur="saveDetail"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-10">
                {{ $t('RAMON.PLAYBOOKS.HONORARIO_INSTALLMENTS') }}
              </span>
              <input
                v-model="detail.honorarioNMensalidades"
                type="number"
                min="0"
                step="1"
                data-testid="playbooks-honorario-mensalidades-input"
                class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
                :placeholder="$t('RAMON.PLAYBOOKS.HONORARIO_INSTALLMENTS')"
                @blur="saveDetail"
              />
            </label>
          </div>
        </div>

        <!-- Seções lado a lado em telas largas: usa a tela cheia de verdade -->
        <div class="grid items-start gap-6 xl:grid-cols-2">
          <section
            v-for="section in SECTIONS"
            :key="section"
            class="p-4 border rounded-xl border-n-weak bg-n-solid-1"
            data-testid="playbooks-section"
          >
            <h3 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
              {{ $t(sectionLabelKey(section)) }}
            </h3>

            <ul class="flex flex-col mb-3 gap-2">
              <li
                v-for="item in itemsBySection[section]"
                :key="item.id"
                data-testid="playbooks-item-row"
                class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
              >
                <div class="flex items-center gap-2">
                  <input
                    :value="item.title"
                    data-testid="playbooks-item-title-input"
                    class="flex-1 px-2 py-1 text-sm font-medium rounded-lg bg-n-alpha-2 text-n-slate-12"
                    :placeholder="$t('RAMON.PLAYBOOKS.ITEM_TITLE_PLACEHOLDER')"
                    @blur="e => updateItem(item, { title: e.target.value })"
                  />
                  <button
                    data-testid="playbooks-item-remove-item"
                    class="text-n-slate-9 hover:text-n-ruby-11"
                    :title="$t('RAMON.PLAYBOOKS.ITEM_DELETE')"
                    @click="removeItem(item)"
                  >
                    <span class="i-lucide-trash-2 size-3.5" />
                  </button>
                </div>
                <!-- field-sizing: auto-cresce com o roteiro (fallback = rows fixo) -->
                <textarea
                  :value="item.content"
                  data-testid="playbooks-item-content-input"
                  rows="2"
                  class="px-2 py-1 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12 [field-sizing:content] min-h-16 max-h-64"
                  :placeholder="$t('RAMON.PLAYBOOKS.ITEM_CONTENT_PLACEHOLDER')"
                  @blur="e => updateItem(item, { content: e.target.value })"
                />
              </li>
              <li
                v-if="!itemsBySection[section].length"
                class="px-1 text-xs text-n-slate-9"
              >
                {{ $t('RAMON.PLAYBOOKS.ITEM_EMPTY') }}
              </li>
            </ul>

            <div class="flex gap-2">
              <input
                v-model="newItemDrafts[section].title"
                data-testid="playbooks-item-add-title"
                class="w-40 shrink-0 px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
                :placeholder="$t('RAMON.PLAYBOOKS.ITEM_TITLE_PLACEHOLDER')"
              />
              <input
                v-model="newItemDrafts[section].content"
                data-testid="playbooks-item-add-content"
                class="flex-1 min-w-0 px-2 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
                :placeholder="$t('RAMON.PLAYBOOKS.ITEM_CONTENT_PLACEHOLDER')"
                @keyup.enter="addItem(section)"
              />
              <button
                data-testid="playbooks-item-add"
                class="shrink-0 whitespace-nowrap px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white"
                @click="addItem(section)"
              >
                {{ $t('RAMON.PLAYBOOKS.ITEM_ADD') }}
              </button>
            </div>
          </section>
        </div>
      </template>
    </div>
    <ConfirmModal
      v-if="thesisToRemove"
      :title="$t('RAMON.PLAYBOOKS.DELETE_CONFIRM')"
      :confirm-label="$t('RAMON.PLAYBOOKS.DELETE')"
      @confirm="confirmRemoveThesis"
      @cancel="thesisToRemove = null"
    />
    <ConfirmModal
      v-if="itemToRemove"
      :title="$t('RAMON.PLAYBOOKS.ITEM_DELETE_CONFIRM')"
      :confirm-label="$t('RAMON.PLAYBOOKS.ITEM_DELETE')"
      @confirm="confirmRemoveItem"
      @cancel="itemToRemove = null"
    />
  </div>
</template>

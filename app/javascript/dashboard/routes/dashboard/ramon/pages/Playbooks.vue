<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import { THESIS_SECTIONS as SECTIONS } from '../helpers/sections';
import { mensagemErro } from '../helpers/erro';
import {
  CARTAO,
  SECAO,
  TITULO,
  CAMPO,
  CAMPO_GRANDE,
  TEXTAREA,
  ROTULO,
  CHIP,
  TOM,
} from '../helpers/ui';

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

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

const syncDetail = () => {
  const thesis = selectedThesis.value;
  if (!thesis) return;
  detail.name = thesis.name || '';
  detail.description = thesis.description || '';
  detail.area = thesis.area || '';
  detail.active = thesis.active !== false;
  detail.honorarioPercentual = thesis.honorario_percentual ?? '';
  detail.honorarioNMensalidades = thesis.honorario_n_mensalidades ?? '';
};

// Observa só o ID: resposta de PATCH mutando o record no store não pode
// resetar os campos enquanto o usuário digita.
watch(selectedId, syncDetail);

const selectThesis = async thesis => {
  selectedId.value = thesis.id;
  if (!thesis.items) {
    await store.dispatch('theses/show', thesis.id);
    // show() pode trazer campos que o index não traz — resync pontual, sem raça.
    syncDetail();
  }
};

const addingThesis = ref(false);
const addThesis = async () => {
  const name = newThesisName.value.trim();
  if (!name || addingThesis.value) return;
  addingThesis.value = true;
  try {
    const created = await store.dispatch('theses/create', { name });
    newThesisName.value = '';
    if (created?.id) {
      selectThesis(created);
    }
  } catch {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  } finally {
    addingThesis.value = false;
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
  store
    .dispatch('theses/update', {
      id: selectedThesis.value.id,
      name: detail.name,
      description: detail.description,
      area: detail.area,
      honorario_percentual: detail.honorarioPercentual,
      honorario_n_mensalidades: detail.honorarioNMensalidades,
    })
    .catch(() => useAlert(t('RAMON.FUNIL.SAVE_ERROR')));
};

const saveActive = () => {
  if (!selectedThesis.value) return;
  store
    .dispatch('theses/update', {
      id: selectedThesis.value.id,
      active: detail.active,
    })
    .catch(() => useAlert(t('RAMON.FUNIL.SAVE_ERROR')));
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

const addingItem = ref('');
const addItem = async section => {
  const draft = newItemDrafts[section];
  const content = draft.content.trim();
  if (!content || addingItem.value === section) return;
  addingItem.value = section;
  try {
    await store.dispatch('theses/createItem', {
      thesisId: selectedThesis.value.id,
      section,
      title: draft.title.trim(),
      content,
    });
    draft.title = '';
    draft.content = '';
  } catch {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  } finally {
    addingItem.value = '';
  }
};

// Rascunho local por item: o refetch pós-save (show) não pode re-sincronizar
// um campo focado no meio da digitação. flush sync = draft existe antes do render.
const itemDrafts = reactive({});
watch(
  () => selectedThesis.value?.items,
  items => {
    (items || []).forEach(item => {
      if (!itemDrafts[item.id]) {
        itemDrafts[item.id] = {
          title: item.title || '',
          content: item.content || '',
        };
      }
    });
  },
  { immediate: true, flush: 'sync' }
);

const saveItem = item => {
  const draft = itemDrafts[item.id];
  if (
    draft.title === (item.title || '') &&
    draft.content === (item.content || '')
  )
    return;
  store
    .dispatch('theses/updateItem', {
      thesisId: selectedThesis.value.id,
      id: item.id,
      title: draft.title,
      content: draft.content,
    })
    .catch(() => useAlert(t('RAMON.FUNIL.SAVE_ERROR')));
};

const itemToRemove = ref(null);
const removeItem = item => {
  itemToRemove.value = item;
};
const confirmRemoveItem = () => {
  const item = itemToRemove.value;
  itemToRemove.value = null;
  // o draft só pode sumir DEPOIS do item sair do store (o template lê
  // itemDrafts[item.id] enquanto o refetch não resolve)
  store
    .dispatch('theses/deleteItem', {
      thesisId: selectedThesis.value.id,
      id: item.id,
    })
    .then(() => delete itemDrafts[item.id])
    .catch(() => useAlert(t('RAMON.FUNIL.SAVE_ERROR')));
};

// Troca o item com o vizinho da mesma seção e manda a ordem da tese inteira
// (as posições são da tese, não da seção) pelo reorder já existente.
const moveItem = (section, index, direction) => {
  const daSecao = itemsBySection.value[section];
  const vizinho = daSecao[index + direction];
  if (!vizinho) return;
  const ids = (selectedThesis.value.items || []).map(item => item.id);
  const a = ids.indexOf(daSecao[index].id);
  const b = ids.indexOf(vizinho.id);
  [ids[a], ids[b]] = [ids[b], ids[a]];
  store
    .dispatch('theses/reorderItems', {
      thesisId: selectedThesis.value.id,
      ids,
    })
    .catch(e => useAlert(mensagemErro(e, t('RAMON.FUNIL.SAVE_ERROR'))));
};

const sectionUsoKey = section =>
  `RAMON.PLAYBOOKS.APARECE_EM.${section.toUpperCase()}`;

// marcador literal: dentro do template, as chaves duplas fechariam o {{ }}
const MARCADOR_NOME = '{{nome}}';

const sectionLabelKey = section =>
  `RAMON.PLAYBOOKS.SECTIONS.${section.toUpperCase()}`;

onMounted(() => store.dispatch('theses/get'));
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <RamonPageHeader class="!mb-0" :title="$t('RAMON.PLAYBOOKS.TITLE')" />

      <div class="flex flex-col items-start gap-5 md:flex-row">
        <!-- Teses: cartão fixo à esquerda enquanto o detalhe rola -->
        <aside
          class="flex w-full flex-col gap-3 md:sticky md:top-0 md:w-80 md:shrink-0"
          :class="CARTAO"
        >
          <h2 class="m-0" :class="TITULO">
            {{ $t('RAMON.PLAYBOOKS.LIST_TITLE') }}
          </h2>

          <ul
            data-testid="playbooks-list"
            class="m-0 flex list-none flex-col gap-0.5 p-0"
          >
            <li
              v-for="(thesis, index) in theses"
              :key="thesis.id"
              data-testid="playbooks-item"
              class="flex cursor-pointer items-center gap-1 rounded-lg py-1 pe-1 ps-2"
              :class="
                selectedId === thesis.id ? TOM.blue : 'hover:bg-n-alpha-2'
              "
              @click="selectThesis(thesis)"
            >
              <span
                class="min-w-0 flex-1 truncate text-sm"
                :class="
                  selectedId === thesis.id ? 'font-medium' : 'text-n-slate-12'
                "
              >
                {{ thesis.name }}
              </span>
              <span
                class="shrink-0"
                :class="[CHIP, thesis.active !== false ? TOM.teal : TOM.slate]"
              >
                {{
                  thesis.active !== false
                    ? $t('RAMON.PLAYBOOKS.ACTIVE')
                    : $t('RAMON.PLAYBOOKS.INACTIVE')
                }}
              </span>
              <Button
                data-testid="playbooks-item-up"
                xs
                ghost
                slate
                icon="i-lucide-chevron-up"
                :aria-label="$t('RAMON.PLAYBOOKS.MOVE_UP')"
                :disabled="index === 0"
                @click.stop="moveThesis(thesis, -1)"
              />
              <Button
                data-testid="playbooks-item-down"
                xs
                ghost
                slate
                icon="i-lucide-chevron-down"
                :aria-label="$t('RAMON.PLAYBOOKS.MOVE_DOWN')"
                :disabled="index === theses.length - 1"
                @click.stop="moveThesis(thesis, 1)"
              />
              <Button
                data-testid="playbooks-item-remove"
                xs
                ghost
                slate
                icon="i-lucide-trash-2"
                :aria-label="$t('RAMON.PLAYBOOKS.DELETE')"
                :title="$t('RAMON.PLAYBOOKS.DELETE')"
                @click.stop="removeThesis(thesis)"
              />
            </li>
            <li
              v-if="!uiFlags.isFetching && !theses.length"
              class="px-2 py-1.5 text-sm text-n-slate-10"
            >
              {{ $t('RAMON.PLAYBOOKS.EMPTY_LIST') }}
            </li>
          </ul>

          <div class="flex gap-2" :class="SECAO">
            <input
              v-model="newThesisName"
              data-testid="playbooks-add-input"
              class="min-w-0 flex-1"
              :class="CAMPO"
              :placeholder="$t('RAMON.PLAYBOOKS.ADD_PLACEHOLDER')"
              @keyup.enter="addThesis"
            />
            <Button
              data-testid="playbooks-add-button"
              sm
              class="shrink-0"
              :label="$t('RAMON.PLAYBOOKS.ADD')"
              :disabled="addingThesis"
              @click="addThesis"
            />
          </div>
        </aside>

        <div class="flex w-full min-w-0 flex-1 flex-col gap-5">
          <p
            v-if="!selectedThesis"
            data-testid="playbooks-empty-detail"
            class="m-0 py-6 text-center text-sm text-n-slate-10"
            :class="CARTAO"
          >
            {{ $t('RAMON.PLAYBOOKS.EMPTY_DETAIL') }}
          </p>

          <template v-else>
            <div
              class="flex flex-col gap-3 !p-4"
              :class="CARTAO"
              data-testid="playbooks-detail"
            >
              <div class="flex flex-wrap items-end gap-3">
                <label class="min-w-0 flex-1 md:min-w-64" :class="ROTULO">
                  {{ $t('RAMON.PLAYBOOKS.NAME') }}
                  <input
                    v-model="detail.name"
                    data-testid="playbooks-name-input"
                    class="!text-base font-medium"
                    :class="CAMPO_GRANDE"
                    :placeholder="$t('RAMON.PLAYBOOKS.NAME')"
                    @blur="saveDetail"
                  />
                </label>
                <label
                  class="flex items-center gap-2 whitespace-nowrap pb-2.5 text-sm text-n-slate-12"
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
              <label :class="ROTULO">
                {{ $t('RAMON.PLAYBOOKS.DESCRIPTION') }}
                <textarea
                  v-model="detail.description"
                  data-testid="playbooks-description-input"
                  rows="2"
                  :class="TEXTAREA"
                  :placeholder="$t('RAMON.PLAYBOOKS.DESCRIPTION')"
                  @blur="saveDetail"
                />
              </label>
              <div class="grid gap-3 md:grid-cols-3">
                <label :class="ROTULO">
                  {{ $t('RAMON.PLAYBOOKS.AREA') }}
                  <input
                    v-model="detail.area"
                    data-testid="playbooks-area-input"
                    :class="CAMPO"
                    :placeholder="$t('RAMON.PLAYBOOKS.AREA')"
                    @blur="saveDetail"
                  />
                </label>
                <label :class="ROTULO">
                  {{ $t('RAMON.PLAYBOOKS.HONORARIO_PERCENT') }}
                  <input
                    v-model="detail.honorarioPercentual"
                    type="number"
                    min="0"
                    max="100"
                    step="0.5"
                    data-testid="playbooks-honorario-percentual-input"
                    class="font-mono"
                    :class="CAMPO"
                    :placeholder="$t('RAMON.PLAYBOOKS.HONORARIO_PERCENT')"
                    @blur="saveDetail"
                  />
                </label>
                <label :class="ROTULO">
                  {{ $t('RAMON.PLAYBOOKS.HONORARIO_INSTALLMENTS') }}
                  <input
                    v-model="detail.honorarioNMensalidades"
                    type="number"
                    min="0"
                    step="1"
                    data-testid="playbooks-honorario-mensalidades-input"
                    class="font-mono"
                    :class="CAMPO"
                    :placeholder="$t('RAMON.PLAYBOOKS.HONORARIO_INSTALLMENTS')"
                    @blur="saveDetail"
                  />
                </label>
              </div>
            </div>

            <p
              data-testid="playbooks-nome-hint"
              class="m-0 flex items-center gap-1.5 text-xs text-n-slate-10"
            >
              <span class="i-lucide-info size-3.5 shrink-0" />
              {{ $t('RAMON.PLAYBOOKS.NOME_HINT', { marcador: MARCADOR_NOME }) }}
            </p>

            <!-- Seções em coluna única: roteiro longo pede linha larga (lado a lado
                 o campo de novo item ficava estreito demais) -->
            <div class="flex flex-col gap-5">
              <section
                v-for="section in SECTIONS"
                :key="section"
                class="flex flex-col gap-3 !p-4"
                :class="CARTAO"
                data-testid="playbooks-section"
              >
                <div>
                  <h3 class="m-0" :class="TITULO">
                    {{ $t(sectionLabelKey(section)) }}
                  </h3>
                  <!-- onde o item desta seção é usado (conferido no código) -->
                  <p
                    data-testid="playbooks-section-uso"
                    class="m-0 mt-1 text-xs text-n-slate-10"
                  >
                    {{ $t(sectionUsoKey(section)) }}
                  </p>
                </div>

                <!-- itens separados por linha, sem caixa dentro do cartão -->
                <ul
                  class="m-0 flex list-none flex-col divide-y divide-n-weak p-0"
                >
                  <li
                    v-for="(item, itemIndex) in itemsBySection[section]"
                    :key="item.id"
                    data-testid="playbooks-item-row"
                    class="flex flex-col gap-1.5 py-3 first:pt-0"
                  >
                    <div class="flex items-center gap-1">
                      <input
                        v-model="itemDrafts[item.id].title"
                        data-testid="playbooks-item-title-input"
                        class="flex-1 font-medium"
                        :class="CAMPO"
                        :placeholder="
                          $t('RAMON.PLAYBOOKS.ITEM_TITLE_PLACEHOLDER')
                        "
                        @blur="saveItem(item)"
                      />
                      <Button
                        data-testid="playbooks-item-move-up"
                        xs
                        ghost
                        slate
                        icon="i-lucide-chevron-up"
                        :aria-label="$t('RAMON.PLAYBOOKS.MOVE_UP')"
                        :disabled="itemIndex === 0"
                        @click="moveItem(section, itemIndex, -1)"
                      />
                      <Button
                        data-testid="playbooks-item-move-down"
                        xs
                        ghost
                        slate
                        icon="i-lucide-chevron-down"
                        :aria-label="$t('RAMON.PLAYBOOKS.MOVE_DOWN')"
                        :disabled="
                          itemIndex === itemsBySection[section].length - 1
                        "
                        @click="moveItem(section, itemIndex, 1)"
                      />
                      <Button
                        data-testid="playbooks-item-remove-item"
                        xs
                        ghost
                        slate
                        icon="i-lucide-trash-2"
                        :aria-label="$t('RAMON.PLAYBOOKS.ITEM_DELETE')"
                        :title="$t('RAMON.PLAYBOOKS.ITEM_DELETE')"
                        @click="removeItem(item)"
                      />
                    </div>
                    <!-- field-sizing: auto-cresce com o roteiro (fallback = rows fixo) -->
                    <textarea
                      v-model="itemDrafts[item.id].content"
                      data-testid="playbooks-item-content-input"
                      rows="2"
                      class="max-h-64 min-h-16 [field-sizing:content]"
                      :class="TEXTAREA"
                      :placeholder="
                        $t('RAMON.PLAYBOOKS.ITEM_CONTENT_PLACEHOLDER')
                      "
                      @blur="saveItem(item)"
                    />
                  </li>
                  <li
                    v-if="!itemsBySection[section].length"
                    class="text-xs text-n-slate-10"
                  >
                    {{ $t('RAMON.PLAYBOOKS.ITEM_EMPTY') }}
                  </li>
                </ul>

                <div class="flex gap-2" :class="SECAO">
                  <input
                    v-model="newItemDrafts[section].title"
                    data-testid="playbooks-item-add-title"
                    class="!w-40 shrink-0"
                    :class="CAMPO"
                    :placeholder="$t('RAMON.PLAYBOOKS.ITEM_TITLE_PLACEHOLDER')"
                    @keyup.enter="addItem(section)"
                  />
                  <input
                    v-model="newItemDrafts[section].content"
                    data-testid="playbooks-item-add-content"
                    class="min-w-0 flex-1"
                    :class="CAMPO"
                    :placeholder="
                      $t('RAMON.PLAYBOOKS.ITEM_CONTENT_PLACEHOLDER')
                    "
                    @keyup.enter="addItem(section)"
                  />
                  <Button
                    data-testid="playbooks-item-add"
                    sm
                    faded
                    slate
                    icon="i-lucide-plus"
                    class="shrink-0"
                    :label="$t('RAMON.PLAYBOOKS.ITEM_ADD')"
                    :disabled="addingItem === section"
                    @click="addItem(section)"
                  />
                </div>
              </section>
            </div>
          </template>
        </div>
      </div>
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

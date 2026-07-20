<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RamonLeadImportsAPI from 'dashboard/api/ramonLeadImports';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import ConfirmModal from '../components/ConfirmModal.vue';

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const benefits = computed(() => getters['leadConfig/getBenefitTypes'].value);
const priorities = computed(() => getters['leadConfig/getPriorities'].value);
const stages = computed(() => getters['leadConfig/getStages'].value);

const saveStalled = (stage, raw) => {
  const days = raw === '' ? null : Math.max(0, Math.floor(Number(raw)));
  if (days === (stage.stalled_after_days ?? null)) return;
  store
    .dispatch('leadConfig/updateStage', {
      id: stage.id,
      stalled_after_days: days,
    })
    .catch(() => useAlert(t('RAMON.FUNIL.SAVE_ERROR')));
};

const newBenefit = ref('');
const newPriority = ref('');
const newWeight = ref(1);

const addingBenefit = ref(false);
const addBenefit = async () => {
  const name = newBenefit.value.trim();
  if (!name || addingBenefit.value) return;
  addingBenefit.value = true;
  try {
    await store.dispatch('leadConfig/createBenefitType', { name });
    newBenefit.value = '';
  } catch {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  } finally {
    addingBenefit.value = false;
  }
};
const benefitToRemove = ref(null);
const removeBenefit = benefit => {
  benefitToRemove.value = benefit;
};
const confirmRemoveBenefit = () => {
  const benefit = benefitToRemove.value;
  if (!benefit) return;
  // Fecha o modal antes do await: sem janela pra duplo-clique despachar 2x.
  benefitToRemove.value = null;
  store
    .dispatch('leadConfig/deleteBenefitType', benefit.id)
    .catch(() => useAlert(t('RAMON.FUNIL_CONFIG.REMOVE_ERROR')));
};

const addingPriority = ref(false);
const addPriority = async () => {
  const name = newPriority.value.trim();
  if (!name || addingPriority.value) return;
  addingPriority.value = true;
  try {
    await store.dispatch('leadConfig/createPriority', {
      name,
      weight: Number(newWeight.value) || 0,
    });
    newPriority.value = '';
    newWeight.value = 1;
  } catch {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
  } finally {
    addingPriority.value = false;
  }
};
const priorityToRemove = ref(null);
const removePriority = priority => {
  priorityToRemove.value = priority;
};
const confirmRemovePriority = () => {
  const priority = priorityToRemove.value;
  if (!priority) return;
  priorityToRemove.value = null;
  store
    .dispatch('leadConfig/deletePriority', priority.id)
    .catch(() => useAlert(t('RAMON.FUNIL_CONFIG.REMOVE_ERROR')));
};

const loadError = ref(false);
const loadConfig = async () => {
  loadError.value = false;
  try {
    await store.dispatch('leadConfig/get');
  } catch {
    loadError.value = true;
  }
};
onMounted(loadConfig);

const importFileInput = ref(null);
const importing = ref(false);
const hasImportFile = ref(false);

const onImportFileChange = () => {
  hasImportFile.value = !!importFileInput.value?.files?.length;
};

const submitImport = async () => {
  const file = importFileInput.value?.files?.[0];
  if (!file) return;
  importing.value = true;
  try {
    await RamonLeadImportsAPI.create(file);
    useAlert(t('RAMON.IMPORT.SENT'));
    importFileInput.value.value = '';
    hasImportFile.value = false;
  } catch (e) {
    useAlert(t('RAMON.IMPORT.ERROR'));
  } finally {
    importing.value = false;
  }
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full p-4 sm:p-8 overflow-y-auto bg-n-background"
  >
    <RamonPageHeader :title="$t('RAMON.FUNIL_CONFIG.TITLE')" />

    <div
      v-if="loadError"
      class="flex items-center gap-3 mb-6"
      data-testid="funil-config-error"
    >
      <p class="text-sm text-n-ruby-11">
        {{ $t('RAMON.FUNIL_CONFIG.LOAD_ERROR') }}
      </p>
      <button
        data-testid="funil-config-retry"
        class="text-sm text-n-iris-11 hover:underline"
        @click="loadConfig"
      >
        {{ $t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <section class="mb-8 max-w-2xl">
      <h2 class="mb-3 text-xs uppercase tracking-widest text-n-slate-9">
        {{ $t('RAMON.FUNIL_CONFIG.BENEFITS') }}
      </h2>
      <ul class="mb-3 rounded-lg border border-n-weak divide-y divide-n-weak">
        <li
          v-for="b in benefits"
          :key="b.id"
          class="flex items-center justify-between px-3 py-2 hover:bg-n-alpha-2"
        >
          <span class="text-sm text-n-slate-12">{{ b.name }}</span>
          <button
            data-testid="benefit-remove"
            class="text-n-slate-9 hover:text-n-ruby-11"
            :title="$t('RAMON.FUNIL_CONFIG.REMOVE')"
            @click="removeBenefit(b)"
          >
            <span class="i-lucide-trash-2 size-4" />
          </button>
        </li>
        <li v-if="!benefits.length" class="px-3 py-2 text-sm text-n-slate-10">
          {{ $t('RAMON.FUNIL_CONFIG.BENEFITS_EMPTY') }}
        </li>
      </ul>
      <div class="flex gap-2">
        <input
          v-model="newBenefit"
          data-testid="benefit-new-input"
          class="flex-1 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          :placeholder="$t('RAMON.FUNIL_CONFIG.BENEFIT_PLACEHOLDER')"
          @keyup.enter="addBenefit"
        />
        <button
          data-testid="benefit-add"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
          :disabled="addingBenefit"
          @click="addBenefit"
        >
          {{ $t('RAMON.FUNIL_CONFIG.ADD') }}
        </button>
      </div>
    </section>

    <section class="max-w-2xl">
      <h2 class="mb-3 text-xs uppercase tracking-widest text-n-slate-9">
        {{ $t('RAMON.FUNIL_CONFIG.PRIORITIES') }}
      </h2>
      <ul class="mb-3 rounded-lg border border-n-weak divide-y divide-n-weak">
        <li
          v-for="p in priorities"
          :key="p.id"
          class="flex items-center justify-between px-3 py-2 hover:bg-n-alpha-2"
        >
          <span class="text-sm text-n-slate-12">{{ p.name }}</span>
          <span class="flex items-center gap-3">
            <span class="text-xs text-n-slate-9">
              {{ $t('RAMON.FUNIL_CONFIG.WEIGHT_OF', { weight: p.weight }) }}
            </span>
            <button
              data-testid="priority-remove"
              class="text-n-slate-9 hover:text-n-ruby-11"
              :title="$t('RAMON.FUNIL_CONFIG.REMOVE')"
              @click="removePriority(p)"
            >
              <span class="i-lucide-trash-2 size-4" />
            </button>
          </span>
        </li>
        <li v-if="!priorities.length" class="px-3 py-2 text-sm text-n-slate-10">
          {{ $t('RAMON.FUNIL_CONFIG.PRIORITIES_EMPTY') }}
        </li>
      </ul>
      <div class="flex gap-2">
        <input
          v-model="newPriority"
          data-testid="priority-new-input"
          class="flex-1 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          :placeholder="$t('RAMON.FUNIL_CONFIG.PRIORITY_PLACEHOLDER')"
          @keyup.enter="addPriority"
        />
        <label class="flex items-center gap-1.5 text-xs text-n-slate-10">
          {{ $t('RAMON.FUNIL_CONFIG.WEIGHT') }}
          <input
            v-model="newWeight"
            type="number"
            data-testid="priority-weight"
            class="w-16 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
          />
        </label>
        <button
          data-testid="priority-add"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
          :disabled="addingPriority"
          @click="addPriority"
        >
          {{ $t('RAMON.FUNIL_CONFIG.ADD') }}
        </button>
      </div>
    </section>

    <section class="mt-8 max-w-2xl">
      <h2 class="mb-1 text-xs uppercase tracking-widest text-n-slate-9">
        {{ $t('RAMON.FUNIL_CONFIG.CADENCE') }}
      </h2>
      <p class="mb-3 text-xs text-n-slate-10">
        {{ $t('RAMON.FUNIL_CONFIG.CADENCE_HINT') }}
      </p>
      <ul class="rounded-lg border border-n-weak divide-y divide-n-weak">
        <li
          v-for="s in stages"
          :key="s.id"
          class="flex items-center justify-between px-3 py-2 hover:bg-n-alpha-2"
        >
          <span class="text-sm text-n-slate-12">{{ s.name }}</span>
          <span class="flex items-center gap-2">
            <input
              :value="s.stalled_after_days"
              data-testid="stage-stalled-days"
              type="number"
              min="0"
              class="w-20 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
              @change="e => saveStalled(s, e.target.value)"
            />
            <span class="text-xs text-n-slate-9">{{
              $t('RAMON.FUNIL_CONFIG.CADENCE_DAYS')
            }}</span>
          </span>
        </li>
      </ul>
    </section>

    <section class="mt-8 max-w-2xl" data-testid="import-leads-section">
      <h2 class="mb-1 text-xs uppercase tracking-widest text-n-slate-9">
        {{ $t('RAMON.IMPORT.TITLE') }}
      </h2>
      <p class="mb-3 text-xs text-n-slate-10">
        {{ $t('RAMON.IMPORT.HINT') }}
        <a
          href="/downloads/import-leads-sample.csv"
          download
          class="text-n-iris-11 hover:underline"
        >
          {{ $t('RAMON.IMPORT.SAMPLE') }}
        </a>
      </p>
      <div class="flex items-center gap-2">
        <input
          ref="importFileInput"
          data-testid="import-leads-file"
          type="file"
          accept=".csv"
          class="text-sm text-n-slate-11"
          @change="onImportFileChange"
        />
        <button
          data-testid="import-leads-submit"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
          :disabled="importing || !hasImportFile"
          @click="submitImport"
        >
          {{ $t('RAMON.IMPORT.SUBMIT') }}
        </button>
      </div>
    </section>
    <ConfirmModal
      v-if="benefitToRemove"
      :title="$t('RAMON.FUNIL_CONFIG.REMOVE_BENEFIT_CONFIRM')"
      :message="benefitToRemove.name"
      :confirm-label="$t('RAMON.FUNIL_CONFIG.REMOVE')"
      @confirm="confirmRemoveBenefit"
      @cancel="benefitToRemove = null"
    />
    <ConfirmModal
      v-if="priorityToRemove"
      :title="$t('RAMON.FUNIL_CONFIG.REMOVE_PRIORITY_CONFIRM')"
      :message="priorityToRemove.name"
      :confirm-label="$t('RAMON.FUNIL_CONFIG.REMOVE')"
      @confirm="confirmRemovePriority"
      @cancel="priorityToRemove = null"
    />
  </div>
</template>

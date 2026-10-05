<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RamonLeadImportsAPI from 'dashboard/api/ramonLeadImports';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { DEFAULT_STAGE_COLOR } from '../helpers/stage';
import {
  CARTAO,
  SECAO,
  TITULO,
  CAMPO,
  ARQUIVO,
  AVISO,
  TOM,
} from '../helpers/ui';

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

const saveProbability = (stage, raw) => {
  const value =
    raw === '' ? null : Math.max(0, Math.min(100, Math.floor(Number(raw))));
  if (value === (stage.probability ?? null)) return;
  store
    .dispatch('leadConfig/updateStage', { id: stage.id, probability: value })
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
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <RamonPageHeader class="!mb-0" :title="$t('RAMON.FUNIL_CONFIG.TITLE')" />

      <div
        v-if="loadError"
        class="flex items-center gap-3"
        :class="[AVISO, TOM.ruby]"
        data-testid="funil-config-error"
      >
        <p class="m-0 text-sm">
          {{ $t('RAMON.FUNIL_CONFIG.LOAD_ERROR') }}
        </p>
        <Button
          data-testid="funil-config-retry"
          link
          xs
          :label="$t('RAMON.LEAD_PANEL.RETRY')"
          @click="loadConfig"
        />
      </div>

      <section class="flex flex-col gap-3" :class="CARTAO">
        <h2 class="m-0" :class="TITULO">
          {{ $t('RAMON.FUNIL_CONFIG.BENEFITS') }}
        </h2>
        <ul class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
          <li
            v-for="b in benefits"
            :key="b.id"
            class="flex items-center justify-between py-1.5"
          >
            <span class="text-sm text-n-slate-12">{{ b.name }}</span>
            <Button
              data-testid="benefit-remove"
              xs
              ghost
              slate
              icon="i-lucide-trash-2"
              :aria-label="$t('RAMON.FUNIL_CONFIG.REMOVE')"
              :title="$t('RAMON.FUNIL_CONFIG.REMOVE')"
              @click="removeBenefit(b)"
            />
          </li>
          <li v-if="!benefits.length" class="py-1.5 text-sm text-n-slate-10">
            {{ $t('RAMON.FUNIL_CONFIG.BENEFITS_EMPTY') }}
          </li>
        </ul>
        <div class="flex gap-2" :class="SECAO">
          <input
            v-model="newBenefit"
            data-testid="benefit-new-input"
            class="flex-1"
            :class="CAMPO"
            :placeholder="$t('RAMON.FUNIL_CONFIG.BENEFIT_PLACEHOLDER')"
            @keyup.enter="addBenefit"
          />
          <Button
            data-testid="benefit-add"
            sm
            class="shrink-0"
            :label="$t('RAMON.FUNIL_CONFIG.ADD')"
            :disabled="addingBenefit"
            @click="addBenefit"
          />
        </div>
      </section>

      <section class="flex flex-col gap-3" :class="CARTAO">
        <h2 class="m-0" :class="TITULO">
          {{ $t('RAMON.FUNIL_CONFIG.PRIORITIES') }}
        </h2>
        <ul class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
          <li
            v-for="p in priorities"
            :key="p.id"
            class="flex items-center justify-between py-1.5"
          >
            <span class="text-sm text-n-slate-12">{{ p.name }}</span>
            <span class="flex items-center gap-3">
              <span class="font-mono text-xs text-n-slate-10">
                {{ $t('RAMON.FUNIL_CONFIG.WEIGHT_OF', { weight: p.weight }) }}
              </span>
              <Button
                data-testid="priority-remove"
                xs
                ghost
                slate
                icon="i-lucide-trash-2"
                :aria-label="$t('RAMON.FUNIL_CONFIG.REMOVE')"
                :title="$t('RAMON.FUNIL_CONFIG.REMOVE')"
                @click="removePriority(p)"
              />
            </span>
          </li>
          <li v-if="!priorities.length" class="py-1.5 text-sm text-n-slate-10">
            {{ $t('RAMON.FUNIL_CONFIG.PRIORITIES_EMPTY') }}
          </li>
        </ul>
        <div class="flex items-center gap-2" :class="SECAO">
          <input
            v-model="newPriority"
            data-testid="priority-new-input"
            class="flex-1"
            :class="CAMPO"
            :placeholder="$t('RAMON.FUNIL_CONFIG.PRIORITY_PLACEHOLDER')"
            @keyup.enter="addPriority"
          />
          <label class="flex items-center gap-1.5 text-xs text-n-slate-10">
            {{ $t('RAMON.FUNIL_CONFIG.WEIGHT') }}
            <input
              v-model="newWeight"
              type="number"
              data-testid="priority-weight"
              class="!w-16 font-mono"
              :class="CAMPO"
            />
          </label>
          <Button
            data-testid="priority-add"
            sm
            class="shrink-0"
            :label="$t('RAMON.FUNIL_CONFIG.ADD')"
            :disabled="addingPriority"
            @click="addPriority"
          />
        </div>
      </section>

      <section class="flex flex-col gap-3" :class="CARTAO">
        <div>
          <h2 class="m-0" :class="TITULO">
            {{ $t('RAMON.FUNIL_CONFIG.CADENCE') }}
          </h2>
          <p class="m-0 mt-1 text-xs text-n-slate-10">
            {{ $t('RAMON.FUNIL_CONFIG.CADENCE_HINT') }}
          </p>
        </div>
        <ul class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
          <li
            v-for="s in stages"
            :key="s.id"
            class="flex items-center justify-between gap-3 py-1.5"
          >
            <!-- mesma pílula de etapa do Funil (cor da etapa, fundo translúcido) -->
            <span class="flex min-w-0 items-center gap-1.5">
              <span
                class="ramon-stage-pill inline-flex min-w-0 items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-[12px] font-semibold"
                :style="{ '--stage': s.color || DEFAULT_STAGE_COLOR }"
              >
                <span class="size-1.5 shrink-0 rounded-full bg-current" />
                <span class="truncate">{{ s.name }}</span>
              </span>
              <span
                v-if="s.is_won"
                class="i-lucide-trophy size-3 shrink-0 text-n-amber-11"
              />
              <span
                v-if="s.is_lost"
                class="i-lucide-x-circle size-3 shrink-0 text-n-ruby-11"
              />
            </span>
            <span class="flex shrink-0 items-center gap-2">
              <input
                :value="s.stalled_after_days"
                data-testid="stage-stalled-days"
                type="number"
                min="0"
                class="!w-20 font-mono"
                :class="CAMPO"
                @change="e => saveStalled(s, e.target.value)"
              />
              <span class="whitespace-nowrap text-xs text-n-slate-10">{{
                $t('RAMON.FUNIL_CONFIG.CADENCE_DAYS')
              }}</span>
              <input
                :value="s.probability"
                data-testid="stage-probability"
                type="number"
                min="0"
                max="100"
                :title="$t('RAMON.FUNIL_CONFIG.PROBABILITY_HINT')"
                class="ms-2 !w-20 font-mono"
                :class="CAMPO"
                @change="e => saveProbability(s, e.target.value)"
              />
              <span class="whitespace-nowrap text-xs text-n-slate-10">{{
                $t('RAMON.FUNIL_CONFIG.PROBABILITY')
              }}</span>
            </span>
          </li>
        </ul>
      </section>

      <section
        class="flex flex-col gap-3"
        :class="CARTAO"
        data-testid="import-leads-section"
      >
        <div>
          <h2 class="m-0" :class="TITULO">
            {{ $t('RAMON.IMPORT.TITLE') }}
          </h2>
          <p class="m-0 mt-1 text-xs text-n-slate-10">
            {{ $t('RAMON.IMPORT.HINT') }}
            <a
              href="/downloads/import-leads-sample.csv"
              download
              class="text-xs text-n-blue-11 hover:underline"
            >
              {{ $t('RAMON.IMPORT.SAMPLE') }}
            </a>
          </p>
        </div>
        <div class="flex items-center gap-2">
          <input
            ref="importFileInput"
            data-testid="import-leads-file"
            type="file"
            accept=".csv"
            class="flex-1"
            :class="ARQUIVO"
            @change="onImportFileChange"
          />
          <Button
            data-testid="import-leads-submit"
            sm
            class="shrink-0"
            :label="$t('RAMON.IMPORT.SUBMIT')"
            :disabled="importing || !hasImportFile"
            @click="submitImport"
          />
        </div>
      </section>
    </div>
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

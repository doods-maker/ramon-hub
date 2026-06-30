<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';

const store = useStore();
const getters = useStoreGetters();

const benefits = computed(() => getters['leadConfig/getBenefitTypes'].value);
const priorities = computed(() => getters['leadConfig/getPriorities'].value);

const newBenefit = ref('');
const newPriority = ref('');
const newWeight = ref(1);

const addBenefit = async () => {
  const name = newBenefit.value.trim();
  if (!name) return;
  await store.dispatch('leadConfig/createBenefitType', { name });
  newBenefit.value = '';
};
const removeBenefit = id => store.dispatch('leadConfig/deleteBenefitType', id);

const addPriority = async () => {
  const name = newPriority.value.trim();
  if (!name) return;
  await store.dispatch('leadConfig/createPriority', {
    name,
    weight: Number(newWeight.value) || 0,
  });
  newPriority.value = '';
  newWeight.value = 1;
};
const removePriority = id => store.dispatch('leadConfig/deletePriority', id);

onMounted(() => store.dispatch('leadConfig/get'));
</script>

<template>
  <div class="flex flex-col h-full p-6 overflow-y-auto">
    <h1 class="mb-6 text-xl font-cormorant text-n-slate-12">
      {{ $t('RAMON.FUNIL_CONFIG.TITLE') }}
    </h1>

    <section class="mb-8">
      <h2 class="mb-3 text-sm uppercase tracking-widest text-n-slate-9">
        {{ $t('RAMON.FUNIL_CONFIG.BENEFITS') }}
      </h2>
      <ul class="mb-3">
        <li
          v-for="b in benefits"
          :key="b.id"
          class="flex items-center justify-between px-3 py-2 rounded-lg hover:bg-n-alpha-2"
        >
          <span class="text-sm text-n-slate-12">{{ b.name }}</span>
          <button
            data-testid="benefit-remove"
            class="text-n-ruby-11"
            @click="removeBenefit(b.id)"
          >
            <span class="i-lucide-trash-2 size-4" />
          </button>
        </li>
      </ul>
      <div class="flex gap-2">
        <input
          v-model="newBenefit"
          data-testid="benefit-new-input"
          class="flex-1 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
          :placeholder="$t('RAMON.FUNIL_CONFIG.BENEFIT_PLACEHOLDER')"
          @keyup.enter="addBenefit"
        />
        <button
          data-testid="benefit-add"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white"
          @click="addBenefit"
        >
          {{ $t('RAMON.FUNIL_CONFIG.ADD') }}
        </button>
      </div>
    </section>

    <section>
      <h2 class="mb-3 text-sm uppercase tracking-widest text-n-slate-9">
        {{ $t('RAMON.FUNIL_CONFIG.PRIORITIES') }}
      </h2>
      <ul class="mb-3">
        <li
          v-for="p in priorities"
          :key="p.id"
          class="flex items-center justify-between px-3 py-2 rounded-lg hover:bg-n-alpha-2"
        >
          <span class="text-sm text-n-slate-12">{{ p.name }}</span>
          <span class="flex items-center gap-3">
            <span class="text-xs text-n-slate-9">{{ p.weight }}</span>
            <button
              data-testid="priority-remove"
              class="text-n-ruby-11"
              @click="removePriority(p.id)"
            >
              <span class="i-lucide-trash-2 size-4" />
            </button>
          </span>
        </li>
      </ul>
      <div class="flex gap-2">
        <input
          v-model="newPriority"
          data-testid="priority-new-input"
          class="flex-1 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
          :placeholder="$t('RAMON.FUNIL_CONFIG.PRIORITY_PLACEHOLDER')"
          @keyup.enter="addPriority"
        />
        <input
          v-model="newWeight"
          type="number"
          data-testid="priority-weight"
          class="w-20 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
        />
        <button
          data-testid="priority-add"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white"
          @click="addPriority"
        >
          {{ $t('RAMON.FUNIL_CONFIG.ADD') }}
        </button>
      </div>
    </section>
  </div>
</template>

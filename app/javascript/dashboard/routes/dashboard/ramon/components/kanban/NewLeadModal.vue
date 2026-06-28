<script setup>
import { ref, computed } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';

const emit = defineEmits(['close', 'created']);
const store = useStore();
const getters = useStoreGetters();

const name = ref('');
const benefitTypeId = ref(null);
const stages = computed(() => getters['leadConfig/getStages'].value);
const benefitTypes = computed(
  () => getters['leadConfig/getBenefitTypes'].value
);

const submit = async () => {
  const firstStage = stages.value[0];
  if (!name.value || !firstStage) return;
  const lead = await store.dispatch('leads/create', {
    name: name.value,
    lead_stage_id: firstStage.id,
    benefit_type_id: benefitTypeId.value,
  });
  emit('created', lead);
  emit('close');
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="emit('close')"
  >
    <div class="w-96 p-5 rounded-2xl bg-n-solid-1 border border-n-weak">
      <h2 class="mb-4 text-lg font-cormorant text-n-slate-12">
        {{ $t('RAMON.FUNIL.NEW_LEAD') }}
      </h2>
      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.FUNIL.LEAD_NAME')
      }}</label>
      <input
        v-model="name"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      />
      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.FUNIL.BENEFIT')
      }}</label>
      <select
        v-model="benefitTypeId"
        class="w-full px-3 py-2 mb-4 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      >
        <option :value="null">—</option>
        <option v-for="b in benefitTypes" :key="b.id" :value="b.id">
          {{ b.name }}
        </option>
      </select>
      <div class="flex justify-end gap-2">
        <button
          class="px-3 py-1.5 text-sm text-n-slate-11"
          @click="emit('close')"
        >
          {{ $t('RAMON.FUNIL.CANCEL') }}
        </button>
        <button
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white"
          @click="submit"
        >
          {{ $t('RAMON.FUNIL.SAVE') }}
        </button>
      </div>
    </div>
  </div>
</template>

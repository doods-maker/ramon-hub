<script setup>
import { ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const props = defineProps({ lead: { type: Object, required: true } });

const store = useStore();
const stages = useMapGetter('leadConfig/getStages');
const benefitTypes = useMapGetter('leadConfig/getBenefitTypes');
const priorities = useMapGetter('leadConfig/getPriorities');
const agents = useMapGetter('agents/getAgents');

// refs locais editáveis, ressincronizados sempre que o lead muda
const name = ref('');
const value = ref('');
const source = ref('');
const notes = ref('');

watch(
  () => props.lead,
  l => {
    name.value = l?.name ?? '';
    value.value = l?.value ?? '';
    source.value = l?.source ?? '';
    notes.value = l?.notes ?? '';
  },
  { immediate: true }
);

const save = payload => {
  store.dispatch('leads/update', { id: props.lead.id, ...payload });
};

// texto: salva no blur só se mudou
const saveText = (key, refVal, original) => {
  const next = refVal.value === '' ? null : refVal.value;
  const prev = original ?? null;
  if (next === prev) return;
  save({ [key]: next });
};

const saveName = () => saveText('name', name, props.lead?.name);
const saveSource = () => saveText('source', source, props.lead?.source);
const saveNotes = () => saveText('notes', notes, props.lead?.notes);
const saveValue = () => {
  const next = value.value === '' ? null : Number(value.value);
  const prev = props.lead?.value == null ? null : Number(props.lead.value);
  if (next === prev) return;
  save({ value: next });
};

// select: salva direto no change
const saveSelect = (key, val) => save({ [key]: val === '' ? null : val });
</script>

<template>
  <div>
    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.NAME')
    }}</label>
    <input
      v-model="name"
      data-testid="field-name"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @blur="saveName"
    />

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.STAGE')
    }}</label>
    <select
      data-testid="field-stage"
      :value="lead.lead_stage_id"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @change="e => saveSelect('lead_stage_id', Number(e.target.value))"
    >
      <option v-for="s in stages" :key="s.id" :value="s.id">
        {{ s.name }}
      </option>
    </select>

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.BENEFIT')
    }}</label>
    <select
      :value="lead.benefit_type_id"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @change="
        e =>
          saveSelect(
            'benefit_type_id',
            e.target.value ? Number(e.target.value) : null
          )
      "
    >
      <option value="">—</option>
      <option v-for="b in benefitTypes" :key="b.id" :value="b.id">
        {{ b.name }}
      </option>
    </select>

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.PRIORITY')
    }}</label>
    <select
      :value="lead.lead_priority_id"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @change="
        e =>
          saveSelect(
            'lead_priority_id',
            e.target.value ? Number(e.target.value) : null
          )
      "
    >
      <option value="">—</option>
      <option v-for="p in priorities" :key="p.id" :value="p.id">
        {{ p.name }}
      </option>
    </select>

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.SDR')
    }}</label>
    <select
      :value="lead.sdr_id"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @change="
        e =>
          saveSelect('sdr_id', e.target.value ? Number(e.target.value) : null)
      "
    >
      <option value="">—</option>
      <option v-for="a in agents" :key="a.id" :value="a.id">
        {{ a.name }}
      </option>
    </select>

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.CLOSER')
    }}</label>
    <select
      :value="lead.closer_id"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @change="
        e =>
          saveSelect(
            'closer_id',
            e.target.value ? Number(e.target.value) : null
          )
      "
    >
      <option value="">—</option>
      <option v-for="a in agents" :key="a.id" :value="a.id">
        {{ a.name }}
      </option>
    </select>

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.VALUE')
    }}</label>
    <input
      v-model="value"
      data-testid="field-value"
      type="number"
      step="0.01"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @blur="saveValue"
    />

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.SOURCE')
    }}</label>
    <input
      v-model="source"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @blur="saveSource"
    />

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.NOTES')
    }}</label>
    <textarea
      v-model="notes"
      rows="3"
      class="w-full px-3 py-2 mb-4 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @blur="saveNotes"
    />

    <!-- Só leitura: contato -->
    <div class="pt-4 mt-2 border-t border-n-weak">
      <p class="mb-2 text-[9px] tracking-widest uppercase text-n-slate-9">
        {{ $t('RAMON.DRAWER.CONTACT') }}
      </p>
      <p v-if="lead.contact_name" class="text-sm text-n-slate-12">
        {{ lead.contact_name }}
      </p>
      <p v-if="lead.contact_phone" class="text-xs text-n-slate-10">
        {{ lead.contact_phone }}
      </p>
      <p v-if="lead.contact_email" class="text-xs text-n-slate-10">
        {{ lead.contact_email }}
      </p>
    </div>
  </div>
</template>

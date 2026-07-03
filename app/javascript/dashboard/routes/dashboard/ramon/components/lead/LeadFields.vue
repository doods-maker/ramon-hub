<script setup>
import { ref, watch, computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import LeadTasksList from './LeadTasksList.vue';
import DocChecklist from './DocChecklist.vue';

const props = defineProps({ lead: { type: Object, required: true } });

const store = useStore();
const stages = useMapGetter('leadConfig/getStages');
const benefitTypes = useMapGetter('leadConfig/getBenefitTypes');
const priorities = useMapGetter('leadConfig/getPriorities');
const lostReasons = useMapGetter('leadConfig/getLostReasons');
const agents = useMapGetter('agents/getAgents');
const theses = useMapGetter('theses/getTheses');
const activeTheses = computed(() => theses.value.filter(t => t.active));

// Motivo da perda só aparece quando o lead está numa etapa marcada como perda.
const currentStage = computed(() =>
  stages.value.find(s => s.id === props.lead?.lead_stage_id)
);
const isLostStage = computed(() => !!currentStage.value?.is_lost);
const reasonNames = computed(() => lostReasons.value.map(r => r.name));

// refs locais editáveis, ressincronizados sempre que o lead muda
const name = ref('');
const value = ref('');
const source = ref('');

watch(
  () => props.lead,
  l => {
    name.value = l?.name ?? '';
    value.value = l?.value ?? '';
    source.value = l?.source ?? '';
  },
  { immediate: true }
);

// notas discretas: lista + adicionar
const noteList = ref([]);
const newNote = ref('');

const loadNotes = async () => {
  noteList.value =
    (await store.dispatch('leads/fetchNotes', props.lead.id)) || [];
};

watch(
  () => props.lead?.id,
  id => {
    if (id) loadNotes();
  },
  { immediate: true }
);

const addNote = async () => {
  const body = newNote.value.trim();
  if (!body) return;
  await store.dispatch('leads/createNote', { leadId: props.lead.id, body });
  newNote.value = '';
  await loadNotes();
};

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
      $t('RAMON.DRAWER.THESIS')
    }}</label>
    <select
      data-testid="field-thesis"
      :value="lead.thesis_id"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @change="
        e =>
          saveSelect(
            'thesis_id',
            e.target.value ? Number(e.target.value) : null
          )
      "
    >
      <option value="">—</option>
      <option v-for="t in activeTheses" :key="t.id" :value="t.id">
        {{ t.name }}
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

    <template v-if="isLostStage">
      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.DRAWER.LOST_REASON')
      }}</label>
      <select
        data-testid="field-lost-reason"
        :value="lead.lost_reason"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @change="e => saveSelect('lost_reason', e.target.value)"
      >
        <option value="">—</option>
        <option
          v-if="lead.lost_reason && !reasonNames.includes(lead.lost_reason)"
          :value="lead.lost_reason"
        >
          {{ lead.lost_reason }}
        </option>
        <option v-for="r in lostReasons" :key="r.id" :value="r.name">
          {{ r.name }}
        </option>
      </select>
    </template>

    <LeadTasksList v-if="lead.id" :lead-id="lead.id" />

    <DocChecklist v-if="lead.thesis_id" :lead="lead" />

    <div class="flex flex-col gap-2 mb-4">
      <span class="text-xs uppercase text-n-slate-10">{{
        $t('RAMON.DRAWER.NOTES')
      }}</span>
      <div
        v-for="note in noteList"
        :key="note.id"
        data-testid="note-item"
        class="flex flex-col gap-1 pl-2 text-sm border-l-2 border-n-weak"
      >
        <strong v-if="note.author_name" class="text-xs opacity-60">{{
          note.author_name
        }}</strong>
        <span class="whitespace-pre-wrap">{{ note.body }}</span>
      </div>
      <textarea
        v-model="newNote"
        data-testid="note-input"
        rows="2"
        maxlength="1000"
        class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        :placeholder="$t('RAMON.DRAWER.NOTES_ADD')"
      />
      <button
        data-testid="note-add"
        class="self-start px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @click="addNote"
      >
        {{ $t('RAMON.DRAWER.NOTES_ADD_BUTTON') }}
      </button>
    </div>

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

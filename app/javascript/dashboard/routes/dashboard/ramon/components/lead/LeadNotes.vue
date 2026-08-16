<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import LeadsAPI from 'dashboard/api/leads';

const props = defineProps({ leadId: { type: Number, required: true } });

defineOptions({ name: 'LeadNotes' });
const { t } = useI18n();

const notes = ref([]);
const draft = ref('');
const saving = ref(false);

// ponytail: mostra as 5 últimas; o histórico completo vive na aba Histórico
const visible = computed(() => notes.value.slice(-5));
const hiddenCount = computed(() => Math.max(0, notes.value.length - 5));

const load = async id => {
  if (!id) return;
  try {
    const { data } = await LeadsAPI.getNotes(id);
    notes.value = data.payload || [];
  } catch (e) {
    // painel segue utilizável sem as notas; salvar avisa se falhar
    notes.value = [];
  }
};
onMounted(() => load(props.leadId));
watch(
  () => props.leadId,
  id => {
    notes.value = [];
    draft.value = '';
    load(id);
  }
);

const save = async () => {
  const body = draft.value.trim();
  if (!body || saving.value) return;
  saving.value = true;
  try {
    const { data } = await LeadsAPI.createNote(props.leadId, body);
    notes.value = [...notes.value, data];
    draft.value = '';
  } catch (e) {
    useAlert(t('RAMON.LEAD_PANEL.NOTES.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

const noteTime = createdAt =>
  createdAt ? dynamicTime(new Date(createdAt).getTime() / 1000) : '';
</script>

<template>
  <!-- Seção "Notas" do mock 1f: entradas com filete bronze + input inline -->
  <div data-testid="lead-notes" class="flex flex-col gap-2">
    <p
      class="text-[10.5px] font-semibold uppercase tracking-[.1em] text-n-slate-10"
    >
      {{ $t('RAMON.LEAD_PANEL.NOTES.TITLE') }}
    </p>
    <p v-if="hiddenCount" class="text-[10.5px] text-n-slate-9">
      {{ $t('RAMON.LEAD_PANEL.NOTES.HIDDEN', { count: hiddenCount }) }}
    </p>
    <div
      v-for="note in visible"
      :key="note.id"
      class="pl-2.5 border-l-2 border-n-iris-9/40"
    >
      <p class="text-[10.5px] text-n-slate-10">
        {{ note.author_name || $t('RAMON.LEAD_PANEL.NOTES.SYSTEM') }} ·
        {{ noteTime(note.created_at) }}
      </p>
      <p
        class="mt-0.5 text-[12.5px] leading-relaxed text-n-slate-11 whitespace-pre-wrap break-words"
      >
        {{ note.body }}
      </p>
    </div>
    <input
      v-model="draft"
      data-testid="lead-note-input"
      :placeholder="$t('RAMON.LEAD_PANEL.NOTES.PLACEHOLDER')"
      :disabled="saving"
      class="w-full px-3 py-2 text-[12.5px] rounded-[9px] bg-n-solid-2 border border-n-weak text-n-slate-12 placeholder:text-n-slate-9 outline-none focus:border-n-slate-8 disabled:opacity-50"
      @keyup.enter="save"
    />
  </div>
</template>

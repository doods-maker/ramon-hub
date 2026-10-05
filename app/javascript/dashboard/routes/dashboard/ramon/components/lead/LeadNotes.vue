<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import { CAMPO, SELECT, TITULO } from '../../helpers/ui';

const props = defineProps({
  leadId: { type: Number, required: true },
  // muda quando o backend grava algo nas notas fora daqui (ex.: retomada)
  refreshKey: { type: String, default: null },
  inConversation: { type: Boolean, default: false },
});

defineOptions({ name: 'LeadNotes' });
const { t } = useI18n();

const notes = ref([]);
const draft = ref('');
const saving = ref(false);

// Lista única de notas do lead: as 5 últimas, "ver todas" abre o resto aqui
// mesmo, texto inteiro (a aba Histórico só guarda um resumo de 60 caracteres).
const showAll = ref(false);
const visible = computed(() =>
  showAll.value ? notes.value : notes.value.slice(-5)
);
const hiddenCount = computed(() => Math.max(0, notes.value.length - 5));

// Templates de nota rápida: chaves fixas, texto no i18n.
const NOTE_TEMPLATE_KEYS = [
  'TRIED_CONTACT',
  'AWAITING_DOCS',
  'MEETING_SCHEDULED',
];
// select volta pro rótulo depois de aplicar (é atalho, não estado)
const applyNoteTemplate = e => {
  const key = e.target.value;
  if (!key) return;
  const text = t(`RAMON.DRAWER.NOTE_TEMPLATES.ITEMS.${key}`);
  draft.value = draft.value ? `${draft.value} ${text}` : text;
  e.target.value = '';
};

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
  () => [props.leadId, props.refreshKey],
  ([id], [prevId]) => {
    if (id !== prevId) {
      notes.value = [];
      draft.value = '';
      showAll.value = false;
    }
    load(id);
  }
);

// Cabeçalho que o backend põe nas notas-rascunho (retomada, AdvBox, copiloto
// noturno, Cal.com): 1ª linha "RASCUNHO (revisar antes de enviar) — <motivo>:",
// texto da mensagem nas linhas seguintes.
const RASCUNHO_PREFIXO = 'RASCUNHO (revisar antes de enviar)';
const isRascunho = note => note.body?.startsWith(RASCUNHO_PREFIXO);
// Só o texto da mensagem vai pro editor; nada é enviado — quem envia é o Eduardo.
const usarNoEditor = note =>
  emitter.emit(
    BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR,
    note.body.split('\n').slice(1).join('\n').trim()
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
    <p :class="TITULO">
      {{ $t('RAMON.LEAD_PANEL.NOTES.TITLE') }}
    </p>
    <Button
      v-if="hiddenCount"
      data-testid="lead-notes-ver-todas"
      link
      slate
      xs
      class="self-start"
      :label="
        showAll
          ? $t('RAMON.LEAD_PANEL.NOTES.SHOW_LESS')
          : $t('RAMON.LEAD_PANEL.NOTES.SHOW_ALL', { count: notes.length })
      "
      @click="showAll = !showAll"
    />
    <div
      v-for="note in visible"
      :key="note.id"
      class="pl-2.5 border-l-2 border-n-blue-9/40"
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
      <Button
        v-if="inConversation && isRascunho(note)"
        data-testid="lead-note-usar-editor"
        link
        xs
        icon="i-lucide-corner-down-left"
        :label="$t('RAMON.LEAD_PANEL.NOTES.USE_IN_EDITOR')"
        @click="usarNoEditor(note)"
      />
    </div>
    <select
      data-testid="note-template-select"
      :class="SELECT"
      @change="applyNoteTemplate"
    >
      <option value="">
        {{ $t('RAMON.DRAWER.NOTE_TEMPLATES.LABEL') }}
      </option>
      <option v-for="key in NOTE_TEMPLATE_KEYS" :key="key" :value="key">
        {{ $t(`RAMON.DRAWER.NOTE_TEMPLATES.ITEMS.${key}`) }}
      </option>
    </select>
    <input
      v-model="draft"
      data-testid="lead-note-input"
      :placeholder="$t('RAMON.LEAD_PANEL.NOTES.PLACEHOLDER')"
      :disabled="saving"
      :class="CAMPO"
      @keyup.enter="save"
    />
  </div>
</template>

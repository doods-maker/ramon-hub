<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import { SELECT, TEXTAREA } from '../../helpers/ui';

// Item "Notas" do painel: editor no topo, lista inteira embaixo. A lista vem
// do painel (ele carrega uma vez e usa também no Resumo e no contador).
const props = defineProps({
  leadId: { type: Number, required: true },
  notes: { type: Array, default: () => [] },
  inConversation: { type: Boolean, default: false },
});
const emit = defineEmits(['created']);

defineOptions({ name: 'LeadNotes' });
const { t } = useI18n();

const draft = ref('');
const saving = ref(false);
watch(
  () => props.leadId,
  () => {
    draft.value = '';
  }
);

// mais recente no topo, logo abaixo do editor
const ordered = computed(() => [...props.notes].reverse());

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
    emit('created', data);
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
  <div data-testid="lead-notes" class="flex flex-col gap-2">
    <!-- 3 linhas, cresce com o texto (field-sizing; sem suporte fica em 3) -->
    <textarea
      v-model="draft"
      data-testid="lead-note-input"
      rows="3"
      :placeholder="$t('RAMON.LEAD_PANEL.NOTES.PLACEHOLDER')"
      :disabled="saving"
      class="[field-sizing:content] min-h-[4.75rem] max-h-72 resize-none"
      :class="TEXTAREA"
      @keydown.enter.ctrl.prevent="save"
      @keydown.enter.meta.prevent="save"
    />
    <div class="flex gap-2">
      <select
        data-testid="note-template-select"
        class="flex-1 min-w-0"
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
      <Button
        data-testid="lead-note-save"
        sm
        :label="$t('RAMON.LEAD_PANEL.NOTES.SAVE')"
        :title="$t('RAMON.LEAD_PANEL.NOTES.SAVE_HINT')"
        :disabled="saving || !draft.trim()"
        @click="save"
      />
    </div>
    <div
      v-for="note in ordered"
      :key="note.id"
      data-testid="lead-note"
      class="pl-2.5 mt-1 border-l-2 border-n-blue-9/40"
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
  </div>
</template>

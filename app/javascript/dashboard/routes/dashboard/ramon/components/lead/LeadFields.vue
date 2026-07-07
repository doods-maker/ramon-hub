<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadTasksList from './LeadTasksList.vue';
import DocChecklist from './DocChecklist.vue';
import { formatBrl, parseBrlInput } from '../../helpers/currency';
import { waMeUrl } from '../../helpers/phone';
import { formatCpf, stripCpf } from '../../helpers/cpf';

const props = defineProps({ lead: { type: Object, required: true } });

const store = useStore();
const { t } = useI18n();
const stages = useMapGetter('leadConfig/getStages');
const benefitTypes = useMapGetter('leadConfig/getBenefitTypes');
const priorities = useMapGetter('leadConfig/getPriorities');
const channels = useMapGetter('leadConfig/getChannels');
const lostReasons = useMapGetter('leadConfig/getLostReasons');
const agents = useMapGetter('agents/getAgents');
const theses = useMapGetter('theses/getTheses');
const activeTheses = computed(() =>
  theses.value.filter(thesis => thesis.active)
);

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
const dcbEm = ref('');
const benefitMonthlyValue = ref('');
const contactCpf = ref('');
const contactNascimento = ref('');
const contactSexo = ref('');

// Etapa controlada localmente para poder reverter o select quando a mudança
// para uma etapa de perda é cancelada, ou quando o backend recusa o update.
const stageId = ref(null);
const lostPrompt = ref(false);
const lostReasonName = ref('');
const wonPrompt = ref(false);
const wonValue = ref('');

watch(
  () => props.lead,
  l => {
    name.value = l?.name ?? '';
    value.value = formatBrl(l?.value);
    source.value = l?.source ?? '';
    dcbEm.value = l?.dcb_em ?? '';
    benefitMonthlyValue.value = formatBrl(l?.benefit_monthly_value);
    contactCpf.value = formatCpf(l?.contact_cpf);
    contactNascimento.value = l?.contact_data_nascimento ?? '';
    contactSexo.value = l?.contact_sexo ?? '';
    stageId.value = l?.lead_stage_id ?? null;
    lostPrompt.value = false;
    lostReasonName.value = '';
    wonPrompt.value = false;
    wonValue.value = '';
  },
  { immediate: true }
);

// notas discretas: lista + adicionar
const noteList = ref([]);
const newNote = ref('');

// Templates de nota rápida (item 8 do 4b): chaves fixas, texto no i18n.
const NOTE_TEMPLATE_KEYS = [
  'TRIED_CONTACT',
  'AWAITING_DOCS',
  'MEETING_SCHEDULED',
];
const noteTemplate = ref('');
const applyNoteTemplate = () => {
  if (!noteTemplate.value) return;
  const text = t(`RAMON.DRAWER.NOTE_TEMPLATES.ITEMS.${noteTemplate.value}`);
  newNote.value = newNote.value ? `${newNote.value}\n${text}` : text;
  noteTemplate.value = '';
};

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
  const next = parseBrlInput(value.value);
  // texto inválido não-vazio: reverte a exibição e não salva (evita apagar o valor)
  if (next === null && String(value.value).trim() !== '') {
    value.value = formatBrl(props.lead?.value);
    return;
  }
  const prev = props.lead?.value == null ? null : Number(props.lead.value);
  value.value = formatBrl(next);
  if (next === prev) return;
  save({ value: next });
};

const saveDcbEm = () => save({ dcb_em: dcbEm.value || null });

const saveBenefitMonthlyValue = () => {
  const next = parseBrlInput(benefitMonthlyValue.value);
  // texto inválido não-vazio: reverte a exibição e não salva (evita apagar o valor)
  if (next === null && String(benefitMonthlyValue.value).trim() !== '') {
    benefitMonthlyValue.value = formatBrl(props.lead?.benefit_monthly_value);
    return;
  }
  const prev =
    props.lead?.benefit_monthly_value == null
      ? null
      : Number(props.lead.benefit_monthly_value);
  benefitMonthlyValue.value = formatBrl(next);
  if (next === prev) return;
  save({ benefit_monthly_value: next });
};

// select: salva direto no change
const saveSelect = (key, val) => save({ [key]: val === '' ? null : val });

// Etapa: envolve o update em try/catch e reverte o select em erro.
const commitStage = async (targetId, extra = {}) => {
  try {
    await store.dispatch('leads/update', {
      id: props.lead.id,
      lead_stage_id: targetId,
      ...extra,
    });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    stageId.value = props.lead?.lead_stage_id ?? null;
  } finally {
    lostPrompt.value = false;
    wonPrompt.value = false;
  }
};

// Mudar de etapa pelo select. Etapa de perda sem motivo → pede o motivo inline
// antes de mandar (senão o backend recusa com 422 e o select fica dessincrono).
// Etapa de ganho sem valor → pede o valor inline, mesmo padrão do drag no Kanban.
const onStageChange = targetId => {
  stageId.value = targetId;
  // Trocar a seleção fecha qualquer prompt aberto da escolha anterior.
  lostPrompt.value = false;
  wonPrompt.value = false;
  const target = stages.value.find(s => s.id === targetId);
  if (target?.is_lost && !props.lead?.lost_reason) {
    lostReasonName.value = '';
    lostPrompt.value = true;
    return;
  }
  if (target?.is_won && props.lead?.value == null) {
    wonValue.value = '';
    wonPrompt.value = true;
    return;
  }
  commitStage(targetId);
};

const confirmLostStage = () => {
  if (!lostReasonName.value) return;
  commitStage(stageId.value, { lost_reason: lostReasonName.value });
};

const cancelLostStage = () => {
  lostPrompt.value = false;
  lostReasonName.value = '';
  stageId.value = props.lead?.lead_stage_id ?? null;
};

const confirmWonStage = () => {
  const parsed = parseBrlInput(wonValue.value);
  commitStage(stageId.value, parsed == null ? {} : { value: parsed });
};

const skipWonStage = () => commitStage(stageId.value);

const copyPhone = async () => {
  await copyTextToClipboard(props.lead.contact_phone);
  useAlert(t('RAMON.KANBAN.CARD.PHONE_COPIED'));
};

const saveContactField = async payload => {
  if (!props.lead?.contact_id) return;
  try {
    await store.dispatch('leads/updateContactFields', {
      leadId: props.lead.id,
      contactId: props.lead.contact_id,
      payload,
    });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    contactCpf.value = formatCpf(props.lead?.contact_cpf);
    contactNascimento.value = props.lead?.contact_data_nascimento ?? '';
    contactSexo.value = props.lead?.contact_sexo ?? '';
  }
};

const saveContactCpf = () => {
  const digits = stripCpf(contactCpf.value);
  if (digits === stripCpf(props.lead?.contact_cpf)) return;
  contactCpf.value = formatCpf(digits);
  saveContactField({ cpf: digits || null });
};

const saveContactNascimento = () =>
  saveContactField({ data_nascimento: contactNascimento.value || null });

const saveContactSexo = () =>
  saveContactField({ sexo: contactSexo.value || null });
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
      :value="stageId"
      :class="lostPrompt || wonPrompt ? 'mb-1' : 'mb-3'"
      class="w-full px-3 py-2 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @change="e => onStageChange(Number(e.target.value))"
    >
      <option v-for="s in stages" :key="s.id" :value="s.id">
        {{ s.name }}
      </option>
    </select>

    <div
      v-if="lostPrompt"
      data-testid="stage-lost-prompt"
      class="flex flex-col gap-2 p-2 mb-3 rounded-lg bg-n-alpha-1 border border-n-weak"
    >
      <select
        v-model="lostReasonName"
        data-testid="stage-lost-reason"
        class="w-full px-2 py-1.5 text-sm rounded bg-n-alpha-2 text-n-slate-12"
      >
        <option value="" disabled>{{ $t('RAMON.FUNIL.LOST.PICK') }}</option>
        <option v-for="r in lostReasons" :key="r.id" :value="r.name">
          {{ r.name }}
        </option>
      </select>
      <div class="flex justify-end gap-2">
        <button
          data-testid="stage-lost-cancel"
          class="px-3 py-1 text-xs text-n-slate-11"
          @click="cancelLostStage"
        >
          {{ $t('RAMON.FUNIL.LOST.CANCEL') }}
        </button>
        <button
          data-testid="stage-lost-confirm"
          class="px-3 py-1 text-xs rounded-lg bg-n-ruby-9 text-white disabled:opacity-50"
          :disabled="!lostReasonName"
          @click="confirmLostStage"
        >
          {{ $t('RAMON.FUNIL.LOST.CONFIRM') }}
        </button>
      </div>
    </div>

    <div
      v-if="wonPrompt"
      data-testid="stage-won-prompt"
      class="flex flex-col gap-2 p-2 mb-3 rounded-lg bg-n-alpha-1 border border-n-weak"
    >
      <label class="text-xs text-n-slate-10">{{
        $t('RAMON.FUNIL.WON.VALUE_LABEL')
      }}</label>
      <input
        v-model="wonValue"
        data-testid="stage-won-value"
        type="text"
        inputmode="decimal"
        class="w-full px-2 py-1.5 text-sm rounded bg-n-alpha-2 text-n-slate-12"
        @keyup.enter="confirmWonStage"
      />
      <div class="flex justify-end gap-2">
        <button
          data-testid="stage-won-skip"
          class="px-3 py-1 text-xs text-n-slate-11"
          @click="skipWonStage"
        >
          {{ $t('RAMON.FUNIL.WON.SKIP') }}
        </button>
        <button
          data-testid="stage-won-save"
          class="px-3 py-1 text-xs rounded-lg bg-n-iris-9 text-white"
          @click="confirmWonStage"
        >
          {{ $t('RAMON.FUNIL.WON.SAVE') }}
        </button>
      </div>
    </div>

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
    <p
      v-if="!lead.thesis_id"
      data-testid="no-thesis-hint"
      class="text-xs text-n-slate-9"
    >
      {{ $t('RAMON.DRAWER.NO_THESIS_HINT') }}
    </p>

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
      type="text"
      inputmode="decimal"
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
      $t('RAMON.DRAWER.CHANNEL')
    }}</label>
    <select
      data-testid="field-channel"
      :value="lead.channel"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @change="e => saveSelect('channel', e.target.value)"
    >
      <option value="">—</option>
      <option v-for="c in channels" :key="c.key" :value="c.key">
        {{ c.label }}
      </option>
    </select>

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.DCB_LABEL')
    }}</label>
    <input
      v-model="dcbEm"
      data-testid="field-dcb-em"
      type="date"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @change="saveDcbEm"
    />

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.BENEFIT_MONTHLY_LABEL')
    }}</label>
    <input
      v-model="benefitMonthlyValue"
      data-testid="field-benefit-monthly-value"
      type="text"
      inputmode="decimal"
      class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      @blur="saveBenefitMonthlyValue"
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
      <select
        v-model="noteTemplate"
        data-testid="note-template-select"
        class="w-full px-3 py-1.5 text-xs rounded-lg bg-n-alpha-1 text-n-slate-11 border border-n-weak"
        @change="applyNoteTemplate"
      >
        <option value="">
          {{ $t('RAMON.DRAWER.NOTE_TEMPLATES.LABEL') }}
        </option>
        <option v-for="key in NOTE_TEMPLATE_KEYS" :key="key" :value="key">
          {{ $t(`RAMON.DRAWER.NOTE_TEMPLATES.ITEMS.${key}`) }}
        </option>
      </select>
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
      <div
        v-if="lead.contact_phone"
        class="flex items-center gap-2 text-xs text-n-slate-10"
      >
        <button
          data-testid="contact-copy-phone"
          :title="$t('RAMON.KANBAN.CARD.COPY_PHONE')"
          class="inline-flex items-center gap-1 hover:text-n-slate-12"
          @click="copyPhone"
        >
          <span class="i-lucide-phone size-3.5" />{{ lead.contact_phone }}
        </button>
        <a
          v-if="!lead.conversation_id"
          data-testid="contact-wa-me"
          :href="waMeUrl(lead.contact_phone)"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1 hover:text-n-iris-11"
        >
          <span class="i-lucide-message-circle size-3.5" />{{
            $t('RAMON.KANBAN.CARD.WHATSAPP')
          }}
        </a>
      </div>
      <p v-if="lead.contact_email" class="text-xs text-n-slate-10">
        {{ lead.contact_email }}
      </p>

      <template v-if="lead.contact_id">
        <label class="block mt-3 mb-1 text-xs text-n-slate-10">{{
          $t('RAMON.DRAWER.PESSOA.CPF')
        }}</label>
        <input
          v-model="contactCpf"
          data-testid="field-contact-cpf"
          type="text"
          inputmode="numeric"
          placeholder="000.000.000-00"
          class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
          @blur="saveContactCpf"
        />

        <label class="block mb-1 text-xs text-n-slate-10">{{
          $t('RAMON.DRAWER.PESSOA.BIRTHDATE')
        }}</label>
        <input
          v-model="contactNascimento"
          data-testid="field-contact-nascimento"
          type="date"
          class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
          @change="saveContactNascimento"
        />

        <label class="block mb-1 text-xs text-n-slate-10">{{
          $t('RAMON.DRAWER.PESSOA.SEX')
        }}</label>
        <select
          v-model="contactSexo"
          data-testid="field-contact-sexo"
          class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
          @change="saveContactSexo"
        >
          <option value="">—</option>
          <option value="M">{{ $t('RAMON.DRAWER.PESSOA.SEX_M') }}</option>
          <option value="F">{{ $t('RAMON.DRAWER.PESSOA.SEX_F') }}</option>
        </select>

        <router-link
          data-testid="field-linha-da-vida-link"
          :to="{
            name: 'ramon_linha_da_vida',
            params: { contactId: lead.contact_id },
          }"
          class="inline-flex items-center gap-1 text-xs text-n-iris-11 hover:underline"
        >
          <span class="i-lucide-git-commit-vertical size-3.5" />{{
            $t('RAMON.LINHA_DA_VIDA.OPEN')
          }}
        </router-link>
      </template>
    </div>
  </div>
</template>

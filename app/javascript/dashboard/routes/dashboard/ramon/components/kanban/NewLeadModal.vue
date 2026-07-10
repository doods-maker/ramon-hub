<script setup>
import { ref, computed, nextTick, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import LeadsAPI from 'dashboard/api/leads';
import ContactAPI from 'dashboard/api/contacts';

const emit = defineEmits(['close', 'created']);
const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const name = ref('');
const nameInput = ref(null);
const phone = ref('+55 ');

const onDocKeydown = e => {
  if (e.key === 'Escape') emit('close');
};
onMounted(() => {
  document.addEventListener('keydown', onDocKeydown);
  nextTick(() => nameInput.value?.focus());
});
onBeforeUnmount(() => document.removeEventListener('keydown', onDocKeydown));
const benefitTypeId = ref(null);
const priorityId = ref(null);
const source = ref('');
const channel = ref('');
const value = ref('');
const existingLead = ref(null);

const stages = computed(() => getters['leadConfig/getStages'].value);
const benefitTypes = computed(
  () => getters['leadConfig/getBenefitTypes'].value
);
const priorities = computed(() => getters['leadConfig/getPriorities'].value);
const sources = computed(() => getters['leadConfig/getSources'].value);
const channels = computed(() => getters['leadConfig/getChannels'].value);

// E.164 a partir do que o usuário digitou; só considera telefone real quando há
// dígitos além do DDI (evita disparar em "+55 " default).
const normalizedPhone = computed(() => {
  const digits = phone.value.replace(/\D/g, '');
  if (digits.length < 8) return '';
  return `+${digits}`;
});

const existingStageName = computed(() => existingLead.value?.stage_name || '');

// Ao sair do campo telefone, procura lead já aberto (etapa ativa) com esse número.
const onPhoneBlur = async () => {
  existingLead.value = null;
  const q = normalizedPhone.value;
  if (!q) return;
  try {
    const { data } = await LeadsAPI.get({ q });
    const leads = data.payload || [];
    existingLead.value =
      leads.find(l => {
        const st = stages.value.find(s => s.id === l.lead_stage_id);
        return st && !st.is_won && !st.is_lost;
      }) || null;
  } catch (e) {
    // busca falhou: seguimos sem aviso de duplicidade
  }
};

const openExisting = () => {
  store.dispatch('leads/upsert', existingLead.value);
  store.dispatch('leads/select', existingLead.value.id);
  emit('close');
};

// Reaproveita o contato nativo pelo telefone; cria se não existir.
// Busca por dígitos SEM o "+": o `+` cru vira espaço na query (Rack) e o
// ILIKE não casa. Comparamos os resultados normalizando ambos os lados
// para só-dígitos. Se a resolução do contato falhar por completo, devolve
// null — o lead nunca deixa de ser criado por causa do contato.
const resolveContactId = async e164 => {
  const digits = e164.replace(/\D/g, '');
  try {
    const { data } = await ContactAPI.search(digits);
    const match = (data.payload || []).find(
      c => (c.phone_number || '').replace(/\D/g, '') === digits
    );
    if (match) return match.id;
  } catch (e) {
    // busca falhou: tenta a criação mesmo assim
  }
  try {
    const { data } = await ContactAPI.create({
      name: name.value.trim(),
      phone_number: e164,
    });
    return data.payload.contact.id;
  } catch (e) {
    useAlert(t('RAMON.FUNIL.NEW.CONTACT_ERROR'));
    return null;
  }
};

const submit = async () => {
  const firstStage = stages.value[0];
  if (!name.value.trim() || !firstStage) return;

  let contactId = null;
  const e164 = normalizedPhone.value;
  if (e164) contactId = await resolveContactId(e164);

  try {
    const lead = await store.dispatch('leads/create', {
      name: name.value.trim(),
      lead_stage_id: firstStage.id,
      benefit_type_id: benefitTypeId.value,
      lead_priority_id: priorityId.value,
      source: source.value.trim() || null,
      channel: channel.value || null,
      value: value.value === '' ? null : Number(value.value),
      contact_id: contactId,
      // banner de duplicado visível → o botão já diz "Criar mesmo assim",
      // então este clique é a confirmação explícita.
      force: existingLead.value ? true : undefined,
    });
    emit('created', lead);
    emit('close');
  } catch (error) {
    const existing = error?.response?.data?.existing;
    if (error?.response?.status === 409 && existing) {
      // gate do servidor (cobre corrida em que o blur não rodou a tempo)
      existingLead.value = existing;
    } else {
      useAlert(t('RAMON.FUNIL.NEW.CREATE_ERROR'));
    }
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="emit('close')"
  >
    <div
      class="w-96 max-w-[92vw] max-h-[90vh] overflow-y-auto p-5 rounded-2xl bg-n-solid-1 border border-n-weak"
    >
      <h2 class="mb-4 text-lg font-cormorant text-n-slate-12">
        {{ $t('RAMON.FUNIL.NEW_LEAD') }}
      </h2>

      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.FUNIL.LEAD_NAME')
      }}</label>
      <input
        ref="nameInput"
        v-model="name"
        data-testid="new-lead-name"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      />

      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.FUNIL.LEAD_PHONE')
      }}</label>
      <input
        v-model="phone"
        data-testid="new-lead-phone"
        class="w-full px-3 py-2 mb-2 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
        @blur="onPhoneBlur"
      />
      <div
        v-if="existingLead"
        data-testid="new-lead-dedup"
        class="flex items-center justify-between gap-2 mb-3 px-3 py-2 text-xs rounded-lg bg-n-amber-3 text-n-amber-11 border border-n-amber-6"
      >
        <span>{{
          $t('RAMON.FUNIL.NEW.DEDUP', {
            name: existingLead.name,
            stage: existingStageName,
          })
        }}</span>
        <button
          data-testid="new-lead-open-existing"
          class="shrink-0 underline hover:text-n-amber-12"
          @click="openExisting"
        >
          {{ $t('RAMON.FUNIL.NEW.OPEN_EXISTING') }}
        </button>
      </div>

      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.FUNIL.BENEFIT')
      }}</label>
      <select
        v-model="benefitTypeId"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      >
        <option :value="null">—</option>
        <option v-for="b in benefitTypes" :key="b.id" :value="b.id">
          {{ b.name }}
        </option>
      </select>

      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.FUNIL.NEW.SOURCE')
      }}</label>
      <input
        v-model="source"
        list="new-lead-sources"
        data-testid="new-lead-source"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      />
      <datalist id="new-lead-sources">
        <option v-for="s in sources" :key="s" :value="s" />
      </datalist>

      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.FUNIL.NEW.CHANNEL')
      }}</label>
      <select
        v-model="channel"
        data-testid="new-lead-channel"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
      >
        <option value="">
          {{ $t('RAMON.FUNIL.NEW.CHANNEL_PLACEHOLDER') }}
        </option>
        <option v-for="c in channels" :key="c.key" :value="c.key">
          {{ c.label }}
        </option>
      </select>

      <div class="flex gap-3">
        <div class="flex-1">
          <label class="block mb-1 text-xs text-n-slate-10">{{
            $t('RAMON.FUNIL.NEW.VALUE')
          }}</label>
          <input
            v-model="value"
            data-testid="new-lead-value"
            type="number"
            step="0.01"
            class="w-full px-3 py-2 mb-4 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
          />
        </div>
        <div class="flex-1">
          <label class="block mb-1 text-xs text-n-slate-10">{{
            $t('RAMON.FUNIL.PRIORITY')
          }}</label>
          <select
            v-model="priorityId"
            data-testid="new-lead-priority"
            class="w-full px-3 py-2 mb-4 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak"
          >
            <option :value="null">—</option>
            <option v-for="p in priorities" :key="p.id" :value="p.id">
              {{ p.name }}
            </option>
          </select>
        </div>
      </div>

      <div class="flex justify-end gap-2">
        <button
          class="px-3 py-1.5 text-sm text-n-slate-11"
          @click="emit('close')"
        >
          {{ $t('RAMON.FUNIL.CANCEL') }}
        </button>
        <button
          data-testid="new-lead-save"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white disabled:opacity-50"
          :disabled="!name.trim()"
          @click="submit"
        >
          {{
            existingLead
              ? $t('RAMON.FUNIL.NEW.CREATE_ANYWAY')
              : $t('RAMON.FUNIL.SAVE')
          }}
        </button>
      </div>
    </div>
  </div>
</template>

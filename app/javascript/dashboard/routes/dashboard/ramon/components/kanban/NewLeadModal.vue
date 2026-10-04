<script setup>
import { ref, computed, nextTick, onMounted } from 'vue';
import { onKeyStroke } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import LeadsAPI from 'dashboard/api/leads';
import ContactAPI from 'dashboard/api/contacts';
import { parseBrlInput } from '../../helpers/currency';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  CAMPO,
  SELECT,
  ROTULO,
  AVISO,
  TOM,
  FUNDO_JANELA,
  JANELA,
  TITULO_JANELA,
  RODAPE_JANELA,
} from '../../helpers/ui';

const emit = defineEmits(['close', 'created']);
const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const name = ref('');
const nameInput = ref(null);
const phone = ref('+55 ');

onMounted(() => {
  nextTick(() => nameInput.value?.focus());
});
const benefitTypeId = ref(null);
const priorityId = ref(null);
const source = ref('');
const channel = ref('');
const value = ref('');
const existingLead = ref(null);

// Esc só fecha com o formulário intocado — Esc por reflexo não pode
// descartar um lead meio digitado (fechar explícito = Cancelar/backdrop).
const isDirty = computed(
  () =>
    Boolean(name.value.trim()) ||
    phone.value.replace(/\D/g, '') !== '55' ||
    benefitTypeId.value !== null ||
    priorityId.value !== null ||
    Boolean(source.value.trim()) ||
    Boolean(channel.value) ||
    value.value !== ''
);
onKeyStroke('Escape', () => {
  if (!isDirty.value) emit('close');
});
// Mesmo guard no backdrop: misclick não descarta um formulário sujo.
const onBackdrop = () => {
  if (!isDirty.value) emit('close');
};

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

// Valor em formato BRL livre ("1.500,00"); texto inválido bloqueia o salvar.
const isValueInvalid = computed(
  () => value.value.trim() !== '' && parseBrlInput(value.value) === null
);

// Guard contra duplo-clique: o segundo submit espera o primeiro terminar.
const submitting = ref(false);

const submit = async () => {
  const firstStage = stages.value[0];
  if (!name.value.trim() || !firstStage) return;
  if (submitting.value || isValueInvalid.value) return;
  submitting.value = true;

  try {
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
        value: value.value.trim() === '' ? null : parseBrlInput(value.value),
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
  } finally {
    submitting.value = false;
  }
};
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="onBackdrop">
    <div class="!w-96" :class="JANELA">
      <h2 :class="TITULO_JANELA">
        {{ $t('RAMON.FUNIL.NEW_LEAD') }}
      </h2>

      <div class="flex flex-col gap-3">
        <label :class="ROTULO">
          {{ $t('RAMON.FUNIL.LEAD_NAME') }}
          <input
            ref="nameInput"
            v-model="name"
            data-testid="new-lead-name"
            :class="CAMPO"
          />
        </label>

        <label :class="ROTULO">
          {{ $t('RAMON.FUNIL.LEAD_PHONE') }}
          <input
            v-model="phone"
            data-testid="new-lead-phone"
            class="font-mono"
            :class="CAMPO"
            @blur="onPhoneBlur"
          />
        </label>
        <div
          v-if="existingLead"
          data-testid="new-lead-dedup"
          class="flex items-center justify-between gap-2"
          :class="[AVISO, TOM.amber]"
        >
          <span>{{
            $t('RAMON.FUNIL.NEW.DEDUP', {
              name: existingLead.name,
              stage: existingStageName,
            })
          }}</span>
          <Button
            data-testid="new-lead-open-existing"
            link
            xs
            amber
            class="shrink-0"
            :label="$t('RAMON.FUNIL.NEW.OPEN_EXISTING')"
            @click="openExisting"
          />
        </div>

        <label :class="ROTULO">
          {{ $t('RAMON.FUNIL.BENEFIT') }}
          <select v-model="benefitTypeId" :class="SELECT">
            <option :value="null">—</option>
            <option v-for="b in benefitTypes" :key="b.id" :value="b.id">
              {{ b.name }}
            </option>
          </select>
        </label>

        <label :class="ROTULO">
          {{ $t('RAMON.FUNIL.NEW.SOURCE') }}
          <input
            v-model="source"
            list="new-lead-sources"
            data-testid="new-lead-source"
            :class="CAMPO"
          />
        </label>
        <datalist id="new-lead-sources">
          <option v-for="s in sources" :key="s" :value="s" />
        </datalist>

        <label :class="ROTULO">
          {{ $t('RAMON.FUNIL.NEW.CHANNEL') }}
          <select
            v-model="channel"
            data-testid="new-lead-channel"
            :class="SELECT"
          >
            <option value="">
              {{ $t('RAMON.FUNIL.NEW.CHANNEL_PLACEHOLDER') }}
            </option>
            <option v-for="c in channels" :key="c.key" :value="c.key">
              {{ c.label }}
            </option>
          </select>
        </label>

        <div class="flex gap-3">
          <div class="flex-1 min-w-0">
            <label :class="ROTULO">
              {{ $t('RAMON.FUNIL.NEW.VALUE') }}
              <input
                v-model="value"
                data-testid="new-lead-value"
                type="text"
                inputmode="decimal"
                class="font-mono"
                :class="[CAMPO, { '!outline-n-ruby-8': isValueInvalid }]"
              />
            </label>
            <p v-if="isValueInvalid" class="mt-1 mb-0 text-xs text-n-ruby-11">
              {{ $t('RAMON.FUNIL.WON.INVALID') }}
            </p>
          </div>
          <label class="flex-1 min-w-0" :class="ROTULO">
            {{ $t('RAMON.FUNIL.PRIORITY') }}
            <select
              v-model="priorityId"
              data-testid="new-lead-priority"
              :class="SELECT"
            >
              <option :value="null">—</option>
              <option v-for="p in priorities" :key="p.id" :value="p.id">
                {{ p.name }}
              </option>
            </select>
          </label>
        </div>
      </div>

      <div :class="RODAPE_JANELA">
        <Button
          sm
          faded
          slate
          :label="$t('RAMON.FUNIL.CANCEL')"
          @click="emit('close')"
        />
        <Button
          data-testid="new-lead-save"
          sm
          :label="
            existingLead
              ? $t('RAMON.FUNIL.NEW.CREATE_ANYWAY')
              : $t('RAMON.FUNIL.SAVE')
          "
          :disabled="
            !name.trim() || submitting || !stages.length || isValueInvalid
          "
          @click="submit"
        />
      </div>
    </div>
  </div>
</template>

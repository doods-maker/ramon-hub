<script setup>
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import { formatBrl, parseBrlInput } from '../../helpers/currency';
import { formatCpf, stripCpf } from '../../helpers/cpf';
import Button from 'dashboard/components-next/button/Button.vue';
import { SECAO, TITULO, CAMPO, SELECT, TOM, AVISO } from '../../helpers/ui';

// "Editar todos os campos": só o que o Resumo NÃO edita. Etapa (pílula do
// cabeçalho), valor (chip), tese/benefício/DCB/canal (cartão Caso), tarefas
// (Próximo passo / + Tarefa), notas (Notas) e telefone (Dados do contato)
// moram no Resumo — aqui não se repetem.
const props = defineProps({ lead: { type: Object, required: true } });

const store = useStore();
// Papéis (playbook §13): só o gestor troca SDR/Closer — o normal é automático.
const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const { t } = useI18n();
const stages = useMapGetter('leadConfig/getStages');
const priorities = useMapGetter('leadConfig/getPriorities');
const lostReasons = useMapGetter('leadConfig/getLostReasons');
const agents = useMapGetter('agents/getAgents');

// Motivo da perda só aparece quando o lead está numa etapa marcada como perda.
const currentStage = computed(() =>
  stages.value.find(s => s.id === props.lead?.lead_stage_id)
);
const isLostStage = computed(() => !!currentStage.value?.is_lost);
const reasonNames = computed(() => lostReasons.value.map(r => r.name));

// refs locais editáveis, ressincronizados sempre que o lead muda
const name = ref('');
const source = ref('');
const benefitMonthlyValue = ref('');
const contactCpf = ref('');
const contactNascimento = ref('');
const contactSexo = ref('');
const npsScore = ref('');

// ressincroniza TUDO — usada na troca de lead e na reversão pós-erro de save
const syncAll = l => {
  name.value = l?.name ?? '';
  source.value = l?.source ?? '';
  benefitMonthlyValue.value = formatBrl(l?.benefit_monthly_value);
  contactCpf.value = formatCpf(l?.contact_cpf);
  contactNascimento.value = l?.contact_data_nascimento ?? '';
  contactSexo.value = l?.contact_sexo ?? '';
  npsScore.value = l?.custom_attributes?.nps?.score ?? '';
};

// [data-testid do input, ref local, leitura do lead] — p/ absorver broadcasts
// sem apagar o que o usuário está digitando (só atualiza campo SEM foco).
const FIELD_SYNC = [
  ['field-name', name, l => l?.name ?? ''],
  ['field-source', source, l => l?.source ?? ''],
  [
    'field-benefit-monthly-value',
    benefitMonthlyValue,
    l => formatBrl(l?.benefit_monthly_value),
  ],
  ['field-contact-cpf', contactCpf, l => formatCpf(l?.contact_cpf)],
  [
    'field-contact-nascimento',
    contactNascimento,
    l => l?.contact_data_nascimento ?? '',
  ],
  ['field-contact-sexo', contactSexo, l => l?.contact_sexo ?? ''],
  ['field-nps', npsScore, l => l?.custom_attributes?.nps?.score ?? ''],
];

watch(
  () => props.lead,
  (l, prev) => {
    // lead trocou: ressincroniza tudo
    if (l?.id !== prev?.id) {
      syncAll(l);
      return;
    }
    // mesmo lead (EDIT/MERGE/broadcast): preserva o campo em digitação
    const focused = document.activeElement?.dataset?.testid;
    FIELD_SYNC.forEach(([testId, target, read]) => {
      if (testId !== focused) target.value = read(l);
    });
  },
  { immediate: true }
);

// try/catch aqui cobre saveText/saveSelect e cia; no erro,
// ressincroniza os refs com o lead da store.
const save = async payload => {
  try {
    await store.dispatch('leads/update', { id: props.lead.id, ...payload });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    syncAll(props.lead);
  }
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

// NPS pós-ganho: grava só a chave nps (o PATCH faz deep_merge server-side).
const currentNps = computed(() => props.lead?.custom_attributes?.nps || null);
const npsRecordedAt = computed(() => {
  const em = currentNps.value?.em;
  if (!em) return null;
  const date = new Date(em);
  if (Number.isNaN(date.getTime())) return null;
  return date.toLocaleDateString('pt-BR');
});
const saveNps = async () => {
  const raw = String(npsScore.value).trim();
  if (raw === '') {
    npsScore.value = currentNps.value?.score ?? '';
    return;
  }
  const score = Number(raw);
  // fora de 0–10 ou não inteiro: reverte sem salvar
  if (!Number.isInteger(score) || score < 0 || score > 10) {
    npsScore.value = currentNps.value?.score ?? '';
    return;
  }
  if (score === currentNps.value?.score) return;
  try {
    await store.dispatch('leads/update', {
      id: props.lead.id,
      custom_attributes: {
        nps: { score, em: new Date().toISOString() },
      },
    });
    useAlert(t('RAMON.NPS.SAVED'));
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    npsScore.value = currentNps.value?.score ?? '';
  }
};

// Portal do cliente: gera/reusa o token no backend e copia a URL pública.
const copyPortalLink = async () => {
  try {
    const { data } = await LeadsAPI.portalLink(props.lead.id);
    await copyTextToClipboard(data.url);
    useAlert(t('RAMON.PORTAL.COPIED'));
  } catch (error) {
    useAlert(t('RAMON.PORTAL.ERROR'));
  }
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

// Consentimento LGPD de marketing (custom_attributes.consent_marketing do contato)
const consent = computed(() => props.lead?.contact_consent_marketing || null);
const consentGranted = computed(() => consent.value?.granted === true);
const consentStatusText = computed(() => {
  if (!consent.value) return t('RAMON.DRAWER.CONSENT.NONE');
  const date = consent.value.at
    ? new Date(consent.value.at).toLocaleDateString('pt-BR')
    : '—';
  if (consentGranted.value)
    return t('RAMON.DRAWER.CONSENT.GRANTED', {
      date,
      source: consent.value.source || '—',
    });
  return t('RAMON.DRAWER.CONSENT.REVOKED', { date });
});
const toggleConsent = () =>
  saveContactField({
    custom_attributes: {
      consent_marketing: {
        granted: !consentGranted.value,
        at: new Date().toISOString(),
        source: 'manual',
      },
    },
  });
</script>

<template>
  <div>
    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.NAME')
    }}</label>
    <input
      v-model="name"
      data-testid="field-name"
      class="!mb-3"
      :class="CAMPO"
      @blur="saveName"
    />

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.PRIORITY')
    }}</label>
    <select
      :value="lead.lead_priority_id"
      class="!mb-3"
      :class="SELECT"
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
      :disabled="!isAdmin"
      class="!mb-3"
      :class="SELECT"
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
      :disabled="!isAdmin"
      class="!mb-3"
      :class="SELECT"
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
      $t('RAMON.DRAWER.SOURCE')
    }}</label>
    <input
      v-model="source"
      data-testid="field-source"
      class="!mb-3"
      :class="CAMPO"
      @blur="saveSource"
    />

    <label class="block mb-1 text-xs text-n-slate-10">{{
      $t('RAMON.DRAWER.BENEFIT_MONTHLY_LABEL')
    }}</label>
    <input
      v-model="benefitMonthlyValue"
      data-testid="field-benefit-monthly-value"
      type="text"
      inputmode="decimal"
      class="!mb-3 font-mono"
      :class="CAMPO"
      @blur="saveBenefitMonthlyValue"
    />

    <template v-if="isLostStage">
      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.DRAWER.LOST_REASON')
      }}</label>
      <select
        data-testid="field-lost-reason"
        :value="lead.lost_reason"
        class="!mb-3"
        :class="SELECT"
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

    <template v-if="lead.won_at">
      <label class="block mb-1 text-xs text-n-slate-10">{{
        $t('RAMON.NPS.LABEL')
      }}</label>
      <input
        v-model="npsScore"
        data-testid="field-nps"
        type="number"
        min="0"
        max="10"
        step="1"
        inputmode="numeric"
        class="font-mono"
        :class="[CAMPO, npsRecordedAt ? '!mb-1' : '!mb-3']"
        @blur="saveNps"
      />
      <p
        v-if="npsRecordedAt"
        data-testid="nps-recorded-at"
        class="mb-3 text-xs text-n-slate-9"
      >
        {{ $t('RAMON.NPS.RECORDED_AT', { date: npsRecordedAt }) }}
      </p>
    </template>

    <div
      v-if="lead.custom_attributes?.advbox"
      class="flex items-center gap-2 mb-4 text-xs"
      :class="SECAO"
      data-testid="advbox-sync"
    >
      <span :class="TITULO">{{ $t('RAMON.ADVBOX.TITLE') }}</span>
      <span
        v-if="lead.custom_attributes.advbox.lawsuits_id"
        class="text-n-teal-11"
      >
        {{
          $t('RAMON.ADVBOX.SYNCED', {
            lawsuit: lead.custom_attributes.advbox.lawsuits_id,
          })
        }}
      </span>
      <span
        v-else-if="lead.custom_attributes.advbox.erro"
        class="text-n-ruby-11"
      >
        {{ $t('RAMON.ADVBOX.ERROR') }}
      </span>
    </div>

    <div class="flex items-center justify-between gap-2 mb-4" :class="SECAO">
      <span :class="TITULO">{{ $t('RAMON.PORTAL.LABEL') }}</span>
      <Button
        data-testid="portal-copy-link"
        sm
        faded
        slate
        icon="i-lucide-link"
        :label="$t('RAMON.PORTAL.COPY_LINK')"
        @click="copyPortalLink"
      />
    </div>

    <!-- contato (telefone fica em "Dados do contato", no Resumo) -->
    <div class="mt-2" :class="SECAO">
      <p class="mb-2" :class="TITULO">
        {{ $t('RAMON.DRAWER.CONTACT') }}
      </p>
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
          :placeholder="$t('RAMON.DRAWER.PESSOA.CPF_PLACEHOLDER')"
          class="!mb-3 font-mono"
          :class="CAMPO"
          @blur="saveContactCpf"
        />

        <label class="block mb-1 text-xs text-n-slate-10">{{
          $t('RAMON.DRAWER.PESSOA.BIRTHDATE')
        }}</label>
        <input
          v-model="contactNascimento"
          data-testid="field-contact-nascimento"
          type="date"
          class="!mb-3 font-mono"
          :class="CAMPO"
          @change="saveContactNascimento"
        />

        <label class="block mb-1 text-xs text-n-slate-10">{{
          $t('RAMON.DRAWER.PESSOA.SEX')
        }}</label>
        <select
          v-model="contactSexo"
          data-testid="field-contact-sexo"
          class="!mb-3"
          :class="SELECT"
          @change="saveContactSexo"
        >
          <option value="">—</option>
          <option value="M">{{ $t('RAMON.DRAWER.PESSOA.SEX_M') }}</option>
          <option value="F">{{ $t('RAMON.DRAWER.PESSOA.SEX_F') }}</option>
        </select>

        <label class="block mb-1 text-xs text-n-slate-10">{{
          $t('RAMON.DRAWER.CONSENT.LABEL')
        }}</label>
        <div
          class="flex items-center justify-between gap-2 mb-3"
          :class="[AVISO, TOM.slate]"
        >
          <span
            data-testid="consent-status"
            class="flex items-center gap-1.5 text-xs"
            :class="consentGranted ? 'text-n-teal-11' : 'text-n-slate-10'"
          >
            <span
              :class="
                consentGranted ? 'i-lucide-shield-check' : 'i-lucide-shield-off'
              "
              class="size-3.5"
            />
            {{ consentStatusText }}
          </span>
          <Button
            data-testid="consent-toggle"
            sm
            faded
            slate
            :label="
              consentGranted
                ? $t('RAMON.DRAWER.CONSENT.REVOKE')
                : $t('RAMON.DRAWER.CONSENT.GRANT')
            "
            @click="toggleConsent"
          />
        </div>

        <router-link
          v-slot="{ navigate }"
          custom
          :to="{
            name: 'ramon_linha_da_vida',
            params: { contactId: lead.contact_id },
          }"
        >
          <Button
            data-testid="field-linha-da-vida-link"
            link
            xs
            icon="i-lucide-git-commit-vertical"
            :label="$t('RAMON.LINHA_DA_VIDA.OPEN')"
            @click="navigate"
          />
        </router-link>
      </template>
    </div>
  </div>
</template>

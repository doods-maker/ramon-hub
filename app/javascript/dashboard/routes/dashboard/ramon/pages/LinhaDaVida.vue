<script setup>
import { ref, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import LinhaDaVidaAPI from 'dashboard/api/linhaDaVida';
import { formatCpf } from '../helpers/cpf';
import { formatBrl } from '../helpers/currency';
import { frontendURL } from '../../../../helper/URLHelper';

const route = useRoute();

const data = ref(null);
const loading = ref(false);
const error = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await LinhaDaVidaAPI.show(route.params.contactId);
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

watch(() => route.params.contactId, fetchData, { immediate: true });

const contact = computed(() => data.value?.contact ?? null);
const leads = computed(() => data.value?.leads ?? []);

// Presente = casos vivos no funil; passado = fechados (ganhos e perdidos).
const openLeads = computed(() =>
  leads.value.filter(l => !l.is_won && !l.is_lost)
);
const closedLeads = computed(() =>
  leads.value
    .filter(l => l.is_won || l.is_lost)
    .sort(
      (a, b) =>
        new Date(b.won_at || b.lost_at) - new Date(a.won_at || a.lost_at)
    )
);

// Futuro = marcos etários não atingidos + DCBs futuras + início da prescrição
// (DCB + 60 meses: quando a pessoa começa a perder parcelas), ordenado por data.
const addMonths = (dateStr, months) => {
  const d = new Date(`${String(dateStr).slice(0, 10)}T12:00:00`);
  d.setMonth(d.getMonth() + months);
  return d;
};

const futureItems = computed(() => {
  const now = new Date();
  const marcos = (data.value?.marcos ?? [])
    .filter(m => !m.atingido)
    .map(m => ({ type: 'marco', date: m.data, marco: m }));
  const dcbs = leads.value
    .filter(l => l.dcb_em && new Date(l.dcb_em) >= now)
    .map(l => ({ type: 'dcb', date: l.dcb_em, lead: l }));
  const prescricoes = leads.value
    .filter(l => l.dcb_em && addMonths(l.dcb_em, 60) >= now)
    .map(l => ({ type: 'prescricao', date: addMonths(l.dcb_em, 60), lead: l }));
  return [...marcos, ...dcbs, ...prescricoes].sort(
    (a, b) => new Date(a.date) - new Date(b.date)
  );
});

const conversationUrl = lead =>
  frontendURL(
    `accounts/${route.params.accountId}/conversations/${lead.conversation_id}`
  );

const fmtDate = value => {
  if (!value) return '';
  return new Date(`${String(value).slice(0, 10)}T12:00:00`).toLocaleDateString(
    'pt-BR'
  );
};
</script>

<template>
  <div class="flex-1 h-full p-6 overflow-y-auto">
    <p v-if="loading" class="text-sm text-n-slate-9">
      {{ $t('RAMON.LINHA_DA_VIDA.LOADING') }}
    </p>
    <p v-else-if="error" class="text-sm text-n-ruby-11">
      {{ $t('RAMON.LINHA_DA_VIDA.ERROR') }}
    </p>

    <template v-else-if="contact">
      <div class="mb-6">
        <h1 class="text-2xl font-cormorant text-n-slate-12">
          {{ contact.name }}
        </h1>
        <p class="text-sm text-n-slate-10">
          <span v-if="contact.cpf">{{ formatCpf(contact.cpf) }} · </span>
          <span v-if="contact.data_nascimento">
            {{ $t('RAMON.LINHA_DA_VIDA.BORN_AT') }}
            {{ fmtDate(contact.data_nascimento) }}
          </span>
          <span v-if="contact.phone_number"> · {{ contact.phone_number }}</span>
        </p>
        <p
          v-if="!contact.data_nascimento"
          data-testid="lifeline-no-birthdate"
          class="mt-1 text-xs text-n-amber-11"
        >
          {{ $t('RAMON.LINHA_DA_VIDA.NO_BIRTHDATE_HINT') }}
        </p>
      </div>

      <!-- FUTURO -->
      <section class="mb-8" data-testid="lifeline-future">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.FUTURE') }}
        </h2>
        <p v-if="!futureItems.length" class="text-sm text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.FUTURE_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-2">
          <li
            v-for="(item, i) in futureItems"
            :key="i"
            class="flex items-baseline gap-3 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <span class="text-xs tabular-nums text-n-slate-10 shrink-0">
              {{ fmtDate(item.date) }}
            </span>
            <template v-if="item.type === 'marco'">
              <span class="text-sm text-n-slate-12">
                {{ $t(`RAMON.LINHA_DA_VIDA.MARCOS.${item.marco.key}`) }}
                ({{ item.marco.idade }}
                <template v-if="item.marco.sexo">
                  ·
                  {{
                    item.marco.sexo === 'M'
                      ? $t('RAMON.DRAWER.PESSOA.SEX_M')
                      : $t('RAMON.DRAWER.PESSOA.SEX_F')
                  }}</template
                >)
              </span>
            </template>
            <template v-else-if="item.type === 'dcb'">
              <span class="text-sm text-n-slate-12">
                {{ $t('RAMON.LINHA_DA_VIDA.DCB_OF', { name: item.lead.name }) }}
              </span>
            </template>
            <template v-else>
              <span class="text-sm text-n-slate-12">
                {{
                  $t('RAMON.LINHA_DA_VIDA.PRESCRIPTION_OF', {
                    name: item.lead.name,
                  })
                }}
              </span>
            </template>
          </li>
        </ul>
        <p class="mt-2 text-xs text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.DISCLAIMER') }}
        </p>
      </section>

      <!-- PRESENTE -->
      <section class="mb-8" data-testid="lifeline-present">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.PRESENT') }}
        </h2>
        <p v-if="!openLeads.length" class="text-sm text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.PRESENT_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-2">
          <li
            v-for="lead in openLeads"
            :key="lead.id"
            class="p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-sm text-n-slate-12">{{ lead.name }}</span>
              <span
                class="px-2 py-0.5 text-xs rounded-full text-white shrink-0"
                :style="{ backgroundColor: lead.stage_color || '#71717a' }"
              >
                {{ lead.stage_name }}
              </span>
            </div>
            <p class="text-xs text-n-slate-10">
              <span v-if="lead.benefit_type_name"
                >{{ lead.benefit_type_name }} ·
              </span>
              <span v-if="lead.thesis_name">{{ lead.thesis_name }} · </span>
              <span v-if="lead.value">{{ formatBrl(lead.value) }}</span>
            </p>
            <router-link
              v-if="lead.conversation_id"
              :to="conversationUrl(lead)"
              class="text-xs text-n-iris-11 hover:underline"
            >
              {{ $t('RAMON.FUNIL.OPEN_CONVERSATION') }}
            </router-link>
            <router-link
              data-testid="lifeline-dossie-link"
              :to="{ name: 'ramon_lead_dossie', params: { leadId: lead.id } }"
              class="ml-3 text-xs text-n-iris-11 hover:underline"
            >
              {{ $t('RAMON.DOSSIE.OPEN') }}
            </router-link>
          </li>
        </ul>
      </section>

      <!-- PASSADO -->
      <section class="mb-8" data-testid="lifeline-past">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.PAST') }}
        </h2>
        <p v-if="!closedLeads.length" class="text-sm text-n-slate-9">
          {{ $t('RAMON.LINHA_DA_VIDA.PAST_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-2">
          <li
            v-for="lead in closedLeads"
            :key="lead.id"
            class="flex items-baseline gap-3 p-3 rounded-lg bg-n-alpha-1 border border-n-weak"
          >
            <span class="text-xs tabular-nums text-n-slate-10 shrink-0">
              {{ fmtDate(lead.won_at || lead.lost_at) }}
            </span>
            <div>
              <span class="text-sm text-n-slate-12">{{ lead.name }}</span>
              <span
                class="ml-2 text-xs"
                :class="lead.is_won ? 'text-n-teal-11' : 'text-n-ruby-11'"
              >
                {{
                  lead.is_won
                    ? $t('RAMON.LINHA_DA_VIDA.WON')
                    : $t('RAMON.LINHA_DA_VIDA.LOST')
                }}
              </span>
              <p class="text-xs text-n-slate-10">
                <span v-if="lead.benefit_type_name"
                  >{{ lead.benefit_type_name }} ·
                </span>
                <span v-if="lead.value">{{ formatBrl(lead.value) }}</span>
                <span v-if="lead.lost_reason"> · {{ lead.lost_reason }}</span>
              </p>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>

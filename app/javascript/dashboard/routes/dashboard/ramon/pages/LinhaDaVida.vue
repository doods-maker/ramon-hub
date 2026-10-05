<script setup>
import { ref, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import LinhaDaVidaAPI from 'dashboard/api/linhaDaVida';
import ContactAPI from 'dashboard/api/contacts';
import { formatCpf } from '../helpers/cpf';
import { formatBrl } from '../helpers/currency';
import { DEFAULT_STAGE_COLOR } from '../helpers/stage';
import { frontendURL } from '../../../../helper/URLHelper';
import {
  AVISO,
  CAMPO_GRANDE,
  CARTAO,
  CHIP,
  LINHA,
  SECAO,
  TITULO,
  TOM,
} from '../helpers/ui';
import Button from 'dashboard/components-next/button/Button.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const data = ref(null);
const loading = ref(false);
const error = ref(false);

const fetchData = async () => {
  // Sem contactId a página está no modo busca (entrada pelo menu).
  if (!route.params.contactId) {
    data.value = null;
    return;
  }
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

// ---- modo busca (rota sem contactId): achar a pessoa pela busca de contatos
const query = ref('');
const results = ref([]);
const searching = ref(false);
let searchTimer = null;
let searchAbort = null;
watch(query, value => {
  clearTimeout(searchTimer);
  const term = value.trim();
  if (term.length < 2) {
    searchAbort?.abort();
    results.value = [];
    searching.value = false;
    return;
  }
  searchTimer = setTimeout(async () => {
    // Aborta a request anterior: resposta velha não sobrescreve a atual.
    searchAbort?.abort();
    const controller = new AbortController();
    searchAbort = controller;
    searching.value = true;
    try {
      // encodeURIComponent: telefone com "+" (e termos com &/#) chegam
      // intactos na query — o endpoint recebe o termo cru interpolado.
      const { data: resp } = await ContactAPI.search(
        encodeURIComponent(term),
        1,
        'name',
        '',
        { signal: controller.signal }
      );
      results.value = resp.payload || [];
    } catch (e) {
      if (!controller.signal.aborted) results.value = [];
    } finally {
      if (searchAbort === controller) searching.value = false;
    }
  }, 300);
});

const openPessoa = contact =>
  router.push({
    name: 'ramon_linha_da_vida',
    params: { contactId: contact.id },
  });

const contact = computed(() => data.value?.contact ?? null);
const leads = computed(() => data.value?.leads ?? []);

const fmtDate = value => {
  if (!value) return '';
  // Prescrição chega como Date (addMonths); marcos/DCB chegam string ISO.
  if (value instanceof Date) return value.toLocaleDateString('pt-BR');
  return new Date(`${String(value).slice(0, 10)}T12:00:00`).toLocaleDateString(
    'pt-BR'
  );
};

// Linha do cabeçalho: CPF · nascimento · telefone (só o que existir); o
// número vai em mono, o rótulo não.
const headerParts = computed(() => {
  const c = contact.value;
  if (!c) return [];
  const parts = [];
  if (c.cpf) parts.push({ label: '', value: formatCpf(c.cpf) });
  if (c.data_nascimento)
    parts.push({
      label: t('RAMON.LINHA_DA_VIDA.BORN_AT'),
      value: fmtDate(c.data_nascimento),
    });
  if (c.phone_number) parts.push({ label: '', value: c.phone_number });
  return parts;
});

// Ícone por tipo de marco futuro (mesmos ícones translúcidos da Atividade).
const FUTURO_VISUAL = {
  marco: { icone: 'i-lucide-cake', tom: TOM.blue },
  dcb: { icone: 'i-lucide-calendar-x', tom: TOM.amber },
  prescricao: { icone: 'i-lucide-hourglass', tom: TOM.ruby },
};

// benefício · tese do caso aberto (o valor vem à parte, em mono)
const detalhes = lead =>
  [lead.benefit_type_name, lead.thesis_name].filter(Boolean).join(' · ');

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
</script>

<template>
  <div class="flex-1 w-full h-full p-4 sm:p-8 overflow-y-auto bg-n-background">
    <!-- Modo busca: rota sem contactId (entrada "Linha da Vida" do menu) -->
    <div
      v-if="!route.params.contactId"
      class="flex flex-col max-w-xl gap-4 mx-auto"
    >
      <header>
        <h1 class="text-[28px] font-semibold leading-tight text-n-slate-12">
          {{ $t('RAMON.LINHA_DA_VIDA.TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ $t('RAMON.LINHA_DA_VIDA.SEARCH_HINT') }}
        </p>
      </header>
      <label class="relative block">
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search size-4 left-3 top-1/2 text-n-slate-10"
        />
        <input
          v-model="query"
          data-testid="pessoa-search"
          class="!pl-9"
          :class="CAMPO_GRANDE"
          :placeholder="$t('RAMON.LINHA_DA_VIDA.SEARCH_PLACEHOLDER')"
        />
      </label>
      <p v-if="searching" class="text-sm text-n-slate-10">
        {{ $t('RAMON.LINHA_DA_VIDA.SEARCHING') }}
      </p>
      <ul
        v-else-if="results.length"
        class="flex flex-col list-none !p-1.5"
        :class="CARTAO"
      >
        <li v-for="c in results" :key="c.id">
          <button
            type="button"
            data-testid="pessoa-result"
            class="flex items-center justify-between gap-3"
            :class="LINHA"
            @click="openPessoa(c)"
          >
            <span class="font-medium truncate text-n-slate-12">
              {{ c.name }}
            </span>
            <span
              class="text-xs shrink-0 text-n-slate-10"
              :class="{ 'font-mono': c.phone_number }"
            >
              {{ c.phone_number || c.email || '' }}
            </span>
          </button>
        </li>
      </ul>
      <p v-else-if="query.trim().length >= 2" class="text-sm text-n-slate-10">
        {{ $t('RAMON.LINHA_DA_VIDA.SEARCH_EMPTY') }}
      </p>
    </div>
    <div
      v-else-if="loading"
      class="flex flex-col max-w-5xl gap-5 mx-auto animate-pulse"
      data-testid="lifeline-skeleton"
    >
      <div class="w-1/3 h-8 rounded-lg bg-n-alpha-2" />
      <div class="h-40 rounded-xl bg-n-alpha-2" />
      <div class="h-32 rounded-xl bg-n-alpha-2" />
      <div class="h-32 rounded-xl bg-n-alpha-2" />
    </div>
    <div v-else-if="error" class="text-sm">
      <p class="text-n-ruby-11">
        {{ $t('RAMON.LINHA_DA_VIDA.ERROR') }}
      </p>
      <Button
        data-testid="lifeline-retry"
        link
        xs
        class="mt-2"
        :label="$t('RAMON.LEAD_PANEL.RETRY')"
        @click="fetchData"
      />
    </div>

    <div v-else-if="contact" class="flex flex-col max-w-5xl gap-5 mx-auto">
      <!-- Cabeçalho: quem é + CPF · nascimento · telefone (só o que existir) -->
      <header>
        <p :class="TITULO">{{ $t('RAMON.LINHA_DA_VIDA.TITLE') }}</p>
        <h1
          class="mt-1 text-[28px] font-semibold leading-tight text-n-slate-12"
        >
          {{ contact.name }}
        </h1>
        <p
          v-if="headerParts.length"
          class="flex flex-wrap items-center gap-x-2 mt-1 text-sm text-n-slate-11"
        >
          <template v-for="(part, i) in headerParts" :key="i">
            <span v-if="i" class="text-n-slate-9">·</span>
            <span>
              {{ part.label }}
              <span class="font-mono tabular-nums">{{ part.value }}</span>
            </span>
          </template>
        </p>
        <p
          v-if="!contact.data_nascimento"
          data-testid="lifeline-no-birthdate"
          class="flex items-center gap-1.5 mt-3"
          :class="[AVISO, TOM.amber]"
        >
          <span class="i-lucide-cake size-3.5 shrink-0" />
          {{ $t('RAMON.LINHA_DA_VIDA.NO_BIRTHDATE_HINT') }}
        </p>
      </header>

      <!-- FUTURO -->
      <section :class="CARTAO" class="!p-4" data-testid="lifeline-future">
        <h2 class="mb-1" :class="TITULO">
          {{ $t('RAMON.LINHA_DA_VIDA.FUTURE') }}
        </h2>
        <p v-if="!futureItems.length" class="py-2 text-sm text-n-slate-10">
          {{ $t('RAMON.LINHA_DA_VIDA.FUTURE_EMPTY') }}
        </p>
        <ul class="list-none">
          <li
            v-for="(item, i) in futureItems"
            :key="i"
            class="flex items-center gap-3 py-2.5 border-t border-n-weak first:border-t-0"
          >
            <span
              class="flex items-center justify-center rounded-full size-8 shrink-0"
              :class="FUTURO_VISUAL[item.type].tom"
            >
              <span class="size-4" :class="FUTURO_VISUAL[item.type].icone" />
            </span>
            <span class="flex-1 min-w-0 text-sm text-n-slate-12">
              <template v-if="item.type === 'marco'">
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
              </template>
              <template v-else-if="item.type === 'dcb'">
                {{ $t('RAMON.LINHA_DA_VIDA.DCB_OF', { name: item.lead.name }) }}
              </template>
              <template v-else>
                {{
                  $t('RAMON.LINHA_DA_VIDA.PRESCRIPTION_OF', {
                    name: item.lead.name,
                  })
                }}
              </template>
            </span>
            <span
              class="flex items-center gap-1 font-mono text-xs tabular-nums shrink-0 text-n-slate-10"
            >
              <span class="i-lucide-calendar size-3" />
              {{ fmtDate(item.date) }}
            </span>
          </li>
        </ul>
        <p class="mt-2 text-[11px] text-n-slate-10" :class="SECAO">
          {{ $t('RAMON.LINHA_DA_VIDA.DISCLAIMER') }}
        </p>
      </section>

      <!-- PRESENTE -->
      <section :class="CARTAO" class="!p-4" data-testid="lifeline-present">
        <h2 class="mb-1" :class="TITULO">
          {{ $t('RAMON.LINHA_DA_VIDA.PRESENT') }}
        </h2>
        <p v-if="!openLeads.length" class="py-2 text-sm text-n-slate-10">
          {{ $t('RAMON.LINHA_DA_VIDA.PRESENT_EMPTY') }}
        </p>
        <ul class="list-none">
          <li
            v-for="lead in openLeads"
            :key="lead.id"
            class="py-2.5 border-t border-n-weak first:border-t-0"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ lead.name }}
              </span>
              <span
                class="ramon-stage-pill border shrink-0"
                :class="CHIP"
                :style="{ '--stage': lead.stage_color || DEFAULT_STAGE_COLOR }"
              >
                {{ lead.stage_name }}
              </span>
            </div>
            <p class="mt-0.5 text-xs text-n-slate-10">
              {{ detalhes(lead) }}
              <template v-if="lead.value">
                <span v-if="detalhes(lead)"> · </span>
                <span class="font-mono tabular-nums">{{
                  formatBrl(lead.value)
                }}</span>
              </template>
            </p>
            <div class="flex items-center gap-3 mt-1">
              <router-link
                v-if="lead.conversation_id"
                v-slot="{ navigate }"
                custom
                :to="conversationUrl(lead)"
              >
                <Button
                  link
                  xs
                  icon="i-lucide-message-square"
                  :label="$t('RAMON.FUNIL.OPEN_CONVERSATION')"
                  @click="navigate"
                />
              </router-link>
              <router-link
                v-slot="{ navigate }"
                custom
                :to="{ name: 'ramon_lead_dossie', params: { leadId: lead.id } }"
              >
                <Button
                  data-testid="lifeline-dossie-link"
                  link
                  xs
                  icon="i-lucide-file-text"
                  :label="$t('RAMON.DOSSIE.OPEN')"
                  @click="navigate"
                />
              </router-link>
            </div>
          </li>
        </ul>
      </section>

      <!-- PASSADO -->
      <section :class="CARTAO" class="!p-4" data-testid="lifeline-past">
        <h2 class="mb-1" :class="TITULO">
          {{ $t('RAMON.LINHA_DA_VIDA.PAST') }}
        </h2>
        <p v-if="!closedLeads.length" class="py-2 text-sm text-n-slate-10">
          {{ $t('RAMON.LINHA_DA_VIDA.PAST_EMPTY') }}
        </p>
        <ul class="list-none">
          <li
            v-for="lead in closedLeads"
            :key="lead.id"
            class="flex items-start gap-3 py-2.5 border-t border-n-weak first:border-t-0"
          >
            <span
              class="flex items-center justify-center rounded-full size-8 shrink-0"
              :class="lead.is_won ? TOM.teal : TOM.ruby"
            >
              <span
                class="size-4"
                :class="lead.is_won ? 'i-lucide-trophy' : 'i-lucide-x'"
              />
            </span>
            <div class="flex-1 min-w-0">
              <p class="flex items-center gap-2 min-w-0">
                <span class="text-sm font-medium truncate text-n-slate-12">
                  {{ lead.name }}
                </span>
                <span
                  class="shrink-0"
                  :class="[CHIP, lead.is_won ? TOM.teal : TOM.ruby]"
                >
                  {{
                    lead.is_won
                      ? $t('RAMON.LINHA_DA_VIDA.WON')
                      : $t('RAMON.LINHA_DA_VIDA.LOST')
                  }}
                </span>
              </p>
              <p class="mt-0.5 text-xs text-n-slate-10">
                <span v-if="lead.benefit_type_name">{{
                  lead.benefit_type_name
                }}</span>
                <template v-if="lead.value">
                  <span v-if="lead.benefit_type_name"> · </span>
                  <span class="font-mono tabular-nums">{{
                    formatBrl(lead.value)
                  }}</span>
                </template>
                <span v-if="lead.lost_reason"> · {{ lead.lost_reason }}</span>
              </p>
            </div>
            <span
              class="flex items-center gap-1 mt-1 font-mono text-xs tabular-nums shrink-0 text-n-slate-10"
            >
              <span class="i-lucide-calendar size-3" />
              {{ fmtDate(lead.won_at || lead.lost_at) }}
            </span>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>

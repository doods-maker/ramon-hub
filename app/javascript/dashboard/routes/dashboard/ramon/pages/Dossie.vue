<script setup>
import { ref, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import { formatBrl } from '../helpers/currency';
import { waMeUrl } from '../helpers/phone';
import { DEFAULT_STAGE_COLOR } from '../helpers/stage';
import { rascunhoCobranca } from '../helpers/rascunhoDocs';
import { BTN_LINHA } from '../components/hoje/hoje';
import Selo from '../components/hoje/Selo.vue';
import EsteiraEtapas from '../components/ficha/EsteiraEtapas.vue';
import WonValueModal from '../components/kanban/WonValueModal.vue';
import LinhaDaVida from './LinhaDaVida.vue';

defineOptions({ name: 'RamonDossie' });

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t, te } = useI18n();

const data = ref(null);
const loading = ref(false);
const error = ref(false);

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const response = await LeadsAPI.getDossie(route.params.leadId);
    data.value = response.data;
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
watch(() => route.params.leadId, fetchData, { immediate: true });

const pessoa = computed(() => data.value?.pessoa ?? {});
const origem = computed(() => data.value?.origem ?? {});
const triagem = computed(() => data.value?.triagem ?? null);
const tese = computed(() => data.value?.tese ?? null);
const timeline = computed(() => data.value?.timeline ?? []);
const tasks = computed(() => data.value?.pendencias?.tasks ?? []);
const docsMissing = computed(() => data.value?.pendencias?.docs_missing ?? []);
const esteira = computed(() => data.value?.esteira ?? []);
const docs = computed(
  () => data.value?.docs ?? { received: 0, total: 0, itens: [] }
);
const calculos = computed(() => data.value?.calculos ?? []);
const calculosTotal = computed(
  () => data.value?.calculos_total ?? calculos.value.length
);
const reunioes = computed(() => data.value?.reunioes ?? []);

const utmEntries = computed(() => Object.entries(origem.value.utm || {}));
const nextTask = computed(() => tasks.value[0] ?? null);
const subtitulo = computed(() =>
  [pessoa.value.thesis_name, pessoa.value.cidade, pessoa.value.profissao]
    .filter(Boolean)
    .join(' · ')
);
const responsavel = computed(() => pessoa.value.closer || pessoa.value.sdr);

// Abas (mockup v2 .abas-ficha); a aba fica na URL (?aba=) pra voltar ao lugar.
const ABAS = [
  'resumo',
  'documentos',
  'calculos',
  'reunioes',
  'linha_da_vida',
  'painel',
];
const valida = aba => (ABAS.includes(aba) ? aba : 'resumo');
const aba = ref(valida(route.query?.aba));
watch(
  () => route.query?.aba,
  value => {
    aba.value = valida(value);
  }
);
const setAba = key => {
  aba.value = key;
  router.replace({ query: { ...route.query, aba: key } });
};
const contagemDaAba = key => {
  if (key === 'documentos' && docs.value.total)
    return `${docs.value.received}/${docs.value.total}`;
  if (key === 'calculos') return String(calculosTotal.value);
  return '';
};

const fmtDateTime = value => {
  if (!value) return '';
  return new Date(value).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};
const fmtDate = value =>
  value ? new Date(value).toLocaleDateString('pt-BR') : '';

const kindLabel = kind => {
  const key = `RAMON.LEAD_PANEL.HISTORY.KIND.${(kind || '').toUpperCase()}`;
  return te(key) ? t(key) : kind;
};

const viabilityLabel = viability =>
  t(`RAMON.TRIAGE.VIABILITY.${(viability || 'unknown').toUpperCase()}`);

const timelineText = item => {
  if (item.type === 'note') return item.body;
  let text = kindLabel(item.kind);
  if (item.to_value) text += ` → ${item.to_value}`;
  return text;
};

const docStatusLabel = status =>
  t(`RAMON.DOCS.STATUS.${(status || 'pendente').toUpperCase()}`);
const DOC_TOM = { recebido: 'ok', solicitado: 'act', pendente: 'warn' };

const CALCULO_TIPO_LABEL = {
  painel: 'RAMON.SIMULADOR.ABA_POSSIBILIDADES',
  honorario: 'RAMON.SIMULADOR.ABA_HONORARIO',
  elegibilidade: 'RAMON.SIMULADOR.ABA_ELEGIBILIDADE',
  pensao: 'RAMON.SIMULADOR.ABA_PENSAO',
  maternidade: 'RAMON.SIMULADOR.ABA_MATERNIDADE',
  planejamento: 'RAMON.SIMULADOR.ABA_PLANEJAMENTO',
};
const calculoTipoLabel = tipo =>
  t(CALCULO_TIPO_LABEL[tipo] || 'RAMON.CALCULOS.TITLE');

const REUNIAO_STATUS_LABEL = {
  transcrevendo: 'RAMON.REUNIOES.STATUS_TRANSCREVENDO',
  pronta: 'RAMON.REUNIOES.STATUS_PRONTA',
  erro: 'RAMON.REUNIOES.STATUS_ERRO',
};
const reuniaoStatusLabel = status => t(REUNIAO_STATUS_LABEL[status]);

// --- Marcar como ganho: SEMPRE pelo WonValueModal (regra de ganho do Kanban) ---
const etapaGanho = computed(() => esteira.value.find(s => s.is_won) || null);
const etapaAtual = computed(() => esteira.value.find(s => s.current) || null);
const podeGanhar = computed(
  () =>
    !!etapaGanho.value &&
    !etapaAtual.value?.is_won &&
    !etapaAtual.value?.is_lost
);
const ganhoAberto = ref(false);
const confirmarGanho = async ({ value }) => {
  try {
    await store.dispatch('leads/update', {
      id: pessoa.value.lead_id,
      lead_stage_id: etapaGanho.value.id,
      ...(value != null ? { value } : {}),
    });
  } catch (e) {
    useAlert(t('RAMON.FUNIL.SAVE_ERROR'));
    return;
  }
  ganhoAberto.value = false;
  fetchData();
};

// --- Cobrar pendentes: rascunho no clipboard + marca pendentes como solicitados ---
const cobrarPendentes = async () => {
  const faltando = docs.value.itens.filter(i => i.status !== 'recebido');
  if (!faltando.length) return;
  try {
    await copyTextToClipboard(
      rascunhoCobranca(
        t,
        pessoa.value.lead_name,
        faltando.map(i => i.title)
      )
    );
  } catch (e) {
    useAlert(t('RAMON.DOCS.COPY_FAILED'));
    return;
  }
  useAlert(t('RAMON.DOCS.COPIED'));
  const docStatus = Object.fromEntries(
    faltando.filter(i => i.status === 'pendente').map(i => [i.id, 'solicitado'])
  );
  // o backend faz deep-merge do custom_attributes: só doc_status muda
  await LeadsAPI.update(pessoa.value.lead_id, {
    custom_attributes: { doc_status: docStatus },
  });
  fetchData();
};

// --- Painel do cliente: gera/reusa o token e copia a URL (igual à gaveta) ---
const copiarLinkPainel = async () => {
  try {
    const { data: resp } = await LeadsAPI.portalLink(pessoa.value.lead_id);
    await copyTextToClipboard(resp.url);
    useAlert(t('RAMON.PORTAL.COPIED'));
  } catch (e) {
    useAlert(t('RAMON.PORTAL.ERROR'));
  }
};

// --- Copiar dossiê (markdown → clipboard, insumo do dossiê W3 pro jurídico) ---
const line = (label, value) => (value ? `- ${label}: ${value}` : null);

const markdown = computed(() => {
  const p = pessoa.value;
  const o = origem.value;
  const parts = [
    `# ${t('RAMON.DOSSIE.TITLE')} — ${p.lead_name || ''}`,
    '',
    `## ${t('RAMON.DOSSIE.WHO')}`,
    line(t('RAMON.DRAWER.NAME'), p.contact_name || p.lead_name),
    line(t('RAMON.DOSSIE.PHONE'), p.phone_number),
    line(t('RAMON.DOSSIE.AGE_LABEL'), p.idade),
    line(t('RAMON.DOSSIE.CITY'), p.cidade),
    line(t('RAMON.DOSSIE.STAGE'), p.stage_name),
    line(t('RAMON.DOSSIE.VALUE'), p.value ? formatBrl(p.value) : null),
    line(
      t('RAMON.DOSSIE.CONSENT'),
      p.consent_marketing
        ? t('RAMON.DOSSIE.CONSENT_YES')
        : t('RAMON.DOSSIE.CONSENT_NO')
    ),
    '',
    `## ${t('RAMON.DOSSIE.ORIGIN')}`,
    line(t('RAMON.DRAWER.SOURCE'), o.source),
    line(t('RAMON.DRAWER.CHANNEL'), o.channel_label || o.channel),
    ...utmEntries.value.map(([k, v]) => `- ${k}: ${v}`),
    o.indicacao ? `- ${t('RAMON.DOSSIE.REFERRAL')}` : null,
    '',
    `## ${t('RAMON.DOSSIE.TRIAGE')}`,
  ];

  if (triagem.value) {
    if (triagem.value.awaiting_human)
      parts.push(`- ${t('RAMON.DOSSIE.TRIAGE_AWAITING_HUMAN')}`);
    parts.push(
      line(
        t('RAMON.TRIAGE.VIABILITY.LABEL'),
        viabilityLabel(triagem.value.viability)
      )
    );
    if (triagem.value.result) parts.push('', triagem.value.result);
  } else {
    parts.push(t('RAMON.DOSSIE.TRIAGE_EMPTY'));
  }

  parts.push('', `## ${t('RAMON.DOSSIE.THESIS')}`);
  if (tese.value) {
    parts.push(line(t('RAMON.DRAWER.THESIS'), tese.value.name));
    parts.push(line(t('RAMON.DOSSIE.FEE'), tese.value.honorario_text));
    if (tese.value.objecoes?.length) {
      parts.push('', `### ${t('RAMON.DOSSIE.OBJECTIONS')}`);
      tese.value.objecoes.forEach(obj =>
        parts.push(`- **${obj.title}** — ${obj.content}`)
      );
    }
  } else {
    parts.push(t('RAMON.DOSSIE.THESIS_EMPTY'));
  }

  parts.push('', `## ${t('RAMON.DOSSIE.TIMELINE')}`);
  timeline.value.forEach(item =>
    parts.push(
      `- ${fmtDateTime(item.created_at)} — ${item.author_name || t('RAMON.LEAD_PANEL.HISTORY.SYSTEM')}: ${timelineText(item)}`
    )
  );

  parts.push('', `## ${t('RAMON.DOSSIE.PENDING')}`);
  tasks.value.forEach(task =>
    parts.push(`- [ ] ${task.title} (${fmtDateTime(task.due_at)})`)
  );
  docsMissing.value.forEach(doc =>
    parts.push(`- [ ] ${t('RAMON.DOSSIE.DOC_PREFIX')} ${doc.title}`)
  );

  return parts.filter(part => part !== null).join('\n');
});

const copyDossie = async () => {
  try {
    await copyTextToClipboard(markdown.value);
    useAlert(t('RAMON.DOSSIE.COPIED'));
  } catch (e) {
    useAlert(t('RAMON.DOSSIE.COPY_FAILED'));
  }
};

// classes do mockup v2 (.bl h2, table, .dado)
const H2 =
  'mb-2.5 flex items-baseline gap-2 text-sm font-semibold text-n-slate-12';
const LINK = 'ms-auto text-[12.5px] font-medium text-n-blue-11 hover:underline';
const TH = 'py-1.5 text-left text-xs font-normal text-n-slate-9';
const TD = 'py-2.5 border-t border-n-weak';
const DADO = 'flex justify-between gap-3 py-1 text-[13px]';
const VAZIO = 'text-[13px] text-n-slate-9';
</script>

<template>
  <div class="w-full h-full overflow-y-auto bg-n-background">
    <div
      v-if="loading && !data"
      class="flex flex-col max-w-[1080px] gap-4 px-8 pt-7 mx-auto animate-pulse"
      data-testid="dossie-skeleton"
    >
      <div class="w-1/3 h-8 rounded bg-n-slate-3" />
      <div class="h-24 rounded-xl bg-n-slate-3" />
      <div class="h-40 rounded-xl bg-n-slate-3" />
    </div>
    <div v-else-if="error" class="px-8 pt-7 text-sm" data-testid="dossie-error">
      <p class="text-n-ruby-11">{{ $t('RAMON.DOSSIE.ERROR') }}</p>
      <button
        type="button"
        data-testid="dossie-retry"
        class="mt-2 text-xs text-n-blue-11 hover:underline"
        @click="fetchData"
      >
        {{ $t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <div v-else-if="data" class="w-full max-w-[1080px] px-8 pt-7 pb-16 mx-auto">
      <router-link
        :to="{ name: 'ramon_clientes' }"
        class="inline-flex items-center gap-1 text-[12.5px] text-n-slate-9 hover:text-n-slate-12"
      >
        <span class="i-lucide-arrow-left size-3.5" />{{
          $t('RAMON.FICHA.VOLTAR')
        }}
      </router-link>

      <header
        class="flex flex-wrap items-end gap-4 mt-3 mb-1"
        data-testid="ficha-header"
      >
        <div class="min-w-0">
          <h1
            class="text-[26px] font-semibold leading-tight tracking-tight text-n-slate-12"
          >
            {{ pessoa.lead_name }}
          </h1>
          <div
            class="flex flex-wrap items-center gap-2.5 mt-1 text-[13.5px] text-n-slate-11"
          >
            <span
              v-if="pessoa.stage_name"
              data-testid="ficha-stage"
              class="ramon-stage-pill inline-flex items-center gap-1.5 px-2.5 py-1 text-[11.5px] font-medium leading-none rounded-full border border-transparent"
              :style="{ '--stage': pessoa.stage_color || DEFAULT_STAGE_COLOR }"
            >
              <span class="size-1.5 rounded-full bg-current" />
              {{ pessoa.stage_name }}
            </span>
            {{ subtitulo }}
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-2 ms-auto">
          <router-link
            v-if="pessoa.conversation_id"
            :to="{
              name: 'inbox_conversation',
              params: { conversation_id: pessoa.conversation_id },
            }"
            data-testid="ficha-open-conversation"
            :class="BTN_LINHA"
          >
            <span class="i-lucide-message-circle size-4" />{{
              $t('RAMON.FICHA.CONVERSA')
            }}
          </router-link>
          <button
            v-else
            type="button"
            disabled
            data-testid="ficha-open-conversation"
            :title="$t('RAMON.FICHA.SEM_CONVERSA')"
            :class="BTN_LINHA"
            class="opacity-50 cursor-not-allowed"
          >
            <span class="i-lucide-message-circle size-4" />{{
              $t('RAMON.FICHA.CONVERSA')
            }}
          </button>
          <router-link
            :to="{ name: 'ramon_reunioes', query: { leadId: pessoa.lead_id } }"
            data-testid="ficha-record-meeting"
            :class="BTN_LINHA"
          >
            <span class="i-lucide-mic size-4" />{{
              $t('RAMON.FICHA.RECORD_MEETING')
            }}
          </router-link>
          <button
            v-if="podeGanhar"
            type="button"
            data-testid="ficha-marcar-ganho"
            class="inline-flex items-center gap-1.5 whitespace-nowrap rounded-[7px] border border-n-teal-9 bg-n-teal-9 px-2.5 py-[5px] text-[12.5px] font-medium text-white hover:brightness-110"
            @click="ganhoAberto = true"
          >
            <span class="i-lucide-trophy size-4" />{{
              $t('RAMON.FICHA.MARCAR_GANHO')
            }}
          </button>
          <button
            type="button"
            data-testid="dossie-copy"
            :title="$t('RAMON.DOSSIE.COPY')"
            :aria-label="$t('RAMON.DOSSIE.COPY')"
            :class="BTN_LINHA"
            @click="copyDossie"
          >
            <span class="i-lucide-clipboard-copy size-4" />
          </button>
        </div>
      </header>

      <EsteiraEtapas v-if="esteira.length" class="mt-6" :stages="esteira" />

      <nav class="flex flex-wrap gap-x-[22px] mt-6 mb-7 border-b border-n-weak">
        <button
          v-for="key in ABAS"
          :key="key"
          type="button"
          :data-testid="`ficha-aba-${key}`"
          class="-mb-px py-2.5 text-[13.5px] border-b-2"
          :class="
            aba === key
              ? 'border-n-blue-9 font-medium text-n-slate-12'
              : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
          "
          @click="setAba(key)"
        >
          {{ $t(`RAMON.FICHA.ABA.${key.toUpperCase()}`) }}
          <span
            v-if="contagemDaAba(key)"
            class="font-mono text-[12.5px] text-n-slate-9"
          >
            {{ contagemDaAba(key) }}
          </span>
        </button>
      </nav>

      <div class="grid items-start gap-12 lg:grid-cols-[1fr_280px]">
        <div class="min-w-0">
          <!-- RESUMO -->
          <template v-if="aba === 'resumo'">
            <section class="mb-9" data-testid="dossie-triagem">
              <h2 :class="H2">{{ $t('RAMON.FICHA.RESUMO_CASO') }}</h2>
              <p
                v-if="triagem?.awaiting_human"
                class="mb-1 text-[13px] text-n-amber-11"
                data-testid="dossie-awaiting-human"
              >
                {{ $t('RAMON.DOSSIE.TRIAGE_AWAITING_HUMAN') }}
              </p>
              <template v-if="triagem">
                <p
                  v-if="triagem.result"
                  class="max-w-[62ch] whitespace-pre-wrap text-n-slate-11"
                >
                  {{ triagem.result }}
                </p>
                <p class="mt-1 text-xs text-n-slate-9">
                  {{ $t('RAMON.TRIAGE.VIABILITY.LABEL') }}:
                  {{ viabilityLabel(triagem.viability) }}
                </p>
              </template>
              <p v-else :class="VAZIO">{{ $t('RAMON.DOSSIE.TRIAGE_EMPTY') }}</p>
            </section>

            <section
              v-if="tasks.length || docsMissing.length"
              class="mb-9"
              data-testid="dossie-pendencias-lista"
            >
              <h2 :class="H2">{{ $t('RAMON.DOSSIE.PENDING') }}</h2>
              <ul class="text-[13px]">
                <li
                  v-for="task in tasks"
                  :key="`t-${task.id}`"
                  class="flex items-baseline gap-3 py-1.5"
                >
                  <span class="text-n-slate-12">{{ task.title }}</span>
                  <span class="ms-auto font-mono text-xs text-n-slate-9">
                    {{ fmtDateTime(task.due_at) }}
                  </span>
                </li>
                <li
                  v-for="(doc, i) in docsMissing"
                  :key="`d-${i}`"
                  class="flex items-baseline gap-3 py-1.5"
                  data-testid="dossie-doc"
                >
                  <span class="text-n-slate-12">{{ doc.title }}</span>
                  <Selo class="ms-auto" :tom="DOC_TOM[doc.status] || 'warn'">
                    {{ docStatusLabel(doc.status) }}
                  </Selo>
                </li>
              </ul>
            </section>

            <section v-if="tese?.objecoes?.length" class="mb-9">
              <h2 :class="H2">{{ $t('RAMON.DOSSIE.OBJECTIONS') }}</h2>
              <div
                v-for="(obj, i) in tese.objecoes"
                :key="i"
                class="mb-2"
                data-testid="dossie-objecao"
              >
                <p class="text-[13px] font-medium text-n-slate-12">
                  {{ obj.title }}
                </p>
                <p class="text-[13px] text-n-slate-11">{{ obj.content }}</p>
              </div>
            </section>

            <section data-testid="dossie-timeline">
              <h2 :class="H2">{{ $t('RAMON.FICHA.HISTORICO') }}</h2>
              <p v-if="!timeline.length" :class="VAZIO">
                {{ $t('RAMON.DOSSIE.TIMELINE_EMPTY') }}
              </p>
              <ul>
                <li
                  v-for="(item, i) in timeline"
                  :key="i"
                  class="flex items-baseline gap-3 py-2 text-[13px] border-t border-n-weak"
                >
                  <span class="font-mono text-xs text-n-slate-9 shrink-0">
                    {{ fmtDateTime(item.created_at) }}
                  </span>
                  <span class="text-n-slate-11">
                    <strong
                      v-if="item.author_name"
                      class="font-medium text-n-slate-12"
                      >{{ item.author_name }}</strong
                    >
                    <span v-else>{{
                      $t('RAMON.LEAD_PANEL.HISTORY.SYSTEM')
                    }}</span>
                    · {{ timelineText(item) }}
                  </span>
                </li>
              </ul>
            </section>
          </template>

          <!-- DOCUMENTOS -->
          <section v-else-if="aba === 'documentos'" data-testid="dossie-docs">
            <h2 :class="H2">
              {{ $t('RAMON.FICHA.DOCS_TITLE') }}
              <span
                v-if="docs.total"
                class="font-mono font-normal text-n-slate-9"
              >
                {{ `${docs.received}/${docs.total}` }}
              </span>
              <button
                v-if="docs.received < docs.total"
                type="button"
                data-testid="ficha-cobrar"
                :class="LINK"
                @click="cobrarPendentes"
              >
                {{ $t('RAMON.DOCS.CHARGE') }}
              </button>
            </h2>
            <p
              v-if="!docs.itens.length"
              :class="VAZIO"
              data-testid="ficha-aba-vazia"
            >
              {{ $t('RAMON.FICHA.DOCS_VAZIO') }}
            </p>
            <table v-else class="w-full text-[13px] border-collapse">
              <thead>
                <tr>
                  <th :class="TH">{{ $t('RAMON.FICHA.DOCUMENTO') }}</th>
                  <th :class="TH">{{ $t('RAMON.FICHA.SITUACAO') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="item in docs.itens"
                  :key="item.id"
                  data-testid="ficha-doc-item"
                >
                  <td :class="TD" class="text-n-slate-12">{{ item.title }}</td>
                  <td :class="TD">
                    <Selo :tom="DOC_TOM[item.status] || 'warn'">
                      {{ docStatusLabel(item.status) }}
                    </Selo>
                  </td>
                </tr>
              </tbody>
            </table>
          </section>

          <!-- CÁLCULOS -->
          <section v-else-if="aba === 'calculos'" data-testid="dossie-calculos">
            <h2 :class="H2">
              {{ $t('RAMON.FICHA.CALCULOS_TITLE') }}
              <span class="font-mono font-normal text-n-slate-9">
                {{ calculosTotal }}
              </span>
              <router-link
                :to="{
                  name: 'ramon_calculos_lead',
                  params: { leadId: pessoa.lead_id },
                }"
                :class="LINK"
              >
                {{ $t('RAMON.FICHA.NOVO_CALCULO') }}
              </router-link>
            </h2>
            <p
              v-if="!calculos.length"
              :class="VAZIO"
              data-testid="ficha-aba-vazia"
            >
              {{ $t('RAMON.FICHA.CALCULOS_EMPTY') }}
            </p>
            <table v-else class="w-full text-[13px] border-collapse">
              <thead>
                <tr>
                  <th :class="TH">{{ $t('RAMON.FICHA.DATA') }}</th>
                  <th :class="TH">{{ $t('RAMON.FICHA.TIPO') }}</th>
                  <th :class="TH">{{ $t('RAMON.FICHA.SEGURADO') }}</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="calculo in calculos" :key="calculo.id">
                  <td
                    :class="TD"
                    class="font-mono text-[12.5px] text-n-slate-11"
                  >
                    {{ fmtDate(calculo.created_at) }}
                  </td>
                  <td :class="TD" class="text-n-slate-12">
                    {{ calculoTipoLabel(calculo.tipo) }}
                  </td>
                  <td :class="TD" class="text-n-slate-11">
                    {{ calculo.segurado_nome }}
                  </td>
                </tr>
              </tbody>
            </table>
          </section>

          <!-- REUNIÕES -->
          <section v-else-if="aba === 'reunioes'" data-testid="dossie-reunioes">
            <h2 :class="H2">
              {{ $t('RAMON.FICHA.REUNIOES_TITLE') }}
              <router-link
                :to="{
                  name: 'ramon_reunioes',
                  query: { leadId: pessoa.lead_id },
                }"
                :class="LINK"
              >
                {{ $t('RAMON.FICHA.RECORD_MEETING') }}
              </router-link>
            </h2>
            <p
              v-if="!reunioes.length"
              :class="VAZIO"
              data-testid="ficha-aba-vazia"
            >
              {{ $t('RAMON.FICHA.REUNIOES_EMPTY') }}
            </p>
            <ul v-else>
              <li
                v-for="reuniao in reunioes"
                :key="reuniao.id"
                class="flex items-baseline gap-3 py-2.5 text-[13px] border-t border-n-weak"
              >
                <router-link
                  :to="{
                    name: 'ramon_reuniao',
                    params: { reuniaoId: reuniao.id },
                  }"
                  class="font-medium text-n-slate-12 hover:text-n-blue-11"
                >
                  {{ reuniao.titulo }}
                </router-link>
                <span class="text-n-slate-11">
                  {{ reuniaoStatusLabel(reuniao.status) }}
                </span>
                <span class="ms-auto font-mono text-xs text-n-slate-9">
                  {{ fmtDateTime(reuniao.created_at) }}
                </span>
              </li>
            </ul>
          </section>

          <!-- LINHA DA VIDA -->
          <template v-else-if="aba === 'linha_da_vida'">
            <LinhaDaVida
              v-if="pessoa.contact_id"
              :contact-id="pessoa.contact_id"
            />
            <p v-else :class="VAZIO" data-testid="ficha-aba-vazia">
              {{ $t('RAMON.FICHA.SEM_CONTATO') }}
            </p>
          </template>

          <!-- PAINEL DO CLIENTE -->
          <section v-else data-testid="dossie-painel">
            <h2 :class="H2">{{ $t('RAMON.PORTAL.LABEL') }}</h2>
            <p class="max-w-[62ch] mb-4 text-[13px] text-n-slate-11">
              {{ $t('RAMON.FICHA.PAINEL_TEXTO') }}
            </p>
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                data-testid="ficha-portal-link"
                :class="BTN_LINHA"
                @click="copiarLinkPainel"
              >
                <span class="i-lucide-link size-4" />{{
                  $t('RAMON.PORTAL.COPY_LINK')
                }}
              </button>
              <router-link
                :to="{ name: 'ramon_portal_clientes' }"
                :class="BTN_LINHA"
              >
                {{ $t('RAMON.FICHA.PAINEL_ABRIR') }}
              </router-link>
            </div>
          </section>
        </div>

        <!-- Lateral: próximo passo + dados -->
        <aside>
          <div
            class="mb-4 rounded-[10px] bg-n-blue-9/[0.08] p-3.5 dark:bg-n-blue-9/[0.16]"
            data-testid="dossie-pendencias"
          >
            <h3 class="mb-1 text-xs font-semibold text-n-blue-11">
              {{ $t('RAMON.FICHA.NEXT_TITLE') }}
            </h3>
            <template v-if="nextTask">
              <p
                class="text-[13.5px] font-medium text-n-slate-12"
                data-testid="dossie-task"
              >
                {{ nextTask.title }}
              </p>
              <p
                v-if="nextTask.due_at"
                class="font-mono text-[12.5px] text-n-slate-11"
              >
                {{ fmtDateTime(nextTask.due_at) }}
              </p>
            </template>
            <p v-else class="text-[12.5px] text-n-slate-11">
              {{ $t('RAMON.FICHA.NEXT_EMPTY') }}
            </p>
          </div>

          <div data-testid="dossie-pessoa">
            <div :class="DADO">
              <span class="text-n-slate-9">{{
                $t('RAMON.FICHA.RESPONSAVEL')
              }}</span>
              <span class="text-n-slate-12">{{ responsavel || '—' }}</span>
            </div>
            <div v-if="pessoa.value" :class="DADO" data-testid="ficha-valor">
              <span class="text-n-slate-9">{{
                $t('RAMON.FICHA.VALOR_ESTIMADO')
              }}</span>
              <span class="flex items-center gap-1.5 font-mono text-n-slate-12">
                <Selo v-if="pessoa.valor_estimado_origem === 'auto'" tom="warn">
                  {{ $t('RAMON.FICHA.ESTIMATED') }}
                </Selo>
                {{ formatBrl(pessoa.value) }}
              </span>
            </div>
            <div v-if="pessoa.phone_number" :class="DADO">
              <span class="text-n-slate-9">{{ $t('RAMON.DOSSIE.PHONE') }}</span>
              <a
                :href="waMeUrl(pessoa.phone_number)"
                target="_blank"
                rel="noopener noreferrer"
                class="font-mono text-n-slate-12 hover:text-n-blue-11"
              >
                {{ pessoa.phone_number }}
              </a>
            </div>
            <div v-if="pessoa.idade" :class="DADO">
              <span class="text-n-slate-9">{{
                $t('RAMON.DOSSIE.AGE_LABEL')
              }}</span>
              <span class="text-n-slate-12">
                {{ $t('RAMON.DOSSIE.AGE', { age: pessoa.idade }) }}
              </span>
            </div>
            <div v-if="pessoa.cidade" :class="DADO">
              <span class="text-n-slate-9">{{ $t('RAMON.DOSSIE.CITY') }}</span>
              <span class="text-n-slate-12">{{ pessoa.cidade }}</span>
            </div>
            <div :class="DADO">
              <span class="text-n-slate-9">{{
                $t('RAMON.DOSSIE.CONSENT')
              }}</span>
              <span
                :class="
                  pessoa.consent_marketing
                    ? 'text-n-teal-11'
                    : 'text-n-amber-11'
                "
              >
                {{
                  pessoa.consent_marketing
                    ? $t('RAMON.DOSSIE.CONSENT_YES')
                    : $t('RAMON.DOSSIE.CONSENT_NO')
                }}
              </span>
            </div>
          </div>

          <div data-testid="dossie-origem">
            <div :class="DADO">
              <span class="text-n-slate-9">{{
                $t('RAMON.DRAWER.SOURCE')
              }}</span>
              <span class="text-right text-n-slate-12">
                {{ origem.channel_label || origem.source || '—' }}
              </span>
            </div>
            <p
              v-if="origem.indicacao"
              class="text-xs text-n-teal-11"
              data-testid="dossie-indicacao"
            >
              {{ $t('RAMON.DOSSIE.REFERRAL') }}
            </p>
            <p
              v-for="[key, value] in utmEntries"
              :key="key"
              class="font-mono text-[11.5px] text-n-slate-9"
            >
              {{ `${key}: ${value}` }}
            </p>
          </div>

          <div data-testid="dossie-tese">
            <div v-if="tese" :class="DADO">
              <span class="text-n-slate-9">{{
                $t('RAMON.DRAWER.THESIS')
              }}</span>
              <span class="text-right text-n-slate-12">{{ tese.name }}</span>
            </div>
            <div
              v-if="tese?.honorario_text"
              :class="DADO"
              data-testid="dossie-honorario"
            >
              <span class="text-n-slate-9">{{ $t('RAMON.DOSSIE.FEE') }}</span>
              <span class="text-right text-n-slate-12">
                {{ tese.honorario_text }}
              </span>
            </div>
          </div>
        </aside>
      </div>
    </div>
    <WonValueModal
      v-if="ganhoAberto"
      :initial-value="pessoa.value ?? null"
      @confirm-value="confirmarGanho"
      @cancel-value="ganhoAberto = false"
    />
  </div>
</template>

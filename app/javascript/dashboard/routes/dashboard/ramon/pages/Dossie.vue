<script setup>
import { ref, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import { formatBrl } from '../helpers/currency';
import { waMeUrl } from '../helpers/phone';
import EsteiraEtapas from '../components/ficha/EsteiraEtapas.vue';

defineOptions({ name: 'RamonDossie' });

const route = useRoute();
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
const reunioes = computed(() => data.value?.reunioes ?? []);

const utmEntries = computed(() => Object.entries(origem.value.utm || {}));

const nextTask = computed(() => tasks.value[0] ?? null);
const docsPercent = computed(() =>
  docs.value.total
    ? Math.round((docs.value.received / docs.value.total) * 100)
    : 0
);
const initial = computed(() =>
  (pessoa.value.lead_name || '').trim().charAt(0).toUpperCase()
);

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

// mesmas cores por status do DocChecklist (recebido=teal, solicitado=iris,
// pendente=amber), aqui só como selo de leitura.
const docChipClass = status => {
  if (status === 'recebido')
    return 'bg-n-teal-3 text-n-teal-11 border-n-teal-6';
  if (status === 'solicitado')
    return 'bg-n-iris-3 text-n-iris-11 border-n-iris-6';
  return 'bg-n-amber-3 text-n-amber-11 border-n-amber-6';
};

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
</script>

<template>
  <div class="flex-1 w-full h-full p-4 sm:p-8 overflow-y-auto bg-n-background">
    <div
      v-if="loading"
      class="flex flex-col max-w-5xl gap-4 mx-auto animate-pulse"
      data-testid="dossie-skeleton"
    >
      <div class="w-1/3 h-8 rounded bg-n-solid-2" />
      <div class="h-24 rounded-xl bg-n-solid-2" />
      <div class="h-24 rounded-xl bg-n-solid-2" />
      <div class="h-40 rounded-xl bg-n-solid-2" />
    </div>
    <div v-else-if="error" class="text-sm" data-testid="dossie-error">
      <p class="text-n-ruby-11">{{ $t('RAMON.DOSSIE.ERROR') }}</p>
      <button
        type="button"
        data-testid="dossie-retry"
        class="mt-2 text-xs text-n-iris-11 hover:underline"
        @click="fetchData"
      >
        {{ $t('RAMON.LEAD_PANEL.RETRY') }}
      </button>
    </div>

    <div v-else-if="data" class="max-w-5xl mx-auto">
      <!-- Cabeçalho da ficha: quem é, quanto vale, a esteira -->
      <section
        class="p-6 border shadow-sm rounded-2xl bg-n-solid-1 border-n-weak"
        data-testid="ficha-header"
      >
        <div class="flex flex-wrap items-start gap-4">
          <div
            class="grid text-xl font-semibold rounded-full size-14 shrink-0 place-items-center bg-n-iris-3 text-n-iris-11 font-cormorant"
          >
            {{ initial }}
          </div>
          <div class="min-w-0">
            <p class="text-xs tracking-[0.2em] uppercase text-n-slate-11">
              {{ $t('RAMON.FICHA.TITLE') }}
            </p>
            <h1 class="text-3xl font-semibold font-cormorant text-n-slate-12">
              {{ pessoa.lead_name }}
            </h1>
            <div class="flex flex-wrap gap-2 mt-2">
              <span
                v-if="pessoa.thesis_name"
                class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-iris-3 text-n-iris-11"
              >
                {{ pessoa.thesis_name }}
              </span>
              <span
                v-if="origem.channel_label"
                class="px-2 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-slate-11"
              >
                {{ origem.channel_label }}
              </span>
              <a
                v-if="pessoa.phone_number"
                :href="waMeUrl(pessoa.phone_number)"
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-iris-11 hover:underline"
              >
                <span class="i-lucide-phone size-3" />{{ pessoa.phone_number }}
              </a>
              <span
                v-if="pessoa.cidade"
                class="px-2 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-slate-11"
              >
                {{ pessoa.cidade }}
              </span>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-3 ml-auto">
            <div
              v-if="pessoa.value"
              class="text-right"
              data-testid="ficha-valor"
            >
              <p class="text-xl font-bold tabular-nums text-n-slate-12">
                {{ formatBrl(pessoa.value) }}
              </p>
              <p class="text-xs text-n-slate-11">
                <span v-if="pessoa.probability" class="tabular-nums">
                  {{ pessoa.probability }}% {{ $t('RAMON.FICHA.PROBABILITY') }}
                </span>
                <span
                  v-if="pessoa.valor_estimado_origem === 'auto'"
                  class="ml-1 px-1.5 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11"
                >
                  {{ $t('RAMON.FICHA.ESTIMATED') }}
                </span>
              </p>
            </div>
            <button
              type="button"
              data-testid="dossie-copy"
              class="flex items-center gap-1 px-3 py-1.5 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak hover:bg-n-alpha-2 shrink-0"
              @click="copyDossie"
            >
              <span class="i-lucide-clipboard-copy size-4" />{{
                $t('RAMON.DOSSIE.COPY')
              }}
            </button>
            <router-link
              v-if="pessoa.conversation_id"
              :to="{
                name: 'inbox_conversation',
                params: { conversation_id: pessoa.conversation_id },
              }"
              data-testid="ficha-open-conversation"
              class="flex items-center gap-1 px-3 py-1.5 text-sm font-semibold text-white rounded-lg shadow-sm bg-n-iris-9 hover:bg-n-iris-10 shrink-0"
            >
              <span class="i-lucide-message-square size-4" />{{
                $t('RAMON.FICHA.OPEN_CONVERSATION')
              }}
            </router-link>
          </div>
        </div>

        <div class="pt-4 mt-6 border-t border-n-weak">
          <EsteiraEtapas :stages="esteira" />
        </div>
      </section>

      <div class="grid items-start gap-5 mt-5 lg:grid-cols-[1fr_340px]">
        <!-- Coluna principal: o que fazer agora -->
        <div class="flex flex-col gap-5">
          <section
            class="p-4 border border-l-4 shadow-sm rounded-xl bg-n-solid-1 border-n-weak border-l-n-iris-9"
            data-testid="dossie-pendencias"
          >
            <h2
              class="mb-2 text-xs font-bold tracking-widest uppercase text-n-slate-11"
            >
              {{ $t('RAMON.FICHA.NEXT_TITLE') }}
            </h2>
            <template v-if="nextTask">
              <p
                class="text-base font-semibold text-n-slate-12"
                data-testid="dossie-task"
              >
                {{ nextTask.title }}
              </p>
              <p
                v-if="nextTask.due_at"
                class="text-sm tabular-nums text-n-slate-11"
              >
                {{ fmtDateTime(nextTask.due_at) }}
              </p>
            </template>
            <p v-else class="text-sm text-n-slate-10">
              {{ $t('RAMON.FICHA.NEXT_EMPTY') }}
            </p>
            <ul v-if="docsMissing.length" class="flex flex-col gap-1 mt-3">
              <li
                v-for="(doc, i) in docsMissing"
                :key="`doc-${i}`"
                class="flex items-baseline gap-2 text-sm text-n-amber-11"
                data-testid="dossie-doc"
              >
                <span
                  class="i-lucide-file-warning size-3 shrink-0 self-center"
                />
                {{ doc.title }}
                <span class="text-xs text-n-slate-10">{{
                  docStatusLabel(doc.status)
                }}</span>
              </li>
            </ul>
          </section>

          <section
            v-if="docs.itens.length"
            class="p-4 border shadow-sm rounded-xl bg-n-solid-1 border-n-weak"
            data-testid="dossie-docs"
          >
            <h2
              class="flex items-center mb-2 text-xs font-bold tracking-widest uppercase text-n-slate-11"
            >
              {{ $t('RAMON.FICHA.DOCS_TITLE') }}
              <span
                class="ml-auto font-normal tracking-normal normal-case tabular-nums"
              >
                {{
                  $t('RAMON.DOCS.COUNT', {
                    received: docs.received,
                    total: docs.total,
                  })
                }}
              </span>
            </h2>
            <div class="h-1.5 overflow-hidden rounded-full bg-n-alpha-2">
              <div
                class="h-full rounded-full bg-n-iris-9"
                :style="{ width: `${docsPercent}%` }"
              />
            </div>
            <ul class="mt-2 divide-y divide-n-weak">
              <li
                v-for="item in docs.itens"
                :key="item.id"
                class="flex items-center gap-2 py-2 text-sm"
                data-testid="ficha-doc-item"
              >
                <span class="truncate text-n-slate-12">{{ item.title }}</span>
                <span
                  class="ml-auto shrink-0 rounded-full border px-2 py-0.5 text-[11px] uppercase"
                  :class="docChipClass(item.status)"
                >
                  {{ docStatusLabel(item.status) }}
                </span>
              </li>
            </ul>
          </section>

          <section
            class="p-4 border shadow-sm rounded-xl bg-n-solid-1 border-n-weak"
            data-testid="dossie-timeline"
          >
            <h2
              class="mb-2 text-xs font-bold tracking-widest uppercase text-n-slate-11"
            >
              {{ $t('RAMON.DOSSIE.TIMELINE') }}
            </h2>
            <p v-if="!timeline.length" class="text-sm text-n-slate-10">
              {{ $t('RAMON.DOSSIE.TIMELINE_EMPTY') }}
            </p>
            <ul class="divide-y divide-n-weak">
              <li
                v-for="(item, i) in timeline"
                :key="i"
                class="flex items-baseline gap-3 py-2 text-sm"
              >
                <span class="text-xs tabular-nums text-n-slate-10 shrink-0">
                  {{ fmtDateTime(item.created_at) }}
                </span>
                <span class="text-n-slate-11">
                  <strong v-if="item.author_name" class="text-n-slate-12">{{
                    item.author_name
                  }}</strong>
                  <span v-else>{{
                    $t('RAMON.LEAD_PANEL.HISTORY.SYSTEM')
                  }}</span>
                  · {{ timelineText(item) }}
                </span>
              </li>
            </ul>
          </section>
        </div>

        <!-- Coluna lateral: o dossiê de leitura -->
        <div class="flex flex-col gap-5">
          <section
            class="p-4 border shadow-sm rounded-xl bg-n-solid-1 border-n-weak"
          >
            <div data-testid="dossie-pessoa">
              <h2
                class="mb-2 text-xs font-bold tracking-widest uppercase text-n-slate-11"
              >
                {{ $t('RAMON.DOSSIE.WHO') }}
              </h2>
              <p class="text-sm text-n-slate-12">
                <span>{{ pessoa.contact_name || pessoa.lead_name }}</span>
                <span v-if="pessoa.idade">
                  · {{ $t('RAMON.DOSSIE.AGE', { age: pessoa.idade }) }}</span
                >
                <span v-if="pessoa.cidade"> · {{ pessoa.cidade }}</span>
              </p>
              <p class="mt-1 text-xs text-n-slate-10">
                {{ $t('RAMON.DOSSIE.CONSENT') }}:
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
              </p>
            </div>

            <div
              class="pt-3 mt-3 border-t border-n-weak"
              data-testid="dossie-origem"
            >
              <h2
                class="mb-2 text-xs font-bold tracking-widest uppercase text-n-slate-11"
              >
                {{ $t('RAMON.DOSSIE.ORIGIN') }}
              </h2>
              <p class="text-sm text-n-slate-12">
                <span v-if="origem.channel_label">{{
                  origem.channel_label
                }}</span>
                <span v-if="origem.source" class="text-n-slate-11">
                  · {{ origem.source }}</span
                >
                <span v-if="!origem.channel_label && !origem.source">—</span>
              </p>
              <p
                v-if="origem.indicacao"
                class="mt-1 text-xs text-n-teal-11"
                data-testid="dossie-indicacao"
              >
                {{ $t('RAMON.DOSSIE.REFERRAL') }}
              </p>
              <p
                v-for="[key, value] in utmEntries"
                :key="key"
                class="text-xs text-n-slate-10"
              >
                {{ key }}: {{ value }}
              </p>
            </div>

            <div
              class="pt-3 mt-3 border-t border-n-weak"
              data-testid="dossie-triagem"
            >
              <h2
                class="mb-2 text-xs font-bold tracking-widest uppercase text-n-slate-11"
              >
                {{ $t('RAMON.DOSSIE.TRIAGE') }}
              </h2>
              <p v-if="!triagem" class="text-sm text-n-slate-10">
                {{ $t('RAMON.DOSSIE.TRIAGE_EMPTY') }}
              </p>
              <template v-else>
                <p
                  v-if="triagem.awaiting_human"
                  class="mb-1 text-sm text-n-amber-11"
                  data-testid="dossie-awaiting-human"
                >
                  {{ $t('RAMON.DOSSIE.TRIAGE_AWAITING_HUMAN') }}
                </p>
                <p class="text-sm text-n-slate-12">
                  {{ $t('RAMON.TRIAGE.VIABILITY.LABEL') }}:
                  {{ viabilityLabel(triagem.viability) }}
                </p>
                <p
                  v-if="triagem.result"
                  class="mt-1 text-sm whitespace-pre-wrap text-n-slate-11"
                >
                  {{ triagem.result }}
                </p>
              </template>
            </div>
          </section>

          <section
            class="p-4 border shadow-sm rounded-xl bg-n-solid-1 border-n-weak"
            data-testid="dossie-calculos"
          >
            <h2
              class="mb-2 text-xs font-bold tracking-widest uppercase text-n-slate-11"
            >
              {{ $t('RAMON.FICHA.CALCULOS_TITLE') }}
            </h2>
            <p v-if="!calculos.length" class="text-sm text-n-slate-10">
              {{ $t('RAMON.FICHA.CALCULOS_EMPTY') }}
            </p>
            <ul v-else class="divide-y divide-n-weak">
              <li v-for="calculo in calculos" :key="calculo.id" class="py-2">
                <p class="text-sm font-semibold text-n-slate-12">
                  {{ calculoTipoLabel(calculo.tipo) }}
                </p>
                <p class="text-xs text-n-slate-10">
                  <span v-if="calculo.segurado_nome">
                    {{ calculo.segurado_nome }} ·
                  </span>
                  <span class="tabular-nums">{{
                    fmtDateTime(calculo.created_at)
                  }}</span>
                </p>
              </li>
            </ul>
          </section>

          <section
            class="p-4 border shadow-sm rounded-xl bg-n-solid-1 border-n-weak"
            data-testid="dossie-reunioes"
          >
            <h2
              class="mb-2 text-xs font-bold tracking-widest uppercase text-n-slate-11"
            >
              {{ $t('RAMON.FICHA.REUNIOES_TITLE') }}
            </h2>
            <p v-if="!reunioes.length" class="text-sm text-n-slate-10">
              {{ $t('RAMON.FICHA.REUNIOES_EMPTY') }}
            </p>
            <ul v-else class="divide-y divide-n-weak">
              <li v-for="reuniao in reunioes" :key="reuniao.id" class="py-2">
                <p class="text-sm font-semibold text-n-slate-12">
                  {{ reuniao.titulo }}
                </p>
                <p class="text-xs text-n-slate-10">
                  {{ reuniaoStatusLabel(reuniao.status) }} ·
                  <span class="tabular-nums">{{
                    fmtDateTime(reuniao.created_at)
                  }}</span>
                </p>
              </li>
            </ul>
            <router-link
              :to="{
                name: 'ramon_reunioes',
                query: { leadId: pessoa.lead_id },
              }"
              data-testid="ficha-record-meeting"
              class="inline-flex items-center gap-1 mt-3 text-xs font-semibold text-n-iris-11 hover:underline"
            >
              <span class="i-lucide-mic size-3.5" />{{
                $t('RAMON.FICHA.RECORD_MEETING')
              }}
            </router-link>
          </section>

          <section
            class="p-4 border shadow-sm rounded-xl bg-n-solid-1 border-n-weak"
            data-testid="dossie-tese"
          >
            <h2
              class="mb-2 text-xs font-bold tracking-widest uppercase text-n-slate-11"
            >
              {{ $t('RAMON.DOSSIE.THESIS') }}
            </h2>
            <p v-if="!tese" class="text-sm text-n-slate-10">
              {{ $t('RAMON.DOSSIE.THESIS_EMPTY') }}
            </p>
            <template v-else>
              <p class="text-sm text-n-slate-12">{{ tese.name }}</p>
              <p
                v-if="tese.honorario_text"
                class="mt-1 text-sm text-n-slate-11"
                data-testid="dossie-honorario"
              >
                {{ $t('RAMON.DOSSIE.FEE') }}: {{ tese.honorario_text }}
              </p>
              <template v-if="tese.objecoes?.length">
                <p class="mt-3 mb-1 text-xs uppercase text-n-slate-10">
                  {{ $t('RAMON.DOSSIE.OBJECTIONS') }}
                </p>
                <div
                  v-for="(obj, i) in tese.objecoes"
                  :key="i"
                  class="mb-2"
                  data-testid="dossie-objecao"
                >
                  <p class="text-sm font-medium text-n-slate-12">
                    {{ obj.title }}
                  </p>
                  <p class="text-sm text-n-slate-11">{{ obj.content }}</p>
                </div>
              </template>
            </template>
          </section>
        </div>
      </div>
    </div>
  </div>
</template>

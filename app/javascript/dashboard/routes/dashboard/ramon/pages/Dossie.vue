<script setup>
import { ref, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import { formatBrl } from '../helpers/currency';
import { waMeUrl } from '../helpers/phone';
import { DEFAULT_STAGE_COLOR } from '../helpers/stage';
import {
  AVISO,
  CARTAO,
  CARTAO_STATUS,
  CHIP,
  FILETE,
  SECAO,
  TITULO,
  TOM,
} from '../helpers/ui';
import Button from 'dashboard/components-next/button/Button.vue';
import EsteiraEtapas from '../components/ficha/EsteiraEtapas.vue';
import ListaAtividades from '../components/conversation/ListaAtividades.vue';

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
// Lead de etapa órfã (fora da esteira configurada, ou sem esteira nenhuma):
// nenhum item marca `current` — sem isso o cabeçalho fica sem etapa visível.
const esteiraSemAtual = computed(() => esteira.value.every(s => !s.current));
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

// mesmas cores por status do DocChecklist (recebido=teal, solicitado=blue,
// pendente=amber), aqui só como selo de leitura.
const docTom = status =>
  ({ recebido: TOM.teal, solicitado: TOM.blue })[status] || TOM.amber;

const VIABILIDADE_TOM = { alta: TOM.teal, media: TOM.amber, baixa: TOM.ruby };
const viabilityTom = viability => VIABILIDADE_TOM[viability] || TOM.slate;

// a linha do tempo usa a mesma lista da Atividade do painel do lead: nota vira
// note_added (texto no to_value), etapas da esteira dão a cor do destino
const atividades = computed(() =>
  timeline.value.map(item =>
    item.type === 'note'
      ? {
          kind: 'note_added',
          to_value: item.body,
          author_name: item.author_name,
          created_at: item.created_at,
        }
      : item
  )
);

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
const REUNIAO_TOM = {
  transcrevendo: TOM.blue,
  pronta: TOM.teal,
  erro: TOM.ruby,
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
      class="flex flex-col max-w-5xl gap-5 mx-auto animate-pulse"
      data-testid="dossie-skeleton"
    >
      <div class="h-40 rounded-xl bg-n-alpha-2" />
      <div class="grid gap-5 lg:grid-cols-[1fr_340px]">
        <div class="h-64 rounded-xl bg-n-alpha-2" />
        <div class="h-64 rounded-xl bg-n-alpha-2" />
      </div>
    </div>
    <div v-else-if="error" class="text-sm" data-testid="dossie-error">
      <p class="text-n-ruby-11">{{ $t('RAMON.DOSSIE.ERROR') }}</p>
      <Button
        data-testid="dossie-retry"
        link
        xs
        class="mt-2"
        :label="$t('RAMON.LEAD_PANEL.RETRY')"
        @click="fetchData"
      />
    </div>

    <div v-else-if="data" class="flex flex-col max-w-5xl gap-5 mx-auto">
      <!-- Cabeçalho da ficha: quem é, quanto vale, a esteira -->
      <section :class="CARTAO" class="!p-5" data-testid="ficha-header">
        <div class="flex flex-wrap items-start gap-4">
          <span
            class="flex items-center justify-center text-xl font-semibold rounded-full size-14 shrink-0"
            :class="TOM.blue"
          >
            {{ initial }}
          </span>
          <div class="min-w-0">
            <p :class="TITULO">{{ $t('RAMON.FICHA.TITLE') }}</p>
            <h1
              class="mt-1 text-[28px] font-semibold leading-tight text-n-slate-12"
            >
              {{ pessoa.lead_name }}
            </h1>
            <div class="flex flex-wrap gap-1.5 mt-2">
              <span v-if="pessoa.thesis_name" :class="[CHIP, TOM.blue]">
                {{ pessoa.thesis_name }}
              </span>
              <span
                v-if="esteiraSemAtual && pessoa.stage_name"
                data-testid="ficha-stage-chip-fallback"
                class="ramon-stage-pill border"
                :class="CHIP"
                :style="{
                  '--stage': pessoa.stage_color || DEFAULT_STAGE_COLOR,
                }"
              >
                <span class="size-1.5 rounded-full bg-current" />
                {{ pessoa.stage_name }}
              </span>
              <span v-if="origem.channel_label" :class="[CHIP, TOM.slate]">
                {{ origem.channel_label }}
              </span>
              <a
                v-if="pessoa.phone_number"
                :href="waMeUrl(pessoa.phone_number)"
                target="_blank"
                rel="noopener noreferrer"
                class="font-mono hover:underline"
                :class="[CHIP, TOM.blue]"
              >
                <span class="i-lucide-phone size-3" />{{ pessoa.phone_number }}
              </a>
              <span v-if="pessoa.cidade" :class="[CHIP, TOM.slate]">
                {{ pessoa.cidade }}
              </span>
            </div>
          </div>
          <div class="flex flex-wrap items-center gap-4 ml-auto">
            <div
              v-if="pessoa.value"
              class="text-right"
              data-testid="ficha-valor"
            >
              <p
                class="font-mono text-xl font-medium tabular-nums text-n-blue-11"
              >
                {{ formatBrl(pessoa.value) }}
              </p>
              <p
                class="flex items-center justify-end gap-1.5 mt-0.5 text-[11px] text-n-slate-10"
              >
                <span v-if="pessoa.probability">
                  <span class="font-mono tabular-nums">{{
                    `${pessoa.probability}%`
                  }}</span>
                  {{ $t('RAMON.FICHA.PROBABILITY') }}
                </span>
                <span
                  v-if="pessoa.valor_estimado_origem === 'auto'"
                  :class="[CHIP, TOM.blue]"
                >
                  <span class="i-lucide-sparkles size-2.5" />
                  {{ $t('RAMON.FICHA.ESTIMATED') }}
                </span>
              </p>
            </div>
            <div class="flex items-center gap-2">
              <Button
                data-testid="dossie-copy"
                sm
                faded
                slate
                icon="i-lucide-clipboard-copy"
                :label="$t('RAMON.DOSSIE.COPY')"
                @click="copyDossie"
              />
              <router-link
                v-if="pessoa.conversation_id"
                v-slot="{ navigate }"
                custom
                :to="{
                  name: 'inbox_conversation',
                  params: { conversation_id: pessoa.conversation_id },
                }"
              >
                <Button
                  data-testid="ficha-open-conversation"
                  sm
                  icon="i-lucide-message-square"
                  :label="$t('RAMON.FICHA.OPEN_CONVERSATION')"
                  @click="navigate"
                />
              </router-link>
            </div>
          </div>
        </div>

        <div v-if="esteira.length" class="mt-5" :class="SECAO">
          <EsteiraEtapas :stages="esteira" />
        </div>
      </section>

      <div class="grid items-start gap-5 lg:grid-cols-[1fr_340px]">
        <!-- Coluna principal: o que fazer agora -->
        <div class="flex flex-col gap-5 min-w-0">
          <section
            :class="[CARTAO_STATUS, FILETE.blue]"
            class="!p-4"
            data-testid="dossie-pendencias"
          >
            <h2 class="mb-2" :class="TITULO">
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
                class="flex items-center gap-1 mt-0.5 font-mono text-xs tabular-nums text-n-slate-10"
              >
                <span class="i-lucide-clock size-3" />
                {{ fmtDateTime(nextTask.due_at) }}
              </p>
            </template>
            <p v-else class="text-sm text-n-slate-10">
              {{ $t('RAMON.FICHA.NEXT_EMPTY') }}
            </p>
            <ul
              v-if="docsMissing.length"
              class="flex flex-col gap-1.5 mt-3 list-none"
              :class="SECAO"
            >
              <li
                v-for="(doc, i) in docsMissing"
                :key="`doc-${i}`"
                class="flex items-center gap-2 text-sm text-n-slate-12"
                data-testid="dossie-doc"
              >
                <span
                  class="i-lucide-file-warning size-3.5 shrink-0 text-n-amber-11"
                />
                <span class="truncate">{{ doc.title }}</span>
                <span class="shrink-0" :class="[CHIP, docTom(doc.status)]">
                  {{ docStatusLabel(doc.status) }}
                </span>
              </li>
            </ul>
          </section>

          <section
            v-if="docs.itens.length"
            :class="CARTAO"
            class="!p-4"
            data-testid="dossie-docs"
          >
            <h2 class="flex items-center mb-2" :class="TITULO">
              {{ $t('RAMON.FICHA.DOCS_TITLE') }}
              <span
                class="ml-auto font-mono text-xs font-normal tracking-normal normal-case tabular-nums"
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
                class="h-full rounded-full bg-n-blue-9"
                :style="{ width: `${docsPercent}%` }"
              />
            </div>
            <ul class="mt-2 list-none">
              <li
                v-for="item in docs.itens"
                :key="item.id"
                class="flex items-center gap-2 py-2 text-sm border-t border-n-weak first:border-t-0"
                data-testid="ficha-doc-item"
              >
                <span class="truncate text-n-slate-12">{{ item.title }}</span>
                <span
                  class="ml-auto shrink-0"
                  :class="[CHIP, docTom(item.status)]"
                >
                  {{ docStatusLabel(item.status) }}
                </span>
              </li>
            </ul>
          </section>

          <section :class="CARTAO" class="!p-4" data-testid="dossie-timeline">
            <h2
              class="flex items-center gap-1.5 text-sm font-semibold text-n-slate-12"
            >
              <span class="i-lucide-activity size-4 text-n-slate-10" />
              {{ $t('RAMON.DOSSIE.TIMELINE') }}
            </h2>
            <p v-if="!timeline.length" class="mt-3 text-xs text-n-slate-9">
              {{ $t('RAMON.DOSSIE.TIMELINE_EMPTY') }}
            </p>
            <ListaAtividades
              v-else
              :activities="atividades"
              :stages="esteira"
              absoluta
            />
          </section>
        </div>

        <!-- Coluna lateral: o dossiê de leitura -->
        <div class="flex flex-col gap-5 min-w-0">
          <section :class="CARTAO" class="!p-4">
            <div data-testid="dossie-pessoa">
              <h2 class="mb-2" :class="TITULO">
                {{ $t('RAMON.DOSSIE.WHO') }}
              </h2>
              <p class="text-sm text-n-slate-12">
                <span class="font-medium">{{
                  pessoa.contact_name || pessoa.lead_name
                }}</span>
                <span v-if="pessoa.idade" class="text-n-slate-11">
                  · {{ $t('RAMON.DOSSIE.AGE', { age: pessoa.idade }) }}</span
                >
                <span v-if="pessoa.cidade" class="text-n-slate-11">
                  · {{ pessoa.cidade }}</span
                >
              </p>
              <p
                class="flex items-center gap-1.5 mt-1.5 text-xs text-n-slate-10"
              >
                {{ $t('RAMON.DOSSIE.CONSENT') }}:
                <span
                  :class="[
                    CHIP,
                    pessoa.consent_marketing ? TOM.teal : TOM.amber,
                  ]"
                >
                  {{
                    pessoa.consent_marketing
                      ? $t('RAMON.DOSSIE.CONSENT_YES')
                      : $t('RAMON.DOSSIE.CONSENT_NO')
                  }}
                </span>
              </p>
            </div>

            <div class="mt-3" :class="SECAO" data-testid="dossie-origem">
              <h2 class="mb-2" :class="TITULO">
                {{ $t('RAMON.DOSSIE.ORIGIN') }}
              </h2>
              <p class="text-sm text-n-slate-12">
                <span v-if="origem.channel_label" class="font-medium">{{
                  origem.channel_label
                }}</span>
                <span v-if="origem.source" class="text-n-slate-11">
                  · {{ origem.source }}</span
                >
                <span v-if="!origem.channel_label && !origem.source">—</span>
              </p>
              <p
                v-if="origem.indicacao"
                class="mt-1.5"
                :class="[CHIP, TOM.teal]"
                data-testid="dossie-indicacao"
              >
                {{ $t('RAMON.DOSSIE.REFERRAL') }}
              </p>
              <p
                v-for="[key, value] in utmEntries"
                :key="key"
                class="mt-0.5 font-mono text-[11px] text-n-slate-10"
              >
                {{ key }}: {{ value }}
              </p>
            </div>

            <div class="mt-3" :class="SECAO" data-testid="dossie-triagem">
              <h2 class="mb-2" :class="TITULO">
                {{ $t('RAMON.DOSSIE.TRIAGE') }}
              </h2>
              <p v-if="!triagem" class="text-sm text-n-slate-10">
                {{ $t('RAMON.DOSSIE.TRIAGE_EMPTY') }}
              </p>
              <template v-else>
                <p class="flex items-center gap-1.5 text-xs text-n-slate-10">
                  {{ $t('RAMON.TRIAGE.VIABILITY.LABEL') }}:
                  <span :class="[CHIP, viabilityTom(triagem.viability)]">
                    {{ viabilityLabel(triagem.viability) }}
                  </span>
                </p>
                <p
                  v-if="triagem.result"
                  class="mt-2 text-sm whitespace-pre-wrap text-n-slate-11"
                >
                  {{ triagem.result }}
                </p>
              </template>
            </div>
          </section>

          <section :class="CARTAO" class="!p-4" data-testid="dossie-calculos">
            <h2 class="mb-2" :class="TITULO">
              {{ $t('RAMON.FICHA.CALCULOS_TITLE') }}
            </h2>
            <p v-if="!calculos.length" class="text-sm text-n-slate-10">
              {{ $t('RAMON.FICHA.CALCULOS_EMPTY') }}
            </p>
            <ul v-else class="list-none">
              <li
                v-for="calculo in calculos"
                :key="calculo.id"
                class="py-2 border-t border-n-weak first:border-t-0"
              >
                <p class="text-sm font-medium text-n-slate-12">
                  {{ calculoTipoLabel(calculo.tipo) }}
                </p>
                <p class="text-xs text-n-slate-10">
                  <span v-if="calculo.segurado_nome">
                    {{ calculo.segurado_nome }} ·
                  </span>
                  <span class="font-mono tabular-nums">{{
                    fmtDateTime(calculo.created_at)
                  }}</span>
                </p>
              </li>
            </ul>
          </section>

          <section :class="CARTAO" class="!p-4" data-testid="dossie-reunioes">
            <h2 class="mb-2" :class="TITULO">
              {{ $t('RAMON.FICHA.REUNIOES_TITLE') }}
            </h2>
            <p v-if="!reunioes.length" class="text-sm text-n-slate-10">
              {{ $t('RAMON.FICHA.REUNIOES_EMPTY') }}
            </p>
            <ul v-else class="list-none">
              <li
                v-for="reuniao in reunioes"
                :key="reuniao.id"
                class="py-2 border-t border-n-weak first:border-t-0"
              >
                <p class="text-sm font-medium text-n-slate-12">
                  {{ reuniao.titulo }}
                </p>
                <p class="flex items-center gap-1.5 mt-0.5 text-xs">
                  <span :class="[CHIP, REUNIAO_TOM[reuniao.status]]">
                    {{ reuniaoStatusLabel(reuniao.status) }}
                  </span>
                  <span class="font-mono tabular-nums text-n-slate-10">{{
                    fmtDateTime(reuniao.created_at)
                  }}</span>
                </p>
              </li>
            </ul>
            <router-link
              v-slot="{ navigate }"
              custom
              :to="{
                name: 'ramon_reunioes',
                query: { leadId: pessoa.lead_id },
              }"
            >
              <Button
                data-testid="ficha-record-meeting"
                link
                xs
                icon="i-lucide-mic"
                class="mt-3"
                :label="$t('RAMON.FICHA.RECORD_MEETING')"
                @click="navigate"
              />
            </router-link>
          </section>

          <section :class="CARTAO" class="!p-4" data-testid="dossie-tese">
            <h2 class="mb-2" :class="TITULO">
              {{ $t('RAMON.DOSSIE.THESIS') }}
            </h2>
            <p v-if="!tese" class="text-sm text-n-slate-10">
              {{ $t('RAMON.DOSSIE.THESIS_EMPTY') }}
            </p>
            <template v-else>
              <p class="text-sm font-medium text-n-slate-12">{{ tese.name }}</p>
              <p
                v-if="tese.honorario_text"
                class="mt-2"
                :class="[AVISO, TOM.blue]"
                data-testid="dossie-honorario"
              >
                {{ $t('RAMON.DOSSIE.FEE') }}: {{ tese.honorario_text }}
              </p>
              <div v-if="tese.objecoes?.length" class="mt-3" :class="SECAO">
                <p class="mb-2" :class="TITULO">
                  {{ $t('RAMON.DOSSIE.OBJECTIONS') }}
                </p>
                <div
                  v-for="(obj, i) in tese.objecoes"
                  :key="i"
                  class="mb-2.5 last:mb-0"
                  data-testid="dossie-objecao"
                >
                  <p class="text-sm font-medium text-n-slate-12">
                    {{ obj.title }}
                  </p>
                  <p class="text-sm text-n-slate-11">{{ obj.content }}</p>
                </div>
              </div>
            </template>
          </section>
        </div>
      </div>
    </div>
  </div>
</template>

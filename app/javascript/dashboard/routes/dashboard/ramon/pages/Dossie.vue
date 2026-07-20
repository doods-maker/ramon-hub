<script setup>
import { ref, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import LeadsAPI from 'dashboard/api/leads';
import { formatBrl } from '../helpers/currency';
import { DEFAULT_STAGE_COLOR } from '../helpers/stage';
import { waMeUrl } from '../helpers/phone';
import RamonPageHeader from '../components/RamonPageHeader.vue';

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

const utmEntries = computed(() => Object.entries(origem.value.utm || {}));

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
  <div class="flex-1 w-full h-full p-8 overflow-y-auto bg-n-background">
    <div
      v-if="loading"
      class="flex flex-col max-w-2xl gap-4 animate-pulse"
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

    <div v-else-if="data" class="max-w-2xl">
      <RamonPageHeader
        compact
        :eyebrow="$t('RAMON.DOSSIE.TITLE')"
        :title="pessoa.lead_name"
      >
        <template #actions>
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
        </template>
      </RamonPageHeader>

      <!-- 1. Quem é -->
      <section class="mb-6" data-testid="dossie-pessoa">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.DOSSIE.WHO') }}
        </h2>
        <div class="p-3 rounded-lg bg-n-alpha-1 border border-n-weak">
          <p class="text-sm text-n-slate-12">
            <span>{{ pessoa.contact_name || pessoa.lead_name }}</span>
            <span v-if="pessoa.idade">
              · {{ $t('RAMON.DOSSIE.AGE', { age: pessoa.idade }) }}</span
            >
            <span v-if="pessoa.cidade"> · {{ pessoa.cidade }}</span>
          </p>
          <p class="text-sm">
            <a
              v-if="pessoa.phone_number"
              :href="waMeUrl(pessoa.phone_number)"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 text-n-iris-11 hover:underline"
            >
              <span class="i-lucide-phone size-3.5" />{{ pessoa.phone_number }}
            </a>
          </p>
          <p class="mt-1 text-sm text-n-slate-11">
            <span
              class="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              <span
                class="rounded-full size-2 shrink-0"
                :style="{
                  backgroundColor: pessoa.stage_color || DEFAULT_STAGE_COLOR,
                }"
              />
              {{ pessoa.stage_name }}
            </span>
            <span v-if="pessoa.value"> · {{ formatBrl(pessoa.value) }}</span>
          </p>
          <p class="mt-1 text-xs text-n-slate-10">
            {{ $t('RAMON.DOSSIE.CONSENT') }}:
            <span
              :class="
                pessoa.consent_marketing ? 'text-n-teal-11' : 'text-n-amber-11'
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
      </section>

      <!-- 2. De onde veio -->
      <section class="mb-6" data-testid="dossie-origem">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.DOSSIE.ORIGIN') }}
        </h2>
        <div class="p-3 rounded-lg bg-n-alpha-1 border border-n-weak">
          <p class="text-sm text-n-slate-12">
            <span v-if="origem.channel_label">{{ origem.channel_label }}</span>
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
      </section>

      <!-- 3. O que a triagem detectou -->
      <section class="mb-6" data-testid="dossie-triagem">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.DOSSIE.TRIAGE') }}
        </h2>
        <div class="p-3 rounded-lg bg-n-alpha-1 border border-n-weak">
          <p v-if="!triagem" class="text-sm text-n-slate-9">
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

      <!-- 4. Tese e argumentos -->
      <section class="mb-6" data-testid="dossie-tese">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.DOSSIE.THESIS') }}
        </h2>
        <div class="p-3 rounded-lg bg-n-alpha-1 border border-n-weak">
          <p v-if="!tese" class="text-sm text-n-slate-9">
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
        </div>
      </section>

      <!-- 5. Linha do tempo recente -->
      <section class="mb-6" data-testid="dossie-timeline">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.DOSSIE.TIMELINE') }}
        </h2>
        <p v-if="!timeline.length" class="text-sm text-n-slate-9">
          {{ $t('RAMON.DOSSIE.TIMELINE_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-1.5">
          <li
            v-for="(item, i) in timeline"
            :key="i"
            class="flex items-baseline gap-3 text-sm"
          >
            <span class="text-xs tabular-nums text-n-slate-10 shrink-0">
              {{ fmtDateTime(item.created_at) }}
            </span>
            <span class="text-n-slate-11">
              <strong v-if="item.author_name" class="text-n-slate-12">{{
                item.author_name
              }}</strong>
              <span v-else>{{ $t('RAMON.LEAD_PANEL.HISTORY.SYSTEM') }}</span>
              · {{ timelineText(item) }}
            </span>
          </li>
        </ul>
      </section>

      <!-- 6. Pendências -->
      <section class="mb-6" data-testid="dossie-pendencias">
        <h2 class="mb-2 text-sm uppercase tracking-widest text-n-slate-9">
          {{ $t('RAMON.DOSSIE.PENDING') }}
        </h2>
        <p
          v-if="!tasks.length && !docsMissing.length"
          class="text-sm text-n-slate-9"
        >
          {{ $t('RAMON.DOSSIE.PENDING_EMPTY') }}
        </p>
        <ul class="flex flex-col gap-1.5">
          <li
            v-for="task in tasks"
            :key="`task-${task.id}`"
            class="flex items-baseline gap-2 text-sm text-n-slate-11"
            data-testid="dossie-task"
          >
            <span class="i-lucide-circle size-3 shrink-0 self-center" />
            {{ task.title }}
            <span class="text-xs text-n-slate-10">{{
              fmtDateTime(task.due_at)
            }}</span>
          </li>
          <li
            v-for="(doc, i) in docsMissing"
            :key="`doc-${i}`"
            class="flex items-baseline gap-2 text-sm text-n-amber-11"
            data-testid="dossie-doc"
          >
            <span class="i-lucide-file-warning size-3 shrink-0 self-center" />
            {{ doc.title }}
            <span class="text-xs text-n-slate-10">{{
              docStatusLabel(doc.status)
            }}</span>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>

<script setup>
// Extrato mensal da variável (playbook §13, item 6; regulamento v2 §6): o gestor
// vê todo mundo, lança a meta do mês e exporta em CSV; SDR/Closer veem só o seu.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import RamonExtratoAPI from 'dashboard/api/ramonExtrato';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import { CAMPO, CARTAO, CHIP, ROTULO, SECAO, TITULO, TOM } from '../helpers/ui';

defineOptions({ name: 'RamonExtrato' });

const { t } = useI18n();
const store = useStore();
const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);

const hoje = new Date();
const mes = ref(
  `${hoje.getFullYear()}-${String(hoje.getMonth() + 1).padStart(2, '0')}`
);
const loading = ref(true);
const error = ref(false);
const pessoas = ref([]);
// meta/rampa editáveis por pessoa (gestor), indexadas pelo user id
const edicao = ref({});

const brl = valor =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    valor || 0
  );
const dataBr = iso => new Date(iso).toLocaleDateString('pt-BR');

// Mês fechado (regulamento §6): a API devolve o extrato guardado com
// fechado_em — só leitura, meta não muda mais.
const fechadoEm = computed(() => pessoas.value[0]?.fechado_em);
const podeEditar = computed(() => isAdmin.value && !fechadoEm.value);
const ddmm = iso =>
  new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });

const carregar = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await RamonExtratoAPI.get(mes.value);
    pessoas.value = data.pessoas;
    edicao.value = Object.fromEntries(
      data.pessoas.map(p => [p.user.id, { meta: p.meta ?? '', rampa: p.rampa }])
    );
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

const salvarMeta = async pessoa => {
  const { meta, rampa } = edicao.value[pessoa.user.id];
  try {
    await RamonExtratoAPI.salvarMeta({
      mes: mes.value,
      user_id: pessoa.user.id,
      papel: pessoa.papel,
      meta: Number(meta) || 0,
      rampa,
    });
    useAlert(t('RAMON.EXTRATO.META_SALVA'));
    await carregar();
  } catch {
    useAlert(t('RAMON.EXTRATO.META_ERRO'));
  }
};

const exportarCsv = () => {
  const linhas = [['pessoa', 'papel', 'data', 'lead', 'evento', 'valor']];
  pessoas.value.forEach(p => {
    p.unidades.forEach(u => {
      linhas.push([
        p.user.name,
        p.papel,
        dataBr(u.data),
        u.lead_nome,
        t(`RAMON.EXTRATO.EVENTO.${u.evento}`),
        String(u.valor).replace('.', ','),
      ]);
    });
    linhas.push([
      p.user.name,
      p.papel,
      '',
      '',
      t('RAMON.EXTRATO.TOTAL'),
      String(p.total).replace('.', ','),
    ]);
  });
  const csv = linhas
    .map(l => l.map(c => `"${String(c ?? '').replace(/"/g, '""')}"`).join(';'))
    .join('\n');
  const link = document.createElement('a');
  link.href = URL.createObjectURL(
    new Blob([String.fromCharCode(0xfeff) + csv], {
      type: 'text/csv;charset=utf-8',
    })
  );
  link.download = `extrato-variavel-${mes.value}.csv`;
  link.click();
  URL.revokeObjectURL(link.href);
};

watch(mes, carregar);
onMounted(carregar);
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <RamonPageHeader
        class="!mb-0"
        :title="t('RAMON.EXTRATO.TITLE')"
        :subtitle="t('RAMON.EXTRATO.SUBTITLE')"
        compact
      />
      <div class="flex flex-wrap items-end gap-3">
        <label :class="ROTULO">
          {{ t('RAMON.EXTRATO.MES') }}
          <input
            v-model="mes"
            type="month"
            data-testid="extrato-mes"
            :class="CAMPO"
            class="w-44"
          />
        </label>
        <Button
          v-if="pessoas.length"
          data-testid="extrato-csv"
          sm
          faded
          slate
          icon="i-lucide-download"
          :label="t('RAMON.EXTRATO.EXPORTAR')"
          @click="exportarCsv"
        />
        <span
          v-if="fechadoEm"
          data-testid="extrato-fechado"
          class="mb-1.5"
          :class="[CHIP, TOM.slate]"
        >
          <span class="i-lucide-lock size-3" />
          {{ t('RAMON.EXTRATO.FECHADO', { data: ddmm(fechadoEm) }) }}
        </span>
      </div>

      <div v-if="loading" class="h-32 animate-pulse rounded-xl bg-n-alpha-2" />
      <div v-else-if="error" class="flex flex-col items-start gap-1 text-sm">
        <p class="m-0 text-n-ruby-11">{{ t('RAMON.EXTRATO.LOAD_ERROR') }}</p>
        <Button link xs :label="t('RAMON.EXTRATO.RETRY')" @click="carregar" />
      </div>
      <p
        v-else-if="!pessoas.length"
        data-testid="extrato-vazio"
        class="m-0 text-sm text-n-slate-10"
      >
        {{ t(isAdmin ? 'RAMON.EXTRATO.VAZIO_GESTOR' : 'RAMON.EXTRATO.VAZIO') }}
      </p>
      <div v-else class="grid gap-4 xl:grid-cols-2">
        <section
          v-for="p in pessoas"
          :key="`${p.user.id}-${p.papel}`"
          data-testid="extrato-pessoa"
          :class="CARTAO"
          class="flex flex-col gap-3"
        >
          <header class="flex flex-wrap items-center justify-between gap-2">
            <h3
              class="m-0 flex items-center gap-2 text-base font-semibold text-n-slate-12"
            >
              {{ p.user.name }}
              <span :class="[CHIP, TOM.slate]">
                {{ t(`RAMON.EXTRATO.PAPEL.${p.papel}`) }}
              </span>
            </h3>
            <span
              data-testid="extrato-total"
              class="font-mono text-lg font-medium tabular-nums text-n-slate-12"
            >
              {{ brl(p.total) }}
            </span>
          </header>

          <div class="flex flex-wrap items-end gap-3 text-sm">
            <template v-if="podeEditar">
              <label :class="ROTULO">
                {{ t('RAMON.EXTRATO.META') }}
                <input
                  v-model="edicao[p.user.id].meta"
                  type="number"
                  min="0"
                  data-testid="extrato-meta"
                  :class="CAMPO"
                  class="w-24 font-mono tabular-nums"
                />
              </label>
              <label
                class="flex h-8 items-center gap-1.5 text-xs text-n-slate-11"
              >
                <input v-model="edicao[p.user.id].rampa" type="checkbox" />
                {{ t('RAMON.EXTRATO.RAMPA') }}
              </label>
              <Button
                data-testid="extrato-salvar-meta"
                sm
                :label="t('RAMON.EXTRATO.SALVAR')"
                @click="salvarMeta(p)"
              />
            </template>
            <span v-else class="text-n-slate-11">
              {{ t('RAMON.EXTRATO.META') }}:
              <span class="font-mono tabular-nums text-n-slate-12">
                {{ p.meta ?? '—' }}
              </span>
              <template v-if="p.rampa">
                · {{ t('RAMON.EXTRATO.RAMPA') }}
              </template>
            </span>
          </div>

          <dl
            class="m-0 grid grid-cols-2 gap-x-4 gap-y-2 text-sm sm:grid-cols-4"
            :class="SECAO"
          >
            <div class="flex flex-col justify-between">
              <dt :class="TITULO">
                {{ t(`RAMON.EXTRATO.CONTAGEM.${p.papel}`) }}
              </dt>
              <dd class="m-0 mt-1 font-mono tabular-nums text-n-slate-12">
                {{ p.contagem }}
              </dd>
            </div>
            <div class="flex flex-col justify-between">
              <dt :class="TITULO">
                {{ t('RAMON.EXTRATO.UNIDADES') }}
              </dt>
              <dd class="m-0 mt-1 font-mono tabular-nums text-n-slate-12">
                {{ brl(p.subtotal) }}
              </dd>
            </div>
            <div class="flex flex-col justify-between">
              <dt :class="TITULO">
                {{ t('RAMON.EXTRATO.BONUS') }}
              </dt>
              <dd class="m-0 mt-1 text-n-slate-12">
                <span class="font-mono tabular-nums">{{ brl(p.bonus) }}</span>
                <span v-if="p.degraus" class="ms-1 text-xs text-n-slate-10">
                  {{ t('RAMON.EXTRATO.DEGRAUS', { count: p.degraus }) }}
                </span>
              </dd>
            </div>
            <div class="flex flex-col justify-between">
              <dt :class="TITULO">
                {{ t('RAMON.EXTRATO.OBS') }}
              </dt>
              <dd class="m-0 mt-1 text-xs text-n-slate-11">
                <template v-if="p.garantia_aplicada">
                  {{ t('RAMON.EXTRATO.GARANTIA') }}
                </template>
                <span
                  v-if="p.descontos < 0"
                  data-testid="extrato-descontos"
                  class="block text-n-ruby-11"
                >
                  {{ t('RAMON.EXTRATO.DESCONTOS') }}
                  <span class="whitespace-nowrap font-mono tabular-nums">
                    {{ brl(p.descontos) }}
                  </span>
                </span>
                <template v-if="!p.garantia_aplicada && !(p.descontos < 0)">
                  —
                </template>
              </dd>
            </div>
          </dl>

          <table v-if="p.unidades.length" class="w-full text-sm">
            <thead>
              <tr class="text-left">
                <th class="py-1.5 pe-3" :class="TITULO">
                  {{ t('RAMON.EXTRATO.COL.DATA') }}
                </th>
                <th class="py-1.5 pe-3" :class="TITULO">
                  {{ t('RAMON.EXTRATO.COL.LEAD') }}
                </th>
                <th class="py-1.5 pe-3" :class="TITULO">
                  {{ t('RAMON.EXTRATO.COL.EVENTO') }}
                </th>
                <th class="py-1.5 text-right" :class="TITULO">
                  {{ t('RAMON.EXTRATO.COL.VALOR') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="u in p.unidades"
                :key="`${u.evento}-${u.lead_id}`"
                data-testid="extrato-unidade"
                class="border-t border-n-weak"
              >
                <td class="py-1.5 pe-3 font-mono tabular-nums text-n-slate-11">
                  {{ dataBr(u.data) }}
                </td>
                <td class="max-w-48 truncate py-1.5 pe-3 text-n-slate-12">
                  {{ u.lead_nome }}
                </td>
                <td class="py-1.5 pe-3 text-n-slate-11">
                  {{ t(`RAMON.EXTRATO.EVENTO.${u.evento}`) }}
                </td>
                <td
                  class="whitespace-nowrap py-1.5 text-right font-mono tabular-nums"
                  :class="u.valor < 0 ? 'text-n-ruby-11' : 'text-n-slate-12'"
                >
                  {{ brl(u.valor) }}
                </td>
              </tr>
            </tbody>
          </table>
          <p v-else class="m-0 text-sm text-n-slate-10">
            {{ t('RAMON.EXTRATO.SEM_UNIDADES') }}
          </p>
        </section>
      </div>
    </div>
  </div>
</template>

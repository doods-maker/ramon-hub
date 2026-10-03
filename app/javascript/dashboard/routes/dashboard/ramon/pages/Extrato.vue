<script setup>
// Extrato mensal da variável (playbook §13, item 6; regulamento v2 §6): o gestor
// vê todo mundo, lança a meta do mês e exporta em CSV; SDR/Closer veem só o seu.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import RamonExtratoAPI from 'dashboard/api/ramonExtrato';
import RamonPageHeader from '../components/RamonPageHeader.vue';

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
  <div
    class="flex flex-col w-full h-full bg-n-background p-4 sm:p-8 overflow-y-auto"
  >
    <RamonPageHeader
      :title="t('RAMON.EXTRATO.TITLE')"
      :subtitle="t('RAMON.EXTRATO.SUBTITLE')"
      compact
    />
    <div class="flex flex-wrap items-end gap-3 mb-4">
      <label class="flex flex-col text-xs text-n-slate-10">
        {{ t('RAMON.EXTRATO.MES') }}
        <input
          v-model="mes"
          type="month"
          data-testid="extrato-mes"
          class="w-44 px-3 py-2 mt-1 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak outline-none focus:border-n-slate-8"
        />
      </label>
      <button
        v-if="pessoas.length"
        data-testid="extrato-csv"
        class="px-3 py-2 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12 hover:bg-n-alpha-3"
        @click="exportarCsv"
      >
        {{ t('RAMON.EXTRATO.EXPORTAR') }}
      </button>
    </div>

    <div v-if="loading" class="flex-1" />
    <div v-else-if="error" class="flex flex-col items-start gap-2">
      <p class="text-n-slate-11">{{ t('RAMON.EXTRATO.LOAD_ERROR') }}</p>
      <button class="text-n-iris-11 underline" @click="carregar">
        {{ t('RAMON.EXTRATO.RETRY') }}
      </button>
    </div>
    <p
      v-else-if="!pessoas.length"
      data-testid="extrato-vazio"
      class="text-n-slate-11"
    >
      {{ t(isAdmin ? 'RAMON.EXTRATO.VAZIO_GESTOR' : 'RAMON.EXTRATO.VAZIO') }}
    </p>
    <div v-else class="grid gap-4 xl:grid-cols-2">
      <section
        v-for="p in pessoas"
        :key="`${p.user.id}-${p.papel}`"
        data-testid="extrato-pessoa"
        class="flex flex-col gap-3 p-4 rounded-xl border border-n-weak bg-n-solid-1"
      >
        <header class="flex flex-wrap items-baseline justify-between gap-2">
          <h3 class="text-base font-semibold text-n-slate-12">
            {{ p.user.name }}
            <span class="ms-1 text-xs font-normal text-n-slate-10">
              {{ t(`RAMON.EXTRATO.PAPEL.${p.papel}`) }}
            </span>
          </h3>
          <span
            data-testid="extrato-total"
            class="text-lg font-semibold text-n-slate-12"
          >
            {{ brl(p.total) }}
          </span>
        </header>

        <div class="flex flex-wrap items-end gap-3 text-sm">
          <template v-if="isAdmin">
            <label class="flex flex-col text-xs text-n-slate-10">
              {{ t('RAMON.EXTRATO.META') }}
              <input
                v-model="edicao[p.user.id].meta"
                type="number"
                min="0"
                data-testid="extrato-meta"
                class="w-24 px-2 py-1.5 mt-1 text-sm rounded-lg bg-n-alpha-1 text-n-slate-12 border border-n-weak outline-none focus:border-n-slate-8"
              />
            </label>
            <label
              class="flex items-center gap-1.5 text-xs text-n-slate-11 pb-2"
            >
              <input v-model="edicao[p.user.id].rampa" type="checkbox" />
              {{ t('RAMON.EXTRATO.RAMPA') }}
            </label>
            <button
              data-testid="extrato-salvar-meta"
              class="px-3 py-1.5 text-xs rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10"
              @click="salvarMeta(p)"
            >
              {{ t('RAMON.EXTRATO.SALVAR') }}
            </button>
          </template>
          <span v-else class="text-n-slate-11">
            {{ t('RAMON.EXTRATO.META') }}: {{ p.meta ?? '—' }}
            <template v-if="p.rampa">· {{ t('RAMON.EXTRATO.RAMPA') }}</template>
          </span>
        </div>

        <dl class="grid grid-cols-2 gap-x-4 gap-y-1 text-sm sm:grid-cols-4">
          <div>
            <dt class="text-xs text-n-slate-10">
              {{ t(`RAMON.EXTRATO.CONTAGEM.${p.papel}`) }}
            </dt>
            <dd class="text-n-slate-12">{{ p.contagem }}</dd>
          </div>
          <div>
            <dt class="text-xs text-n-slate-10">
              {{ t('RAMON.EXTRATO.UNIDADES') }}
            </dt>
            <dd class="text-n-slate-12">{{ brl(p.subtotal) }}</dd>
          </div>
          <div>
            <dt class="text-xs text-n-slate-10">
              {{ t('RAMON.EXTRATO.BONUS') }}
            </dt>
            <dd class="text-n-slate-12">
              {{ brl(p.bonus) }}
              <span v-if="p.degraus" class="text-xs text-n-slate-10">
                {{ t('RAMON.EXTRATO.DEGRAUS', { count: p.degraus }) }}
              </span>
            </dd>
          </div>
          <div>
            <dt class="text-xs text-n-slate-10">
              {{ t('RAMON.EXTRATO.OBS') }}
            </dt>
            <dd class="text-xs text-n-slate-11">
              <template v-if="p.garantia_aplicada">
                {{ t('RAMON.EXTRATO.GARANTIA') }}
              </template>
              <template v-else>—</template>
            </dd>
          </div>
        </dl>

        <table v-if="p.unidades.length" class="w-full text-sm">
          <thead>
            <tr class="text-xs text-left text-n-slate-10">
              <th class="py-1 font-normal">
                {{ t('RAMON.EXTRATO.COL.DATA') }}
              </th>
              <th class="py-1 font-normal">
                {{ t('RAMON.EXTRATO.COL.LEAD') }}
              </th>
              <th class="py-1 font-normal">
                {{ t('RAMON.EXTRATO.COL.EVENTO') }}
              </th>
              <th class="py-1 font-normal text-right">
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
              <td class="py-1 text-n-slate-11">{{ dataBr(u.data) }}</td>
              <td class="py-1 text-n-slate-12 truncate max-w-48">
                {{ u.lead_nome }}
              </td>
              <td class="py-1 text-n-slate-11">
                {{ t(`RAMON.EXTRATO.EVENTO.${u.evento}`) }}
              </td>
              <td class="py-1 text-right text-n-slate-12">
                {{ brl(u.valor) }}
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else class="text-sm text-n-slate-10">
          {{ t('RAMON.EXTRATO.SEM_UNIDADES') }}
        </p>
      </section>
    </div>
  </div>
</template>

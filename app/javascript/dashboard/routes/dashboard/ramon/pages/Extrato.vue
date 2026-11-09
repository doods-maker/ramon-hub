<script setup>
// Extrato mensal da variável (playbook §13, item 6): o gestor vê todo mundo,
// lança papel/meta/fator do mês e o Programa de Metas do híbrido, e exporta em
// CSV; SDR/Closer veem só o seu. Duas grades (09/11/2026): sdr/closer = modelo
// A (valor até a meta e acima, × fator), hibrido = modelo B (comissão da tese +
// Programa). DSR em linha própria; bônus do Programa sem DSR por cima.
import { computed, onMounted, reactive, ref, watch } from 'vue';
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
// papel/meta/fator editáveis por pessoa (gestor), indexados pelo user id
const edicao = ref({});
const PAPEIS = ['sdr', 'closer', 'hibrido'];
// mês fechado antes de 09/11/2026 guardou o bônus como número (grade antiga)
const bonusDe = p => (Array.isArray(p.bonus) ? p.bonus : []);

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
      data.pessoas.map(p => [
        p.user.id,
        // fator vazio = vale o calculado; preenchido só se o gestor já corrigiu
        {
          papel: p.papel,
          meta: p.meta ?? '',
          fator: p.fator_base?.manual ? p.fator : '',
        },
      ])
    );
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

const salvarMeta = async pessoa => {
  const { papel, meta, fator } = edicao.value[pessoa.user.id];
  try {
    await RamonExtratoAPI.salvarMeta({
      mes: mes.value,
      user_id: pessoa.user.id,
      papel,
      meta: Number(meta) || 0,
      fator: fator === '' || fator === null ? null : Number(fator),
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
    const resumo = [
      [t('RAMON.EXTRATO.DSR'), p.dsr],
      ...bonusDe(p).map(b => [
        t(`RAMON.EXTRATO.BONUS_TIPO.${b.tipo}`),
        b.valor,
      ]),
      [t('RAMON.EXTRATO.TOTAL'), p.total],
    ];
    resumo.forEach(([rotulo, valor]) => {
      linhas.push([
        p.user.name,
        p.papel,
        '',
        '',
        rotulo,
        String(valor ?? 0).replace('.', ','),
      ]);
    });
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

// Programa de Metas do híbrido (um por trimestre; kit contratacao, doc 09)
const programas = ref([]);
const VAZIO = {
  id: null,
  inicio: '',
  fim: '',
  faixa1Min: '',
  faixa1Valor: '',
  faixa2Min: '',
  faixa2Valor: '',
  gasAcima: '',
  gasValor: '',
  constMin: '',
  constMax: '',
  constValor: '',
};
const CAMPOS_PROGRAMA = [
  ['faixa1Min', 'FAIXA1_MIN', 'faixa1-min'],
  ['faixa1Valor', 'FAIXA1_VALOR', 'faixa1-valor'],
  ['faixa2Min', 'FAIXA2_MIN', 'faixa2-min'],
  ['faixa2Valor', 'FAIXA2_VALOR', 'faixa2-valor'],
  ['gasAcima', 'GAS_ACIMA', 'gas-acima'],
  ['gasValor', 'GAS_VALOR', 'gas-valor'],
  ['constMin', 'CONST_MIN', 'const-min'],
  ['constMax', 'CONST_MAX', 'const-max'],
  ['constValor', 'CONST_VALOR', 'const-valor'],
];
const programa = reactive({ ...VAZIO });
const num = v => (v === '' || v === null || v === undefined ? null : Number(v));

const carregarProgramas = async () => {
  if (!isAdmin.value) return;
  try {
    const { data } = await RamonExtratoAPI.programas();
    programas.value = data;
  } catch {
    programas.value = [];
  }
};

const editarPrograma = item => {
  const { faixas = [], gas, constancia } = item.regras;
  Object.assign(programa, {
    ...VAZIO,
    id: item.id,
    inicio: item.inicio,
    fim: item.fim,
    faixa1Min: faixas[0]?.min ?? '',
    faixa1Valor: faixas[0]?.valor ?? '',
    faixa2Min: faixas[1]?.min ?? '',
    faixa2Valor: faixas[1]?.valor ?? '',
    gasAcima: gas?.acima_de ?? '',
    gasValor: gas?.valor ?? '',
    constMin: constancia?.min_mes ?? '',
    constMax: constancia ? constancia.max_problemas * 100 : '',
    constValor: constancia?.valor ?? '',
  });
};

const regrasDoForm = () => {
  const faixas = [
    [programa.faixa1Min, programa.faixa1Valor],
    [programa.faixa2Min, programa.faixa2Valor],
  ]
    .filter(([min, valor]) => num(min) !== null && num(valor) !== null)
    .map(([min, valor]) => ({ min: num(min), valor: num(valor) }));
  const regras = { faixas };
  if (num(programa.gasAcima) !== null && num(programa.gasValor) !== null) {
    regras.gas = {
      acima_de: num(programa.gasAcima),
      valor: num(programa.gasValor),
    };
  }
  if (num(programa.constMin) !== null && num(programa.constValor) !== null) {
    regras.constancia = {
      min_mes: num(programa.constMin),
      max_problemas: (num(programa.constMax) || 0) / 100,
      valor: num(programa.constValor),
    };
  }
  return regras;
};

const salvarPrograma = async () => {
  try {
    await RamonExtratoAPI.salvarPrograma({
      ...(programa.id ? { id: programa.id } : {}),
      inicio: programa.inicio,
      fim: programa.fim,
      regras: regrasDoForm(),
    });
    useAlert(t('RAMON.EXTRATO.PROGRAMA.SALVO'));
    Object.assign(programa, VAZIO);
    await Promise.all([carregarProgramas(), carregar()]);
  } catch {
    useAlert(t('RAMON.EXTRATO.PROGRAMA.ERRO'));
  }
};

watch(mes, carregar);
onMounted(() => {
  carregar();
  carregarProgramas();
});
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
                {{ t('RAMON.EXTRATO.PAPEL_ROTULO') }}
                <select
                  v-model="edicao[p.user.id].papel"
                  data-testid="extrato-papel"
                  :class="CAMPO"
                  class="w-32"
                >
                  <option v-for="papel in PAPEIS" :key="papel" :value="papel">
                    {{ t(`RAMON.EXTRATO.PAPEL.${papel}`) }}
                  </option>
                </select>
              </label>
              <template v-if="edicao[p.user.id].papel !== 'hibrido'">
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
                <label :class="ROTULO" :title="t('RAMON.EXTRATO.FATOR_AJUDA')">
                  {{ t('RAMON.EXTRATO.FATOR') }}
                  <input
                    v-model="edicao[p.user.id].fator"
                    type="number"
                    min="0.1"
                    max="2"
                    step="0.1"
                    data-testid="extrato-fator"
                    :class="CAMPO"
                    class="w-28 font-mono tabular-nums"
                  />
                </label>
              </template>
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
              <template v-if="p.fator && p.fator !== 1">
                · {{ t('RAMON.EXTRATO.FATOR') }}
                <span class="font-mono tabular-nums">{{ p.fator }}</span>
              </template>
            </span>
          </div>

          <!-- A cenoura: quanto falta, a conta do fator, reuniões da IA, constância -->
          <ul class="m-0 flex flex-col gap-1 p-0 text-xs text-n-slate-11">
            <li v-if="p.faltam_meta > 0" data-testid="extrato-faltam">
              {{ t('RAMON.EXTRATO.FALTAM_META', { count: p.faltam_meta }) }}
            </li>
            <li v-else-if="p.faltam_meta === 0" data-testid="extrato-faltam">
              {{ t('RAMON.EXTRATO.META_BATIDA') }}
            </li>
            <li v-if="p.fator_base?.tipo" data-testid="extrato-fator-base">
              {{
                t(`RAMON.EXTRATO.FATOR_BASE.${p.fator_base.tipo}`, {
                  num: p.fator_base.numerador,
                  den: p.fator_base.denominador,
                  taxa: Math.round((p.fator_base.taxa || 0) * 100),
                  fator: p.fator_base.calculado ?? p.fator,
                })
              }}
            </li>
            <li
              v-else-if="p.fator_base?.primeiro"
              data-testid="extrato-fator-base"
            >
              {{ t('RAMON.EXTRATO.FATOR_BASE.primeiro') }}
            </li>
            <li v-if="p.fator_base?.manual" data-testid="extrato-fator-manual">
              {{
                t('RAMON.EXTRATO.FATOR_BASE.manual', {
                  fator: p.fator,
                  calculado: p.fator_base.calculado,
                })
              }}
            </li>
            <li v-if="p.reunioes_ia" data-testid="extrato-reunioes-ia">
              {{ t('RAMON.EXTRATO.REUNIOES_IA', { count: p.reunioes_ia }) }}
            </li>
            <li v-if="p.proxima_faixa" data-testid="extrato-proxima-faixa">
              {{
                t(
                  p.proxima_faixa.gas
                    ? 'RAMON.EXTRATO.PROXIMO_GAS'
                    : 'RAMON.EXTRATO.PROXIMA_FAIXA',
                  {
                    faltam: p.proxima_faixa.faltam,
                    valor: brl(p.proxima_faixa.valor),
                  }
                )
              }}
            </li>
            <li v-if="p.constancia" class="flex flex-wrap items-center gap-2">
              {{ t('RAMON.EXTRATO.CONSTANCIA', { min: p.constancia.min_mes }) }}
              <span
                v-for="m in p.constancia.meses"
                :key="m.mes"
                data-testid="extrato-constancia-mes"
                :class="[CHIP, m.ok ? TOM.teal : TOM.amber]"
              >
                {{ m.mes }} · {{ m.contagem }}
              </span>
              <span
                v-if="
                  p.constancia.taxa !== null && p.constancia.taxa !== undefined
                "
                data-testid="extrato-constancia-taxa"
                :class="[
                  CHIP,
                  p.constancia.taxa <= p.constancia.max_problemas
                    ? TOM.teal
                    : TOM.amber,
                ]"
              >
                {{
                  t('RAMON.EXTRATO.CONSTANCIA_TAXA', {
                    taxa: Math.round(p.constancia.taxa * 100),
                    max: Math.round(p.constancia.max_problemas * 100),
                  })
                }}
              </span>
            </li>
          </ul>

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
                {{ t('RAMON.EXTRATO.VARIAVEL') }}
              </dt>
              <dd class="m-0 mt-1 font-mono tabular-nums text-n-slate-12">
                {{ brl(p.variavel ?? p.subtotal) }}
              </dd>
            </div>
            <div class="flex flex-col justify-between">
              <dt :class="TITULO">
                {{ t('RAMON.EXTRATO.DSR') }}
              </dt>
              <dd
                data-testid="extrato-dsr"
                class="m-0 mt-1 font-mono tabular-nums text-n-slate-12"
              >
                {{ brl(p.dsr) }}
              </dd>
            </div>
            <div class="flex flex-col justify-between">
              <dt :class="TITULO">
                {{ t('RAMON.EXTRATO.BONUS') }}
              </dt>
              <dd class="m-0 mt-1 text-xs text-n-slate-11">
                <span
                  v-for="b in bonusDe(p)"
                  :key="b.tipo"
                  data-testid="extrato-bonus"
                  class="block"
                >
                  {{ t(`RAMON.EXTRATO.BONUS_TIPO.${b.tipo}`) }}
                  <span class="whitespace-nowrap font-mono tabular-nums">
                    {{ brl(b.valor) }}
                  </span>
                </span>
                <span
                  v-if="p.sem_valor"
                  data-testid="extrato-sem-valor"
                  class="block text-n-amber-11"
                >
                  {{ t('RAMON.EXTRATO.SEM_VALOR', { count: p.sem_valor }) }}
                </span>
                <template v-if="!bonusDe(p).length && !p.sem_valor">
                  {{ t('RAMON.EXTRATO.NENHUM') }}
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

      <section
        v-if="isAdmin"
        data-testid="extrato-programa"
        :class="CARTAO"
        class="flex flex-col gap-4"
      >
        <h3 class="m-0 text-base font-semibold text-n-slate-12">
          {{ t('RAMON.EXTRATO.PROGRAMA.TITULO') }}
        </h3>
        <p class="m-0 text-xs text-n-slate-10">
          {{ t('RAMON.EXTRATO.PROGRAMA.AJUDA') }}
        </p>
        <ul v-if="programas.length" class="m-0 flex flex-col gap-1 p-0">
          <li
            v-for="item in programas"
            :key="item.id"
            class="flex items-center gap-2 text-sm text-n-slate-12"
          >
            <span class="font-mono tabular-nums">
              {{
                t('RAMON.EXTRATO.PROGRAMA.VIGENCIA', {
                  inicio: dataBr(`${item.inicio}T12:00:00`),
                  fim: dataBr(`${item.fim}T12:00:00`),
                })
              }}
            </span>
            <Button
              link
              xs
              :label="t('RAMON.EXTRATO.PROGRAMA.EDITAR')"
              @click="editarPrograma(item)"
            />
          </li>
        </ul>
        <div class="flex flex-wrap items-end gap-4 text-sm">
          <label :class="ROTULO">
            {{ t('RAMON.EXTRATO.PROGRAMA.INICIO') }}
            <input
              v-model="programa.inicio"
              type="date"
              data-testid="programa-inicio"
              :class="CAMPO"
            />
          </label>
          <label :class="ROTULO">
            {{ t('RAMON.EXTRATO.PROGRAMA.FIM') }}
            <input
              v-model="programa.fim"
              type="date"
              data-testid="programa-fim"
              :class="CAMPO"
            />
          </label>
        </div>
        <div class="grid gap-4 text-sm sm:grid-cols-3">
          <label
            v-for="[campo, rotulo, testid] in CAMPOS_PROGRAMA"
            :key="campo"
            :class="ROTULO"
          >
            {{ t(`RAMON.EXTRATO.PROGRAMA.${rotulo}`) }}
            <input
              v-model="programa[campo]"
              type="number"
              min="0"
              :data-testid="`programa-${testid}`"
              :class="CAMPO"
              class="font-mono tabular-nums"
            />
          </label>
        </div>
        <div>
          <Button
            data-testid="programa-salvar"
            sm
            :disabled="!programa.inicio || !programa.fim"
            :label="t('RAMON.EXTRATO.PROGRAMA.SALVAR')"
            @click="salvarPrograma"
          />
        </div>
      </section>
    </div>
  </div>
</template>

<script setup>
// Uso e custo da IA (Inteligência, só admin): quanto a IA gastou no período, em quê e com
// qual modelo; provedor/modelo por função (salvo pela API captain/preferences) e o teto do
// alerta de gasto. A assinatura do Claude (VPS) só existe no agente @claude — termos de uso.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonIaUsoAPI from 'dashboard/api/ramonIaUso';
import CaptainPreferencesAPI from 'dashboard/api/captain/preferences';
import {
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
  AVISO,
  CAMPO,
  CARTAO,
  CHIP,
  ROTULO,
  SELECT,
  TITULO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

defineOptions({ name: 'CaptainUsoCusto' });

const { t, te } = useI18n();

const PERIODOS = ['hoje', '7d', '30d', 'mes'];
const GRUPOS = [
  { chave: 'funcao', campo: 'por_funcao' },
  { chave: 'assistente', campo: 'por_assistente' },
  { chave: 'modelo', campo: 'por_modelo' },
];
// "Claude da VPS" não entra aqui: a assinatura só serve o agente @claude.
const PROVEDORES = ['deepseek', 'openai', 'anthropic'];
const NUM = 'font-mono tabular-nums whitespace-nowrap';
// <progress> nativo pintado só com Tailwind (mesmo da Visão geral).
const BARRA =
  'mt-2 block h-2 w-full appearance-none overflow-hidden rounded-full bg-n-slate-9/10 [&::-webkit-progress-bar]:bg-n-slate-9/10 [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9';
const BARRA_ESTOURO =
  '[&::-webkit-progress-value]:bg-n-ruby-9 [&::-moz-progress-bar]:bg-n-ruby-9';

const periodo = ref('7d');
const grupo = ref('funcao');
const dados = ref(null);
const loading = ref(false);
const error = ref(false);
const teto = ref('');
const salvando = ref('');
// provedor trocado na tela, antes de escolher o modelo (funcao → provedor)
const provedorNaTela = ref({});

const fetchData = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await RamonIaUsoAPI.get({ periodo: periodo.value });
    dados.value = data;
    periodo.value = data.periodo ?? periodo.value;
    teto.value = data.teto_diario_usd ?? '';
  } catch (e) {
    error.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(fetchData);

const trocarPeriodo = valor => {
  periodo.value = valor;
  fetchData();
};

const fmtUsd = valor => {
  if (valor === null || valor === undefined) return '—';
  const casas = valor > 0 && valor < 0.01 ? 4 : 2;
  const numero = valor.toLocaleString('pt-BR', {
    minimumFractionDigits: casas,
    maximumFractionDigits: casas,
  });
  return `US$ ${numero}`;
};
const fmtNum = valor => (valor ?? 0).toLocaleString('pt-BR');
const fmtCompacto = valor =>
  new Intl.NumberFormat('pt-BR', {
    notation: 'compact',
    maximumFractionDigits: 1,
  }).format(valor ?? 0);
const fmtDia = iso => {
  const [, mes, dia] = iso.split('-');
  return `${dia}/${mes}`;
};

const total = computed(() => dados.value.total);
const hojeUsd = computed(() => dados.value.hoje_usd ?? 0);
const tetoDia = computed(() => dados.value.teto_diario_usd);
const estourou = computed(() => tetoDia.value && hojeUsd.value > tetoDia.value);
const agente = computed(() => dados.value.agente);
const fluxos = computed(() => dados.value.fluxos);
const chaves = computed(() => dados.value.chaves ?? {});

// Gráfico: barras em SVG (atributos, sem style) na escala do maior dia.
const dias = computed(() => dados.value.por_dia ?? []);
const maiorDia = computed(() =>
  Math.max(0, ...dias.value.map(dia => dia.custo_usd))
);
const barras = computed(() =>
  dias.value.map((dia, indice) => {
    const altura = maiorDia.value
      ? Math.max(1.5, (dia.custo_usd / maiorDia.value) * 100)
      : 0;
    return {
      ...dia,
      x: indice + 0.15,
      y: 100 - altura,
      altura,
      dica: t('IA_USO.GRAFICO.DICA', {
        dia: fmtDia(dia.dia),
        custo: fmtUsd(dia.custo_usd),
        n: dia.chamadas,
      }),
    };
  })
);
// Rótulo de todo dia até 7; acima disso, só o 1º, o do meio e o último.
const rotulosDias = computed(() => {
  const lista = dias.value;
  if (lista.length <= 7) return lista.map(dia => fmtDia(dia.dia));
  const meio = Math.floor(lista.length / 2);
  return lista.map((dia, i) =>
    [0, meio, lista.length - 1].includes(i) ? fmtDia(dia.dia) : ''
  );
});

const rotuloFuncao = chave =>
  te(`IA_USO.FUNCOES.${chave}`) ? t(`IA_USO.FUNCOES.${chave}`) : chave;
const linhas = computed(() => {
  const campo = GRUPOS.find(item => item.chave === grupo.value).campo;
  return (dados.value[campo] ?? []).map(linha => ({
    ...linha,
    nome: {
      funcao: () => rotuloFuncao(linha.chave),
      assistente: () =>
        linha.nome || t('IA_USO.TABELA.SEM_NOME', { id: linha.chave }),
      modelo: () => linha.chave || '—',
    }[grupo.value](),
    tokens: linha.input_tokens + linha.output_tokens,
  }));
});

// Provedor e modelo por função.
const escolhas = computed(() => dados.value.escolhas ?? []);
const provedorDe = escolha =>
  provedorNaTela.value[escolha.funcao] ?? escolha.provider;
const modelosDe = escolha =>
  escolha.modelos.filter(modelo => modelo.provider === provedorDe(escolha));
const modeloSelecionado = escolha =>
  escolha.fonte === 'tela' && provedorDe(escolha) === escolha.provider
    ? escolha.salvo
    : '';
const rotuloProvedor = provedor =>
  te(`IA_USO.PROVEDORES.${provedor}`)
    ? t(`IA_USO.PROVEDORES.${provedor}`)
    : provedor || '—';
const opcaoProvedor = provedor =>
  chaves.value[provedor]
    ? rotuloProvedor(provedor)
    : `${rotuloProvedor(provedor)} (${t('IA_USO.ESCOLHA.SEM_CHAVE')})`;
const emUso = escolha =>
  t('IA_USO.ESCOLHA.EM_USO', {
    modelo: `${rotuloProvedor(escolha.provider)} · ${escolha.model}`,
  });

const trocarProvedor = (escolha, provedor) => {
  provedorNaTela.value = {
    ...provedorNaTela.value,
    [escolha.funcao]: provedor,
  };
};
const salvarModelo = async (escolha, modelo) => {
  salvando.value = escolha.funcao;
  try {
    await CaptainPreferencesAPI.updatePreferences({
      captain_models: { [escolha.feature]: modelo },
    });
    useAlert(t('IA_USO.ESCOLHA.SALVO'));
    provedorNaTela.value = {};
    await fetchData();
  } catch (e) {
    useAlert(t('IA_USO.ESCOLHA.ERRO_SALVAR'));
  } finally {
    salvando.value = '';
  }
};

const salvarTeto = async () => {
  try {
    await RamonIaUsoAPI.salvarTeto(teto.value === '' ? null : teto.value);
    useAlert(t('IA_USO.ALERTA.SALVO'));
    await fetchData();
  } catch (e) {
    useAlert(t('IA_USO.ALERTA.ERRO'));
  }
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <div class="flex flex-wrap items-end justify-between gap-3">
        <div class="min-w-0">
          <h1 class="text-xl font-medium text-n-slate-12">
            {{ t('IA_USO.TITULO') }}
          </h1>
          <p class="max-w-2xl mt-1 text-sm text-n-slate-10">
            {{ t('IA_USO.SUBTITULO') }}
          </p>
        </div>
        <nav class="flex border-b border-n-weak" data-testid="uso-periodos">
          <button
            v-for="valor in PERIODOS"
            :key="valor"
            type="button"
            :class="[ABA, periodo === valor ? ABA_ATIVA : ABA_INATIVA]"
            @click="trocarPeriodo(valor)"
          >
            {{ t(`IA_USO.PERIODO.${valor}`) }}
          </button>
        </nav>
      </div>

      <div
        v-if="error"
        data-testid="uso-erro"
        class="mt-4 text-sm"
        :class="CARTAO"
      >
        <p class="text-n-ruby-11">{{ t('IA_USO.ERRO') }}</p>
        <button
          type="button"
          class="mt-1 text-xs text-n-blue-11 hover:underline"
          @click="fetchData"
        >
          {{ t('IA_USO.TENTAR') }}
        </button>
      </div>
      <p v-else-if="!dados" class="mt-6 text-sm text-n-slate-10">
        {{ t('IA_USO.CARREGANDO') }}
      </p>

      <div
        v-else
        class="flex flex-col gap-3 mt-5"
        :class="{ 'opacity-60': loading }"
      >
        <!-- resumo do período -->
        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <section data-testid="uso-custo" :class="CARTAO">
            <h2 :class="TITULO">{{ t('IA_USO.RESUMO.CUSTO') }}</h2>
            <p class="mt-2 text-2xl font-semibold text-n-slate-12" :class="NUM">
              {{ fmtUsd(total.custo_usd ?? 0) }}
            </p>
            <p v-if="total.sem_preco" class="mt-1 text-xs text-n-amber-11">
              {{ t('IA_USO.RESUMO.SEM_PRECO', { n: total.sem_preco }) }}
            </p>
          </section>
          <section data-testid="uso-hoje" :class="CARTAO">
            <h2 :class="TITULO">{{ t('IA_USO.RESUMO.HOJE') }}</h2>
            <p
              class="mt-2 text-2xl font-semibold"
              :class="[NUM, estourou ? 'text-n-ruby-11' : 'text-n-slate-12']"
            >
              {{ fmtUsd(hojeUsd) }}
            </p>
            <progress
              v-if="tetoDia"
              :class="[BARRA, estourou ? BARRA_ESTOURO : '']"
              :value="Math.min(hojeUsd, tetoDia)"
              :max="tetoDia"
            />
            <p class="mt-1 text-xs text-n-slate-10">
              {{
                tetoDia
                  ? t('IA_USO.RESUMO.TETO', { valor: fmtUsd(tetoDia) })
                  : t('IA_USO.RESUMO.SEM_TETO')
              }}
            </p>
          </section>
          <section data-testid="uso-chamadas" :class="CARTAO">
            <h2 :class="TITULO">{{ t('IA_USO.RESUMO.CHAMADAS') }}</h2>
            <p class="mt-2 text-2xl font-semibold text-n-slate-12" :class="NUM">
              {{ fmtNum(total.chamadas) }}
            </p>
            <span
              class="mt-1"
              :class="[CHIP, total.erros ? TOM.ruby : TOM.slate]"
            >
              {{ t('IA_USO.RESUMO.ERROS', { n: total.erros }) }}
            </span>
          </section>
          <section data-testid="uso-tokens" :class="CARTAO">
            <h2 :class="TITULO">{{ t('IA_USO.RESUMO.TOKENS') }}</h2>
            <p class="mt-2 text-2xl font-semibold text-n-slate-12" :class="NUM">
              {{ fmtCompacto(total.input_tokens + total.output_tokens) }}
            </p>
            <p class="tabular-nums mt-1 text-xs text-n-slate-10">
              {{
                t('IA_USO.RESUMO.ENTRADA_SAIDA', {
                  entrada: fmtCompacto(total.input_tokens),
                  saida: fmtCompacto(total.output_tokens),
                })
              }}
            </p>
          </section>
        </div>

        <!-- custo por dia -->
        <section data-testid="uso-grafico" :class="CARTAO">
          <h2 :class="TITULO">{{ t('IA_USO.GRAFICO.TITULO') }}</h2>
          <svg
            class="block w-full h-32 mt-3"
            :viewBox="`0 0 ${Math.max(barras.length, 1)} 100`"
            preserveAspectRatio="none"
            role="img"
            :aria-label="t('IA_USO.GRAFICO.TITULO')"
          >
            <line
              x1="0"
              y1="100"
              :x2="Math.max(barras.length, 1)"
              y2="100"
              class="stroke-n-weak"
              vector-effect="non-scaling-stroke"
            />
            <rect
              v-for="barra in barras"
              :key="barra.dia"
              :x="barra.x"
              :y="barra.y"
              width="0.7"
              :height="barra.altura"
              rx="0.08"
              class="fill-n-blue-9 hover:fill-n-blue-10"
            >
              <title>{{ barra.dica }}</title>
            </rect>
          </svg>
          <div class="flex mt-1 text-[10.5px] text-n-slate-10" :class="NUM">
            <span
              v-for="(rotulo, i) in rotulosDias"
              :key="i"
              class="flex-1 text-center whitespace-nowrap"
            >
              {{ rotulo }}
            </span>
          </div>
        </section>

        <div class="grid gap-3 lg:grid-cols-2">
          <!-- agente @claude -->
          <section data-testid="uso-agente" :class="CARTAO">
            <h2 :class="TITULO">{{ t('IA_USO.AGENTE.TITULO') }}</h2>
            <p class="tabular-nums mt-2 text-sm text-n-slate-12">
              {{
                t('IA_USO.AGENTE.HOJE', { n: agente.hoje, teto: agente.teto })
              }}
            </p>
            <progress :class="BARRA" :value="agente.hoje" :max="agente.teto" />
            <p class="tabular-nums mt-2 text-sm text-n-slate-12">
              {{
                t('IA_USO.AGENTE.EQUIVALENTE', {
                  valor: fmtUsd(agente.custo_periodo_usd),
                })
              }}
            </p>
            <p class="mt-1 text-xs text-n-slate-10">
              {{ t('IA_USO.AGENTE.NOTA') }}
            </p>
          </section>
          <!-- fluxos com IA -->
          <section data-testid="uso-fluxos" :class="CARTAO">
            <h2 :class="TITULO">{{ t('IA_USO.FLUXOS.TITULO') }}</h2>
            <p class="tabular-nums mt-2 text-sm text-n-slate-12">
              {{
                t('IA_USO.FLUXOS.HOJE', { n: fluxos.hoje, teto: fluxos.teto })
              }}
            </p>
            <progress :class="BARRA" :value="fluxos.hoje" :max="fluxos.teto" />
            <p class="mt-2 text-xs text-n-slate-10">
              {{ t('IA_USO.FLUXOS.NOTA') }}
            </p>
          </section>
        </div>

        <!-- detalhe por função / assistente / modelo -->
        <section data-testid="uso-tabela" :class="CARTAO">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 :class="TITULO">{{ t('IA_USO.TABELA.TITULO') }}</h2>
            <nav class="flex border-b border-n-weak">
              <button
                v-for="item in GRUPOS"
                :key="item.chave"
                type="button"
                :class="[ABA, grupo === item.chave ? ABA_ATIVA : ABA_INATIVA]"
                @click="grupo = item.chave"
              >
                {{ t(`IA_USO.TABELA.${item.chave}`) }}
              </button>
            </nav>
          </div>
          <p v-if="!linhas.length" class="mt-3 text-sm text-n-slate-11">
            {{ t('IA_USO.TABELA.VAZIO') }}
          </p>
          <div v-else class="mt-2 overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="text-left text-xs text-n-slate-10">
                  <th class="py-1.5 pr-3 font-medium">
                    {{ t('IA_USO.TABELA.NOME') }}
                  </th>
                  <th class="py-1.5 px-3 font-medium text-right">
                    {{ t('IA_USO.TABELA.CHAMADAS') }}
                  </th>
                  <th class="py-1.5 px-3 font-medium text-right">
                    {{ t('IA_USO.TABELA.TOKENS') }}
                  </th>
                  <th class="py-1.5 px-3 font-medium text-right">
                    {{ t('IA_USO.TABELA.CUSTO') }}
                  </th>
                  <th class="py-1.5 pl-3 font-medium text-right">
                    {{ t('IA_USO.TABELA.ERROS') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="linha in linhas"
                  :key="String(linha.chave)"
                  class="border-t border-n-weak text-n-slate-12"
                >
                  <td class="py-1.5 pr-3">{{ linha.nome }}</td>
                  <td class="py-1.5 px-3 text-right" :class="NUM">
                    {{ fmtNum(linha.chamadas) }}
                  </td>
                  <td class="py-1.5 px-3 text-right" :class="NUM">
                    {{ fmtCompacto(linha.tokens) }}
                  </td>
                  <td class="py-1.5 px-3 text-right" :class="NUM">
                    {{ fmtUsd(linha.custo_usd) }}
                  </td>
                  <td
                    class="py-1.5 pl-3 text-right"
                    :class="[NUM, linha.erros ? 'text-n-ruby-11' : '']"
                  >
                    {{ fmtNum(linha.erros) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <!-- provedor e modelo por função -->
        <section data-testid="uso-escolhas" :class="CARTAO">
          <h2 :class="TITULO">{{ t('IA_USO.ESCOLHA.TITULO') }}</h2>
          <p class="mt-1 text-xs text-n-slate-10">
            {{ t('IA_USO.ESCOLHA.DESCRICAO') }}
          </p>
          <ul class="flex flex-col mt-2 list-none">
            <li
              v-for="escolha in escolhas"
              :key="escolha.funcao"
              :data-testid="`escolha-${escolha.funcao}`"
              class="grid gap-2 py-3 border-t border-n-weak first:border-t-0 md:grid-cols-[1fr_auto] md:items-center"
            >
              <div class="min-w-0">
                <p class="text-sm font-medium text-n-slate-12">
                  {{ t(`IA_USO.ESCOLHA.FUNCOES.${escolha.funcao}`) }}
                </p>
                <p class="text-xs text-n-slate-10">
                  {{ t(`IA_USO.ESCOLHA.DESCRICOES.${escolha.funcao}`) }}
                </p>
                <p class="tabular-nums mt-1 text-xs text-n-slate-11">
                  {{ emUso(escolha) }}
                </p>
              </div>
              <div
                v-if="escolha.funcao === 'agente'"
                class="flex flex-wrap items-center gap-1.5"
              >
                <span :class="[CHIP, TOM.iris]">
                  {{ rotuloProvedor('claude_vps') }}
                </span>
                <span :class="[CHIP, TOM.slate]">
                  {{ t('IA_USO.ESCOLHA.FIXO') }}
                </span>
              </div>
              <div v-else class="grid grid-cols-2 gap-2 md:w-[26rem]">
                <label :class="ROTULO">
                  {{ t('IA_USO.ESCOLHA.PROVEDOR') }}
                  <select
                    :class="SELECT"
                    :value="provedorDe(escolha)"
                    :disabled="salvando === escolha.funcao"
                    data-testid="select-provedor"
                    @change="trocarProvedor(escolha, $event.target.value)"
                  >
                    <option
                      v-for="provedor in PROVEDORES"
                      :key="provedor"
                      :value="provedor"
                      :disabled="!chaves[provedor]"
                    >
                      {{ opcaoProvedor(provedor) }}
                    </option>
                  </select>
                </label>
                <label :class="ROTULO">
                  {{ t('IA_USO.ESCOLHA.MODELO') }}
                  <select
                    :class="SELECT"
                    :value="modeloSelecionado(escolha)"
                    :disabled="salvando === escolha.funcao"
                    data-testid="select-modelo"
                    @change="salvarModelo(escolha, $event.target.value)"
                  >
                    <option value="">{{ t('IA_USO.ESCOLHA.PADRAO') }}</option>
                    <option
                      v-for="modelo in modelosDe(escolha)"
                      :key="modelo.id"
                      :value="modelo.id"
                    >
                      {{ modelo.display_name }}
                    </option>
                  </select>
                </label>
              </div>
            </li>
          </ul>
          <p
            class="mt-1"
            :class="[AVISO, TOM.amber]"
            data-testid="aviso-assinatura"
          >
            {{ t('IA_USO.ESCOLHA.ASSINATURA') }}
          </p>
        </section>

        <div class="grid gap-3 lg:grid-cols-2">
          <!-- chaves no servidor -->
          <section data-testid="uso-chaves" :class="CARTAO">
            <h2 :class="TITULO">{{ t('IA_USO.CHAVES.TITULO') }}</h2>
            <ul class="flex flex-col gap-1.5 mt-2 list-none">
              <li
                v-for="(ok, provedor) in chaves"
                :key="provedor"
                class="flex items-center justify-between gap-2 text-sm text-n-slate-12"
              >
                <span>{{ rotuloProvedor(provedor) }}</span>
                <span :class="[CHIP, ok ? TOM.teal : TOM.slate]">
                  {{ ok ? t('IA_USO.CHAVES.SIM') : t('IA_USO.CHAVES.NAO') }}
                </span>
              </li>
            </ul>
          </section>
          <!-- alerta de gasto -->
          <section data-testid="uso-alerta" :class="CARTAO">
            <h2 :class="TITULO">{{ t('IA_USO.ALERTA.TITULO') }}</h2>
            <p class="mt-1 text-xs text-n-slate-10">
              {{ t('IA_USO.ALERTA.DESCRICAO') }}
            </p>
            <div class="flex items-end gap-2 mt-3">
              <label class="flex-1" :class="ROTULO">
                {{ t('IA_USO.ALERTA.TETO') }}
                <input
                  v-model="teto"
                  type="number"
                  min="0"
                  step="0.01"
                  data-testid="input-teto"
                  :class="[CAMPO, NUM]"
                />
              </label>
              <Button
                size="sm"
                :label="t('IA_USO.ALERTA.SALVAR')"
                data-testid="salvar-teto"
                @click="salvarTeto"
              />
            </div>
          </section>
        </div>
      </div>
    </div>
  </section>
</template>

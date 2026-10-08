<script setup>
// Casos de teste da IA: conversas-modelo do assistente com o critério do que é
// resposta boa. "Rodar todos" depois de cada ajuste — em modo teste, nada é
// gravado — e o histórico mostra se a IA piorou (ruby) ou melhorou (verde).
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import IaCasosAPI from 'dashboard/api/captain/iaCasos';
import CaptainFerramentasAPI from 'dashboard/api/captain/ferramentas';
import { ferramentaInfo } from 'dashboard/routes/dashboard/ramon/helpers/ferramentas';
import {
  CARTAO,
  CARTAO_STATUS,
  FILETE,
  CHIP,
  TOM,
  CAMPO,
  SELECT,
  TITULO,
  SECAO,
  AVISO,
  FUNDO_JANELA,
  JANELA,
  TITULO_JANELA,
  RODAPE_JANELA,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import AbasTestar from './AbasTestar.vue';
import CasoForm from './CasoForm.vue';
import {
  filtrarCasos,
  gruposDe,
  resultadoPorCaso,
  ordenarPorAtencao,
  rodadaAtiva,
  fmtUsd,
  fmtDuracao,
  fmtQuando,
} from './casos';

defineOptions({ name: 'CaptainCasosTeste' });

const POLL_MS = 3000;

const { t } = useI18n();
const route = useRoute();
const assistantId = computed(() => Number(route.params.assistantId));

const casos = ref([]);
const estimativa = ref({ casos: 0, custo_usd: 0, segundos: 0 });
const rodadas = ref([]);
const noturno = ref(false);
const rodada = ref(null);
const ferramentas = ref([]);
const carregando = ref(false);
const erro = ref(false);
const aviso = ref('');
const busca = ref('');
const grupo = ref('');
const filtroAtivo = ref('');
const aberto = ref(null);
const editando = ref(null);
const salvando = ref(false);
const confirmando = ref(false);
const disparando = ref(false);
let timer = null;

const pararPolling = () => {
  clearTimeout(timer);
  timer = null;
};

const carregarCasos = async () => {
  const { data } = await IaCasosAPI.casos(assistantId.value);
  casos.value = data.payload;
  estimativa.value = data.estimativa;
};

const carregarRodadas = async () => {
  const { data } = await IaCasosAPI.rodadas(assistantId.value);
  rodadas.value = data.payload;
  noturno.value = !!data.noturno;
};

// I-X6: rodada da madrugada (vale para todos os assistentes da conta); erro volta a chave.
const alternarNoturno = async ligado => {
  noturno.value = ligado;
  try {
    await IaCasosAPI.noturno(assistantId.value, ligado);
    aviso.value = ligado
      ? t('INTEL.CADERNO.NOTURNO_LIGADO')
      : t('INTEL.CADERNO.NOTURNO_DESLIGADO');
  } catch (e) {
    noturno.value = !ligado;
  }
};

const abrirRodada = async id => {
  pararPolling();
  const { data } = await IaCasosAPI.rodada(assistantId.value, id);
  rodada.value = data;
  if (rodadaAtiva(data)) {
    timer = setTimeout(() => abrirRodada(id), POLL_MS);
  } else if (rodadaAtiva(rodadas.value.find(item => item.id === id))) {
    // acabou agora: atualiza o placar do histórico
    carregarRodadas();
  }
};

const carregar = async () => {
  pararPolling();
  carregando.value = true;
  erro.value = false;
  rodada.value = null;
  try {
    await Promise.all([carregarCasos(), carregarRodadas()]);
    if (rodadas.value.length) await abrirRodada(rodadas.value[0].id);
  } catch (e) {
    erro.value = true;
  } finally {
    carregando.value = false;
  }
};
watch(assistantId, carregar, { immediate: true });

// só para mostrar o nome das ferramentas; sem ele, fica o id
const carregarFerramentas = async () => {
  try {
    const { data } = await CaptainFerramentasAPI.get();
    ferramentas.value = data.payload;
  } catch (e) {
    ferramentas.value = [];
  }
};
carregarFerramentas();
onBeforeUnmount(pararPolling);

const grupos = computed(() => gruposDe(casos.value));
const resultados = computed(() => resultadoPorCaso(rodada.value));
const visiveis = computed(() =>
  ordenarPorAtencao(
    filtrarCasos(casos.value, {
      busca: busca.value,
      grupo: grupo.value,
      ativo: filtroAtivo.value,
    }),
    resultados.value
  )
);
const emAndamento = computed(() => rodadaAtiva(rodada.value));
const feitos = computed(() => rodada.value?.resultados?.length || 0);
const progresso = computed(() =>
  rodada.value?.total
    ? Math.round((feitos.value / rodada.value.total) * 100)
    : 0
);
const comparacao = computed(() => rodada.value?.comparacao);
const minutos = computed(() =>
  Math.max(1, Math.round(estimativa.value.segundos / 60))
);

const rodar = async () => {
  disparando.value = true;
  aviso.value = '';
  try {
    const { data } = await IaCasosAPI.rodar(assistantId.value);
    rodadas.value = [data, ...rodadas.value];
    confirmando.value = false;
    await abrirRodada(data.id);
  } catch (e) {
    aviso.value =
      e?.response?.data?.error || t('CAPTAIN_RAMON.CASOS.ERRO_RODAR');
    confirmando.value = false;
  } finally {
    disparando.value = false;
  }
};

const salvar = async payload => {
  salvando.value = true;
  try {
    if (editando.value?.id) {
      await IaCasosAPI.atualizar(assistantId.value, editando.value.id, payload);
    } else {
      await IaCasosAPI.criar(assistantId.value, payload);
    }
    editando.value = null;
    await carregarCasos();
  } catch (e) {
    aviso.value = t('CAPTAIN_RAMON.CASOS.ERRO_SALVAR');
  } finally {
    salvando.value = false;
  }
};

const remover = async () => {
  await IaCasosAPI.remover(assistantId.value, editando.value.id);
  editando.value = null;
  await carregarCasos();
};

const toggle = id => {
  aberto.value = aberto.value === id ? null : id;
};

// textos montados no script: o template não aceita string crua (eslint i18n)
const placar = item => `${item.passou}/${item.total}`;
const linhaRodada = item =>
  `${fmtQuando(item.created_at)} · ${item.duracao_ms ? fmtDuracao(item.duracao_ms) : '—'}`;
const fala = caso => caso.mensagens?.[caso.mensagens.length - 1]?.content || '';
const nomeFerramenta = nome => ferramentaInfo(nome, ferramentas.value).title;

const chipCaso = caso => {
  const resultado = resultados.value[caso.id];
  if (resultado?.delta === 'piorou')
    return { tom: TOM.ruby, label: t('CAPTAIN_RAMON.CASOS.PIOROU') };
  if (resultado?.delta === 'melhorou')
    return { tom: TOM.teal, label: t('CAPTAIN_RAMON.CASOS.MELHOROU') };
  if (resultado)
    return resultado.passou
      ? { tom: TOM.teal, label: t('CAPTAIN_RAMON.CASOS.PASSOU') }
      : { tom: TOM.ruby, label: t('CAPTAIN_RAMON.CASOS.FALHOU') };
  if (!caso.ativo)
    return { tom: TOM.slate, label: t('CAPTAIN_RAMON.CASOS.INATIVO') };
  if (emAndamento.value)
    return { tom: TOM.slate, label: t('CAPTAIN_RAMON.CASOS.AGUARDANDO') };
  return null;
};
// piorou/melhorou ganham o filete do kit (ruby/teal) à esquerda
const cartaoCaso = caso => {
  const delta = resultados.value[caso.id]?.delta;
  if (delta === 'piorou') return [CARTAO_STATUS, FILETE.ruby];
  if (delta === 'melhorou') return [CARTAO_STATUS, FILETE.teal];
  return CARTAO;
};
const tomStatus = status =>
  ({
    fila: TOM.slate,
    rodando: TOM.blue,
    concluida: TOM.teal,
    erro: TOM.ruby,
  })[status];
</script>

<template>
  <PageLayout
    show-assistant-switcher
    :show-pagination-footer="false"
    :header-title="t('CAPTAIN_RAMON.CASOS.TITLE')"
    class="h-full"
  >
    <template #search>
      <Button
        variant="faded"
        color="slate"
        size="sm"
        icon="i-lucide-plus"
        :label="t('CAPTAIN_RAMON.CASOS.NOVO')"
        data-testid="casos-novo"
        @click="editando = {}"
      />
      <Button
        size="sm"
        icon="i-lucide-play"
        :label="t('CAPTAIN_RAMON.CASOS.RODAR')"
        :disabled="emAndamento || !estimativa.casos"
        data-testid="casos-rodar"
        @click="confirmando = true"
      />
    </template>
    <template #subHeader>
      <AbasTestar ativa="casos" />
    </template>

    <template #body>
      <div
        v-if="erro"
        data-testid="casos-erro"
        class="text-sm"
        :class="[CARTAO]"
      >
        <p class="text-n-ruby-11">{{ t('CAPTAIN_RAMON.LOAD_ERROR') }}</p>
        <Button
          variant="link"
          size="sm"
          :label="t('CAPTAIN_RAMON.RETRY')"
          @click="carregar"
        />
      </div>

      <div v-else-if="!carregando" class="flex flex-col gap-4 pb-6">
        <p class="text-sm text-n-slate-10">
          {{ t('CAPTAIN_RAMON.CASOS.SUBTITLE') }}
        </p>

        <div
          data-testid="casos-noturno"
          class="flex items-start gap-3"
          :class="CARTAO"
        >
          <Switch
            data-testid="casos-noturno-chave"
            class="mt-0.5"
            :model-value="noturno"
            @update:model-value="alternarNoturno"
          />
          <div class="flex flex-col gap-1">
            <span class="text-sm text-n-slate-12">
              {{ t('INTEL.CADERNO.NOTURNO') }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{
                t('INTEL.CADERNO.NOTURNO_AJUDA', {
                  n: fmtUsd(estimativa.custo_usd),
                })
              }}
            </span>
          </div>
        </div>

        <p v-if="aviso" :class="[AVISO, TOM.amber]" data-testid="casos-aviso">
          {{ aviso }}
        </p>

        <!-- rodada selecionada: progresso ao vivo ou placar -->
        <section
          v-if="rodada"
          class="p-4"
          :class="[CARTAO]"
          data-testid="casos-rodada"
        >
          <div class="flex flex-wrap items-baseline gap-x-4 gap-y-1">
            <p :class="TITULO">
              {{
                emAndamento
                  ? t('CAPTAIN_RAMON.CASOS.RODANDO')
                  : t('CAPTAIN_RAMON.CASOS.RODADA')
              }}
            </p>
            <span :class="[CHIP, tomStatus(rodada.status)]">
              {{ t(`CAPTAIN_RAMON.CASOS.STATUS.${rodada.status}`) }}
            </span>
            <span class="text-xs text-n-slate-10 font-mono">
              {{ linhaRodada(rodada) }}
            </span>
          </div>
          <div class="flex flex-wrap items-end gap-x-8 gap-y-3 mt-3">
            <div>
              <p
                class="text-3xl font-semibold font-mono text-n-slate-12"
                data-testid="casos-placar"
              >
                {{ placar(rodada) }}
              </p>
              <p class="text-xs text-n-slate-10">
                {{ t('CAPTAIN_RAMON.CASOS.PASSARAM') }}
              </p>
            </div>
            <div v-if="comparacao" class="flex flex-wrap gap-2 pb-1">
              <span class="font-mono" :class="[CHIP, TOM.slate]">
                {{
                  t('CAPTAIN_RAMON.CASOS.ANTES', { placar: placar(comparacao) })
                }}
              </span>
              <span
                v-if="comparacao.pioraram.length"
                :class="[CHIP, TOM.ruby]"
                data-testid="casos-pioraram"
              >
                {{
                  t('CAPTAIN_RAMON.CASOS.PIORARAM', comparacao.pioraram.length)
                }}
              </span>
              <span
                v-if="comparacao.melhoraram.length"
                :class="[CHIP, TOM.teal]"
                data-testid="casos-melhoraram"
              >
                {{
                  t(
                    'CAPTAIN_RAMON.CASOS.MELHORARAM',
                    comparacao.melhoraram.length
                  )
                }}
              </span>
            </div>
          </div>
          <div v-if="emAndamento" class="mt-3" data-testid="casos-progresso">
            <div class="h-1.5 rounded-full bg-n-alpha-2 overflow-hidden">
              <div
                class="h-full rounded-full bg-n-blue-9 transition-all"
                :style="{ width: `${progresso}%` }"
              />
            </div>
            <p class="mt-1 text-xs text-n-slate-10 font-mono">
              {{
                t('CAPTAIN_RAMON.CASOS.FEITOS', { feitos, total: rodada.total })
              }}
            </p>
          </div>
          <p
            v-if="rodada.status === 'erro'"
            class="mt-3"
            :class="[AVISO, TOM.ruby]"
          >
            {{ rodada.erro }}
          </p>
        </section>
        <p v-else :class="[AVISO, TOM.slate]" data-testid="casos-sem-rodada">
          {{ t('CAPTAIN_RAMON.CASOS.SEM_RODADA') }}
        </p>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_15rem]">
          <!-- casos -->
          <section class="min-w-0">
            <div class="flex flex-wrap gap-2">
              <input
                v-model="busca"
                :placeholder="t('CAPTAIN_RAMON.CASOS.BUSCA')"
                class="!w-56"
                :class="[CAMPO]"
                data-testid="casos-busca"
              />
              <select v-model="grupo" class="!w-44" :class="[SELECT]">
                <option value="">
                  {{ t('CAPTAIN_RAMON.CASOS.TODOS_GRUPOS') }}
                </option>
                <option v-for="item in grupos" :key="item" :value="item">
                  {{ item }}
                </option>
              </select>
              <select
                v-model="filtroAtivo"
                class="!w-40"
                :class="[SELECT]"
                data-testid="casos-filtro-ativo"
              >
                <option value="">
                  {{ t('CAPTAIN_RAMON.CASOS.FILTRO_ATIVO.TODOS') }}
                </option>
                <option value="ativos">
                  {{ t('CAPTAIN_RAMON.CASOS.FILTRO_ATIVO.ATIVOS') }}
                </option>
                <option value="inativos">
                  {{ t('CAPTAIN_RAMON.CASOS.FILTRO_ATIVO.INATIVOS') }}
                </option>
              </select>
            </div>

            <p
              v-if="!casos.length"
              class="mt-3"
              :class="[AVISO, TOM.slate]"
              data-testid="casos-vazio"
            >
              {{ t('CAPTAIN_RAMON.CASOS.VAZIO') }}
            </p>

            <ul class="flex flex-col gap-2 mt-3 list-none ps-0">
              <li
                v-for="caso in visiveis"
                :key="caso.id"
                :class="cartaoCaso(caso)"
                data-testid="caso-linha"
              >
                <button
                  type="button"
                  class="flex items-start w-full gap-3 text-left"
                  @click="toggle(caso.id)"
                >
                  <span
                    v-if="chipCaso(caso)"
                    class="shrink-0 mt-0.5"
                    :class="[CHIP, chipCaso(caso).tom]"
                    data-testid="caso-chip"
                  >
                    {{ chipCaso(caso).label }}
                  </span>
                  <span class="min-w-0 flex-1">
                    <span
                      class="block text-sm font-medium text-n-slate-12 truncate"
                    >
                      {{ caso.titulo }}
                    </span>
                    <span
                      v-if="!caso.titulo.includes(fala(caso))"
                      class="block text-xs text-n-slate-10 truncate"
                    >
                      {{ fala(caso) }}
                    </span>
                  </span>
                  <span
                    v-if="caso.grupo"
                    class="shrink-0"
                    :class="[CHIP, TOM.slate]"
                  >
                    {{ caso.grupo }}
                  </span>
                </button>

                <div
                  v-if="aberto === caso.id"
                  class="mt-3 flex flex-col gap-3 text-sm"
                  :class="[SECAO]"
                  data-testid="caso-detalhe"
                >
                  <template v-if="resultados[caso.id]">
                    <div v-if="resultados[caso.id].motivos?.length">
                      <p :class="TITULO">
                        {{ t('CAPTAIN_RAMON.CASOS.DETALHE.MOTIVOS') }}
                      </p>
                      <ul class="mt-1 list-disc ps-5 text-n-ruby-11">
                        <li
                          v-for="motivo in resultados[caso.id].motivos"
                          :key="motivo"
                        >
                          {{ motivo }}
                        </li>
                      </ul>
                    </div>
                    <div>
                      <p :class="TITULO">
                        {{ t('CAPTAIN_RAMON.CASOS.DETALHE.RESPOSTA') }}
                      </p>
                      <p class="mt-1 whitespace-pre-wrap text-n-slate-12">
                        {{ resultados[caso.id].resposta }}
                      </p>
                    </div>
                    <div>
                      <p :class="TITULO">
                        {{ t('CAPTAIN_RAMON.CASOS.DETALHE.FERRAMENTAS') }}
                      </p>
                      <p
                        v-if="!resultados[caso.id].ferramentas?.length"
                        class="mt-1 text-n-slate-10"
                      >
                        {{ t('CAPTAIN_RAMON.CASOS.DETALHE.NENHUMA') }}
                      </p>
                      <ul
                        v-else
                        class="mt-1 flex flex-col gap-1 list-none ps-0"
                      >
                        <li
                          v-for="(tool, indice) in resultados[caso.id]
                            .ferramentas"
                          :key="indice"
                          class="text-xs"
                        >
                          <span class="font-medium text-n-slate-12">
                            {{ nomeFerramenta(tool.nome) }}
                          </span>
                          <span
                            class="block font-mono text-n-slate-10 break-words"
                          >
                            {{ tool.resultado }}
                          </span>
                        </li>
                      </ul>
                    </div>
                    <p class="text-xs text-n-slate-10 font-mono">
                      {{
                        t('CAPTAIN_RAMON.CASOS.DETALHE.RODAPE', {
                          handoff: resultados[caso.id].handoff
                            ? t('CAPTAIN_RAMON.CASOS.SIM')
                            : t('CAPTAIN_RAMON.CASOS.NAO'),
                          duracao: fmtDuracao(resultados[caso.id].duracao_ms),
                        })
                      }}
                    </p>
                  </template>
                  <p v-else class="text-n-slate-10">
                    {{ t('CAPTAIN_RAMON.CASOS.DETALHE.SEM_RESULTADO') }}
                  </p>
                  <div>
                    <Button
                      variant="faded"
                      color="slate"
                      size="xs"
                      icon="i-lucide-pencil"
                      :label="t('CAPTAIN_RAMON.CASOS.DETALHE.EDITAR')"
                      data-testid="caso-editar"
                      @click="editando = caso"
                    />
                  </div>
                </div>
              </li>
            </ul>
          </section>

          <!-- histórico de rodadas -->
          <aside v-if="rodadas.length" class="min-w-0">
            <p :class="TITULO">{{ t('CAPTAIN_RAMON.CASOS.HISTORICO') }}</p>
            <ul
              class="flex flex-col gap-1 mt-2 list-none ps-0"
              data-testid="casos-historico"
            >
              <li v-for="item in rodadas" :key="item.id">
                <button
                  type="button"
                  class="flex items-center justify-between w-full gap-2 px-2 py-1.5 text-left rounded-lg hover:bg-n-alpha-2"
                  :class="item.id === rodada?.id ? 'bg-n-alpha-2' : ''"
                  @click="abrirRodada(item.id)"
                >
                  <span class="text-xs text-n-slate-11 font-mono">
                    {{ fmtQuando(item.created_at) }}
                  </span>
                  <span
                    v-if="item.status === 'concluida'"
                    class="text-sm font-semibold font-mono text-n-slate-12"
                  >
                    {{ placar(item) }}
                  </span>
                  <span v-else :class="[CHIP, tomStatus(item.status)]">
                    {{ t(`CAPTAIN_RAMON.CASOS.STATUS.${item.status}`) }}
                  </span>
                </button>
              </li>
            </ul>
          </aside>
        </div>
      </div>
    </template>
  </PageLayout>

  <CasoForm
    v-if="editando"
    :caso="editando.id ? editando : null"
    :ferramentas="ferramentas"
    :salvando="salvando"
    @salvar="salvar"
    @remover="remover"
    @fechar="editando = null"
  />

  <div
    v-if="confirmando"
    :class="FUNDO_JANELA"
    @click.self="confirmando = false"
  >
    <div class="!w-96" :class="[JANELA]" data-testid="casos-confirmar">
      <h3 :class="TITULO_JANELA">
        {{ t('CAPTAIN_RAMON.CASOS.CONFIRMAR_TITULO', { n: estimativa.casos }) }}
      </h3>
      <p class="text-sm text-n-slate-11">
        <span class="font-mono text-n-slate-12">
          {{ fmtUsd(estimativa.custo_usd) }}
        </span>
        {{ t('CAPTAIN_RAMON.CASOS.CONFIRMAR_TEMPO', { min: minutos }) }}
      </p>
      <p class="mt-3" :class="[AVISO, TOM.blue]">
        {{ t('CAPTAIN_RAMON.CASOS.CONFIRMAR_SEGURO') }}
      </p>
      <div :class="RODAPE_JANELA">
        <Button
          variant="faded"
          color="slate"
          size="sm"
          :label="t('CAPTAIN_RAMON.CASOS.CANCELAR')"
          @click="confirmando = false"
        />
        <Button
          size="sm"
          :is-loading="disparando"
          :label="t('CAPTAIN_RAMON.CASOS.CONFIRMAR')"
          data-testid="casos-confirmar-rodar"
          @click="rodar"
        />
      </div>
    </div>
  </div>
</template>

<script setup>
// Conferência de fases: a etapa do ADVBOX (movida à mão, costuma atrasar) ao
// lado da fase que o Painel do Cliente calcula pelo andamento do tribunal. A
// equipe marca o que atualizar; só o administrador aplica no ADVBOX.
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RamonConferenciaFasesAPI from 'dashboard/api/ramonConferenciaFases';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import ConferenciaCard from '../components/conferencia/ConferenciaCard.vue';
import { AVISO, CAMPO, CHIP, ROTULO, SELECT, TOM } from '../helpers/ui';
import {
  GRUPOS,
  TOM_DO_GRUPO,
  contaNoResumo,
  diaMesHora,
} from '../helpers/conferenciaFases';

defineOptions({ name: 'RamonConferenciaFases' });

const { t } = useI18n();

const filtros = ref({ grupo: 'atrasada', responsavel: '', q: '' });
const pagina = ref(1);
const linhas = ref([]);
const total = ref(0);
const porPagina = ref(50);
const resumo = ref({ grupos: {}, responsaveis: [] });
const atualizadoEm = ref(null);
const podeAplicar = ref(false);
const loading = ref(true);
const error = ref(false);
const confirmando = ref(false);
const enviados = ref(null); // nº enfileirado no último "Aplicar"

const carregar = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await RamonConferenciaFasesAPI.get(
      Object.fromEntries(
        Object.entries({ ...filtros.value, page: pagina.value }).filter(
          ([, v]) => v !== ''
        )
      )
    );
    linhas.value = data.payload;
    total.value = data.total;
    porPagina.value = data.por_pagina;
    resumo.value = data.resumo;
    atualizadoEm.value = data.atualizado_em;
    podeAplicar.value = data.permissoes.aplicar;
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

const irPara = n => {
  pagina.value = n;
  carregar();
};

// Busca digitada: espera parar de digitar antes de pedir de novo.
let espera;
watch(
  filtros,
  () => {
    clearTimeout(espera);
    espera = setTimeout(() => irPara(1), 300);
  },
  { deep: true }
);

// Marcação otimista: troca a linha na hora, depois pela resposta do backend;
// o resumo (conferidos, errados, para aplicar) acompanha pela diferença.
const ajustarResumo = (antes, depois) => {
  const [a, d] = [contaNoResumo(antes), contaNoResumo(depois)];
  Object.keys(d).forEach(k => {
    resumo.value[k] += d[k] - a[k];
  });
};
const salvar = async (linha, body) => {
  const i = linhas.value.findIndex(l => l.id === linha.id);
  const trocar = nova => {
    ajustarResumo(linhas.value[i], nova);
    linhas.value[i] = nova;
  };
  trocar({ ...linha, ...body });
  try {
    const { data } = await RamonConferenciaFasesAPI.update(linha.id, body);
    trocar(data);
  } catch (e) {
    trocar(linha);
    useAlert(e?.response?.data?.error || t('RAMON.CONFERENCIA.ERRO_SALVAR'));
  }
};

const aplicar = async () => {
  confirmando.value = false;
  try {
    const { data } = await RamonConferenciaFasesAPI.aplicar();
    enviados.value = data.enfileirados;
  } catch (e) {
    useAlert(e?.response?.data?.error || t('RAMON.CONFERENCIA.ERRO_APLICAR'));
  }
};

const subtitulo = computed(() =>
  atualizadoEm.value
    ? `${t('RAMON.CONFERENCIA.SUBTITLE')} ${t('RAMON.CONFERENCIA.ATUALIZADO_EM', diaMesHora(atualizadoEm.value))}`
    : t('RAMON.CONFERENCIA.SUBTITLE')
);

const chips = computed(() => {
  const r = resumo.value;
  return [
    ...GRUPOS.map(g => ({
      chave: g,
      n: r.grupos[g] || 0,
      tom: TOM_DO_GRUPO[g],
    })),
    { chave: 'conferidos', n: r.conferidos, tom: 'blue' },
    { chave: 'errados', n: r.errados, tom: 'ruby' },
    { chave: 'para_aplicar', n: r.para_aplicar, tom: 'amber' },
  ];
});

// Montada = a carga noturna já trouxe algum processo (em qualquer grupo).
const montada = computed(() =>
  Object.values(resumo.value.grupos).some(n => n > 0)
);
const paginas = computed(() =>
  Math.max(1, Math.ceil(total.value / porPagina.value))
);

const segmento = ativo => [
  CHIP,
  ativo ? TOM.blue : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12',
];

onMounted(carregar);
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <RamonPageHeader
        class="!mb-0"
        :title="t('RAMON.CONFERENCIA.TITLE')"
        :subtitle="subtitulo"
        compact
      >
        <template v-if="podeAplicar" #actions>
          <Button
            sm
            icon="i-lucide-send"
            data-testid="conferencia-aplicar"
            :disabled="!resumo.para_aplicar"
            :label="t('RAMON.CONFERENCIA.APLICAR', { n: resumo.para_aplicar })"
            @click="confirmando = true"
          />
        </template>
      </RamonPageHeader>

      <p
        v-if="enviados !== null"
        data-testid="conferencia-enviados"
        :class="[AVISO, TOM.teal]"
        class="m-0"
      >
        {{ t('RAMON.CONFERENCIA.ENVIADOS', { n: enviados }) }}
      </p>

      <div class="flex flex-wrap gap-1.5" data-testid="conferencia-resumo">
        <span v-for="c in chips" :key="c.chave" :class="[CHIP, TOM[c.tom]]">
          {{ t(`RAMON.CONFERENCIA.RESUMO.${c.chave}`, { n: c.n }, c.n) }}
        </span>
      </div>

      <div class="flex flex-wrap items-end gap-3">
        <div
          class="flex flex-wrap items-center gap-0.5 rounded-lg border border-n-weak p-0.5"
        >
          <button
            v-for="g in [...GRUPOS, '']"
            :key="g"
            type="button"
            :data-testid="`conferencia-grupo-${g || 'todos'}`"
            :class="segmento(filtros.grupo === g)"
            @click="filtros.grupo = g"
          >
            {{
              g
                ? t(`RAMON.CONFERENCIA.GRUPO.${g}`)
                : t('RAMON.CONFERENCIA.TODOS')
            }}
          </button>
        </div>
        <label :class="ROTULO">
          {{ t('RAMON.CONFERENCIA.RESPONSAVEL') }}
          <select
            v-model="filtros.responsavel"
            data-testid="conferencia-responsavel"
            :class="SELECT"
            class="w-52"
          >
            <option value="">
              {{ t('RAMON.CONFERENCIA.TODOS_RESPONSAVEIS') }}
            </option>
            <option v-for="r in resumo.responsaveis" :key="r" :value="r">
              {{ r }}
            </option>
          </select>
        </label>
        <label :class="ROTULO" class="min-w-[12rem] flex-1">
          {{ t('RAMON.CONFERENCIA.BUSCA') }}
          <input
            v-model.trim="filtros.q"
            type="search"
            data-testid="conferencia-busca"
            :class="CAMPO"
            :placeholder="t('RAMON.CONFERENCIA.BUSCA_PLACEHOLDER')"
          />
        </label>
      </div>

      <div v-if="loading" class="h-64 animate-pulse rounded-xl bg-n-alpha-2" />
      <div v-else-if="error" class="flex flex-col items-start gap-1 text-sm">
        <p class="m-0 text-n-ruby-11">
          {{ t('RAMON.CONFERENCIA.LOAD_ERROR') }}
        </p>
        <Button
          link
          xs
          :label="t('RAMON.CONFERENCIA.RETRY')"
          @click="carregar"
        />
      </div>
      <p
        v-else-if="!linhas.length"
        data-testid="conferencia-vazio"
        class="m-0 text-sm text-n-slate-10"
      >
        {{
          montada
            ? t('RAMON.CONFERENCIA.NENHUM')
            : t('RAMON.CONFERENCIA.NAO_MONTADA')
        }}
      </p>
      <template v-else>
        <ConferenciaCard
          v-for="l in linhas"
          :key="l.id"
          :linha="l"
          @salvar="body => salvar(l, body)"
        />
        <footer class="flex items-center justify-between gap-3">
          <span
            data-testid="conferencia-paginacao"
            class="font-mono text-xs tabular-nums text-n-slate-10"
          >
            {{ t('RAMON.CONFERENCIA.PAGINACAO', { pagina, paginas }) }}
          </span>
          <div class="flex gap-2">
            <Button
              xs
              faded
              slate
              icon="i-lucide-chevron-left"
              data-testid="conferencia-anterior"
              :disabled="pagina === 1"
              :label="t('RAMON.CONFERENCIA.ANTERIOR')"
              @click="irPara(pagina - 1)"
            />
            <Button
              xs
              faded
              slate
              trailing-icon
              icon="i-lucide-chevron-right"
              data-testid="conferencia-proxima"
              :disabled="pagina >= paginas"
              :label="t('RAMON.CONFERENCIA.PROXIMA')"
              @click="irPara(pagina + 1)"
            />
          </div>
        </footer>
      </template>
    </div>

    <ConfirmModal
      v-if="confirmando"
      :title="t('RAMON.CONFERENCIA.CONFIRMAR_TITULO')"
      :message="t('RAMON.CONFERENCIA.CONFIRMAR', { n: resumo.para_aplicar })"
      :confirm-label="t('RAMON.CONFERENCIA.CONFIRMAR_BOTAO')"
      confirm-color="blue"
      @confirm="aplicar"
      @cancel="confirmando = false"
    />
  </div>
</template>

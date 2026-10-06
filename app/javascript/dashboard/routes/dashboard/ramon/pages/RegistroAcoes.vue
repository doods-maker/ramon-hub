<script setup>
// Registro de ações (só administrador): quem fez o quê, quando, e o que era
// antes — a trilha somente-inclusão (audits), guardada por 5 anos (LGPD).
// Filtros vão pro backend; a frase em pt-BR sai de helpers/registroAcoes.
import { onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import RamonRegistroAcoesAPI from 'dashboard/api/ramonRegistroAcoes';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import {
  CAMPO,
  CARTAO,
  CHIP,
  ROTULO,
  SELECT,
  TITULO,
  TOM,
} from '../helpers/ui';
import {
  TIPOS,
  TOM_DO_TIPO,
  fraseDoRegistro,
  linhaCsv,
  mudancasDoRegistro,
  paraCsv,
  quandoSp,
  quemFez,
  rotaDoAlvo,
} from '../helpers/registroAcoes';

defineOptions({ name: 'RamonRegistroAcoes' });

const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const filtros = ref({ desde: '', ate: '', user_id: '', tipo: '', q: '' });
const pagina = ref(1);
const registros = ref([]);
const pessoas = ref([]);
const total = ref(0);
const porPagina = ref(50);
const loading = ref(true);
const error = ref(false);
const exportando = ref(false);

// Só os filtros preenchidos vão na query.
const params = extra =>
  Object.fromEntries(
    Object.entries({ ...filtros.value, ...extra }).filter(([, v]) => v !== '')
  );

const carregar = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await RamonRegistroAcoesAPI.listar(
      params({ page: pagina.value })
    );
    registros.value = data.registros;
    pessoas.value = data.pessoas;
    total.value = data.total;
    porPagina.value = data.por_pagina;
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

// CSV do filtro atual inteiro (não só a página), com as mesmas frases da tela.
const exportarCsv = async () => {
  exportando.value = true;
  try {
    const { data } = await RamonRegistroAcoesAPI.listar(params({ todos: 1 }));
    const cabecalho = ['QUANDO', 'QUEM', 'TIPO', 'O_QUE', 'ALVO', 'MUDANCAS'];
    const csv = paraCsv([
      cabecalho.map(c => t(`RAMON.REGISTRO.CSV.${c}`)),
      ...data.registros.map(r => linhaCsv(r, t)),
    ]);
    const link = document.createElement('a');
    link.href = URL.createObjectURL(
      new Blob([csv], { type: 'text/csv;charset=utf-8' })
    );
    link.download = 'registro-de-acoes.csv';
    link.click();
    URL.revokeObjectURL(link.href);
  } catch {
    useAlert(t('RAMON.REGISTRO.CSV_ERRO'));
  } finally {
    exportando.value = false;
  }
};

const rota = alvo => {
  const destino = rotaDoAlvo(alvo);
  return destino && accountScopedRoute(destino.name, destino.params);
};

const intervalo = () => ({
  de: (pagina.value - 1) * porPagina.value + 1,
  ate: (pagina.value - 1) * porPagina.value + registros.value.length,
  total: total.value,
});

onMounted(carregar);
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <RamonPageHeader
        class="!mb-0"
        :title="t('RAMON.REGISTRO.TITLE')"
        :subtitle="t('RAMON.REGISTRO.SUBTITLE')"
        compact
      />

      <div class="flex flex-wrap items-end gap-3">
        <label :class="ROTULO">
          {{ t('RAMON.REGISTRO.DESDE') }}
          <input
            v-model="filtros.desde"
            type="date"
            data-testid="registro-desde"
            :class="CAMPO"
            class="w-40"
          />
        </label>
        <label :class="ROTULO">
          {{ t('RAMON.REGISTRO.ATE') }}
          <input
            v-model="filtros.ate"
            type="date"
            data-testid="registro-ate"
            :class="CAMPO"
            class="w-40"
          />
        </label>
        <label :class="ROTULO">
          {{ t('RAMON.REGISTRO.QUEM') }}
          <select
            v-model="filtros.user_id"
            data-testid="registro-pessoa"
            :class="SELECT"
            class="w-44"
          >
            <option value="">{{ t('RAMON.REGISTRO.TODOS') }}</option>
            <option v-for="p in pessoas" :key="p.id" :value="p.id">
              {{ p.nome }}
            </option>
          </select>
        </label>
        <label :class="ROTULO">
          {{ t('RAMON.REGISTRO.TIPO_FILTRO') }}
          <select
            v-model="filtros.tipo"
            data-testid="registro-tipo"
            :class="SELECT"
            class="w-36"
          >
            <option value="">{{ t('RAMON.REGISTRO.TODOS') }}</option>
            <option v-for="tipo in TIPOS" :key="tipo" :value="tipo">
              {{ t(`RAMON.REGISTRO.TIPO.${tipo}`) }}
            </option>
          </select>
        </label>
        <label :class="ROTULO" class="min-w-[12rem] flex-1">
          {{ t('RAMON.REGISTRO.BUSCA') }}
          <input
            v-model.trim="filtros.q"
            type="search"
            data-testid="registro-busca"
            :class="CAMPO"
            :placeholder="t('RAMON.REGISTRO.BUSCA_PLACEHOLDER')"
          />
        </label>
        <Button
          data-testid="registro-csv"
          sm
          faded
          slate
          icon="i-lucide-download"
          :is-loading="exportando"
          :disabled="!total"
          :label="t('RAMON.REGISTRO.EXPORTAR')"
          @click="exportarCsv"
        />
      </div>

      <div v-if="loading" class="h-64 animate-pulse rounded-xl bg-n-alpha-2" />
      <div v-else-if="error" class="flex flex-col items-start gap-1 text-sm">
        <p class="m-0 text-n-ruby-11">{{ t('RAMON.REGISTRO.LOAD_ERROR') }}</p>
        <Button link xs :label="t('RAMON.REGISTRO.RETRY')" @click="carregar" />
      </div>
      <p
        v-else-if="!registros.length"
        data-testid="registro-vazio"
        class="m-0 text-sm text-n-slate-10"
      >
        {{ t('RAMON.REGISTRO.VAZIO') }}
      </p>
      <section v-else :class="CARTAO" class="!p-0">
        <div
          class="hidden grid-cols-[9.5rem_10rem_minmax(0,1fr)_minmax(0,17rem)_2rem] gap-4 border-b border-n-weak px-4 py-2.5 md:grid"
          :class="TITULO"
        >
          <span>{{ t('RAMON.REGISTRO.COL.QUANDO') }}</span>
          <span>{{ t('RAMON.REGISTRO.COL.QUEM') }}</span>
          <span>{{ t('RAMON.REGISTRO.COL.O_QUE') }}</span>
          <span>{{ t('RAMON.REGISTRO.COL.ANTES_DEPOIS') }}</span>
        </div>
        <ul class="m-0 list-none divide-y divide-n-weak p-0">
          <li
            v-for="r in registros"
            :key="r.id"
            data-testid="registro-linha"
            class="grid grid-cols-1 gap-x-4 gap-y-1 px-4 py-3 text-sm md:grid-cols-[9.5rem_10rem_minmax(0,1fr)_minmax(0,17rem)_2rem] md:items-start"
          >
            <time
              :datetime="r.quando"
              class="font-mono text-xs tabular-nums text-n-slate-11 md:pt-0.5"
            >
              {{ quandoSp(r.quando) }}
            </time>
            <span
              class="truncate"
              :class="r.quem ? 'text-n-slate-12' : 'italic text-n-slate-10'"
            >
              {{ quemFez(r, t) }}
            </span>
            <div class="flex min-w-0 flex-col gap-1">
              <span class="text-n-slate-12" data-testid="registro-frase">
                <span
                  class="me-1.5 align-[1px]"
                  :class="[CHIP, TOM[TOM_DO_TIPO[r.tipo]]]"
                >
                  {{ t(`RAMON.REGISTRO.TIPO.${r.tipo}`) }}
                </span>
                {{ fraseDoRegistro(r, t) }}
              </span>
              <span
                v-if="r.alvo?.nome"
                class="truncate text-xs text-n-slate-10"
              >
                {{ r.alvo.nome }}
              </span>
            </div>
            <ul class="m-0 flex list-none flex-col gap-0.5 p-0 text-xs">
              <li
                v-for="m in mudancasDoRegistro(r, t)"
                :key="m.campo"
                data-testid="registro-mudanca"
                class="min-w-0 break-words"
              >
                <span class="me-1.5 text-n-slate-10">{{ m.rotulo }}</span>
                <span
                  class="text-n-slate-10 line-through decoration-n-slate-8"
                  :class="m.mono && 'font-mono tabular-nums'"
                >
                  {{ m.antes }}
                </span>
                <span
                  class="i-lucide-arrow-right mx-1 size-3 align-[-2px] text-n-slate-9"
                />
                <span
                  class="text-n-slate-12"
                  :class="m.mono && 'font-mono tabular-nums'"
                >
                  {{ m.depois }}
                </span>
              </li>
            </ul>
            <router-link
              v-if="rota(r.alvo)"
              :to="rota(r.alvo)"
              data-testid="registro-abrir"
              class="flex size-7 items-center justify-center rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
              :title="t('RAMON.REGISTRO.ABRIR')"
              :aria-label="t('RAMON.REGISTRO.ABRIR')"
            >
              <span class="i-lucide-arrow-up-right size-4" />
            </router-link>
          </li>
        </ul>
        <footer
          class="flex items-center justify-between gap-3 border-t border-n-weak px-4 py-2.5"
        >
          <span
            data-testid="registro-paginacao"
            class="font-mono text-xs tabular-nums text-n-slate-10"
          >
            {{ t('RAMON.REGISTRO.PAGINACAO', intervalo()) }}
          </span>
          <div class="flex gap-2">
            <Button
              xs
              faded
              slate
              icon="i-lucide-chevron-left"
              data-testid="registro-anterior"
              :disabled="pagina === 1"
              :label="t('RAMON.REGISTRO.ANTERIOR')"
              @click="irPara(pagina - 1)"
            />
            <Button
              xs
              faded
              slate
              trailing-icon
              icon="i-lucide-chevron-right"
              data-testid="registro-proxima"
              :disabled="pagina * porPagina >= total"
              :label="t('RAMON.REGISTRO.PROXIMA')"
              @click="irPara(pagina + 1)"
            />
          </div>
        </footer>
      </section>
    </div>
  </div>
</template>

<script setup>
// Metas do modelo na aba Custos e metas: liga/desliga ("Usar metas" — desligadas não
// entram no Metabase), sobe o mensal.json (avisa antes de desfazer edição à mão),
// apaga tudo e edita mês a mês. A fonte é o modelo.mjs; aqui é o ajuste fino.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RamonMarketingAPI from 'dashboard/api/ramonMarketing';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ConfirmModal from '../ConfirmModal.vue';
import { parseBrlInput } from '../../helpers/currency';
import { ARQUIVO, CAMPO, CARTAO, TITULO, TOM } from '../../helpers/ui';

const props = defineProps({
  metas: { type: Object, required: true },
});
const emit = defineEmits(['atualizar']);

const { t } = useI18n();

// Ordem das colunas = métricas do mensal.json (Ramon::MetasDoModelo::METRICAS).
const METRICAS = [
  'contratos',
  'reunioes_agendadas',
  'reunioes_realizadas',
  'gasto_anuncio',
  'custo_area',
  'cac',
];

const comoData = valor => new Date(`${String(valor).slice(0, 10)}T12:00:00`);
const mesBr = valor =>
  comoData(valor).toLocaleDateString('pt-BR', {
    month: 'short',
    year: 'numeric',
  });
// Mostra e lê no formato pt-BR: "1.215" é mil duzentos e quinze (o parseBrlInput
// trataria como 1,215 — só pontos em grupos de 3 = milhar).
const numeroBr = valor =>
  Number(valor).toLocaleString('pt-BR', { maximumFractionDigits: 2 });
const lerNumero = texto => {
  const limpo = String(texto).trim();
  if (/^\d{1,3}(\.\d{3})+$/.test(limpo))
    return Number(limpo.replace(/\./g, ''));
  return parseBrlInput(limpo);
};

// { '2026-10-01': { contratos: {id, valor, editada}, ... }, ... } na ordem dos meses.
const meses = computed(() => {
  const porMes = {};
  props.metas.linhas.forEach(m => {
    porMes[m.mes] = { ...porMes[m.mes], [m.metrica]: m };
  });
  return Object.entries(porMes).map(([mes, celulas]) => ({ mes, celulas }));
});
const editadas = computed(
  () => props.metas.linhas.filter(m => m.editada).length
);

const falhou = e =>
  useAlert(e?.response?.data?.error || t('RAMON.MARKETING.ERRO'));

const alternar = async ativas => {
  try {
    await RamonMarketingAPI.metasAtivas(ativas);
    emit('atualizar');
  } catch (e) {
    falhou(e);
  }
};

const salvar = async (meta, evento) => {
  const desfazer = () => {
    evento.target.value = numeroBr(meta.valor);
  };
  const valor = lerNumero(evento.target.value);
  if (valor === null || valor < 0) {
    desfazer();
    useAlert(t('RAMON.MARKETING.METAS.VALOR_INVALIDO'));
    return;
  }
  if (valor === Number(meta.valor)) return;
  try {
    await RamonMarketingAPI.editarMeta(meta.id, valor);
    useAlert(t('RAMON.MARKETING.METAS.SALVA'));
    emit('atualizar');
  } catch (e) {
    desfazer(); // não gravou: a célula volta ao valor salvo
    falhou(e);
  }
};

// Subir por cima de edição à mão: o backend responde 409 e a tela pergunta antes.
const pendente = ref(null);
const enviar = async (texto, confirmar = false) => {
  try {
    const { data } = await RamonMarketingAPI.importarMetas(texto, confirmar);
    useAlert(t('RAMON.MARKETING.METAS.OK', data));
    emit('atualizar');
  } catch (e) {
    if (e?.response?.status === 409) {
      pendente.value = { texto, editadas: e.response.data.editadas };
      return;
    }
    falhou(e);
  }
};
const subir = async evento => {
  const arquivo = evento.target.files?.[0];
  evento.target.value = '';
  if (arquivo) await enviar(await arquivo.text());
};
const sobrescrever = () => {
  const { texto } = pendente.value;
  pendente.value = null;
  enviar(texto, true);
};

const apagando = ref(false);
const apagar = async () => {
  apagando.value = false;
  try {
    await RamonMarketingAPI.apagarMetas();
    emit('atualizar');
  } catch (e) {
    falhou(e);
  }
};
</script>

<template>
  <section :class="CARTAO" class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h2 :class="TITULO">{{ t('RAMON.MARKETING.METAS.TITLE') }}</h2>
      <label
        v-if="metas.linhas.length"
        class="flex items-center gap-2 text-sm text-n-slate-12"
      >
        <!-- Controlado pela prop: com o listener, o Switch só emite o valor novo e
             não vira sozinho — se o PUT falhar, continua mostrando o estado real. -->
        <Switch :model-value="metas.ativas" @update:model-value="alternar" />
        {{ t('RAMON.MARKETING.METAS.USAR') }}
      </label>
    </div>
    <p class="text-sm text-n-slate-11">{{ t('RAMON.MARKETING.METAS.COMO') }}</p>
    <p
      v-if="metas.linhas.length && !metas.ativas"
      :class="TOM.amber"
      class="self-start rounded-lg px-3 py-2 text-xs"
    >
      {{ t('RAMON.MARKETING.METAS.DESLIGADAS') }}
    </p>
    <div class="flex flex-wrap items-center gap-3">
      <input
        type="file"
        accept=".json,application/json"
        :class="ARQUIVO"
        class="max-w-sm"
        :aria-label="t('RAMON.MARKETING.METAS.TITLE')"
        @change="subir"
      />
      <Button
        v-if="metas.linhas.length"
        xs
        ghost
        ruby
        icon="i-lucide-trash-2"
        :label="t('RAMON.MARKETING.METAS.APAGAR')"
        @click="apagando = true"
      />
    </div>

    <p v-if="!metas.linhas.length" class="text-sm text-n-slate-10">
      {{ t('RAMON.MARKETING.METAS.VAZIO') }}
    </p>
    <div v-else class="overflow-x-auto">
      <p v-if="editadas" class="mb-2 text-xs text-n-slate-11">
        {{ t('RAMON.MARKETING.METAS.EDITADAS', { n: editadas }) }}
      </p>
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left text-xs text-n-slate-10">
            <th class="py-1 pr-2 font-medium">
              {{ t('RAMON.MARKETING.METAS.MES') }}
            </th>
            <th
              v-for="metrica in METRICAS"
              :key="metrica"
              class="py-1 px-1 text-right font-medium"
            >
              {{ t(`RAMON.MARKETING.METRICAS.${metrica.toUpperCase()}`) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="linha in meses"
            :key="linha.mes"
            class="border-t border-n-weak text-n-slate-12"
          >
            <td class="py-1 pr-2 whitespace-nowrap">{{ mesBr(linha.mes) }}</td>
            <td v-for="metrica in METRICAS" :key="metrica" class="py-1 px-1">
              <input
                v-if="linha.celulas[metrica]"
                :value="numeroBr(linha.celulas[metrica].valor)"
                inputmode="decimal"
                :class="[
                  CAMPO,
                  // ! vence o fundo/contorno do CAMPO (mesma propriedade, ordem do CSS decide)
                  linha.celulas[metrica].editada
                    ? '!bg-n-amber-9/15 !outline-n-amber-9'
                    : '',
                ]"
                class="min-w-[5.5rem] text-right font-mono"
                :title="
                  linha.celulas[metrica].editada
                    ? t('RAMON.MARKETING.METAS.EDITADA')
                    : ''
                "
                :aria-label="`${mesBr(linha.mes)} ${t(`RAMON.MARKETING.METRICAS.${metrica.toUpperCase()}`)}`"
                @change="salvar(linha.celulas[metrica], $event)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <ConfirmModal
      v-if="pendente"
      :title="t('RAMON.MARKETING.METAS.SOBRESCREVER_TITULO')"
      :message="
        t('RAMON.MARKETING.METAS.SOBRESCREVER_MSG', { n: pendente.editadas })
      "
      :confirm-label="t('RAMON.MARKETING.METAS.SOBRESCREVER')"
      @confirm="sobrescrever"
      @cancel="pendente = null"
    />
    <ConfirmModal
      v-if="apagando"
      :title="t('RAMON.MARKETING.METAS.CONFIRMAR_APAGAR')"
      :confirm-label="t('RAMON.MARKETING.METAS.APAGAR')"
      @confirm="apagar"
      @cancel="apagando = false"
    />
  </section>
</template>

<script setup>
// Aba "Custos e metas" da área Marketing (spec 2026-11-07-marketing-trafego-design):
// o que o Metabase não faz — lançar custo, subir o CSV do Gerenciador e o mensal.json
// do modelo — e o estado da conexão com a Meta. Os números ficam na aba Tráfego.
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RamonMarketingAPI from 'dashboard/api/ramonMarketing';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import ConfirmModal from '../components/ConfirmModal.vue';
import MetasModelo from '../components/marketing/MetasModelo.vue';
import { formatBrl, parseBrlInput } from '../helpers/currency';
import {
  ARQUIVO,
  AVISO,
  CAMPO,
  CARTAO,
  CHIP,
  ROTULO,
  SELECT,
  TITULO,
  TOM,
} from '../helpers/ui';

defineOptions({ name: 'RamonMarketingCustos' });

const { t } = useI18n();
const carregando = ref(true);
const erro = ref(false);
const dados = ref(null);
const salvando = ref(false);
const novo = reactive({
  data: new Date().toISOString().slice(0, 10),
  valor: '',
  categoria: '',
  thesis_id: '',
  observacao: '',
});

const carregar = async () => {
  erro.value = false;
  try {
    dados.value = (await RamonMarketingAPI.get()).data;
  } catch {
    erro.value = true;
  } finally {
    carregando.value = false;
  }
};

// Data pura (AAAA-MM-DD) ao meio-dia: sem escorregar um dia pelo fuso.
const comoData = valor => new Date(`${String(valor).slice(0, 10)}T12:00:00`);
const dataBr = valor =>
  valor ? comoData(valor).toLocaleDateString('pt-BR') : '';

// Linhas do quadro de estado: chave ligada/desligada ou configurada/faltando.
const conexao = computed(() => {
  const s = dados.value?.status || {};
  return [
    ['GASTO', s.gasto, 'LIGADO'],
    ['CONTA_ANUNCIOS', s.conta_anuncios, 'CONFIGURADO'],
    ['PAINEL_TRAFEGO', s.painel_trafego, 'CONFIGURADO'],
    ['INSIGHTS_IG', s.insights_ig, 'LIGADO'],
    ['CAPI', s.capi, 'LIGADO'],
  ].map(([chave, ok, tipo]) => ({
    chave,
    ok,
    rotulo: t(`RAMON.MARKETING.STATUS.${ok ? tipo : `NAO_${tipo}`}`),
  }));
});

const ultimoGasto = computed(() => {
  const u = dados.value?.status?.ultimo_gasto;
  if (!u) return t('RAMON.MARKETING.STATUS.SEM_GASTO');
  return t('RAMON.MARKETING.STATUS.ULTIMO_GASTO', {
    data: dataBr(u.data),
    origem: u.origem === 'csv' ? 'CSV' : 'API',
  });
});

const categoria = c => t(`RAMON.MARKETING.CATEGORIAS.${c.toUpperCase()}`);

const lancar = async () => {
  const valor = parseBrlInput(novo.valor);
  if (!valor || !novo.categoria || !novo.data) {
    useAlert(t('RAMON.MARKETING.CUSTO.INCOMPLETO'));
    return;
  }
  salvando.value = true;
  try {
    await RamonMarketingAPI.criarCusto({
      ...novo,
      valor,
      thesis_id: novo.thesis_id || null,
    });
    Object.assign(novo, { valor: '', observacao: '' });
    await carregar();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('RAMON.MARKETING.ERRO'));
  } finally {
    salvando.value = false;
  }
};

// Remover pede confirmação no modal da casa (regras de design: nada de window.confirm).
const removendo = ref(null);
const remover = async () => {
  const custo = removendo.value;
  removendo.value = null;
  try {
    await RamonMarketingAPI.removerCusto(custo.id);
    await carregar();
  } catch {
    useAlert(t('RAMON.MARKETING.ERRO'));
  }
};

// Lê o arquivo no navegador e manda o texto; limpa o input para poder subir o mesmo de novo.
const subir = async (evento, enviar, sucesso) => {
  const arquivo = evento.target.files?.[0];
  evento.target.value = '';
  if (!arquivo) return;
  try {
    const { data } = await enviar(await arquivo.text());
    useAlert(t(sucesso, data));
    await carregar();
  } catch (e) {
    useAlert(e?.response?.data?.error || t('RAMON.MARKETING.ERRO'));
  }
};
const subirGasto = e =>
  subir(
    e,
    texto => RamonMarketingAPI.importarGasto(texto),
    'RAMON.MARKETING.GASTO.OK'
  );

onMounted(carregar);
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-y-auto bg-n-background p-4 sm:p-8"
  >
    <RamonPageHeader
      :title="t('RAMON.MARKETING.CUSTOS.TITLE')"
      :subtitle="t('RAMON.MARKETING.CUSTOS.SUBTITLE')"
      compact
    />
    <div v-if="carregando" class="flex-1" />
    <div
      v-else-if="erro"
      :class="[AVISO, TOM.ruby]"
      class="flex items-center gap-3 self-start"
    >
      {{ t('RAMON.MARKETING.ERRO') }}
      <Button link xs :label="t('RAMON.MARKETING.TENTAR')" @click="carregar" />
    </div>
    <div v-else class="flex flex-col gap-4">
      <div class="grid gap-4 lg:grid-cols-2">
        <section :class="CARTAO" class="flex flex-col gap-2">
          <h2 :class="TITULO">{{ t('RAMON.MARKETING.STATUS.TITLE') }}</h2>
          <div
            v-for="linha in conexao"
            :key="linha.chave"
            class="flex items-center justify-between gap-2 text-sm text-n-slate-12"
          >
            {{ t(`RAMON.MARKETING.STATUS.${linha.chave}`) }}
            <span :class="[CHIP, linha.ok ? TOM.teal : TOM.slate]">
              {{ linha.rotulo }}
            </span>
          </div>
          <p class="text-xs text-n-slate-11">{{ ultimoGasto }}</p>
          <p class="text-xs text-n-slate-10">
            {{ t('RAMON.MARKETING.STATUS.NOTA') }}
          </p>
        </section>

        <section :class="CARTAO" class="flex flex-col gap-2">
          <h2 :class="TITULO">{{ t('RAMON.MARKETING.GASTO.TITLE') }}</h2>
          <p class="text-sm text-n-slate-11">
            {{ t('RAMON.MARKETING.GASTO.COMO') }}
          </p>
          <input
            type="file"
            accept=".csv,text/csv"
            :class="ARQUIVO"
            :aria-label="t('RAMON.MARKETING.GASTO.TITLE')"
            @change="subirGasto"
          />
        </section>
      </div>

      <MetasModelo :metas="dados.metas" @atualizar="carregar" />

      <section :class="CARTAO" class="flex flex-col gap-3">
        <h2 :class="TITULO">{{ t('RAMON.MARKETING.CUSTO.TITLE') }}</h2>
        <form
          class="grid items-end gap-3 sm:grid-cols-2 lg:grid-cols-6"
          @submit.prevent="lancar"
        >
          <label :class="ROTULO">
            {{ t('RAMON.MARKETING.CUSTO.DATA') }}
            <input v-model="novo.data" type="date" :class="CAMPO" required />
          </label>
          <label :class="ROTULO">
            {{ t('RAMON.MARKETING.CUSTO.VALOR') }}
            <input
              v-model="novo.valor"
              inputmode="decimal"
              :class="CAMPO"
              required
            />
          </label>
          <label :class="ROTULO">
            {{ t('RAMON.MARKETING.CUSTO.CATEGORIA') }}
            <select v-model="novo.categoria" :class="SELECT" required>
              <option value="" disabled>
                {{ t('RAMON.MARKETING.CUSTO.ESCOLHA') }}
              </option>
              <option v-for="c in dados.categorias" :key="c" :value="c">
                {{ categoria(c) }}
              </option>
            </select>
          </label>
          <label :class="ROTULO">
            {{ t('RAMON.MARKETING.CUSTO.TESE') }}
            <select v-model="novo.thesis_id" :class="SELECT">
              <option value="">{{ t('RAMON.MARKETING.CUSTO.GERAL') }}</option>
              <option
                v-for="tese in dados.teses"
                :key="tese.id"
                :value="tese.id"
              >
                {{ tese.name }}
              </option>
            </select>
          </label>
          <label :class="ROTULO">
            {{ t('RAMON.MARKETING.CUSTO.OBSERVACAO') }}
            <input v-model="novo.observacao" :class="CAMPO" />
          </label>
          <Button
            type="submit"
            sm
            :is-loading="salvando"
            :label="t('RAMON.MARKETING.CUSTO.LANCAR')"
          />
        </form>

        <p v-if="!dados.custos.length" class="text-sm text-n-slate-10">
          {{ t('RAMON.MARKETING.CUSTO.VAZIO') }}
        </p>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-xs text-n-slate-10">
                <th class="py-1 font-medium">
                  {{ t('RAMON.MARKETING.CUSTO.DATA') }}
                </th>
                <th class="py-1 font-medium">
                  {{ t('RAMON.MARKETING.CUSTO.CATEGORIA') }}
                </th>
                <th class="py-1 font-medium">
                  {{ t('RAMON.MARKETING.CUSTO.TESE') }}
                </th>
                <th class="py-1 font-medium">
                  {{ t('RAMON.MARKETING.CUSTO.OBSERVACAO') }}
                </th>
                <th class="py-1 font-medium text-right">
                  {{ t('RAMON.MARKETING.CUSTO.VALOR') }}
                </th>
                <th />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="custo in dados.custos"
                :key="custo.id"
                class="border-t border-n-weak text-n-slate-12"
              >
                <td class="py-1.5 font-mono">{{ dataBr(custo.data) }}</td>
                <td class="py-1.5">{{ categoria(custo.categoria) }}</td>
                <td class="py-1.5">
                  {{ custo.thesis_name || t('RAMON.MARKETING.CUSTO.GERAL') }}
                </td>
                <td class="py-1.5 text-n-slate-11">{{ custo.observacao }}</td>
                <td class="py-1.5 font-mono text-right">
                  {{ formatBrl(custo.valor) }}
                </td>
                <td class="py-1.5 text-right">
                  <Button
                    xs
                    ghost
                    ruby
                    icon="i-lucide-trash-2"
                    :aria-label="t('RAMON.MARKETING.CUSTO.REMOVER')"
                    @click="removendo = custo"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    <ConfirmModal
      v-if="removendo"
      :title="t('RAMON.MARKETING.CUSTO.CONFIRMAR_REMOVER')"
      :confirm-label="t('RAMON.MARKETING.CUSTO.REMOVER')"
      @confirm="remover"
      @cancel="removendo = null"
    />
  </div>
</template>

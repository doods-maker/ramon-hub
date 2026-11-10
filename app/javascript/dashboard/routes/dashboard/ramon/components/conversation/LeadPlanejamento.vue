<script setup>
import { ref, computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/leads';
import Button from 'dashboard/components-next/button/Button.vue';
import PlanejamentoTextos from './PlanejamentoTextos.vue';
import {
  AVISO,
  CAMPO,
  CARTAO,
  CHIP,
  ROTULO,
  SELECT,
  TITULO,
  TOM,
} from '../../helpers/ui';

const props = defineProps({
  lead: { type: Object, required: true },
  seguradoNome: { type: String, default: '' },
  // params da linha do histórico: { perfil, dados } reabre no resultado sem
  // chamar o motor; linha antiga (sem dados) começa do zero.
  inicial: { type: Object, default: null },
});
defineOptions({ name: 'LeadPlanejamento' });

const { t } = useI18n();

const FORMAS = [
  'pro_labore',
  'pro_labore_mais_salario',
  'carne_20',
  'simplificado_11',
  'baixa_renda_5',
  'empregado',
];
const INTERVALO = 2000;
const MAX_CONSULTAS = 60; // 2 min

const perfilVazio = () => ({
  forma: 'pro_labore',
  empresa: '',
  salario_atual: '',
  salario_emprego: '',
  cenario_livre: '',
  turma: '',
  facultativo_semestral: false,
  descarte_pontos: 'nao',
});

const perfil = ref(null); // formulário (passo 2)
const perfilCalculado = ref(null); // o perfil que gerou `dados`: vai no Gerar
const motivo = ref('');
const dados = ref(null); // editado no lugar pelo PlanejamentoTextos
const avisos = ref([]);
const carregando = ref(false);
const hasError = ref(false);
const errorMessage = ref('');
const ultimaAcao = ref('comecar');
const calculoId = ref(null);
const geracao = ref(null); // { estado, drive, drive_motivo, drive_erro }
const baixando = ref(false);
let timer = null;
let consultas = 0;

const gerando = computed(() => geracao.value?.estado === 'gerando');
const ocupado = computed(
  () => carregando.value || gerando.value || baixando.value
);
const comSalarioEmprego = computed(
  () => perfil.value?.forma === 'pro_labore_mais_salario'
);
const comFacultativo = computed(() =>
  perfil.value?.forma?.startsWith('pro_labore')
);
const cenarios = computed(() =>
  Array.isArray(dados.value?.cenarios) ? dados.value.cenarios : []
);

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const money = v => (v === null || v === undefined ? '' : brl.format(Number(v)));

// jsdom (specs) não implementa Blob.text() — FileReader funciona nos dois.
const blobToText = blob =>
  new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error);
    reader.readAsText(blob);
  });

const mostrarErro = mensagem => {
  errorMessage.value = mensagem || t('RAMON.SIMULADOR.PLANEJAMENTO_ERRO');
  hasError.value = true;
};

// planejamentoArquivo usa responseType: 'blob', então em erro o axios entrega
// error.response.data como Blob (não JSON) — precisa ler o texto antes.
const handleError = async error => {
  const data = error?.response?.data;
  if (data instanceof Blob) {
    try {
      mostrarErro(JSON.parse(await blobToText(data)).error);
    } catch {
      mostrarErro();
    }
  } else {
    mostrarErro(data?.error);
  }
};

const limparErro = acao => {
  ultimaAcao.value = acao;
  hasError.value = false;
  errorMessage.value = '';
};

const pararConsulta = () => {
  clearTimeout(timer);
  timer = null;
};

const comecar = async () => {
  limparErro('comecar');
  carregando.value = true;
  try {
    const { data } = await LeadsAPI.planejamento(props.lead.id, {
      segurado_nome: props.seguradoNome || undefined,
    });
    const sug = data.forma_sugerida || {};
    perfil.value = {
      ...perfilVazio(),
      forma: sug.forma || 'pro_labore',
      salario_atual:
        sug.salario_atual === null || sug.salario_atual === undefined
          ? ''
          : String(sug.salario_atual),
    };
    motivo.value = (sug.motivo || '').replace(/\.$/, ''); // a frase já fecha com ponto
  } catch (error) {
    await handleError(error);
  } finally {
    carregando.value = false;
  }
};

const perfilParaEnviar = () => {
  const p = perfil.value;
  return {
    ...p,
    salario_emprego: comSalarioEmprego.value ? p.salario_emprego : '',
    facultativo_semestral: comFacultativo.value && p.facultativo_semestral,
  };
};

const calcular = async () => {
  limparErro('calcular');
  carregando.value = true;
  const enviado = perfilParaEnviar();
  try {
    const { data } = await LeadsAPI.planejamento(props.lead.id, {
      perfil: enviado,
      segurado_nome: props.seguradoNome || undefined,
    });
    dados.value = data.dados;
    avisos.value = data.avisos || [];
    perfilCalculado.value = enviado;
    pararConsulta();
    geracao.value = null;
  } catch (error) {
    await handleError(error);
  } finally {
    carregando.value = false;
  }
};

const consultar = async () => {
  consultas += 1;
  try {
    const { data } = await LeadsAPI.planejamentoGeracao(
      props.lead.id,
      calculoId.value
    );
    // linha sem geração devolve null: nada gerado, para sem quebrar
    if (!data?.estado) {
      geracao.value = null;
    } else if (data.estado !== 'gerando') {
      geracao.value = data;
      if (data.estado === 'erro') mostrarErro(data.erro);
    } else if (consultas >= MAX_CONSULTAS) {
      geracao.value = null;
      mostrarErro(t('RAMON.SIMULADOR.PLANEJAMENTO_DEMOROU'));
    } else {
      timer = setTimeout(consultar, INTERVALO);
    }
  } catch (error) {
    geracao.value = null;
    await handleError(error);
  }
};

const gerar = async () => {
  limparErro('gerar');
  pararConsulta();
  geracao.value = { estado: 'gerando' };
  try {
    const { data } = await LeadsAPI.planejamentoGerar(props.lead.id, {
      perfil: perfilCalculado.value,
      dados: dados.value,
      segurado_nome: props.seguradoNome || undefined,
    });
    calculoId.value = data.calculo_id;
    consultas = 0;
    timer = setTimeout(consultar, INTERVALO);
  } catch (error) {
    geracao.value = null;
    await handleError(error);
  }
};

const nomeDoArquivo = (headers, tipo) => {
  const m = /filename\*=UTF-8''([^;]+)/i.exec(
    headers?.['content-disposition'] || ''
  );
  if (m) return decodeURIComponent(m[1]);
  return `planejamento-lead-${props.lead.id}.${tipo === 'pdf' ? 'pdf' : 'xlsx'}`;
};

const ultimoTipo = ref('pdf');
const baixar = async tipo => {
  limparErro('baixar');
  ultimoTipo.value = tipo;
  baixando.value = true;
  try {
    const { data, headers } = await LeadsAPI.planejamentoArquivo(
      props.lead.id,
      calculoId.value,
      tipo
    );
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = nomeDoArquivo(headers, tipo);
    link.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    await handleError(error);
  } finally {
    baixando.value = false;
  }
};

const retry = () =>
  ({
    comecar,
    calcular,
    gerar,
    baixar: () => baixar(ultimoTipo.value),
  })[ultimaAcao.value]();

if (props.inicial?.dados) {
  // cópia: a edição não mexe no objeto do histórico que veio por prop
  const copia = JSON.parse(JSON.stringify(props.inicial));
  perfil.value = { ...perfilVazio(), ...(copia.perfil || {}) };
  perfilCalculado.value = copia.perfil || {};
  dados.value = copia.dados;
}

onBeforeUnmount(pararConsulta);
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="lead-planejamento">
    <Button
      v-if="!perfil"
      data-testid="planejamento-comecar"
      :disabled="ocupado"
      sm
      class="self-start"
      :label="
        carregando
          ? $t('RAMON.SIMULADOR.PLANEJAMENTO_LENDO')
          : $t('RAMON.SIMULADOR.PLANEJAMENTO_COMECAR')
      "
      @click="comecar"
    />

    <div v-if="hasError" data-testid="planejamento-error">
      <p class="mb-0" :class="[AVISO, TOM.ruby]">{{ errorMessage }}</p>
      <Button
        data-testid="planejamento-retry"
        link
        xs
        class="mt-1"
        :label="$t('RAMON.LEAD_PANEL.RETRY')"
        @click="retry"
      />
    </div>

    <div
      v-if="perfil"
      class="flex flex-col gap-2"
      data-testid="planejamento-perfil"
    >
      <p v-if="motivo" class="mb-0" :class="[AVISO, TOM.slate]">
        {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_SUGERIDA', { motivo }) }}
      </p>
      <div class="grid grid-cols-2 gap-2">
        <label :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_FORMA') }}
          <select
            v-model="perfil.forma"
            data-testid="planejamento-forma"
            :class="SELECT"
          >
            <option v-for="f in FORMAS" :key="f" :value="f">
              {{ $t(`RAMON.SIMULADOR.PLANEJAMENTO_FORMA_${f.toUpperCase()}`) }}
            </option>
          </select>
        </label>
        <label :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_EMPRESA') }}
          <input
            v-model="perfil.empresa"
            type="text"
            data-testid="planejamento-empresa"
            :class="CAMPO"
          />
        </label>
        <label :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_SALARIO_ATUAL') }}
          <input
            v-model="perfil.salario_atual"
            type="text"
            inputmode="decimal"
            data-testid="planejamento-salario-atual"
            class="font-mono"
            :class="CAMPO"
          />
        </label>
        <label v-if="comSalarioEmprego" :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_SALARIO_EMPREGO') }}
          <input
            v-model="perfil.salario_emprego"
            type="text"
            inputmode="decimal"
            data-testid="planejamento-salario-emprego"
            class="font-mono"
            :class="CAMPO"
          />
        </label>
        <label :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_CENARIO_LIVRE') }}
          <input
            v-model="perfil.cenario_livre"
            type="text"
            inputmode="decimal"
            data-testid="planejamento-cenario-livre"
            class="font-mono"
            :class="CAMPO"
          />
        </label>
        <label :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_TURMA') }}
          <input
            v-model="perfil.turma"
            type="text"
            data-testid="planejamento-turma"
            :class="CAMPO"
          />
        </label>
      </div>
      <label
        v-if="comFacultativo"
        class="flex items-center gap-2 text-xs text-n-slate-11"
      >
        <input
          v-model="perfil.facultativo_semestral"
          type="checkbox"
          data-testid="planejamento-facultativo"
        />
        {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_FACULTATIVO') }}
      </label>
      <details class="text-xs text-n-slate-11">
        <summary class="cursor-pointer">
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_AVANCADO') }}
        </summary>
        <label class="mt-2" :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_DESCARTE_PONTOS') }}
          <select
            v-model="perfil.descarte_pontos"
            data-testid="planejamento-descarte"
            :class="SELECT"
          >
            <option value="nao">
              {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_DESCARTE_PONTOS_NAO') }}
            </option>
            <option value="tempo_minimo">
              {{
                $t('RAMON.SIMULADOR.PLANEJAMENTO_DESCARTE_PONTOS_TEMPO_MINIMO')
              }}
            </option>
          </select>
        </label>
      </details>
      <Button
        data-testid="planejamento-calcular"
        :disabled="ocupado"
        sm
        class="self-start"
        :label="
          carregando
            ? $t('RAMON.SIMULADOR.PLANEJAMENTO_CALCULANDO')
            : $t('RAMON.SIMULADOR.PLANEJAMENTO_CALCULAR')
        "
        @click="calcular"
      />
    </div>

    <template v-if="dados">
      <div
        class="flex flex-col gap-2"
        :class="CARTAO"
        data-testid="planejamento-resultado"
      >
        <div class="flex flex-wrap gap-1">
          <span
            v-if="dados.formato_textos === 'rascunho'"
            :class="[CHIP, TOM.amber]"
          >
            {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_AGUARDANDO_TEXTOS') }}
          </span>
          <span v-if="dados.versao === 'curta'" :class="[CHIP, TOM.slate]">
            {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_VERSAO_CURTA') }}
          </span>
        </div>
        <p
          v-if="dados.aposentadoria"
          class="mb-0 flex flex-wrap items-baseline gap-x-2 text-sm text-n-slate-12"
        >
          <span :class="TITULO">
            {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_APOSENTADORIA') }}
          </span>
          <span class="font-mono">{{ dados.aposentadoria.data }}</span>
          <span>{{ dados.aposentadoria.regra }}</span>
        </p>
        <div v-if="cenarios.length" class="overflow-x-auto">
          <table class="w-full text-xs text-n-slate-11">
            <thead>
              <tr class="text-n-slate-10">
                <th class="p-1 text-start font-medium">
                  {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_CENARIO') }}
                </th>
                <th class="p-1 text-end font-medium">
                  {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_SALARIO') }}
                </th>
                <th class="p-1 text-end font-medium">
                  {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_RMI_PROJETADA') }}
                </th>
                <th class="p-1 text-end font-medium">
                  {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_CUSTO') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="(c, i) in cenarios"
                :key="i"
                :class="{ 'font-semibold text-n-slate-12': c.sugestao }"
                :data-testid="`planejamento-cenario-${i}`"
              >
                <td class="p-1">{{ c.nome }}</td>
                <td class="p-1 text-end font-mono">{{ money(c.v) }}</td>
                <td class="p-1 text-end font-mono">{{ money(c.rmi) }}</td>
                <td class="p-1 text-end font-mono">{{ money(c.custo) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-if="dados.sugestao?.curta" class="mb-0 text-sm text-n-slate-12">
          {{ dados.sugestao.curta }}
        </p>
        <p
          v-if="dados.parar?.data"
          class="mb-0 flex flex-wrap items-baseline gap-x-2 text-xs text-n-slate-11"
        >
          <span :class="TITULO">
            {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_PARAR') }}
          </span>
          <span class="font-mono">{{ dados.parar.data }}</span>
          <span v-if="dados.parar.rmi" class="font-mono">
            {{ money(dados.parar.rmi) }}
          </span>
        </p>
        <ul
          v-if="avisos.length"
          class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4 mb-0"
          data-testid="planejamento-avisos"
        >
          <li v-for="(aviso, i) in avisos" :key="i">{{ aviso }}</li>
        </ul>
      </div>

      <PlanejamentoTextos :dados="dados" />

      <div class="flex flex-wrap items-center gap-2">
        <Button
          data-testid="planejamento-gerar"
          :disabled="ocupado"
          sm
          :label="
            gerando
              ? $t('RAMON.SIMULADOR.PLANEJAMENTO_GERANDO')
              : $t('RAMON.SIMULADOR.PLANEJAMENTO_GERAR')
          "
          @click="gerar"
        />
        <template v-if="geracao?.estado === 'pronto'">
          <Button
            data-testid="planejamento-baixar-pdf"
            :disabled="ocupado"
            sm
            faded
            slate
            :label="$t('RAMON.SIMULADOR.PLANEJAMENTO_PDF_BAIXAR')"
            @click="baixar('pdf')"
          />
          <Button
            data-testid="planejamento-baixar-memoria"
            :disabled="ocupado"
            sm
            faded
            slate
            :label="$t('RAMON.SIMULADOR.PLANEJAMENTO_MEMORIA_BAIXAR')"
            @click="baixar('memoria')"
          />
        </template>
      </div>
      <p
        v-if="geracao?.estado === 'pronto'"
        class="mb-0"
        :class="[AVISO, geracao.drive_erro ? TOM.amber : TOM.slate]"
        data-testid="planejamento-drive"
      >
        <a
          v-if="geracao.drive?.pasta_url"
          :href="geracao.drive.pasta_url"
          target="_blank"
          rel="noopener noreferrer"
          class="underline"
        >
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_DRIVE_SALVO') }}
        </a>
        <template v-else-if="geracao.drive_erro">
          {{ geracao.drive_erro }}
        </template>
        <template v-else>
          {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_DRIVE_SO_DOWNLOAD') }}
        </template>
      </p>
    </template>
  </div>
</template>

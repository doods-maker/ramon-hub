<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import LeadsAPI from 'dashboard/api/leads';
import ThesesAPI from 'dashboard/api/theses';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  ABA,
  ABA_ATIVA,
  ABA_INATIVA,
  ARQUIVO,
  AVISO,
  CAMPO,
  CARTAO,
  CARTAO_STATUS,
  CHIP,
  FILETE,
  ROTULO,
  SECAO,
  SELECT,
  TITULO,
  TOM,
} from '../../helpers/ui';
import LeadLiquidacao from './LeadLiquidacao.vue';
import LeadElegibilidade from './LeadElegibilidade.vue';
import LeadPensao from './LeadPensao.vue';
import LeadMaternidade from './LeadMaternidade.vue';
import LeadPlanejamento from './LeadPlanejamento.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const props = defineProps({
  lead: { type: Object, required: true },
  // Cálculo reaberto do histórico: { tipo, params, cnis }. O componente é
  // remontado com :key, então basta semear o estado inicial aqui.
  inicial: { type: Object, default: null },
  // Nome digitado no cálculo rápido (tela Cálculos, sem cliente): vai junto
  // de cada POST de cálculo e vira o segurado_nome do histórico. Só a
  // instância do rascunho recebe — lead real usa o contato, como sempre.
  seguradoNome: { type: String, default: '' },
  // custom_attributes.ultima_simulacao do lead (só o painel passa): o form
  // abre com os parâmetros dela e o resultado salvo aparece rotulado.
  ultimaSimulacao: { type: Object, default: null },
});
defineOptions({ name: 'LeadSimulador' });

const { t } = useI18n();

// Default do benefício pela tese do lead (heurística sobre os nomes seedados).
const guessBeneficio = name => {
  const n = (name || '').toLowerCase();
  if (n.includes('acidente')) return 'acidente';
  if (n.includes('permanente') || n.includes('invalidez')) return 'permanente';
  return 'temporaria';
};

const ini = props.inicial?.params || props.ultimaSimulacao?.parametros || {};
const ultimaData = props.ultimaSimulacao?.em
  ? new Date(props.ultimaSimulacao.em).toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
    })
  : '';

const form = ref({
  nascimento: ini.nascimento || props.lead.contact_data_nascimento || '',
  // Sem sexo conhecido o campo nasce vazio e é obrigatório: ele vai junto do
  // CNIS e entra em todo cálculo (antes caía em 'M' calado).
  sexo: ini.sexo || props.lead.contact_sexo || '',
  der: ini.der || '',
  salario: ini.salario || '',
  beneficio: ini.beneficio || guessBeneficio(props.lead.thesis_name),
  origem: ini.origem || 'previdenciaria',
  acrescimo_25:
    ini.acrescimo_25 ?? (props.lead.thesis_name || '').includes('25%'),
});

const isLoading = ref(false);
const resultado = ref(null);
const motorDown = ref(false);
const errorMessage = ref('');
const cnis = ref(props.lead.cnis_resumo || null);
const cnisLoading = ref(false);
// PDF fica só na memória do browser (LGPD): reprocessar com ajustes reenvia
// o mesmo arquivo; depois de F5 é preciso selecionar o PDF de novo.
const cnisFile = ref(null);
const vinculos = ref([]);
const excluidos = ref([]);
const mensalidades = ref({});
const especiaisGrau = ref({});
const especiaisInicio = ref({});
const especiaisFim = ref({});
const ajustesOpen = ref(false);
const memoria = ref(null);
const memoriaLoading = ref(false);

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const money = value => brl.format(Number(value || 0));

// Com CNIS anexado, nascimento/sexo/salário vêm do histórico real.
const canSimulate = computed(() =>
  cnis.value
    ? Boolean(form.value.der)
    : Boolean(
        form.value.nascimento &&
          form.value.sexo &&
          form.value.der &&
          form.value.salario
      )
);

const honorario = computed(() => resultado.value?.honorario || null);
const motorInfo = computed(() => resultado.value?.motor || {});
const avisosQualidade = computed(() =>
  (resultado.value?.avisos || []).filter(a =>
    /qualidade de segurado|27-A|Tema 1360/i.test(a)
  )
);
const avisosGerais = computed(() =>
  (resultado.value?.avisos || []).filter(
    a => !avisosQualidade.value.includes(a)
  )
);

const handleMotorError = error => {
  if (error?.response?.status === 503) {
    motorDown.value = true;
  } else {
    errorMessage.value =
      error?.response?.data?.error || t('RAMON.SIMULADOR.GENERIC_ERROR');
  }
};

const applyCnis = data => {
  cnis.value = data;
  vinculos.value = data.vinculos_detalhe || [];
  const parametros = data.parametros || {};
  excluidos.value = parametros.excluir_seqs
    ? parametros.excluir_seqs.split(',').map(Number)
    : [];
  mensalidades.value = parametros.mensalidades
    ? JSON.parse(parametros.mensalidades)
    : {};
  const especiais = parametros.especiais
    ? JSON.parse(parametros.especiais)
    : {};
  especiaisGrau.value = {};
  especiaisInicio.value = {};
  especiaisFim.value = {};
  Object.entries(especiais).forEach(([seq, v]) => {
    especiaisGrau.value[seq] = v.grau;
    if (v.inicio) especiaisInicio.value[seq] = v.inicio;
    if (v.fim) especiaisFim.value[seq] = v.fim;
  });
};

// Cálculo reaberto: o CNIS já vem processado do histórico (nada de reanexar o
// PDF). O servidor já devolveu esse mesmo CNIS pro caso, então recalcular vale.
if (props.inicial?.cnis) applyCnis(props.inicial.cnis);

const mensalidadesJson = () => {
  // valores como string: o motor converte pra Decimal sem artefato de float
  const entries = Object.entries(mensalidades.value)
    .filter(([, v]) => v)
    .map(([k, v]) => [k, String(v)]);
  return entries.length ? JSON.stringify(Object.fromEntries(entries)) : '';
};

// Espelha mensalidadesJson: filtra vínculos sem grau marcado; trecho
// (inicio/fim) é opcional — vazio vira null (motor aceita ausência de trecho
// = período todo).
const especiaisJson = () => {
  const entries = Object.entries(especiaisGrau.value)
    .filter(([, grau]) => grau)
    .map(([seq, grau]) => [
      seq,
      {
        grau: Number(grau),
        inicio: especiaisInicio.value[seq] || null,
        fim: especiaisFim.value[seq] || null,
      },
    ]);
  return entries.length ? JSON.stringify(Object.fromEntries(entries)) : '';
};

const GRAUS_ESPECIAIS = [15, 20, 25];

// Checkbox do kit é booleano: o array de excluídos é montado aqui.
const toggleExcluido = (seq, marcado) => {
  excluidos.value = marcado
    ? [...excluidos.value, seq]
    : excluidos.value.filter(s => s !== seq);
};

const tituloDe = v => [v.seq, v.tipo, v.origem].filter(Boolean).join(' · ');
const periodoDe = v => (v.inicio ? `${v.inicio} → ${v.fim || '…'}` : '');

const uploadCnis = async opts => {
  cnisLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.uploadCnis(
      props.lead.id,
      cnisFile.value,
      form.value.sexo,
      opts
    );
    applyCnis(data);
    resultado.value = null;
    memoria.value = null;
  } catch (error) {
    handleMotorError(error);
  } finally {
    cnisLoading.value = false;
  }
};

const onCnisFile = async event => {
  const file = event.target.files[0];
  if (!file) return;
  cnisFile.value = file;
  await uploadCnis({});
  event.target.value = '';
};

// Depois de F5 o PDF não está mais na memória — reanexar para poder reaplicar.
const onRefile = event => {
  cnisFile.value = event.target.files[0] || null;
};

const reaplicar = () =>
  uploadCnis({
    excluirSeqs: excluidos.value.join(','),
    mensalidades: mensalidadesJson(),
  });

const toggleAjustes = async () => {
  ajustesOpen.value = !ajustesOpen.value;
  if (ajustesOpen.value && !vinculos.value.length) {
    try {
      const { data } = await LeadsAPI.getCnis(props.lead.id);
      applyCnis(data);
    } catch {
      errorMessage.value = t('RAMON.SIMULADOR.GENERIC_ERROR');
    }
  }
};

const removeCnis = async () => {
  errorMessage.value = '';
  try {
    await LeadsAPI.deleteCnis(props.lead.id);
    cnis.value = null;
    cnisFile.value = null;
    vinculos.value = [];
    excluidos.value = [];
    mensalidades.value = {};
    especiaisGrau.value = {};
    especiaisInicio.value = {};
    especiaisFim.value = {};
    ajustesOpen.value = false;
    resultado.value = null;
    memoria.value = null;
  } catch {
    errorMessage.value = t('RAMON.SIMULADOR.GENERIC_ERROR');
  }
};

// Persiste o essencial da última simulação no lead (o Modo Foco da Esteira
// lê custom_attributes.ultima_simulacao; o PATCH faz deep_merge no server).
// Vira o VALOR do lead no funil (LeadValorEstimado), então só acontece no
// clique explícito em "Salvar como valor deste lead" — simular não grava.
// `f` = formulário do momento em que o resultado saiu (não o de agora).
const persistirUltimaSimulacao = (data, f) =>
  LeadsAPI.update(props.lead.id, {
    custom_attributes: {
      ultima_simulacao: {
        mensal: data.mensal,
        atrasados: data.atrasados,
        honorario_valor: data.honorario?.valor || null,
        tese: data.honorario?.tese || props.lead.thesis_name || null,
        em: new Date().toISOString(),
        parametros: {
          der: f.der,
          salario: f.salario,
          beneficio: f.beneficio,
          origem: f.origem,
          acrescimo_25: f.acrescimo_25,
          usar_cnis: f.usar_cnis,
        },
      },
    },
  });

const salvandoValor = ref(false);
const valorSalvo = ref(false);
let formDoResultado = null;
const salvarValor = async () => {
  salvandoValor.value = true;
  try {
    await persistirUltimaSimulacao(resultado.value, formDoResultado);
    valorSalvo.value = true;
    useAlert(t('RAMON.SIMULADOR.VALOR_SALVO'));
  } catch {
    useAlert(t('RAMON.SIMULADOR.SALVAR_VALOR_ERRO'));
  } finally {
    salvandoValor.value = false;
  }
};

const simulate = async () => {
  isLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  resultado.value = null;
  memoria.value = null;
  try {
    const { data } = await LeadsAPI.simulate(props.lead.id, {
      ...form.value,
      usar_cnis: Boolean(cnis.value),
      segurado_nome: props.seguradoNome || undefined,
    });
    resultado.value = data;
    formDoResultado = { ...form.value, usar_cnis: Boolean(cnis.value) };
    valorSalvo.value = false;
  } catch (error) {
    handleMotorError(error);
  } finally {
    isLoading.value = false;
  }
};

// Memória de cálculo do motor (competência/índice/corrigido): re-simula com o
// flag opt-in — payload grande, só quando o advogado pede.
const verMemoria = async () => {
  if (memoria.value) {
    memoria.value = null;
    return;
  }
  memoriaLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.simulate(props.lead.id, {
      ...form.value,
      usar_cnis: Boolean(cnis.value),
      memoria_calculo: true,
      segurado_nome: props.seguradoNome || undefined,
    });
    resultado.value = data;
    memoria.value = data.motor?.memoria_calculo || null;
  } catch (error) {
    handleMotorError(error);
  } finally {
    memoriaLoading.value = false;
  }
};

// Painel de possibilidades (todas as regras, estilo Previdenciarista):
// CNIS e/ou vínculos manuais (ex.: atividade rural que não está no CNIS).
const painelLoading = ref(false);
const painel = ref(null);
const vinculosExtras = ref([]);

const addVinculoExtra = () =>
  vinculosExtras.value.push({
    inicio: '',
    fim: '',
    tipo: 'EMPREGO',
    salario: '',
    especialGrau: undefined,
    especialInicio: '',
    especialFim: '',
  });
const removeVinculoExtra = index => vinculosExtras.value.splice(index, 1);

const vinculosExtrasJson = () =>
  vinculosExtras.value
    .filter(v => v.inicio && v.fim)
    .map(({ especialGrau, especialInicio, especialFim, ...v }) => ({
      ...v,
      ...(especialGrau
        ? {
            especial: {
              grau: Number(especialGrau),
              inicio: especialInicio || null,
              fim: especialFim || null,
            },
          }
        : {}),
    }));

const canPainel = computed(() =>
  Boolean(
    form.value.der &&
      (cnis.value ||
        (form.value.nascimento &&
          form.value.sexo &&
          vinculosExtras.value.some(v => v.inicio && v.fim)))
  )
);

// A elegibilidade não aceita vínculos manuais (sem suporte no motor ainda) —
// CNIS é obrigatório, diferente do canPainel (que aceita vínculos avulsos).
const canElegibilidade = computed(() => Boolean(form.value.der && cnis.value));

// Pensão e maternidade usam data própria (data_obito/data_evento) dentro do
// componente filho — o gate da aba é só o CNIS, igual à elegibilidade.
const canPensao = computed(() => Boolean(cnis.value));
const canMaternidade = computed(() => Boolean(cnis.value));
const canPlanejamento = computed(() => Boolean(cnis.value));

const calcularPainel = async () => {
  painelLoading.value = true;
  motorDown.value = false;
  errorMessage.value = '';
  try {
    const { data } = await LeadsAPI.painel(props.lead.id, {
      der: form.value.der,
      nascimento: form.value.nascimento,
      sexo: form.value.sexo,
      vinculos_extras: vinculosExtrasJson(),
      especiais: especiaisJson(),
      segurado_nome: props.seguradoNome || undefined,
    });
    painel.value = data;
  } catch (error) {
    handleMotorError(error);
  } finally {
    painelLoading.value = false;
  }
};

const nomeSexo = sexo =>
  sexo === 'F' ? t('RAMON.SIMULADOR.SEXO_F') : t('RAMON.SIMULADOR.SEXO_M');

// Trocar o sexo usado no CNIS: o servidor corrige o segurado guardado (o PDF
// não precisa voltar). Resultados na tela eram do sexo antigo — saem, e as
// abas filhas remontam (calculoVersao) pra não mostrar conta velha.
const sexoTrocando = ref(false);
const calculoVersao = ref(0);
const trocarSexo = async () => {
  sexoTrocando.value = true;
  errorMessage.value = '';
  try {
    const novo = cnis.value.sexo === 'F' ? 'M' : 'F';
    const { data } = await LeadsAPI.trocarSexoCnis(props.lead.id, novo);
    cnis.value = { ...cnis.value, sexo: data.sexo };
    form.value.sexo = data.sexo;
    resultado.value = null;
    memoria.value = null;
    painel.value = null;
    calculoVersao.value += 1;
  } catch {
    errorMessage.value = t('RAMON.SIMULADOR.GENERIC_ERROR');
  } finally {
    sexoTrocando.value = false;
  }
};

// Caso de cálculo (rascunho ou caso oculto, fora do funil) nasce sem tese e o
// Honorário não tem regra: a aba oferece a tese ali mesmo. Escolher grava a
// tese no caso (não é lead do funil) e já calcula.
const casoDeCalculo = props.lead.source === 'calculo-advbox';
const teseId = ref(props.lead.thesis_id || '');
const teses = ref([]);
const teseSalvando = ref(false);
if (casoDeCalculo) {
  ThesesAPI.get()
    .then(({ data }) => {
      teses.value = (data || []).filter(tese => tese.active);
    })
    .catch(() => {});
}
const escolherTese = async () => {
  teseSalvando.value = true;
  errorMessage.value = '';
  try {
    await LeadsAPI.update(props.lead.id, { thesis_id: teseId.value || null });
    if (canSimulate.value) await simulate();
  } catch {
    errorMessage.value = t('RAMON.SIMULADOR.GENERIC_ERROR');
  } finally {
    teseSalvando.value = false;
  }
};

const liquidacaoRef = ref(null);

// RMI com descartes é a que o advogado usa na conta quando existe (é a maior).
const liquidarCartao = cartao => {
  liquidacaoRef.value?.preencher(cartao.rmi_com_descartes || cartao.rmi);
};

// filete do cartão: verde = elegível, vermelho = não, âmbar = depende
const bordaDe = cartao => {
  if (cartao.elegivel === true) return FILETE.teal;
  if (cartao.elegivel === false) return FILETE.ruby;
  return FILETE.amber;
};

const dataBr = iso => (iso ? iso.split('-').reverse().join('/') : '');

// Aba padrão = Possibilidades (uso "hub = Previdenciarista"); o fluxo de
// honorário do auxílio-acidente vive na 2ª aba, intacto. Cálculo reaberto do
// histórico volta na aba em que foi feito.
// ponytail: o reabrir restaura o que é caro (CNIS + nascimento/sexo/DER +
// ajustes de vínculo). Campos próprios das abas pensão/maternidade/
// planejamento ficam guardados no snapshot mas não são repreenchidos —
// preencher de novo é digitação de segundos. Ligar se incomodar.
// Última simulação salva é do Honorário: abre nela, onde o resultado aparece.
const aba = ref(
  props.inicial?.tipo || (props.ultimaSimulacao ? 'honorario' : 'painel')
);
</script>

<template>
  <div class="flex flex-col gap-3 p-1" data-testid="lead-simulador">
    <div
      v-if="cnis"
      class="flex flex-col gap-1"
      :class="CARTAO"
      data-testid="sim-cnis-chip"
    >
      <div class="flex items-center justify-between gap-2">
        <span
          class="flex items-center min-w-0 gap-1.5 text-sm font-medium text-n-slate-12"
        >
          <span class="i-lucide-file-text size-4 shrink-0 text-n-blue-11" />
          <span class="truncate">{{ cnis.filename }}</span>
        </span>
        <Button
          data-testid="sim-cnis-remove"
          link
          ruby
          xs
          :label="$t('RAMON.SIMULADOR.CNIS_REMOVE')"
          @click="removeCnis"
        />
      </div>
      <span class="text-xs text-n-slate-10">
        {{
          $t('RAMON.SIMULADOR.CNIS_LOADED', {
            competencias: cnis.competencias,
            vinculos: cnis.vinculos,
          })
        }}
      </span>
      <span
        v-if="cnis.sexo"
        class="flex items-center gap-2 text-xs text-n-slate-10"
        data-testid="sim-cnis-sexo"
      >
        {{
          $t('RAMON.SIMULADOR.CNIS_SEXO_USADO', { sexo: nomeSexo(cnis.sexo) })
        }}
        <Button
          data-testid="sim-cnis-sexo-trocar"
          link
          xs
          :disabled="sexoTrocando"
          :label="$t('RAMON.SIMULADOR.CNIS_SEXO_TROCAR')"
          @click="trocarSexo"
        />
      </span>
      <ul
        v-if="cnis.avisos && cnis.avisos.length"
        class="flex flex-col gap-1 list-disc ps-7 my-1"
        :class="[AVISO, TOM.amber]"
        data-testid="sim-cnis-avisos"
      >
        <li v-for="(aviso, i) in cnis.avisos" :key="i">{{ aviso }}</li>
      </ul>
      <Button
        data-testid="sim-cnis-ajustes-toggle"
        link
        slate
        xs
        class="self-start"
        :label="$t('RAMON.SIMULADOR.VINCULOS_TOGGLE')"
        @click="toggleAjustes"
      />
      <div
        v-if="ajustesOpen"
        class="flex flex-col gap-2 pt-1"
        data-testid="sim-cnis-vinculos"
      >
        <div
          v-for="v in vinculos"
          :key="v.seq"
          class="flex flex-col gap-1"
          :class="SECAO"
        >
          <span class="text-xs text-n-slate-12 truncate">
            {{ tituloDe(v) }}
          </span>
          <span v-if="v.inicio" class="font-mono text-xs text-n-slate-10">
            {{ periodoDe(v) }}
          </span>
          <label class="flex items-center gap-2 text-xs text-n-slate-11">
            <Checkbox
              :model-value="excluidos.includes(v.seq)"
              :data-testid="`sim-vinculo-excluir-${v.seq}`"
              @update:model-value="on => toggleExcluido(v.seq, on)"
            />
            {{ $t('RAMON.SIMULADOR.VINCULO_EXCLUIR') }}
          </label>
          <label v-if="v.tipo === 'BENEFICIO'" class="sm:w-1/3" :class="ROTULO">
            {{ $t('RAMON.SIMULADOR.VINCULO_MENSALIDADE') }}
            <input
              v-model="mensalidades[v.seq]"
              type="number"
              min="0"
              step="0.01"
              class="font-mono"
              :class="[CAMPO]"
              :data-testid="`sim-vinculo-mensalidade-${v.seq}`"
            />
          </label>
          <div
            v-if="v.tipo !== 'BENEFICIO'"
            class="grid items-end grid-cols-3 gap-2"
          >
            <label :class="ROTULO">
              {{ $t('RAMON.SIMULADOR.ESPECIAL_LABEL') }}
              <select
                v-model="especiaisGrau[v.seq]"
                :data-testid="`sim-especial-grau-${v.seq}`"
                :class="SELECT"
              >
                <option :value="undefined">
                  {{ $t('RAMON.SIMULADOR.ESPECIAL_NAO') }}
                </option>
                <option v-for="g in GRAUS_ESPECIAIS" :key="g" :value="g">
                  {{ g }}
                </option>
              </select>
            </label>
            <template v-if="especiaisGrau[v.seq]">
              <input
                v-model="especiaisInicio[v.seq]"
                type="date"
                :data-testid="`sim-especial-inicio-${v.seq}`"
                class="font-mono"
                :class="[CAMPO]"
              />
              <input
                v-model="especiaisFim[v.seq]"
                type="date"
                :data-testid="`sim-especial-fim-${v.seq}`"
                class="font-mono"
                :class="[CAMPO]"
              />
            </template>
          </div>
        </div>
        <label v-if="!cnisFile" :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.VINCULOS_REUPLOAD_HINT') }}
          <input
            type="file"
            accept="application/pdf"
            data-testid="sim-cnis-refile"
            class="!mb-0"
            :class="[ARQUIVO]"
            @change="onRefile"
          />
        </label>
        <Button
          data-testid="sim-cnis-reaplicar"
          :disabled="!cnisFile || cnisLoading"
          sm
          faded
          slate
          class="self-start"
          :label="
            cnisLoading
              ? $t('RAMON.SIMULADOR.CNIS_LOADING')
              : $t('RAMON.SIMULADOR.VINCULOS_REAPLICAR')
          "
          @click="reaplicar"
        />
      </div>
    </div>
    <label v-else :class="ROTULO">
      {{
        cnisLoading
          ? $t('RAMON.SIMULADOR.CNIS_LOADING')
          : $t('RAMON.SIMULADOR.CNIS_LABEL')
      }}
      <input
        type="file"
        accept="application/pdf"
        data-testid="sim-cnis-file"
        :disabled="cnisLoading || !form.sexo"
        class="!mb-0"
        :class="[ARQUIVO]"
        @change="onCnisFile"
      />
      <span
        v-if="!form.sexo"
        class="text-n-amber-11"
        data-testid="sim-sexo-antes-cnis"
      >
        {{ $t('RAMON.SIMULADOR.SEXO_ANTES_CNIS') }}
      </span>
      <span v-else class="text-n-slate-10">
        {{ $t('RAMON.SIMULADOR.CNIS_HINT') }}
      </span>
    </label>

    <div class="grid grid-cols-2 gap-2">
      <label v-if="!cnis" :class="ROTULO">
        {{ $t('RAMON.SIMULADOR.NASCIMENTO') }}
        <input
          v-model="form.nascimento"
          type="date"
          data-testid="sim-nascimento"
          class="font-mono"
          :class="[CAMPO]"
        />
      </label>
      <label v-if="!cnis" :class="ROTULO">
        {{ $t('RAMON.SIMULADOR.SEXO') }}
        <select v-model="form.sexo" data-testid="sim-sexo" :class="SELECT">
          <option value="" disabled>
            {{ $t('RAMON.SIMULADOR.SEXO_SELECIONE') }}
          </option>
          <option value="M">{{ $t('RAMON.SIMULADOR.SEXO_M') }}</option>
          <option value="F">{{ $t('RAMON.SIMULADOR.SEXO_F') }}</option>
        </select>
      </label>
      <label :class="ROTULO">
        {{ $t('RAMON.SIMULADOR.DER') }}
        <input
          v-model="form.der"
          type="date"
          data-testid="sim-der"
          class="font-mono"
          :class="[CAMPO]"
        />
      </label>
    </div>

    <div
      class="flex flex-wrap border-b border-n-weak"
      role="tablist"
      data-testid="sim-abas"
    >
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'painel'"
        data-testid="sim-aba-painel"
        :class="[ABA, aba === 'painel' ? ABA_ATIVA : ABA_INATIVA]"
        @click="aba = 'painel'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_POSSIBILIDADES') }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'honorario'"
        data-testid="sim-aba-honorario"
        :class="[ABA, aba === 'honorario' ? ABA_ATIVA : ABA_INATIVA]"
        @click="aba = 'honorario'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_HONORARIO') }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'elegibilidade'"
        data-testid="sim-aba-elegibilidade"
        :class="[ABA, aba === 'elegibilidade' ? ABA_ATIVA : ABA_INATIVA]"
        @click="aba = 'elegibilidade'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_ELEGIBILIDADE') }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'pensao'"
        data-testid="sim-aba-pensao"
        :class="[ABA, aba === 'pensao' ? ABA_ATIVA : ABA_INATIVA]"
        @click="aba = 'pensao'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_PENSAO') }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'maternidade'"
        data-testid="sim-aba-maternidade"
        :class="[ABA, aba === 'maternidade' ? ABA_ATIVA : ABA_INATIVA]"
        @click="aba = 'maternidade'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_MATERNIDADE') }}
      </button>
      <button
        type="button"
        role="tab"
        :aria-selected="aba === 'planejamento'"
        data-testid="sim-aba-planejamento"
        :class="[ABA, aba === 'planejamento' ? ABA_ATIVA : ABA_INATIVA]"
        @click="aba = 'planejamento'"
      >
        {{ $t('RAMON.SIMULADOR.ABA_PLANEJAMENTO') }}
      </button>
    </div>

    <p
      v-if="motorDown"
      class="mb-0"
      :class="[AVISO, TOM.amber]"
      data-testid="sim-motor-down"
    >
      {{ $t('RAMON.SIMULADOR.MOTOR_DOWN') }}
    </p>
    <p
      v-else-if="errorMessage"
      class="mb-0"
      :class="[AVISO, TOM.ruby]"
      data-testid="sim-error"
    >
      {{ errorMessage }}
    </p>

    <div
      v-show="aba === 'honorario'"
      class="flex flex-col gap-3"
      data-testid="sim-secao-honorario"
    >
      <label v-if="casoDeCalculo" class="sm:w-1/2" :class="ROTULO">
        {{ $t('RAMON.SIMULADOR.TESE') }}
        <select
          v-model="teseId"
          data-testid="sim-tese"
          :disabled="teseSalvando"
          :class="SELECT"
          @change="escolherTese"
        >
          <option value="" disabled>
            {{ $t('RAMON.SIMULADOR.TESE_SELECIONE') }}
          </option>
          <option v-for="tese in teses" :key="tese.id" :value="tese.id">
            {{ tese.name }}
          </option>
        </select>
      </label>
      <div class="grid grid-cols-2 gap-2">
        <label v-if="!cnis" :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.SALARIO') }}
          <input
            v-model="form.salario"
            type="number"
            min="0"
            step="0.01"
            data-testid="sim-salario"
            class="font-mono"
            :class="[CAMPO]"
          />
        </label>
        <label :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.BENEFICIO') }}
          <select
            v-model="form.beneficio"
            data-testid="sim-beneficio"
            :class="SELECT"
          >
            <option value="temporaria">
              {{ $t('RAMON.SIMULADOR.BENEFICIO_TEMPORARIA') }}
            </option>
            <option value="permanente">
              {{ $t('RAMON.SIMULADOR.BENEFICIO_PERMANENTE') }}
            </option>
            <option value="acidente">
              {{ $t('RAMON.SIMULADOR.BENEFICIO_ACIDENTE') }}
            </option>
          </select>
        </label>
        <label :class="ROTULO">
          {{ $t('RAMON.SIMULADOR.ORIGEM') }}
          <select
            v-model="form.origem"
            data-testid="sim-origem"
            :class="SELECT"
          >
            <option value="previdenciaria">
              {{ $t('RAMON.SIMULADOR.ORIGEM_PREVIDENCIARIA') }}
            </option>
            <option value="acidentaria">
              {{ $t('RAMON.SIMULADOR.ORIGEM_ACIDENTARIA') }}
            </option>
          </select>
        </label>
      </div>

      <label class="flex items-center gap-2 text-xs text-n-slate-11">
        <Checkbox v-model="form.acrescimo_25" data-testid="sim-acrescimo" />
        {{ $t('RAMON.SIMULADOR.ACRESCIMO') }}
      </label>

      <Button
        data-testid="sim-run"
        :disabled="!canSimulate || isLoading"
        sm
        class="self-start"
        :label="
          isLoading
            ? $t('RAMON.SIMULADOR.SIMULANDO')
            : $t('RAMON.SIMULADOR.SIMULAR')
        "
        @click="simulate"
      />

      <div
        v-if="!resultado && ultimaSimulacao"
        class="flex flex-col gap-1.5"
        :class="CARTAO"
        data-testid="sim-ultima"
      >
        <p class="mb-0" :class="TITULO">
          {{ $t('RAMON.SIMULADOR.ULTIMA_TITULO', { data: ultimaData }) }}
        </p>
        <p v-if="ultimaSimulacao.atrasados != null" class="mb-0 text-sm">
          <span class="text-n-slate-10">
            {{ $t('RAMON.SIMULADOR.ATRASADOS') }}:
          </span>
          <span class="font-mono font-semibold text-n-slate-12">
            {{ `~${money(ultimaSimulacao.atrasados)}` }}
          </span>
        </p>
        <p v-if="ultimaSimulacao.mensal != null" class="mb-0 text-sm">
          <span class="text-n-slate-10">
            {{ $t('RAMON.SIMULADOR.MENSAL_ESTIMADO') }}:
          </span>
          <span class="font-mono font-semibold text-n-slate-12">
            {{ `~${money(ultimaSimulacao.mensal)}` }}
          </span>
        </p>
        <p v-if="ultimaSimulacao.honorario_valor" class="mb-0 text-sm">
          <span class="text-n-slate-10">
            {{ $t('RAMON.SIMULADOR.HONORARIO') }}:
          </span>
          <span class="font-mono font-semibold text-n-slate-12">
            {{ `~${money(ultimaSimulacao.honorario_valor)}` }}
          </span>
        </p>
        <p class="mb-0 text-xs text-n-slate-10">
          {{ $t('RAMON.SIMULADOR.ULTIMA_HINT') }}
        </p>
      </div>

      <div
        v-if="resultado"
        class="flex flex-col gap-2"
        :class="CARTAO"
        data-testid="sim-resultado"
      >
        <p class="mb-0 text-sm text-n-slate-12">
          <span class="text-n-slate-10">
            {{ $t('RAMON.SIMULADOR.ATRASADOS') }}:
          </span>
          <span class="font-mono font-semibold" data-testid="sim-atrasados">
            {{ `~${money(resultado.atrasados)}` }}
          </span>
        </p>
        <!-- Um número só, um nome só: o mesmo valor mensal que a Esteira, o
             painel e a "Última simulação" mostram. -->
        <p class="mb-0 text-sm text-n-slate-12" data-testid="sim-mensal">
          <span class="text-n-slate-10">
            {{ $t('RAMON.SIMULADOR.MENSAL_ESTIMADO') }}:
          </span>
          <span class="font-mono font-semibold">
            {{ `~${money(resultado.mensal)}` }}
          </span>
        </p>
        <p class="mb-0 text-xs text-n-slate-10" data-testid="sim-perda-mensal">
          {{
            $t('RAMON.SIMULADOR.PERDA_MENSAL', {
              value: money(resultado.perda_mensal),
            })
          }}
        </p>
        <div
          v-if="avisosQualidade.length"
          class="flex flex-col gap-1"
          :class="[AVISO, TOM.ruby]"
          data-testid="sim-aviso-qualidade"
        >
          <p v-for="(aviso, i) in avisosQualidade" :key="i" class="mb-0">
            {{ aviso }}
          </p>
          <p class="mb-0 font-medium">
            {{ $t('RAMON.SIMULADOR.ELEG_VER_ABA') }}
          </p>
        </div>
        <p
          v-if="honorario && honorario.valor"
          class="mb-0 text-sm text-n-slate-12"
          data-testid="sim-honorario"
        >
          <span class="text-n-slate-10">
            {{ $t('RAMON.SIMULADOR.HONORARIO') }}:
          </span>
          <span class="font-mono font-semibold">{{
            `~${money(honorario.valor)}`
          }}</span>
          <span class="text-xs text-n-slate-10">
            ({{
              $t('RAMON.SIMULADOR.HONORARIO_FORMULA', {
                percentual: honorario.percentual,
                n: honorario.n_mensalidades,
                tese: honorario.tese,
              })
            }})
          </span>
        </p>
        <p
          v-else
          class="mb-0 text-xs text-n-amber-11"
          data-testid="sim-sem-honorario"
        >
          {{
            casoDeCalculo
              ? $t('RAMON.SIMULADOR.TESE_ESCOLHA')
              : $t('RAMON.SIMULADOR.NO_FEE_CONFIG')
          }}
        </p>
        <p class="mb-0 text-xs text-n-slate-10">
          {{
            $t('RAMON.SIMULADOR.ESTIMATIVA_BASE', {
              meses: resultado.atrasados_estimativa?.meses || 0,
            })
          }}
        </p>
        <p
          v-if="motorInfo.rmi_com_descartes"
          class="mb-0 text-xs text-n-slate-10"
          data-testid="sim-duas-medias"
        >
          {{
            $t('RAMON.SIMULADOR.DUAS_MEDIAS', {
              rmi: money(motorInfo.rmi),
              descartes: money(motorInfo.rmi_com_descartes),
            })
          }}
        </p>
        <ul
          v-if="avisosGerais.length"
          class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4"
          data-testid="sim-avisos"
        >
          <li v-for="(aviso, i) in avisosGerais" :key="i">{{ aviso }}</li>
        </ul>
        <Button
          data-testid="sim-memoria-toggle"
          :disabled="memoriaLoading"
          link
          slate
          xs
          class="self-start"
          :label="
            memoriaLoading
              ? $t('RAMON.SIMULADOR.MEMORIA_LOADING')
              : memoria
                ? $t('RAMON.SIMULADOR.MEMORIA_HIDE')
                : $t('RAMON.SIMULADOR.MEMORIA_SHOW')
          "
          @click="verMemoria"
        />
        <!-- Lead do funil: o resultado só vira valor do lead se pedir. Caso de
             cálculo (rascunho/oculto) não tem valor de funil. -->
        <Button
          v-if="!casoDeCalculo"
          data-testid="sim-salvar-valor"
          sm
          faded
          :color="valorSalvo ? 'teal' : 'blue'"
          :icon="valorSalvo ? 'i-lucide-check' : 'i-lucide-save'"
          :disabled="salvandoValor || valorSalvo"
          class="self-start"
          :label="
            valorSalvo
              ? $t('RAMON.SIMULADOR.VALOR_SALVO')
              : $t('RAMON.SIMULADOR.SALVAR_VALOR')
          "
          @click="salvarValor"
        />
        <div
          v-if="memoria"
          class="flex flex-col gap-1"
          data-testid="sim-memoria"
        >
          <div
            class="max-h-64 overflow-y-auto overflow-x-auto rounded-lg border border-n-weak"
          >
            <table class="w-full font-mono text-xs text-n-slate-11">
              <thead class="sticky top-0 bg-n-solid-2 font-sans">
                <tr class="text-n-slate-10">
                  <th class="p-1 text-start font-medium">
                    {{ $t('RAMON.SIMULADOR.MEMORIA_COMPETENCIA') }}
                  </th>
                  <th class="p-1 text-end font-medium">
                    {{ $t('RAMON.SIMULADOR.MEMORIA_SALARIO') }}
                  </th>
                  <th class="p-1 text-end font-medium">
                    {{ $t('RAMON.SIMULADOR.MEMORIA_INDICE') }}
                  </th>
                  <th class="p-1 text-end font-medium">
                    {{ $t('RAMON.SIMULADOR.MEMORIA_CORRIGIDO') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="linha in memoria.salarios" :key="linha.competencia">
                  <td class="p-1 whitespace-nowrap">{{ linha.competencia }}</td>
                  <td class="p-1 text-end whitespace-nowrap">
                    {{ money(linha.salario) }}
                  </td>
                  <td class="p-1 text-end whitespace-nowrap">
                    {{ linha.indice }}
                  </td>
                  <td class="p-1 text-end whitespace-nowrap">
                    {{ money(linha.corrigido) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p
            class="mb-0 text-xs text-n-slate-10"
            data-testid="sim-memoria-resumo"
          >
            {{
              $t('RAMON.SIMULADOR.MEMORIA_RESUMO', {
                soma: money(memoria.soma),
                divisor: memoria.divisor,
                media: money(memoria.media),
              })
            }}
          </p>
        </div>
      </div>
    </div>

    <div
      v-show="aba === 'painel'"
      class="flex flex-col gap-2"
      data-testid="sim-painel-secao"
    >
      <span :class="TITULO">
        {{ $t('RAMON.SIMULADOR.PAINEL_TITULO') }}
      </span>
      <div
        v-for="(v, i) in vinculosExtras"
        :key="i"
        class="flex flex-col gap-1"
        :class="CARTAO"
        :data-testid="`sim-vinculo-extra-${i}`"
      >
        <div class="grid grid-cols-2 gap-2">
          <label :class="ROTULO">
            {{ $t('RAMON.SIMULADOR.VINCULO_INICIO') }}
            <input
              v-model="v.inicio"
              type="date"
              class="font-mono"
              :class="[CAMPO]"
            />
          </label>
          <label :class="ROTULO">
            {{ $t('RAMON.SIMULADOR.VINCULO_FIM') }}
            <input
              v-model="v.fim"
              type="date"
              class="font-mono"
              :class="[CAMPO]"
            />
          </label>
          <label :class="ROTULO">
            {{ $t('RAMON.SIMULADOR.VINCULO_TIPO') }}
            <select v-model="v.tipo" :class="SELECT">
              <option value="EMPREGO">
                {{ $t('RAMON.SIMULADOR.VINCULO_TIPO_EMPREGO') }}
              </option>
              <option value="RECOLHIMENTO">
                {{ $t('RAMON.SIMULADOR.VINCULO_TIPO_RECOLHIMENTO') }}
              </option>
            </select>
          </label>
          <label :class="ROTULO">
            {{ $t('RAMON.SIMULADOR.VINCULO_SALARIO') }}
            <input
              v-model="v.salario"
              type="number"
              min="0"
              step="0.01"
              class="font-mono"
              :class="[CAMPO]"
            />
          </label>
        </div>
        <div class="grid items-end grid-cols-3 gap-2">
          <label :class="ROTULO">
            {{ $t('RAMON.SIMULADOR.ESPECIAL_LABEL') }}
            <select
              v-model="v.especialGrau"
              :data-testid="`sim-vinculo-extra-especial-grau-${i}`"
              :class="SELECT"
            >
              <option :value="undefined">
                {{ $t('RAMON.SIMULADOR.ESPECIAL_NAO') }}
              </option>
              <option v-for="g in GRAUS_ESPECIAIS" :key="g" :value="g">
                {{ g }}
              </option>
            </select>
          </label>
          <template v-if="v.especialGrau">
            <input
              v-model="v.especialInicio"
              type="date"
              :data-testid="`sim-vinculo-extra-especial-inicio-${i}`"
              class="font-mono"
              :class="[CAMPO]"
            />
            <input
              v-model="v.especialFim"
              type="date"
              :data-testid="`sim-vinculo-extra-especial-fim-${i}`"
              class="font-mono"
              :class="[CAMPO]"
            />
          </template>
        </div>
        <Button
          link
          ruby
          xs
          class="self-start"
          :label="$t('RAMON.SIMULADOR.VINCULO_REMOVER')"
          @click="removeVinculoExtra(i)"
        />
      </div>
      <Button
        data-testid="sim-vinculo-extra-add"
        link
        slate
        xs
        class="self-start"
        :label="$t('RAMON.SIMULADOR.VINCULO_ADICIONAR')"
        @click="addVinculoExtra"
      />
      <Button
        data-testid="sim-painel-run"
        :disabled="!canPainel || painelLoading"
        sm
        class="self-start"
        :label="
          painelLoading
            ? $t('RAMON.SIMULADOR.PAINEL_CALCULANDO')
            : $t('RAMON.SIMULADOR.PAINEL_CALCULAR')
        "
        @click="calcularPainel"
      />

      <div
        v-if="painel"
        class="flex flex-col gap-2"
        data-testid="sim-painel-resultado"
      >
        <p class="mb-0 text-xs text-n-slate-11" data-testid="sim-painel-resumo">
          {{
            $t('RAMON.SIMULADOR.PAINEL_RESUMO', {
              idade: painel.resumo.idade,
              tempo: painel.resumo.tempo_contribuicao,
              tempoReforma: painel.resumo.tempo_na_reforma,
              carencia: painel.resumo.carencia,
              media: money(painel.resumo.media),
            })
          }}
        </p>
        <div
          v-for="cartao in painel.cartoes"
          :key="cartao.id"
          class="flex flex-col gap-1"
          :class="[CARTAO_STATUS, bordaDe(cartao)]"
          :data-testid="`sim-cartao-${cartao.id}`"
        >
          <div class="flex items-start justify-between gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ cartao.titulo }}
            </span>
            <span
              class="font-mono text-sm font-semibold text-n-slate-12 whitespace-nowrap"
            >
              {{ money(cartao.rmi) }}
            </span>
          </div>
          <span class="text-xs text-n-slate-10">{{ cartao.subtitulo }}</span>
          <span
            v-if="cartao.elegivel === true"
            class="self-start"
            :class="[CHIP, TOM.teal]"
          >
            {{ $t('RAMON.SIMULADOR.PAINEL_ELEGIVEL') }}
          </span>
          <span
            v-else-if="cartao.elegivel === null && cartao.depende_de"
            class="self-start"
            :class="[CHIP, TOM.amber]"
          >
            {{
              $t('RAMON.SIMULADOR.PAINEL_DEPENDE', { de: cartao.depende_de })
            }}
          </span>
          <template v-for="req in cartao.requisitos || []" :key="req.nome">
            <span v-if="req.faltou" class="text-xs text-n-ruby-11">
              {{
                $t('RAMON.SIMULADOR.PAINEL_FALTOU', {
                  requisito: $t(
                    `RAMON.SIMULADOR.REQ_${req.nome.toUpperCase()}`
                  ),
                  atual: req.atual,
                  faltou: req.faltou,
                })
              }}
            </span>
          </template>
          <span v-if="cartao.rmi_com_descartes" class="text-xs text-n-slate-10">
            {{
              $t('RAMON.SIMULADOR.PAINEL_DESCARTES', {
                valor: money(cartao.rmi_com_descartes),
              })
            }}
          </span>
          <span v-if="cartao.previsao" class="text-xs text-n-slate-10">
            {{
              $t('RAMON.SIMULADOR.PAINEL_PREVISAO', {
                data: dataBr(cartao.previsao),
              })
            }}
          </span>
          <Button
            v-if="cartao.rmi"
            :data-testid="`sim-cartao-liquidar-${cartao.id}`"
            link
            slate
            xs
            class="self-start"
            :label="$t('RAMON.SIMULADOR.PAINEL_LIQUIDAR')"
            @click="liquidarCartao(cartao)"
          />
        </div>
        <ul
          v-if="painel.avisos && painel.avisos.length"
          class="flex flex-col gap-1 text-xs text-n-slate-10 list-disc ps-4"
        >
          <li v-for="(aviso, i) in painel.avisos" :key="i">{{ aviso }}</li>
        </ul>
      </div>
      <LeadLiquidacao ref="liquidacaoRef" :lead="lead" />
    </div>

    <div
      v-show="aba === 'elegibilidade'"
      class="flex flex-col gap-2"
      data-testid="sim-elegibilidade-secao"
    >
      <p
        v-if="!canElegibilidade"
        class="mb-0"
        :class="[AVISO, TOM.amber]"
        data-testid="sim-elegibilidade-hint"
      >
        {{ $t('RAMON.SIMULADOR.ELEG_PRECISA_CNIS') }}
      </p>
      <LeadElegibilidade
        v-else
        :key="calculoVersao"
        :lead="lead"
        :der="form.der"
        :segurado-nome="seguradoNome"
      />
    </div>

    <div
      v-show="aba === 'pensao'"
      class="flex flex-col gap-2"
      data-testid="sim-pensao-secao"
    >
      <p
        v-if="!canPensao"
        class="mb-0"
        :class="[AVISO, TOM.amber]"
        data-testid="sim-pensao-hint"
      >
        {{ $t('RAMON.SIMULADOR.PENSAO_PRECISA_CNIS') }}
      </p>
      <LeadPensao
        v-else
        :key="calculoVersao"
        :lead="lead"
        :segurado-nome="seguradoNome"
      />
    </div>

    <div
      v-show="aba === 'maternidade'"
      class="flex flex-col gap-2"
      data-testid="sim-maternidade-secao"
    >
      <p
        v-if="!canMaternidade"
        class="mb-0"
        :class="[AVISO, TOM.amber]"
        data-testid="sim-maternidade-hint"
      >
        {{ $t('RAMON.SIMULADOR.MATERNIDADE_PRECISA_CNIS') }}
      </p>
      <LeadMaternidade
        v-else
        :key="calculoVersao"
        :lead="lead"
        :segurado-nome="seguradoNome"
      />
    </div>

    <div
      v-show="aba === 'planejamento'"
      class="flex flex-col gap-2"
      data-testid="sim-planejamento-secao"
    >
      <p
        v-if="!canPlanejamento"
        class="mb-0"
        :class="[AVISO, TOM.amber]"
        data-testid="sim-planejamento-hint"
      >
        {{ $t('RAMON.SIMULADOR.PLANEJAMENTO_PRECISA_CNIS') }}
      </p>
      <LeadPlanejamento
        v-else
        :key="calculoVersao"
        :lead="lead"
        :segurado-nome="seguradoNome"
      />
    </div>

    <p
      class="mb-0 italic"
      :class="[AVISO, TOM.amber]"
      data-testid="sim-disclaimer"
    >
      {{ $t('RAMON.SIMULADOR.DISCLAIMER') }}
    </p>
  </div>
</template>

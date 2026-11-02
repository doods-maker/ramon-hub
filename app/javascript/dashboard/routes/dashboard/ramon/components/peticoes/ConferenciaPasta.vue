<script setup>
// Conferência da petição apontada pela pasta do Drive: mostra o que o hub leu
// (recusas, alertas, avisos, dados), deixa corrigir e confirma. Confirmar salva
// os dados e vira rascunho; o backend confere tudo de novo. Enquanto a leitura
// está em andamento, pergunta ao servidor a cada 3 s.
import { computed, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import RamonPeticoesAPI from 'dashboard/api/ramonPeticoes';
import Button from 'dashboard/components-next/button/Button.vue';
import CamposPeticao from './CamposPeticao.vue';
import {
  dadosDoForm,
  erroPeticao,
  formDaPeticao,
  mensagemAlerta,
  mensagemAviso,
  mensagemProblema,
  mensagemRecusa,
  podeConfirmar,
  responsavelIncerto,
} from './helpers';
import { AVISO, CARTAO, TITULO, TOM } from '../../helpers/ui';

const props = defineProps({
  peticao: { type: Object, required: true },
  tribunais: { type: Array, default: () => [] },
});
const emit = defineEmits(['atualizado', 'confirmado']);

const { t } = useI18n();
const meuId = useMapGetter('getCurrentUserID');

const CAMPOS_DIST = [
  'partes',
  'classe',
  'assuntos',
  'valor_causa',
  'competencia',
];

const contato = ref(null);
const form = ref({});
const conferidos = ref([]); // alertas marcados como "conferi e está certo"
const ocupado = ref(''); // 'salvar' | 'confirmar' | 'reler'
const erro = ref('');

const leitura = computed(() => props.peticao.leitura || {});
const estado = computed(() => leitura.value.estado);
const recusas = computed(() => leitura.value.recusas || []);
const alertas = computed(() => props.peticao.alertas || []);
const avisos = computed(() => props.peticao.avisos || []);
const incertos = computed(() => leitura.value.incertos || []);
const distribuicao = computed(
  () => (props.peticao.inicial && leitura.value.campos?.inicial) || null
);
const principal = computed(() => props.peticao.arquivos.find(a => a.principal));
const exigeResponsavel = computed(() => responsavelIncerto(props.peticao));
const problemas = computed(() => {
  const tribunal = props.tribunais.find(
    tr => tr.chave === props.peticao.tribunal
  );
  return (props.peticao.problemas || []).map(p =>
    mensagemProblema(p, props.peticao.arquivos, tribunal, t)
  );
});
const liberado = computed(() => podeConfirmar(props.peticao, conferidos.value));

const reiniciar = p => {
  contato.value = p.contato;
  form.value = formDaPeticao(p, meuId.value);
};
// O form só recomeça com outra petição ou outro estado de leitura (ou após
// salvar/reler): um pacote novo vindo do PacoteEditor não apaga o que se digitou.
watch(
  [() => props.peticao.id, estado],
  ([id, novo], [idAntigo]) => {
    reiniciar(props.peticao);
    // Releitura: as marcações de "conferi" não valem para a leitura nova.
    if (novo === 'lendo' || id !== idAntigo) conferidos.value = [];
  },
  { immediate: true }
);

// Polling só enquanto lê; cada resposta nova da petição rearma o relógio.
let relogio = null;
const parar = () => clearTimeout(relogio);
const agendar = () => {
  parar();
  // eslint-disable-next-line no-use-before-define
  if (estado.value === 'lendo') relogio = setTimeout(consultar, 3000);
};
const consultar = async () => {
  try {
    const { data } = await RamonPeticoesAPI.show(props.peticao.id);
    emit('atualizado', data);
  } catch {
    // ponytail: falha de rede só tenta de novo; sem contador de tentativas
    agendar();
  }
};
watch(() => props.peticao, agendar, { immediate: true });
onUnmounted(parar);

const executar = async (nome, chamada, aoTerminar) => {
  ocupado.value = nome;
  erro.value = '';
  try {
    aoTerminar(await chamada());
  } catch (e) {
    erro.value = erroPeticao(e, t);
  } finally {
    ocupado.value = '';
  }
};

const salvarDados = () =>
  RamonPeticoesAPI.update(
    props.peticao.id,
    dadosDoForm(form.value, contato.value)
  );

const salvar = () =>
  executar(
    'salvar',
    async () => (await salvarDados()).data,
    data => {
      reiniciar(data);
      emit('atualizado', data);
    }
  );

const confirmar = () =>
  executar(
    'confirmar',
    async () => {
      await salvarDados();
      const { data } = await RamonPeticoesAPI.confirmar(
        props.peticao.id,
        alertas.value.length > 0
      );
      return data;
    },
    data => emit('confirmado', data)
  );

const reler = () =>
  executar(
    'reler',
    async () => (await RamonPeticoesAPI.relerPasta(props.peticao.id)).data,
    data => {
      conferidos.value = [];
      reiniciar(data);
      emit('atualizado', data);
    }
  );

// Abre a aba antes do download (senão o bloqueador de pop-up barra).
const abrirPeca = async () => {
  const aba = window.open('', '_blank');
  try {
    const blob = await RamonPeticoesAPI.baixarArquivo(principal.value.url);
    const href = URL.createObjectURL(blob);
    if (aba) {
      aba.opener = null;
      aba.location.href = href;
    }
    setTimeout(() => URL.revokeObjectURL(href), 60000);
  } catch (e) {
    aba?.close();
    erro.value = erroPeticao(e, t);
  }
};

const marcar = alerta => {
  conferidos.value = conferidos.value.includes(alerta)
    ? conferidos.value.filter(a => a !== alerta)
    : [...conferidos.value, alerta];
};
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="conferencia-pasta">
    <div
      v-if="estado === 'lendo'"
      class="animate-pulse"
      :class="[AVISO, TOM.slate]"
      data-testid="conferencia-lendo"
    >
      {{ t('RAMON.PETICOES.PASTA.LENDO') }}
    </div>

    <div
      v-else-if="estado === 'erro'"
      class="flex flex-wrap items-center justify-between gap-2"
      :class="[AVISO, TOM.ruby]"
      data-testid="conferencia-erro"
    >
      <span>{{ t('RAMON.PETICOES.PASTA.ERRO_LEITURA') }}</span>
      <Button
        xs
        faded
        ruby
        icon="i-lucide-refresh-cw"
        :is-loading="ocupado === 'reler'"
        :label="t('RAMON.PETICOES.PASTA.RELER')"
        @click="reler"
      />
    </div>

    <template v-else>
      <div
        v-if="recusas.length"
        :class="[AVISO, TOM.ruby]"
        data-testid="conferencia-recusas"
      >
        <p class="m-0 mb-1" :class="TITULO">
          {{ t('RAMON.PETICOES.PASTA.RECUSAS_TITULO') }}
        </p>
        <ul class="m-0 list-disc ps-4">
          <li v-for="r in recusas" :key="r">{{ mensagemRecusa(r, t) }}</li>
        </ul>
      </div>

      <div
        v-if="alertas.length"
        :class="[AVISO, TOM.amber]"
        data-testid="conferencia-alertas"
      >
        <p class="m-0 mb-1" :class="TITULO">
          {{ t('RAMON.PETICOES.PASTA.ALERTAS_TITULO') }}
        </p>
        <label
          v-for="a in alertas"
          :key="a"
          class="mb-1 flex items-start gap-2 last:mb-0"
        >
          <input
            type="checkbox"
            class="mt-0.5"
            :checked="conferidos.includes(a)"
            :data-testid="`conferencia-alerta-${a}`"
            @change="marcar(a)"
          />
          <span>
            {{ mensagemAlerta(a, t) }}
            <span class="font-semibold">
              {{ t('RAMON.PETICOES.PASTA.CONFERI') }}
            </span>
          </span>
        </label>
      </div>

      <div
        v-if="avisos.length"
        :class="[AVISO, TOM.amber]"
        data-testid="conferencia-avisos"
      >
        <ul class="m-0 list-disc ps-4">
          <li v-for="a in avisos" :key="a">{{ mensagemAviso(a, t) }}</li>
        </ul>
      </div>

      <section :class="CARTAO" class="flex flex-col gap-3">
        <p class="m-0" :class="TITULO">
          {{ t('RAMON.PETICOES.PASTA.DADOS') }}
        </p>
        <p v-if="incertos.length" class="m-0 text-xs text-n-slate-10">
          {{ t('RAMON.PETICOES.PASTA.INCERTOS_AJUDA') }}
        </p>
        <CamposPeticao
          v-model:form="form"
          v-model:contato="contato"
          :tribunais="tribunais"
          :incertos="incertos"
          :obrigatorios="false"
        >
          <template v-if="exigeResponsavel" #responsavel>
            <label class="flex items-center gap-2 text-xs text-n-slate-12">
              <input
                type="checkbox"
                :checked="conferidos.includes('responsavel')"
                data-testid="conferencia-responsavel"
                @change="marcar('responsavel')"
              />
              {{ t('RAMON.PETICOES.PASTA.CONFERI_RESPONSAVEL') }}
            </label>
          </template>
        </CamposPeticao>
      </section>

      <section
        v-if="distribuicao"
        :class="CARTAO"
        class="flex flex-col gap-2 text-sm"
        data-testid="conferencia-distribuicao"
      >
        <p class="m-0" :class="TITULO">
          {{ t('RAMON.PETICOES.PASTA.DISTRIBUICAO') }}
        </p>
        <dl
          class="m-0 grid grid-cols-1 gap-x-4 gap-y-1 sm:grid-cols-[10rem_1fr]"
        >
          <template v-for="campo in CAMPOS_DIST" :key="campo">
            <dt class="text-xs text-n-slate-10">
              {{ t(`RAMON.PETICOES.PASTA.DIST.${campo}`) }}
            </dt>
            <dd class="m-0 break-words text-n-slate-12">
              {{ [].concat(distribuicao[campo] || []).join('; ') || '—' }}
            </dd>
          </template>
        </dl>
      </section>
    </template>

    <div
      v-if="problemas.length && estado === 'lida'"
      :class="[AVISO, TOM.ruby]"
      data-testid="conferencia-problemas"
    >
      <p class="m-0 mb-1" :class="TITULO">
        {{ t('RAMON.PETICOES.PROBLEMAS_TITULO') }}
      </p>
      <ul class="m-0 list-disc ps-4">
        <li v-for="p in problemas" :key="p">{{ p }}</li>
      </ul>
    </div>

    <p
      v-if="erro"
      class="m-0 text-xs text-n-ruby-11"
      data-testid="conferencia-erro-acao"
    >
      {{ erro }}
    </p>

    <div class="flex flex-wrap justify-end gap-2">
      <Button
        v-if="principal && estado === 'lida'"
        sm
        faded
        slate
        icon="i-lucide-file-text"
        :label="t('RAMON.PETICOES.PASTA.ABRIR_PECA')"
        @click="abrirPeca"
      />
      <Button
        v-if="estado !== 'erro'"
        sm
        faded
        slate
        icon="i-lucide-refresh-cw"
        data-testid="conferencia-reler"
        :disabled="estado === 'lendo'"
        :is-loading="ocupado === 'reler'"
        :label="t('RAMON.PETICOES.PASTA.RELER')"
        @click="reler"
      />
      <template v-if="estado === 'lida'">
        <Button
          sm
          faded
          slate
          data-testid="conferencia-salvar"
          :is-loading="ocupado === 'salvar'"
          :label="t('RAMON.PETICOES.SALVAR')"
          @click="salvar"
        />
        <Button
          sm
          icon="i-lucide-check"
          data-testid="conferencia-confirmar"
          :disabled="!liberado"
          :is-loading="ocupado === 'confirmar'"
          :label="t('RAMON.PETICOES.PASTA.CONFIRMAR')"
          @click="confirmar"
        />
      </template>
    </div>
  </div>
</template>

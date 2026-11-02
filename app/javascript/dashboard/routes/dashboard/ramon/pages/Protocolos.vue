<script setup>
// Protocolos (Peticionamento · Fase 1): lista de petições e, com peticaoId,
// o detalhe — pacote, conferência contra a regra do tribunal, "Baixar todos"
// e o registro do protocolo feito à mão no tribunal. Acesso: admin ou time
// `advogados` (o backend decide; 401 = sem acesso).
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import RamonPeticoesAPI from 'dashboard/api/ramonPeticoes';
import Button from 'dashboard/components-next/button/Button.vue';
import ConfirmButton from 'dashboard/components-next/button/ConfirmButton.vue';
import RamonPageHeader from '../components/RamonPageHeader.vue';
import PeticaoForm from '../components/peticoes/PeticaoForm.vue';
import PacoteEditor from '../components/peticoes/PacoteEditor.vue';
import ConferenciaPasta from '../components/peticoes/ConferenciaPasta.vue';
import SeletorDrive from '../components/peticoes/SeletorDrive.vue';
import RegistrarProtocolo from '../components/peticoes/RegistrarProtocolo.vue';
import {
  baixarTodos,
  erroPeticao,
  mensagemProblema,
} from '../components/peticoes/helpers';
import { AVISO, CARTAO, CHIP, TITULO, TOM } from '../helpers/ui';

defineOptions({ name: 'RamonProtocolos' });

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { isAdmin } = useAdmin();
const meuId = useMapGetter('getCurrentUserID');

// Conferência, lista de pastas e apontar: só admin até o lançamento.
const pastaLiberada = isAdmin; // ponytail: trocar por ref(true) no lançamento
const STATUS = computed(() =>
  pastaLiberada.value
    ? ['conferencia', 'rascunho', 'protocolada']
    : ['rascunho', 'protocolada']
);
const TOM_STATUS = {
  conferencia: TOM.iris,
  rascunho: TOM.amber,
  protocolada: TOM.teal,
};
// O sino leva direto à conferência.
const status = ref(
  route.query.status === 'conferencia' && pastaLiberada.value
    ? 'conferencia'
    : 'rascunho'
);
const lista = ref([]);
const tribunais = ref([]);
const tipos = ref([]);
const pastas = ref([]); // pastas prontas da esteira (só na conferência)
const peticao = ref(null);
const loading = ref(true);
const erro = ref(''); // chave i18n do erro de carga
const form = ref(null); // 'nova' | 'editar'
const registrando = ref(false);
const apontando = ref(false); // seletor de pasta aberto

const peticaoId = computed(() => route.params.peticaoId);

const falhaCarga = e => {
  erro.value =
    e?.response?.status === 401
      ? 'RAMON.PETICOES.SEM_ACESSO'
      : 'RAMON.PETICOES.LOAD_ERROR';
};

const carregarLista = async () => {
  const { data } = await RamonPeticoesAPI.get({ status: status.value });
  lista.value = data.payload;
  tribunais.value = data.tribunais;
  tipos.value = data.tipos;
  pastas.value =
    pastaLiberada.value && status.value === 'conferencia'
      ? (await RamonPeticoesAPI.pastasProntas()).data.pastas
      : [];
};

// A lista também traz tribunais e tipos, que o detalhe usa.
const carregar = async () => {
  loading.value = true;
  erro.value = '';
  try {
    await carregarLista();
    peticao.value = peticaoId.value
      ? (await RamonPeticoesAPI.show(peticaoId.value)).data
      : null;
  } catch (e) {
    falhaCarga(e);
  } finally {
    loading.value = false;
  }
};

watch(peticaoId, carregar, { immediate: true });
watch(status, () => carregarLista().catch(falhaCarga));

const abrir = id =>
  router.push({ name: 'ramon_protocolo', params: { peticaoId: id } });
const voltar = () => router.push({ name: 'ramon_protocolos' });

const salvo = data => {
  const nova = form.value === 'nova';
  form.value = null;
  if (nova) abrir(data.id);
  else peticao.value = data;
};

// Rascunho ou conferência (o backend recusa a protocolada); volta para a lista.
const excluir = async () => {
  try {
    await RamonPeticoesAPI.delete(peticao.value.id);
    voltar();
  } catch (e) {
    useAlert(erroPeticao(e, t));
  }
};

const baixarPacote = () =>
  baixarTodos(peticao.value.arquivos, a =>
    RamonPeticoesAPI.baixarArquivo(a.url)
  ).catch(e => useAlert(erroPeticao(e, t)));

// Aponta a pasta; se já existe petição dela, abre essa.
const pastaEscolhida = async pastaId => {
  try {
    const { data } = await RamonPeticoesAPI.pelaPasta(pastaId);
    apontando.value = false;
    abrir(data.id);
  } catch (e) {
    const existente = e?.response?.data?.peticao_id;
    useAlert(erroPeticao(e, t));
    if (existente) {
      apontando.value = false;
      abrir(existente);
    }
  }
};

// A pasta mudou no Drive: refaz a leitura e a petição volta à conferência.
const relerPasta = async () => {
  try {
    peticao.value = (await RamonPeticoesAPI.relerPasta(peticao.value.id)).data;
  } catch (e) {
    useAlert(erroPeticao(e, t));
  }
};

const registrado = data => {
  registrando.value = false;
  peticao.value = data;
};

const tribunalDaPeticao = computed(() =>
  tribunais.value.find(tr => tr.chave === peticao.value?.tribunal)
);
const problemas = computed(() =>
  (peticao.value?.problemas || []).map(p =>
    mensagemProblema(p, peticao.value.arquivos, tribunalDaPeticao.value, t)
  )
);
const rascunho = computed(() => peticao.value?.status === 'rascunho');
const conferencia = computed(() => peticao.value?.status === 'conferencia');
// Durante a leitura (ou se falhou) ainda não há pacote para mostrar.
const pacoteVisivel = computed(
  () => !conferencia.value || peticao.value.leitura?.estado === 'lida'
);
// Só o responsável ou o admin registra (o backend também barra).
const podeRegistrar = computed(
  () => isAdmin.value || peticao.value?.responsavel?.id === meuId.value
);

const processo = p =>
  p.numero_processo || (p.inicial ? t('RAMON.PETICOES.INICIAL') : '—');
const cliente = p => p.contato?.name || '—';
// Prazo perto (até 2 dias úteis, vencido também) só importa no rascunho.
const corPrazo = p =>
  p.status === 'rascunho' && p.prazo_perto
    ? 'font-semibold text-n-ruby-11'
    : 'text-n-slate-11';
const dia = d => (d ? d.split('-').reverse().join('/') : '—');
const quando = iso => (iso ? new Date(iso).toLocaleString('pt-BR') : '—');

const segmento = ativo => [
  CHIP,
  ativo ? TOM.blue : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12',
];
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-background p-4 sm:p-8">
    <div class="mx-auto flex w-full max-w-6xl flex-col gap-5">
      <RamonPageHeader
        class="!mb-0"
        compact
        :title="t('RAMON.PETICOES.TITLE')"
        :subtitle="t('RAMON.PETICOES.SUBTITLE')"
      >
        <template v-if="!erro" #actions>
          <Button
            v-if="peticaoId"
            sm
            faded
            slate
            icon="i-lucide-arrow-left"
            :label="t('RAMON.PETICOES.VOLTAR')"
            @click="voltar"
          />
          <Button
            v-else-if="pastaLiberada"
            sm
            faded
            slate
            icon="i-lucide-folder-search"
            data-testid="protocolos-apontar"
            :label="t('RAMON.PETICOES.PASTA.APONTAR')"
            @click="apontando = true"
          />
          <Button
            v-if="!peticaoId"
            sm
            icon="i-lucide-plus"
            data-testid="protocolos-nova"
            :label="t('RAMON.PETICOES.NOVA')"
            @click="form = 'nova'"
          />
        </template>
      </RamonPageHeader>

      <div v-if="loading" class="h-64 animate-pulse rounded-xl bg-n-alpha-2" />
      <div v-else-if="erro" class="flex flex-col items-start gap-1 text-sm">
        <p class="m-0 text-n-ruby-11" data-testid="protocolos-erro">
          {{ t(erro) }}
        </p>
        <Button
          v-if="erro === 'RAMON.PETICOES.LOAD_ERROR'"
          link
          xs
          :label="t('RAMON.PETICOES.RETRY')"
          @click="carregar"
        />
      </div>

      <!-- Detalhe -->
      <template v-else-if="peticao">
        <section :class="CARTAO" class="flex flex-col gap-3">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="flex min-w-0 flex-col gap-1">
              <span class="flex flex-wrap items-center gap-2">
                <span class="font-mono text-base text-n-slate-12">{{
                  processo(peticao)
                }}</span>
                <span :class="[CHIP, TOM.slate]">{{
                  peticao.tribunal_nome
                }}</span>
                <span :class="[CHIP, TOM_STATUS[peticao.status]]">
                  {{ t(`RAMON.PETICOES.STATUS.${peticao.status}`) }}
                </span>
              </span>
              <span v-if="peticao.descricao" class="text-sm text-n-slate-11">{{
                peticao.descricao
              }}</span>
              <span
                class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-n-slate-10"
              >
                <span>
                  {{ t('RAMON.PETICOES.CLIENTE') }}
                  <span class="text-n-slate-12">{{ cliente(peticao) }}</span>
                </span>
                <span>
                  {{ t('RAMON.PETICOES.RESPONSAVEL') }}
                  <span class="text-n-slate-12">{{
                    peticao.responsavel.name
                  }}</span>
                </span>
                <span>
                  {{ t('RAMON.PETICOES.PRAZO') }}
                  <span class="font-mono" :class="corPrazo(peticao)">
                    {{ dia(peticao.prazo) }}
                  </span>
                </span>
              </span>
            </div>
            <div v-if="rascunho || conferencia" class="flex gap-2">
              <Button
                v-if="rascunho"
                xs
                faded
                slate
                icon="i-lucide-pencil"
                :label="t('RAMON.PETICOES.EDITAR')"
                @click="form = 'editar'"
              />
              <ConfirmButton
                size="xs"
                variant="faded"
                color="slate"
                confirm-color="ruby"
                icon="i-lucide-trash-2"
                data-testid="protocolo-excluir"
                :label="t('RAMON.PETICOES.EXCLUIR')"
                :confirm-label="t('RAMON.PETICOES.EXCLUIR_CONFIRMA')"
                @click="excluir"
              />
            </div>
          </div>

          <!-- Protocolada: registro + comprovante + pasta no Drive -->
          <div
            v-if="peticao.status === 'protocolada'"
            class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-n-slate-11"
            data-testid="protocolo-registrado"
          >
            <span>
              {{ t('RAMON.PETICOES.PROTOCOLADA_EM') }}
              <span class="font-mono">{{
                quando(peticao.protocolada_em)
              }}</span>
            </span>
            <span>
              {{ t('RAMON.PETICOES.NUMERO_EVENTO') }}
              <span class="font-mono">{{ peticao.numero_evento }}</span>
            </span>
            <a
              v-if="peticao.comprovante_url"
              :href="peticao.comprovante_url"
              class="text-n-blue-11 hover:underline"
            >
              {{ t('RAMON.PETICOES.VER_COMPROVANTE') }}
            </a>
            <a
              v-if="peticao.drive_pasta_id"
              :href="`https://drive.google.com/drive/folders/${peticao.drive_pasta_id}`"
              target="_blank"
              rel="noopener noreferrer"
              class="text-n-blue-11 hover:underline"
            >
              {{ t('RAMON.PETICOES.VER_NO_DRIVE') }}
            </a>
            <span v-else>{{
              t(
                peticao.drive_ligado
                  ? 'RAMON.PETICOES.ARQUIVANDO'
                  : 'RAMON.PETICOES.DRIVE_DESLIGADO'
              )
            }}</span>
          </div>
        </section>

        <ConferenciaPasta
          v-if="conferencia"
          :peticao="peticao"
          :tribunais="tribunais"
          @atualizado="peticao = $event"
          @confirmado="peticao = $event"
        />

        <PacoteEditor
          v-if="pacoteVisivel"
          :peticao="peticao"
          :tipos="tipos"
          :pacote-fechado="!!peticao.pela_pasta"
          @atualizar="peticao = $event"
        />

        <template v-if="rascunho">
          <div
            v-if="problemas.length"
            :class="[AVISO, TOM.ruby]"
            data-testid="protocolo-problemas"
          >
            <p class="m-0 mb-1" :class="TITULO">
              {{ t('RAMON.PETICOES.PROBLEMAS_TITULO') }}
            </p>
            <ul class="m-0 list-disc ps-4">
              <li v-for="p in problemas" :key="p">{{ p }}</li>
            </ul>
          </div>
          <p
            v-else
            class="m-0"
            :class="[AVISO, TOM.teal]"
            data-testid="protocolo-pronto"
          >
            {{ t('RAMON.PETICOES.PACOTE_PRONTO') }}
          </p>

          <div class="flex flex-wrap justify-end gap-2">
            <Button
              v-if="peticao.pela_pasta"
              sm
              faded
              slate
              icon="i-lucide-refresh-cw"
              data-testid="protocolo-reler"
              :label="t('RAMON.PETICOES.PASTA.RELER')"
              @click="relerPasta"
            />
            <Button
              sm
              faded
              slate
              icon="i-lucide-download"
              data-testid="protocolo-baixar"
              :disabled="problemas.length > 0"
              :label="t('RAMON.PETICOES.BAIXAR_TODOS')"
              @click="baixarPacote"
            />
            <Button
              v-if="podeRegistrar"
              sm
              icon="i-lucide-stamp"
              data-testid="protocolo-registrar"
              :disabled="problemas.length > 0"
              :label="t('RAMON.PETICOES.REGISTRAR')"
              @click="registrando = true"
            />
          </div>
        </template>
      </template>

      <!-- Lista -->
      <template v-else>
        <div
          class="flex flex-wrap items-center gap-0.5 self-start rounded-lg border border-n-weak p-0.5"
        >
          <button
            v-for="s in STATUS"
            :key="s"
            type="button"
            :data-testid="`protocolos-filtro-${s}`"
            :class="segmento(status === s)"
            @click="status = s"
          >
            {{ t(`RAMON.PETICOES.FILTRO.${s}`) }}
          </button>
        </div>

        <section
          v-if="pastas.length"
          :class="CARTAO"
          class="flex flex-col gap-2"
          data-testid="protocolos-pastas"
        >
          <h2 class="m-0" :class="TITULO">
            {{ t('RAMON.PETICOES.PASTA.PRONTAS_TITULO') }}
          </h2>
          <button
            v-for="pasta in pastas"
            :key="pasta.id"
            type="button"
            data-testid="protocolos-pasta"
            class="flex flex-wrap items-center justify-between gap-2 rounded-lg px-2 py-1.5 text-start text-sm hover:bg-n-alpha-2"
            @click="pastaEscolhida(pasta.drive_pasta_id)"
          >
            <span class="text-n-slate-12">{{
              pasta.titulo || t('RAMON.PETICOES.PASTA.SEM_TITULO')
            }}</span>
            <span class="text-xs text-n-slate-10">{{
              pasta.responsavel?.name ||
              t('RAMON.PETICOES.PASTA.SEM_RESPONSAVEL')
            }}</span>
          </button>
        </section>

        <p
          v-if="!lista.length"
          :class="CARTAO"
          class="m-0 py-6 text-center text-sm text-n-slate-10"
        >
          {{ t('RAMON.PETICOES.VAZIO') }}
        </p>
        <div v-else :class="CARTAO" class="overflow-x-auto !p-0">
          <table class="w-full border-separate border-spacing-0 text-sm">
            <thead>
              <tr>
                <th
                  v-for="col in [
                    'PROCESSO',
                    'CLIENTE',
                    'TRIBUNAL',
                    'RESPONSAVEL',
                    'PRAZO',
                    'STATUS_COL',
                  ]"
                  :key="col"
                  class="border-b border-n-weak px-3 py-2 text-left"
                  :class="TITULO"
                >
                  {{ t(`RAMON.PETICOES.${col}`) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="p in lista"
                :key="p.id"
                data-testid="protocolos-linha"
                class="cursor-pointer hover:bg-n-alpha-2"
                @click="abrir(p.id)"
              >
                <td
                  class="border-b border-n-weak px-3 py-2 font-mono text-xs text-n-slate-12"
                >
                  {{ processo(p) }}
                </td>
                <td class="border-b border-n-weak px-3 py-2 text-n-slate-12">
                  {{ cliente(p) }}
                </td>
                <td class="border-b border-n-weak px-3 py-2 text-n-slate-11">
                  {{ p.tribunal_nome }}
                </td>
                <td class="border-b border-n-weak px-3 py-2 text-n-slate-11">
                  {{ p.responsavel.name }}
                </td>
                <td
                  class="border-b border-n-weak px-3 py-2 font-mono text-xs"
                  :class="corPrazo(p)"
                >
                  {{ dia(p.prazo) }}
                </td>
                <td class="border-b border-n-weak px-3 py-2">
                  <span :class="[CHIP, TOM_STATUS[p.status]]">
                    {{ t(`RAMON.PETICOES.STATUS.${p.status}`) }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </div>

    <PeticaoForm
      v-if="form"
      :peticao="form === 'editar' ? peticao : null"
      :tribunais="tribunais"
      @salvo="salvo"
      @cancel="form = null"
    />
    <SeletorDrive
      v-if="apontando"
      modo-pasta
      @pasta-escolhida="pastaEscolhida"
      @cancel="apontando = false"
    />
    <RegistrarProtocolo
      v-if="registrando"
      :peticao-id="peticao.id"
      @registrado="registrado"
      @cancel="registrando = false"
    />
  </div>
</template>

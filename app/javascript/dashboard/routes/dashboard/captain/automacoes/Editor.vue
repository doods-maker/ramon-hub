<script setup>
// Editor de um fluxo (B2, mockup tela 2): barra (Ligado + limite, Versões,
// Testar com um lead…, Publicar vN), quadro vertical, paleta e painel do passo.
// Sem passo selecionado, o painel mostra as execuções recentes do fluxo.
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router';
import { onClickOutside } from '@vueuse/core';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ConfirmModal from 'dashboard/routes/dashboard/ramon/components/ConfirmModal.vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import {
  AVISO,
  CAMPO,
  CHIP,
  LINHA,
  MENU,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import {
  adicionarPasso,
  duplicarPasso,
  idDoErro,
  ligar,
  podarSetas,
  quando,
  trocarConfig,
} from './fluxo';
import { useFluxoEditor } from './useFluxoEditor';
import Quadro from './Quadro.vue';
import Paleta from './Paleta.vue';
import PainelPasso from './PainelPasso.vue';
import TestarComLead from './TestarComLead.vue';

defineOptions({ name: 'CaptainAutomacaoEditor' });

const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();
const etapas = useMapGetter('leadConfig/getStages');
const pessoas = useMapGetter('agents/getAgents');
const teses = useMapGetter('theses/getTheses');

const {
  fluxo,
  nodes,
  edges,
  sujo,
  salvando,
  errosFront,
  errosServidor,
  mostrarErros,
  nosComErro,
  carregar,
  salvar,
  atualizar,
  publicar,
  ensaiar,
  rodar,
} = useFluxoEditor();

const selecionado = ref(null);
const paleta = ref(false);
const versoesAbertas = ref(false);
const versoesRef = ref(null);
const testando = ref(false);
const ocupadoTeste = ref(false);
const errosTeste = ref([]);
const excluindo = ref(false);
const execucoes = ref([]);
const publicando = ref(false);
onClickOutside(versoesRef, () => {
  versoesAbertas.value = false;
});

const fluxoId = computed(() => Number(route.params.fluxoId));
const carregarExecucoes = async () => {
  const { data } = await RamonFluxosAPI.execucoes(fluxoId.value);
  execucoes.value = data.payload.slice(0, 20);
};

// Não perde a última edição: avisa ao fechar a aba e salva ao sair da tela.
const avisarSaida = e => {
  if (sujo.value) e.preventDefault();
};
const erroCarga = ref(false);
const abrirFluxo = async () => {
  erroCarga.value = false;
  try {
    await carregar(fluxoId.value);
  } catch (e) {
    erroCarga.value = true;
    return;
  }
  carregarExecucoes();
};
onMounted(() => {
  window.addEventListener('beforeunload', avisarSaida);
  if (!etapas.value.length) store.dispatch('leadConfig/get');
  if (!pessoas.value.length) store.dispatch('agents/get');
  if (!teses.value.length) store.dispatch('theses/get');
  abrirFluxo();
});
// fluxo do sistema (D7): só leitura — o back recusa salvar, publicar e rodar
const somenteLeitura = computed(() => fluxo.value?.origem === 'sistema');
// excluído: não há mais rascunho para salvar (o save daria 404 e prenderia a tela)
const deletado = ref(false);
onBeforeRouteLeave(async () => {
  if (deletado.value || !sujo.value) return true;
  try {
    await salvar();
    return true;
  } catch (e) {
    useAlert(t(`${K}.EDITOR.ERRO_SALVAR`));
    return false;
  }
});
onBeforeUnmount(() => {
  window.removeEventListener('beforeunload', avisarSaida);
  if (!deletado.value && sujo.value) salvar().catch(() => {});
});

const noSelecionado = computed(
  () => nodes.value.find(n => n.id === selecionado.value) || null
);
// Delete/Backspace apaga direto no v-model do quadro: solta a seleção que sumiu.
watch(nodes, lista => {
  if (selecionado.value && !lista.some(n => n.id === selecionado.value))
    selecionado.value = null;
});

const textoErro = e =>
  e.codigo === 'FALTA'
    ? t(`${K}.ERROS.FALTA`, {
        campo: t(`${K}.CAMPOS_OBRIGATORIOS.${e.params.campo}`),
      })
    : t(`${K}.ERROS.${e.codigo}`, e.params);
const errosDoNo = computed(() => {
  if (!noSelecionado.value) return [];
  const id = noSelecionado.value.id;
  return [
    ...(mostrarErros.value
      ? errosFront.value.filter(e => e.no === id).map(textoErro)
      : []),
    ...errosServidor.value.filter(m => idDoErro(m) === id),
  ];
});
const errosGerais = computed(() => [
  ...(mostrarErros.value
    ? errosFront.value.filter(e => !e.no).map(textoErro)
    : []),
  ...errosServidor.value.filter(m => !idDoErro(m)),
]);

// quadro — toda seta nova passa pelo ligar() (recusa laço/próprio passo, troca a da porta)
const conectar = conexao => {
  const novas = ligar(edges.value, conexao);
  if (novas) edges.value = novas;
};
const abrirPaleta = id => {
  selecionado.value = id;
  paleta.value = true;
};
const adicionar = item => {
  const r = adicionarPasso(nodes.value, edges.value, item, selecionado.value);
  nodes.value = r.nodes;
  edges.value = r.edges;
  selecionado.value = r.id;
  paleta.value = false;
};
const mudarConfig = config => {
  const id = selecionado.value;
  nodes.value = trocarConfig(nodes.value, id, config);
  const f = podarSetas(
    edges.value,
    nodes.value.find(n => n.id === id)
  );
  if (f.length !== edges.value.length) edges.value = f;
};
const duplicar = () => {
  const r = duplicarPasso(nodes.value, selecionado.value);
  nodes.value = r.nodes;
  selecionado.value = r.id;
};
const excluirPasso = () => {
  const id = selecionado.value;
  // o gatilho é único: não se apaga
  if (noSelecionado.value?.data.tipo === 'gatilho') return;
  nodes.value = nodes.value.filter(n => n.id !== id);
  edges.value = edges.value.filter(e => e.source !== id && e.target !== id);
  selecionado.value = null;
};

// barra
const seloRascunho = computed(() =>
  fluxo.value?.versao
    ? t(`${K}.EDITOR.SELO_PUBLICADA`, { versao: fluxo.value.versao })
    : t(`${K}.EDITOR.SELO_NUNCA`)
);
// re-render devolve aos campos (nome, limite) o valor salvo
const desfazerCampos = () => {
  fluxo.value = { ...fluxo.value };
};
const salvarSeguro = async attrs => {
  try {
    await atualizar(attrs);
  } catch (e) {
    useAlert(t(`${K}.EDITOR.ERRO_SALVAR`));
    desfazerCampos();
  }
};
const mudarLimite = valor =>
  salvarSeguro({ limite_dia: valor ? Number(valor) : null });
const mudarNome = nome =>
  nome.trim() ? salvarSeguro({ nome: nome.trim() }) : desfazerCampos();
const clicarPublicar = async () => {
  publicando.value = true;
  try {
    const versao = await publicar();
    if (versao) useAlert(t(`${K}.EDITOR.PUBLICADO`, { versao }));
  } catch (e) {
    useAlert(t(`${K}.EDITOR.ERRO_SALVAR`));
  } finally {
    publicando.value = false;
  }
};

// testar
const podeRodar = computed(
  () =>
    fluxo.value?.gatilho_tipo === 'manual' &&
    Boolean(fluxo.value?.versao) &&
    fluxo.value?.ativo
);
const abrirExecucao = execId =>
  router.push(
    accountScopedRoute('captain_automacoes_execucao', {
      fluxoId: fluxoId.value,
      execId,
    })
  );
const testar = async (acao, alvo) => {
  ocupadoTeste.value = true;
  errosTeste.value = [];
  try {
    const exec = acao === 'rodar' ? await rodar(alvo) : await ensaiar(alvo);
    abrirExecucao(exec.id);
  } catch (e) {
    const dados = e.response?.data || {};
    if (dados.erro === 'FLUXO_NAO_RODOU')
      errosTeste.value = [t(`${K}.TESTAR.NAO_RODOU`)];
    else errosTeste.value = dados.erros || [t(`${K}.TESTAR.ERRO`)];
  } finally {
    ocupadoTeste.value = false;
  }
};

const excluirFluxo = async () => {
  try {
    await RamonFluxosAPI.delete(fluxoId.value);
  } catch (e) {
    useAlert(t(`${K}.EDITOR.ERRO_SALVAR`));
    excluindo.value = false;
    return;
  }
  deletado.value = true;
  router.push(accountScopedRoute('captain_automacoes_index'));
};

const corStatus = {
  concluida: TOM.teal,
  esperando: TOM.amber,
  falhou: TOM.ruby,
  cancelada: TOM.slate,
  rodando: TOM.blue,
};
const haQuanto = iso => dynamicTime(Math.floor(new Date(iso).getTime() / 1000));
</script>

<template>
  <section class="flex flex-col w-full h-full bg-n-surface-1">
    <div
      class="flex h-14 shrink-0 items-center gap-2.5 border-b border-n-weak pl-5 pr-4"
    >
      <router-link
        :to="accountScopedRoute('captain_automacoes_index')"
        class="flex items-center gap-1 text-[13px] text-n-slate-10 hover:text-n-slate-12"
      >
        <i class="i-lucide-chevron-left size-4" />
        {{ t(`${K}.EDITOR.VOLTAR`) }}
      </router-link>
      <template v-if="fluxo">
        <input
          class="reset-base min-w-0 max-w-xs flex-1 bg-transparent text-[15px] font-semibold text-n-slate-12 outline-none"
          :aria-label="t(`${K}.EDITOR.NOME`)"
          :readonly="somenteLeitura"
          :value="fluxo.nome"
          @change="mudarNome($event.target.value)"
        />
        <span
          v-if="somenteLeitura"
          :class="[CHIP, TOM.slate]"
          class="font-mono"
        >
          {{ t(`${K}.EDITOR.SOMENTE_LEITURA`) }}
        </span>
        <span v-else :class="[CHIP, TOM.slate]" class="font-mono">
          {{ salvando ? t(`${K}.EDITOR.SALVANDO`) : seloRascunho }}
        </span>

        <div class="ml-auto flex items-center gap-2">
          <span
            v-if="!somenteLeitura"
            class="flex items-center gap-2 border-r border-n-weak pr-2.5 text-[12.5px] text-n-slate-11"
          >
            <span
              :title="fluxo.versao ? '' : t(`${K}.PUBLIQUE_ANTES`)"
              :class="fluxo.versao ? '' : 'opacity-50'"
            >
              <Switch
                :disabled="!fluxo.versao"
                :model-value="fluxo.ativo"
                @update:model-value="v => salvarSeguro({ ativo: v })"
              />
            </span>
            {{ t(`${K}.EDITOR.LIGADO`) }} · {{ t(`${K}.EDITOR.LIMITE`) }}
            <input
              :class="CAMPO"
              class="!h-7 !w-14 !px-1.5 text-center"
              type="number"
              min="1"
              :value="fluxo.limite_dia ?? ''"
              @change="mudarLimite($event.target.value)"
            />
            {{ t(`${K}.EDITOR.POR_DIA`) }}
          </span>
          <div ref="versoesRef" class="relative">
            <Button
              outline
              slate
              sm
              icon="i-lucide-history"
              :label="t(`${K}.EDITOR.VERSOES`)"
              @click="versoesAbertas = !versoesAbertas"
            />
            <div
              v-if="versoesAbertas"
              :class="MENU"
              class="absolute right-0 top-full z-20 mt-1 w-56"
            >
              <p
                v-if="!fluxo.versoes?.length"
                class="p-2 text-xs text-n-slate-10"
              >
                {{ t(`${K}.EDITOR.SEM_VERSOES`) }}
              </p>
              <div
                v-for="v in fluxo.versoes"
                :key="v.numero"
                class="flex items-center justify-between px-2 py-1.5 text-[13px] text-n-slate-12"
              >
                {{
                  t(`${K}.EDITOR.VERSAO_ITEM`, {
                    numero: v.numero,
                    data: quando(v.created_at),
                  })
                }}
                <span
                  v-if="v.numero === fluxo.versao"
                  :class="[CHIP, TOM.teal]"
                >
                  {{ t(`${K}.EDITOR.NO_AR`) }}
                </span>
              </div>
            </div>
          </div>
          <Button
            v-if="!somenteLeitura"
            outline
            slate
            sm
            icon="i-lucide-flask-conical"
            :label="t(`${K}.EDITOR.TESTAR`)"
            @click="testando = true"
          />
          <Button
            v-if="!somenteLeitura"
            sm
            icon="i-lucide-upload"
            :label="
              t(`${K}.EDITOR.PUBLICAR`, { versao: (fluxo.versao || 0) + 1 })
            "
            :is-loading="publicando"
            @click="clicarPublicar"
          />
          <Button
            v-if="fluxo.origem !== 'sistema'"
            ghost
            ruby
            sm
            icon="i-lucide-trash-2"
            :title="t(`${K}.EDITOR.EXCLUIR_FLUXO`)"
            @click="excluindo = true"
          />
        </div>
      </template>
    </div>

    <div v-if="erroCarga" class="p-6 text-sm text-n-ruby-11">
      {{ t('CAPTAIN_RAMON.LOAD_ERROR') }}
      <button
        type="button"
        class="ml-1 text-n-blue-11 hover:underline"
        @click="abrirFluxo"
      >
        {{ t('CAPTAIN_RAMON.RETRY') }}
      </button>
    </div>

    <div v-else class="flex min-h-0 flex-1">
      <div class="relative min-w-0 flex-1">
        <Quadro
          v-if="fluxo"
          v-model:nodes="nodes"
          v-model:edges="edges"
          :somente-leitura="somenteLeitura"
          :selecionado="selecionado"
          :erros="nosComErro"
          @selecionar="id => (selecionado = somenteLeitura ? null : id)"
          @conectar="conectar"
          @adicionar="abrirPaleta"
        />
        <Button
          v-if="fluxo && !somenteLeitura"
          class="!absolute left-3.5 top-3.5 z-10"
          faded
          blue
          sm
          icon="i-lucide-plus"
          :label="t(`${K}.EDITOR.ADICIONAR`)"
          @click="paleta = true"
        />
        <Paleta v-if="paleta" @escolher="adicionar" @fechar="paleta = false" />
        <div
          v-if="errosGerais.length || (mostrarErros && nosComErro.size)"
          :class="[AVISO, TOM.ruby]"
          class="absolute left-1/2 top-3.5 z-10 max-w-lg -translate-x-1/2 shadow-sm"
          data-testid="editor-erros"
        >
          <b class="block">{{ t(`${K}.EDITOR.ERROS_TITULO`) }}</b>
          <p v-for="e in errosGerais" :key="e">{{ e }}</p>
          <p v-if="nosComErro.size">
            {{ t(`${K}.EDITOR.ERROS_NOS`, { n: nosComErro.size }) }}
          </p>
        </div>
      </div>

      <aside
        class="flex w-[340px] shrink-0 flex-col border-l border-n-weak bg-n-solid-1"
      >
        <PainelPasso
          v-if="noSelecionado"
          :key="noSelecionado.id"
          :no="noSelecionado"
          :erros="errosDoNo"
          @update:config="mudarConfig"
          @duplicar="duplicar"
          @excluir="excluirPasso"
        />
        <div v-else class="flex min-h-0 flex-1 flex-col px-4 py-3.5">
          <p class="mb-3 text-xs text-n-slate-10">
            {{ t(`${K}.EDITOR.SELECIONE`) }}
          </p>
          <h4
            class="mb-2 text-[11px] font-medium uppercase tracking-wider text-n-slate-10"
          >
            {{ t(`${K}.EDITOR.EXECUCOES`) }}
          </h4>
          <p v-if="!execucoes.length" class="text-xs text-n-slate-10">
            {{ t(`${K}.EDITOR.SEM_EXECUCOES`) }}
          </p>
          <div class="flex flex-col overflow-y-auto">
            <button
              v-for="ex in execucoes"
              :key="ex.id"
              type="button"
              :class="LINHA"
              class="flex items-center gap-2"
              @click="abrirExecucao(ex.id)"
            >
              <span :class="[CHIP, corStatus[ex.status]]">{{
                t(`${K}.STATUS.${ex.status}`)
              }}</span>
              <span class="min-w-0 flex-1 truncate">{{ ex.alvo_nome }}</span>
              <span
                v-if="ex.ensaio"
                class="font-mono text-[10.5px] text-n-slate-10"
              >
                {{ t(`${K}.EXECUCAO.ENSAIO`) }}
              </span>
              <span class="font-mono text-[11px] text-n-slate-10">{{
                haQuanto(ex.created_at)
              }}</span>
            </button>
          </div>
        </div>
      </aside>
    </div>

    <TestarComLead
      v-if="testando"
      :erros="errosTeste"
      :ocupado="ocupadoTeste"
      :pode-rodar="podeRodar"
      @ensaiar="alvo => testar('ensaiar', alvo)"
      @rodar="alvo => testar('rodar', alvo)"
      @fechar="testando = false"
    />
    <ConfirmModal
      v-if="excluindo"
      :title="t(`${K}.EDITOR.EXCLUIR_TITULO`)"
      :message="t(`${K}.EDITOR.EXCLUIR_MSG`)"
      :confirm-label="t(`${K}.EDITOR.EXCLUIR_FLUXO`)"
      @confirm="excluirFluxo"
      @cancel="excluindo = false"
    />
  </section>
</template>

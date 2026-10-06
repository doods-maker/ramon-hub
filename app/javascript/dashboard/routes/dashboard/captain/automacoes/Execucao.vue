<script setup>
// Execução / ensaio (B2, mockup tela 3): o desenho EM QUE a execução rodou,
// só leitura, caminho aceso (teal), passo onde espera em âmbar, erro em ruby;
// à direita o alvo e a trilha com horários.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import { AVISO, CHIP, TOM } from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { PASSOS, caminhoAceso, paraVueFlow, quando } from './fluxo';
import Quadro from './Quadro.vue';

defineOptions({ name: 'CaptainAutomacaoExecucao' });

const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { accountScopedRoute } = useAccount();

const fluxo = ref(null);
const exec = ref(null);
const erro = ref(false);
const nodes = ref([]);
const edges = ref([]);

const fluxoId = computed(() => Number(route.params.fluxoId));
const caminho = computed(() =>
  caminhoAceso(exec.value?.trilha, exec.value?.grafo)
);
const errosTrilha = computed(
  () => new Set((exec.value?.trilha || []).filter(l => l.erro).map(l => l.no))
);
const saidasTomadas = computed(() =>
  Object.fromEntries((exec.value?.trilha || []).map(l => [l.no, l.saida]))
);
const atual = computed(() =>
  exec.value?.status === 'esperando' ? exec.value.no_atual : null
);

onMounted(async () => {
  try {
    const [f, e] = await Promise.all([
      RamonFluxosAPI.show(fluxoId.value),
      RamonFluxosAPI.execucao(fluxoId.value, route.params.execId),
    ]);
    fluxo.value = f.data;
    exec.value = e.data;
    const vf = paraVueFlow(e.data.grafo);
    const acesas = caminhoAceso(e.data.trilha, e.data.grafo).setas;
    nodes.value = vf.nodes;
    edges.value = vf.edges.map(ed =>
      acesas.has(ed.id) ? { ...ed, class: 'aceso' } : ed
    );
  } catch (err) {
    erro.value = true;
  }
});

const COR_STATUS = {
  concluida: TOM.teal,
  esperando: TOM.amber,
  falhou: TOM.ruby,
  cancelada: TOM.slate,
  rodando: TOM.blue,
};
const noDe = id => (exec.value?.grafo?.nos || []).find(n => n.id === id);
const tituloLinha = linha => {
  if (linha.no === 'cancelado') return t(`${K}.EXECUCAO.CANCELADO`);
  const no = noDe(linha.no);
  if (no?.config?.rotulo) return no.config.rotulo;
  if (linha.tipo === 'gatilho')
    return t(`${K}.GATILHOS.${no?.config?.tipo}`, t(`${K}.PASSOS.gatilho`));
  return PASSOS[linha.tipo] ? t(`${K}.PASSOS.${linha.tipo}`) : linha.tipo;
};
const corLinha = linha => {
  if (linha.erro) return 'bg-n-ruby-9';
  if (linha.no === 'cancelado') return 'bg-n-slate-8';
  if (linha.tipo === 'esperar') return 'bg-n-amber-9';
  return 'bg-n-teal-9';
};
const iniciais = nome =>
  (nome || '?')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map(p => p[0].toUpperCase())
    .join('');
const intervalo = computed(() =>
  t(`${K}.EXECUCAO.INTERVALO`, {
    versao: exec.value.versao
      ? t(`${K}.EXECUCAO.VERSAO`, { versao: exec.value.versao })
      : t(`${K}.EXECUCAO.RASCUNHO`),
    inicio: quando(exec.value.created_at),
    fim: quando(exec.value.updated_at),
  })
);

const voltarEditar = () =>
  router.push(
    accountScopedRoute('captain_automacoes_editor', { fluxoId: fluxoId.value })
  );
const abrirAlvo = () => {
  if (exec.value.lead_id) {
    router.push(accountScopedRoute('ramon_funil'));
    store.dispatch('leads/select', exec.value.lead_id);
  } else {
    router.push(
      accountScopedRoute('inbox_conversation', {
        conversation_id: exec.value.conversation_display_id,
      })
    );
  }
};
const verConversa = () =>
  router.push(
    accountScopedRoute('inbox_conversation', {
      conversation_id: exec.value.conversation_display_id,
    })
  );
</script>

<template>
  <section class="flex flex-col w-full h-full bg-n-surface-1">
    <div
      class="flex h-14 shrink-0 items-center gap-2.5 border-b border-n-weak pl-5 pr-4"
    >
      <button
        type="button"
        class="flex items-center gap-1 text-[13px] text-n-slate-10 hover:text-n-slate-12"
        @click="voltarEditar"
      >
        <i class="i-lucide-chevron-left size-4" />
        {{ fluxo?.nome }}
      </button>
      <template v-if="exec">
        <h1 class="text-[15px] font-semibold text-n-slate-12">
          {{ t(`${K}.EXECUCAO.TITULO`, { id: exec.id }) }}
        </h1>
        <span :class="[CHIP, COR_STATUS[exec.status]]" class="font-mono">{{
          t(`${K}.STATUS.${exec.status}`)
        }}</span>
        <span v-if="exec.ensaio" :class="[CHIP, TOM.iris]" class="font-mono">{{
          t(`${K}.EXECUCAO.ENSAIO`)
        }}</span>
      </template>
      <Button
        class="ml-auto"
        data-testid="voltar-editar"
        outline
        slate
        sm
        icon="i-lucide-pencil"
        :label="t(`${K}.EXECUCAO.VOLTAR_EDITAR`)"
        @click="voltarEditar"
      />
    </div>

    <p v-if="erro" class="p-6 text-sm text-n-ruby-11">
      {{ t(`${K}.EXECUCAO.NAO_ACHEI`) }}
    </p>

    <div v-else-if="exec" class="flex min-h-0 flex-1">
      <div class="relative min-w-0 flex-1">
        <Quadro
          v-model:nodes="nodes"
          v-model:edges="edges"
          somente-leitura
          :acesos="caminho.nos"
          :atual="atual"
          :erros="errosTrilha"
          :saidas-tomadas="saidasTomadas"
        />
      </div>

      <aside
        class="flex w-[340px] shrink-0 flex-col border-l border-n-weak bg-n-solid-1"
      >
        <div
          class="flex items-center gap-2.5 border-b border-n-weak px-4 py-3.5"
        >
          <span
            class="grid size-7 place-items-center rounded-lg"
            :class="TOM.teal"
          >
            <i class="i-lucide-route size-4" />
          </span>
          <div>
            <b class="block text-sm font-semibold text-n-slate-12">{{
              t(`${K}.EXECUCAO.CAMINHO`)
            }}</b>
            <span class="font-mono text-xs text-n-slate-10">{{
              intervalo
            }}</span>
          </div>
        </div>

        <div class="flex-1 overflow-y-auto px-4 py-3.5">
          <div
            class="mb-4 flex items-center gap-2.5 rounded-xl border border-n-weak px-3 py-2.5"
          >
            <span
              class="grid size-7 place-items-center rounded-full bg-n-alpha-2 text-[11px] font-semibold text-n-slate-12"
            >
              {{ iniciais(exec.alvo_nome) }}
            </span>
            <div class="min-w-0">
              <b
                class="block truncate text-[13.5px] font-medium text-n-slate-12"
              >
                {{ exec.alvo_nome }}
              </b>
              <span class="text-xs text-n-slate-11">
                {{
                  exec.lead_id
                    ? t(`${K}.EXECUCAO.LEAD_N`, { id: exec.lead_id })
                    : t(`${K}.EXECUCAO.CONVERSA_N`, {
                        id: exec.conversation_display_id,
                      })
                }}
              </span>
            </div>
            <Button
              class="ml-auto"
              outline
              slate
              xs
              :label="t(`${K}.EXECUCAO.ABRIR`)"
              @click="abrirAlvo"
            />
          </div>

          <ol class="relative">
            <li
              v-for="(linha, i) in exec.trilha"
              :key="i"
              data-testid="trilha-item"
              class="relative pb-4 pl-6 last:pb-0"
            >
              <span
                class="absolute left-[5px] top-1.5 size-[9px] rounded-full"
                :class="corLinha(linha)"
              />
              <span
                v-if="i < exec.trilha.length - 1"
                class="absolute bottom-0 left-[9px] top-[18px] w-px bg-n-slate-6"
              />
              <span class="float-right font-mono text-xs text-n-slate-10">{{
                quando(linha.em)
              }}</span>
              <b class="text-[13px] font-medium text-n-slate-12">{{
                tituloLinha(linha)
              }}</b>
              <p
                class="mt-0.5 text-[12.5px] text-n-slate-11"
                :class="linha.erro ? 'text-n-ruby-11' : ''"
              >
                {{ linha.resumo }}
              </p>
            </li>
          </ol>

          <p
            v-if="exec.status === 'esperando' && exec.retomar_em"
            :class="[AVISO, TOM.amber]"
            class="mt-4"
          >
            {{
              t(`${K}.EXECUCAO.ESPERANDO_ATE`, {
                quando: quando(exec.retomar_em),
              })
            }}
          </p>
          <p v-if="exec.erro" :class="[AVISO, TOM.ruby]" class="mt-4">
            {{ t(`${K}.EXECUCAO.ERRO`, { erro: exec.erro }) }}
          </p>
        </div>

        <div
          v-if="exec.conversation_display_id"
          class="border-t border-n-weak px-4 py-3"
        >
          <Button
            outline
            slate
            sm
            icon="i-lucide-message-square"
            :label="t(`${K}.EXECUCAO.VER_CONVERSA`)"
            @click="verConversa"
          />
        </div>
      </aside>
    </div>
  </section>
</template>

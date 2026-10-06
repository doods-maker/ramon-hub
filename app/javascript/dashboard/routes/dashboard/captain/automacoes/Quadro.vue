<script setup>
// Casca do Vue Flow (spec §7): fluxo de cima para baixo, minimapa, zoom e
// fundo pontilhado como o mockup. Editor = arrasta/liga/apaga; execução =
// só leitura com o caminho aceso (acesos != null).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { ConnectionMode, VueFlow, Panel, useVueFlow } from '@vue-flow/core';
import { MiniMap } from '@vue-flow/minimap';
import '@vue-flow/core/dist/style.css';
import '@vue-flow/minimap/dist/style.css';
import Button from 'dashboard/components-next/button/Button.vue';
import NoPasso from './NoPasso.vue';

const props = defineProps({
  somenteLeitura: { type: Boolean, default: false },
  selecionado: { type: String, default: null },
  erros: { type: Object, default: () => new Set() },
  acesos: { type: Object, default: null },
  atual: { type: String, default: null },
  saidasTomadas: { type: Object, default: () => ({}) },
});
// adicionar(id) = "+" tracejado de um passo folha (mockup .mais)
const emit = defineEmits(['selecionar', 'conectar', 'adicionar']);
const nodes = defineModel('nodes', { type: Array, required: true });
const edges = defineModel('edges', { type: Array, required: true });

const { t } = useI18n();
const { zoomIn, zoomOut, fitView, getViewport, setViewport } = useVueFlow();

const estado = id => {
  if (props.erros.has(id)) return 'erro';
  if (props.acesos) {
    if (id === props.atual) return 'atual';
    return props.acesos.has(id) ? 'aceso' : 'apagado';
  }
  return id === props.selecionado ? 'selecionado' : '';
};
const folha = id => !edges.value.some(e => e.source === id);
// Ajuste inicial (1x): fluxo longo não encolhe abaixo de 0.75 (nós legíveis, o resto se rola); curto fica como antes.
// Longo (zoom no piso): ancora o TOPO do fluxo (gatilho) a 20px do alto, x centrado do fit. O quadro fica invisível até o ajuste (sem flash em zoom 1).
const MIN_ZOOM_FIT = 0.75;
const pronto = ref(!nodes.value.length); // vazio não dispara nodesInitialized
let ajustou = false;
const ajustarNaEntrada = async () => {
  if (ajustou) return;
  ajustou = true;
  await fitView({ minZoom: MIN_ZOOM_FIT }); // maxZoom segue o do quadro (1.5): curto fica como antes
  const { x, zoom } = getViewport();
  if (zoom <= MIN_ZOOM_FIT + 0.001) {
    const topo = Math.min(...nodes.value.map(n => n.position.y));
    await setViewport({ x, y: 20 - topo * zoom, zoom });
  }
  pronto.value = true;
};
</script>

<template>
  <VueFlow
    v-model:nodes="nodes"
    v-model:edges="edges"
    class="h-full bg-n-surface-2 [background-image:radial-gradient(rgb(var(--slate-6))_1.2px,transparent_1.2px)] [background-size:20px_20px] [&_.vue-flow\_\_edge-path]:stroke-n-slate-7 [&_.vue-flow\_\_edge-path]:[stroke-width:2] [&_.aceso_.vue-flow\_\_edge-path]:stroke-n-teal-9 [&_.aceso_.vue-flow\_\_edge-path]:[stroke-width:2.5] [&_.selected_.vue-flow\_\_edge-path]:stroke-n-blue-9"
    :class="{ 'opacity-0': !pronto }"
    :nodes-draggable="!somenteLeitura"
    :nodes-connectable="!somenteLeitura"
    :connection-mode="ConnectionMode.Strict"
    :elements-selectable="!somenteLeitura"
    :delete-key-code="somenteLeitura ? null : ['Backspace', 'Delete']"
    :min-zoom="0.4"
    :max-zoom="1.5"
    @nodes-initialized="ajustarNaEntrada"
    @connect="emit('conectar', $event)"
    @node-click="({ node }) => emit('selecionar', node.id)"
    @pane-click="emit('selecionar', null)"
  >
    <template #node-passo="{ id, data }">
      <NoPasso
        :id="id"
        :tipo="data.tipo"
        :config="data.config"
        :estado="estado(id)"
        :somente-leitura="somenteLeitura"
        :saida-tomada="saidasTomadas[id]"
        :folha="folha(id)"
        @adicionar="emit('adicionar', id)"
      />
    </template>
    <Panel
      position="bottom-left"
      class="flex gap-0.5 rounded-lg border border-n-weak bg-n-solid-1 p-0.5"
    >
      <Button
        ghost
        slate
        xs
        icon="i-lucide-zoom-in"
        :title="t('CAPTAIN_RAMON.FLUXOS.EDITOR.ZOOM_IN')"
        @click="zoomIn()"
      />
      <Button
        ghost
        slate
        xs
        icon="i-lucide-zoom-out"
        :title="t('CAPTAIN_RAMON.FLUXOS.EDITOR.ZOOM_OUT')"
        @click="zoomOut()"
      />
      <Button
        ghost
        slate
        xs
        icon="i-lucide-maximize"
        :title="t('CAPTAIN_RAMON.FLUXOS.EDITOR.AJUSTAR')"
        @click="fitView()"
      />
    </Panel>
    <MiniMap
      pannable
      zoomable
      node-class-name="fill-n-slate-6"
      class="overflow-hidden rounded-lg border border-n-weak !bg-n-solid-1 [&_.vue-flow\_\_minimap-mask]:fill-n-blue-9/10"
    />
  </VueFlow>
</template>

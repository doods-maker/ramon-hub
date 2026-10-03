<script setup>
// Paleta Ctrl K (redesign v2, Onda 5 — mockup #busca): leads, clientes do
// painel e nº de processo, tudo local (zero cota do ADVBOX), + ações.
// A command bar antiga (ninja-keys) fica em Ctrl+Shift+K e no "Mais comandos…".
import { computed, nextTick, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useEmitter } from 'dashboard/composables/emitter';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import RamonBuscaAPI from 'dashboard/api/ramonBusca';
import { DEFAULT_STAGE_COLOR } from '../../helpers/stage';
import Selo from '../hoje/Selo.vue';

const router = useRouter();
const { t } = useI18n();

const VAZIO = { leads: [], clientes: [], processos: [] };
const aberto = ref(false);
const termo = ref('');
const resultado = ref(VAZIO);
const ativo = ref(0);
const input = ref(null);
let focoAnterior = null;

const abrir = () => {
  if (aberto.value) return;
  focoAnterior = document.activeElement;
  aberto.value = true;
  ativo.value = 0;
  nextTick(() => input.value?.focus());
};
const fechar = () => {
  aberto.value = false;
  termo.value = '';
  resultado.value = VAZIO;
  focoAnterior?.focus?.();
};

useEmitter(BUS_EVENTS.OPEN_COMMAND_BAR, abrir);
useKeyboardEvents({
  '$mod+KeyK': {
    action: e => {
      e.preventDefault();
      abrir();
    },
    allowOnFocusedInput: true,
  },
});

// Debounce de 250 ms; < 2 caracteres não vai ao servidor. `pedido` descarta
// resposta velha que chegue depois de uma mais nova.
let timer = null;
let pedido = 0;
watch(termo, value => {
  clearTimeout(timer);
  ativo.value = 0;
  const q = value.trim();
  if (q.length < 2) {
    resultado.value = VAZIO;
    return;
  }
  timer = setTimeout(async () => {
    pedido += 1;
    const meu = pedido;
    try {
      const { data } = await RamonBuscaAPI.get(q);
      if (meu === pedido) resultado.value = data;
    } catch (e) {
      if (meu === pedido) resultado.value = VAZIO;
    }
  }, 250);
});

const ir = rota => () => router.push(rota);
const itens = computed(() => [
  ...resultado.value.leads.map(lead => ({
    key: `lead-${lead.id}`,
    grupo: 'pessoas',
    icon: 'i-lucide-user',
    titulo: lead.nome,
    detalhe: lead.tese,
    mono: lead.telefone,
    etapa: lead.stage_name && {
      nome: lead.stage_name,
      cor: lead.stage_color || DEFAULT_STAGE_COLOR,
    },
    abrir: ir({ name: 'ramon_lead_dossie', params: { leadId: lead.id } }),
  })),
  ...resultado.value.clientes.map(cliente => ({
    key: `cliente-${cliente.id}`,
    grupo: 'pessoas',
    icon: 'i-lucide-user',
    titulo: cliente.nome,
    detalhe: [
      cliente.desde && t('RAMON.BUSCA.CLIENTE_DESDE', { ano: cliente.desde }),
      cliente.advogada,
    ]
      .filter(Boolean)
      .join(' · '),
    selo: t('RAMON.BUSCA.CLIENTE'),
    abrir: ir({ name: 'ramon_portal_clientes' }),
  })),
  ...resultado.value.processos.map(processo => ({
    key: `processo-${processo.numero}`,
    grupo: 'processos',
    icon: 'i-lucide-scale',
    titulo: processo.numero,
    tituloMono: true,
    detalhe: [processo.cliente, processo.tipo].filter(Boolean).join(' · '),
    abrir: ir({ name: 'ramon_portal_clientes' }),
  })),
  {
    key: 'acao-novo-lead',
    grupo: 'acoes',
    icon: 'i-lucide-plus',
    titulo: t('RAMON.BUSCA.NOVO_LEAD'),
    abrir: ir({ name: 'ramon_funil', query: { novo: '1' } }),
  },
  {
    key: 'acao-novo-calculo',
    grupo: 'acoes',
    icon: 'i-lucide-calculator',
    titulo: t('RAMON.BUSCA.NOVO_CALCULO'),
    abrir: ir({ name: 'ramon_calculos' }),
  },
  {
    key: 'acao-conversas',
    grupo: 'acoes',
    icon: 'i-lucide-message-circle',
    titulo: t('RAMON.BUSCA.NAS_CONVERSAS'),
    abrir: () =>
      router.push({ name: 'search', query: { q: termo.value.trim() } }),
  },
  {
    key: 'acao-mais',
    grupo: 'acoes',
    icon: 'i-lucide-command',
    titulo: t('RAMON.BUSCA.MAIS_COMANDOS'),
    abrir: () => emitter.emit(BUS_EVENTS.OPEN_NINJA),
  },
]);
const GRUPOS = ['pessoas', 'processos', 'acoes'];
const grupos = computed(() =>
  GRUPOS.map(key => ({
    key,
    itens: itens.value.filter(item => item.grupo === key),
  })).filter(grupo => grupo.itens.length)
);
const indice = item => itens.value.indexOf(item);

const escolher = item => {
  fechar();
  item.abrir();
};
const onKeydown = e => {
  if (e.key === 'Escape') {
    e.preventDefault();
    fechar();
  } else if (e.key === 'ArrowDown') {
    e.preventDefault();
    ativo.value = Math.min(ativo.value + 1, itens.value.length - 1);
  } else if (e.key === 'ArrowUp') {
    e.preventDefault();
    ativo.value = Math.max(ativo.value - 1, 0);
  } else if (e.key === 'Enter') {
    e.preventDefault();
    const item = itens.value[ativo.value];
    if (item) escolher(item);
  }
};
</script>

<template>
  <div
    v-if="aberto"
    class="fixed inset-0 z-50 flex items-start justify-center px-4 pt-[12vh] bg-white/60 backdrop-blur-sm dark:bg-black/60"
    @click.self="fechar"
  >
    <div
      role="dialog"
      :aria-label="t('RAMON.BUSCA.TITULO')"
      class="w-[620px] max-w-[calc(100vw-32px)] overflow-hidden rounded-[14px] border border-n-strong bg-n-background shadow-[0_24px_64px_rgb(0_0_0/0.18)]"
    >
      <div class="flex items-center gap-2.5 px-4 py-3.5 border-b border-n-weak">
        <span class="i-lucide-search size-4 text-n-slate-9" />
        <input
          ref="input"
          v-model="termo"
          class="flex-1 min-w-0 bg-transparent border-0 outline-none text-[15px] text-n-slate-12"
          :aria-label="t('RAMON.BUSCA.TITULO')"
          :placeholder="t('RAMON.BUSCA.PLACEHOLDER')"
          @keydown="onKeydown"
        />
        <kbd
          class="rounded-[5px] border border-n-strong px-1.5 font-mono text-[11px] text-n-slate-9"
        >
          {{ t('RAMON.BUSCA.ESC') }}
        </kbd>
      </div>
      <div class="max-h-[60vh] overflow-y-auto">
        <div v-for="grupo in grupos" :key="grupo.key" class="p-2">
          <h4 class="px-2 pt-1.5 pb-1 text-[11.5px] font-medium text-n-slate-9">
            {{ t(`RAMON.BUSCA.GRUPO.${grupo.key.toUpperCase()}`) }}
          </h4>
          <button
            v-for="item in grupo.itens"
            :key="item.key"
            type="button"
            :data-testid="`cmd-${item.key}`"
            class="flex items-center w-full gap-3 px-2.5 py-[9px] text-left rounded-lg text-[13.5px] text-n-slate-12"
            :class="
              indice(item) === ativo
                ? 'bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16]'
                : 'hover:bg-n-slate-3'
            "
            @mouseenter="ativo = indice(item)"
            @click="escolher(item)"
          >
            <span
              class="grid flex-shrink-0 size-7 place-items-center rounded-[7px]"
              :class="
                indice(item) === ativo
                  ? 'bg-n-blue-9 text-white'
                  : 'bg-n-slate-4 text-n-slate-11'
              "
            >
              <span :class="item.icon" class="size-4" />
            </span>
            <span class="flex-1 min-w-0">
              <span
                class="block truncate"
                :class="item.tituloMono ? 'font-mono text-[13px]' : ''"
              >
                {{ item.titulo }}
              </span>
              <span
                v-if="item.detalhe || item.mono"
                class="block truncate text-[12.5px] text-n-slate-11"
              >
                {{
                  item.detalhe && item.mono ? `${item.detalhe} ·` : item.detalhe
                }}
                <span v-if="item.mono" class="font-mono">{{ item.mono }}</span>
              </span>
            </span>
            <span
              v-if="item.etapa"
              class="ramon-stage-pill inline-flex items-center flex-shrink-0 gap-1.5 px-2.5 py-1 text-[11.5px] font-medium leading-none rounded-full border border-transparent"
              :style="{ '--stage': item.etapa.cor }"
            >
              <span class="size-1.5 rounded-full bg-current" />
              {{ item.etapa.nome }}
            </span>
            <Selo v-else-if="item.selo" class="flex-shrink-0">
              {{ item.selo }}
            </Selo>
          </button>
        </div>
      </div>
      <div
        class="flex flex-wrap gap-x-4 px-4 py-2.5 border-t border-n-weak text-[11.5px] text-n-slate-9"
      >
        <span>{{ t('RAMON.BUSCA.NAVEGAR') }}</span>
        <span>{{ t('RAMON.BUSCA.ABRIR') }}</span>
        <span>{{ t('RAMON.BUSCA.DICA') }}</span>
      </div>
    </div>
  </div>
</template>

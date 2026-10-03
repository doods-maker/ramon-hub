<script setup>
// Painel da caixa do escritório (redesign v2, mockup .painel[recepcao advogada]):
// quem atribuiu, "Atribuir a…" com a advogada do processo sugerida, o cliente
// do ADVBOX (espelho do Painel do Cliente) ou "Número novo" → comercial.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import RamonClienteAPI from 'dashboard/api/ramonCliente';
import { BTN_CHEIO, BTN_TINT, horaDe, diaMes } from '../hoje/hoje';
import { telefoneBr } from '../../helpers/phone';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  encaminhando: { type: Boolean, default: false },
});
const emit = defineEmits(['encaminhar']);
defineOptions({ name: 'ClientePanel' });

const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const currentUserId = useMapGetter('getCurrentUserID');
const teams = useMapGetter('teams/getTeams');
const membrosDe = useMapGetter('teamMembers/getTeamMembers');

const dados = ref(null);
const erro = ref(false);
const carregar = async () => {
  dados.value = null;
  erro.value = false;
  try {
    const { data } = await RamonClienteAPI.get(props.conversationId);
    dados.value = data;
  } catch (e) {
    erro.value = true;
  }
};
watch(() => props.conversationId, carregar, { immediate: true });

// ----- atribuição -----
const meta = computed(() => currentChat.value?.meta || {});
const souResponsavel = computed(
  () =>
    meta.value.assignee?.id && meta.value.assignee.id === currentUserId.value
);
const atribuicao = computed(
  () => currentChat.value?.additional_attributes?.ramon_atribuicao
);
const mostraFaixa = computed(
  () =>
    souResponsavel.value &&
    atribuicao.value?.por_nome &&
    atribuicao.value.por_id !== currentUserId.value
);
// Recepção sem dono e sem time = triagem: só aí "Número novo" encaminha.
const naRecepcao = computed(() => !meta.value.team && !meta.value.assignee);

const normaliza = nome =>
  (nome || '').normalize('NFD').replace(/\p{M}/gu, '').trim().toLowerCase();
const timeChamado = nome =>
  (teams.value || []).find(time => normaliza(time.name) === nome);
const advogados = computed(() => timeChamado('advogados'));
const controladoria = computed(() => timeChamado('controladoria'));
watch(
  [advogados, controladoria],
  times =>
    times
      .filter(time => time && !membrosDe.value(time.id).length)
      .forEach(time => store.dispatch('teamMembers/get', { teamId: time.id })),
  { immediate: true }
);

const pessoas = computed(() => {
  const membros = advogados.value ? membrosDe.value(advogados.value.id) : [];
  const sugestao = dados.value?.sugestao_user_id;
  return [...membros].sort(
    (a, b) => Number(b.id === sugestao) - Number(a.id === sugestao)
  );
});
const nomeControladoria = computed(() => {
  const pessoa = controladoria.value
    ? membrosDe.value(controladoria.value.id)[0]
    : null;
  return pessoa
    ? t('RAMON.CLIENTE_PANEL.CONTROLADORIA_COM', { nome: pessoa.name })
    : t('RAMON.CLIENTE_PANEL.CONTROLADORIA');
});
const iniciais = nome =>
  (nome || '')
    .replace(/^dra?\.\s*/i, '')
    .split(/\s+/)
    .map(parte => parte[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

const menuAberto = ref(false);
const conversa = () => Number(props.conversationId);
const atribuirPessoa = async pessoa => {
  menuAberto.value = false;
  await store.dispatch('assignAgent', {
    conversationId: conversa(),
    agentId: pessoa.id,
  });
  useAlert(t('CONVERSATION.CHANGE_AGENT'));
};
const atribuirControladoria = async () => {
  menuAberto.value = false;
  await store.dispatch('assignTeam', {
    conversationId: conversa(),
    teamId: controladoria.value.id,
  });
  useAlert(t('CONVERSATION.CHANGE_TEAM'));
};
// Devolver = volta pra fila sem responsável e sem time.
const devolver = async () => {
  await store.dispatch('assignAgent', {
    conversationId: conversa(),
    agentId: null,
  });
  await store.dispatch('assignTeam', { conversationId: conversa(), teamId: 0 });
};

// ----- cliente -----
const desde = computed(() => {
  const valor = dados.value?.desde;
  return valor ? `${valor.slice(5, 7)}/${valor.slice(0, 4)}` : null;
});
const compromisso = computed(() => {
  const c = dados.value?.compromisso;
  if (!c) return null;
  const quando = [diaMes(c.data), c.hora].filter(Boolean).join(', ');
  return `${t(`RAMON.CLIENTE_PANEL.COMPROMISSO.${c.tipo}`)} · ${quando}`;
});

const SECAO = 'border-b border-n-weak px-[18px] py-4';
const TITULO = 'mb-2 flex justify-between text-xs font-medium text-n-slate-9';
const DADO = 'flex justify-between gap-3 py-1 text-[13px]';
</script>

<template>
  <div class="min-w-0 flex-1 overflow-y-auto" data-testid="cliente-panel">
    <div
      v-if="mostraFaixa"
      data-testid="cliente-faixa-atribuida"
      class="flex items-center gap-2 bg-n-blue-9/[0.08] px-[18px] py-2.5 text-[12.5px] font-medium text-n-blue-11 dark:bg-n-blue-9/[0.16]"
    >
      <span class="i-lucide-user-check size-4 flex-shrink-0" />
      {{
        t('RAMON.CLIENTE_PANEL.ATRIBUIDA_POR', {
          nome: atribuicao.por_nome,
          hora: horaDe(atribuicao.em),
        })
      }}
      <button
        type="button"
        data-testid="cliente-devolver"
        class="ml-auto text-xs underline underline-offset-2"
        @click="devolver"
      >
        {{ t('RAMON.CLIENTE_PANEL.DEVOLVER') }}
      </button>
    </div>

    <div v-if="!souResponsavel" :class="SECAO">
      <button
        type="button"
        data-testid="cliente-atribuir"
        :class="BTN_CHEIO"
        class="w-full justify-center !rounded-[9px] !px-4 !py-[9px] !text-sm"
        @click="menuAberto = !menuAberto"
      >
        <span class="i-lucide-user-plus size-4" />
        {{ t('RAMON.CLIENTE_PANEL.ATRIBUIR') }}
      </button>
      <div
        v-if="menuAberto"
        data-testid="cliente-menu-pessoas"
        class="mt-2 rounded-[10px] border border-n-strong bg-n-background p-1.5 shadow-[0_8px_24px_rgb(0_0_0/0.08)]"
      >
        <button
          v-for="pessoa in pessoas"
          :key="pessoa.id"
          type="button"
          data-testid="cliente-pessoa"
          class="flex w-full items-center gap-2.5 rounded-[7px] px-2 py-[7px] text-left text-[13px] text-n-slate-12 hover:bg-n-slate-3"
          :class="{
            'bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16]':
              pessoa.id === dados?.sugestao_user_id,
          }"
          @click="atribuirPessoa(pessoa)"
        >
          <span
            class="grid size-6 flex-shrink-0 place-items-center rounded-full bg-n-slate-4 text-[10px] font-semibold text-n-slate-11"
          >
            {{ iniciais(pessoa.name) }}
          </span>
          <span class="truncate">{{ pessoa.name }}</span>
          <small
            v-if="pessoa.id === dados?.sugestao_user_id"
            class="ml-auto whitespace-nowrap text-[11.5px] font-medium text-n-blue-11"
          >
            {{ t('RAMON.CLIENTE_PANEL.DO_PROCESSO') }}
          </small>
        </button>
        <template v-if="controladoria">
          <div class="my-1.5 border-t border-n-weak" />
          <button
            type="button"
            data-testid="cliente-controladoria"
            class="flex w-full items-center gap-2.5 rounded-[7px] px-2 py-[7px] text-left text-[13px] text-n-slate-12 hover:bg-n-slate-3"
            @click="atribuirControladoria"
          >
            <span
              class="grid size-6 flex-shrink-0 place-items-center rounded-full bg-n-slate-4 text-[10px] font-semibold text-n-slate-11"
            >
              {{ iniciais(nomeControladoria) }}
            </span>
            {{ nomeControladoria }}
          </button>
        </template>
      </div>
    </div>

    <p v-if="erro" class="px-[18px] py-4 text-sm text-n-ruby-11">
      {{ t('RAMON.CLIENTE_PANEL.ERRO') }}
    </p>
    <p v-else-if="!dados" class="px-[18px] py-4 text-sm text-n-slate-10">
      {{ t('RAMON.CLIENTE_PANEL.CARREGANDO') }}
    </p>

    <template v-else-if="dados.cliente">
      <div :class="SECAO">
        <h3 :class="TITULO">
          {{
            desde
              ? t('RAMON.CLIENTE_PANEL.CLIENTE_DESDE', { data: desde })
              : t('RAMON.CLIENTE_PANEL.CLIENTE')
          }}
        </h3>
        <div :class="DADO">
          <span class="text-n-slate-9">
            {{ t('RAMON.CLIENTE_PANEL.ADVOGADA') }}
          </span>
          <span class="text-right text-n-slate-12">
            {{ dados.advogada?.nome || '—' }}
          </span>
        </div>
        <div :class="DADO">
          <span class="text-n-slate-9">
            {{ t('RAMON.CLIENTE_PANEL.TELEFONE') }}
          </span>
          <span class="font-mono text-[12.5px] text-n-slate-12">
            {{ telefoneBr(dados.telefone) }}
          </span>
        </div>
        <div
          v-if="compromisso"
          data-testid="cliente-compromisso"
          class="mt-1 rounded-[10px] bg-n-blue-9/[0.08] px-3.5 py-3 dark:bg-n-blue-9/[0.16]"
        >
          <b class="block text-[13.5px] font-semibold text-n-blue-11">
            {{ compromisso }}
          </b>
          <span v-if="dados.compromisso.notas" class="text-[12.5px]">
            {{ dados.compromisso.notas }}
          </span>
        </div>
      </div>

      <div :class="SECAO">
        <h3 :class="TITULO">
          {{ t('RAMON.CLIENTE_PANEL.PROCESSOS') }}
          <span class="font-mono">{{ dados.processos.length }}</span>
        </h3>
        <div
          v-for="processo in dados.processos"
          :key="processo.numero"
          class="mb-3 last:mb-0"
        >
          <div class="font-mono text-[12.5px] font-medium text-n-slate-12">
            {{ processo.numero }}
          </div>
          <div class="mt-0.5 text-[12.5px] text-n-slate-11">
            {{ [processo.tipo, processo.fase].filter(Boolean).join(' · ') }}
          </div>
          <div v-if="processo.ultimo_andamento" :class="DADO" class="mt-1">
            <span class="text-n-slate-9">
              {{ t('RAMON.CLIENTE_PANEL.ULTIMO_ANDAMENTO') }}
            </span>
            <span class="text-right text-n-slate-12">
              {{
                `${diaMes(processo.ultimo_andamento.data)} · ${processo.ultimo_andamento.titulo}`
              }}
            </span>
          </div>
        </div>
      </div>

      <a
        href="https://app.advbox.com.br"
        target="_blank"
        rel="noopener noreferrer"
        class="flex items-center justify-between border-b border-n-weak px-[18px] py-3 text-[13px] text-n-slate-11 hover:bg-n-slate-3 hover:text-n-slate-12"
      >
        {{ t('RAMON.CLIENTE_PANEL.VER_ADVBOX') }}
        <span class="i-lucide-external-link size-4" />
      </a>
    </template>

    <div v-else :class="SECAO" data-testid="cliente-numero-novo">
      <h3 :class="TITULO">{{ t('RAMON.CLIENTE_PANEL.NUMERO_NOVO') }}</h3>
      <p class="text-[12.5px] text-n-slate-11">
        {{ t('RAMON.CLIENTE_PANEL.NUMERO_NOVO_APOIO') }}
      </p>
      <button
        v-if="naRecepcao"
        type="button"
        data-testid="lead-panel-encaminhar-comercial"
        :class="BTN_TINT"
        class="mt-3"
        :disabled="encaminhando"
        @click="emit('encaminhar')"
      >
        {{ t('RAMON.LEAD_PANEL.ENCAMINHAR_COMERCIAL') }}
      </button>
    </div>
  </div>
</template>

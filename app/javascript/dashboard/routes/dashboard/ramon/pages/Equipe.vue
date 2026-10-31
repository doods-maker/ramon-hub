<script setup>
import {
  computed,
  ref,
  watch,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener } from '@vueuse/core';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useChatStore } from 'dashboard/stores/chat';

// Equipe · chat interno (Fatia 2): Geral, setores (times) e 1:1 à esquerda,
// conversa à direita. Administrador lê tudo — o aviso no topo diz isso.
const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const chat = useChatStore();

const meuId = computed(() => getters.getCurrentUserID.value);
const colegas = computed(() =>
  (getters['agents/getAgents']?.value ?? [])
    .filter(a => a.id !== meuId.value)
    .sort((a, b) => a.name.localeCompare(b.name))
);

const meus = computed(() => chat.canais.filter(c => c.participante));
const grupos = computed(() => [
  {
    titulo: 'RAMON.EQUIPE.CANAIS',
    canais: meus.value.filter(c => c.tipo !== 'direto'),
  },
  {
    titulo: 'RAMON.EQUIPE.CONVERSAS',
    canais: meus.value.filter(c => c.tipo === 'direto'),
  },
  {
    titulo: 'RAMON.EQUIPE.VISAO_ADMIN',
    canais: chat.canais.filter(c => !c.participante),
  },
]);
const nomeDo = c =>
  c.tipo === 'geral' ? t('RAMON.EQUIPE.GERAL') : c.nome || '—';
const prefixo = c => (c.tipo === 'direto' ? '@' : '#');

const aberto = computed(() => chat.aberto);
const mensagens = computed(() => chat.mensagens[chat.abertoId] ?? []);
const texto = ref('');
const enviando = ref(false);
const novoColega = ref('');
const listaRef = ref(null);

const hora = iso =>
  new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

const abrir = id =>
  chat.abrir(id).catch(() => useAlert(t('RAMON.EQUIPE.ERRO')));

const enviar = async () => {
  const conteudo = texto.value.trim();
  if (!conteudo || enviando.value) return;
  enviando.value = true;
  try {
    await chat.enviar(conteudo);
    texto.value = '';
  } catch {
    useAlert(t('RAMON.EQUIPE.ERRO'));
  } finally {
    enviando.value = false;
  }
};

const abrirDireto = async () => {
  const id = Number(novoColega.value);
  novoColega.value = '';
  if (!id) return;
  try {
    await chat.direto(id);
  } catch {
    useAlert(t('RAMON.EQUIPE.ERRO'));
  }
};

// Mensagem nova no fim (não a página anterior carregada no topo) → rola pro fim.
watch(
  () => mensagens.value.at(-1)?.id,
  async () => {
    await nextTick();
    if (listaRef.value) listaRef.value.scrollTop = listaRef.value.scrollHeight;
  }
);

// Voltou pra aba com a conversa aberta: o que chegou enquanto isso foi lido.
useEventListener(document, 'visibilitychange', () => {
  if (document.visibilityState === 'visible' && aberto.value?.nao_lidas)
    chat.marcarLido(aberto.value.id);
});

onMounted(async () => {
  store.dispatch('agents/get');
  if (!chat.canais.length) await chat.carregar().catch(() => {});
  const inicial = chat.abertoId ?? chat.canais[0]?.id;
  if (inicial) abrir(inicial);
});
onBeforeUnmount(() => chat.fechar());
</script>

<template>
  <div class="flex flex-col w-full h-full min-h-0">
    <p
      data-testid="aviso-admin"
      class="flex items-center gap-2 px-4 py-2 text-xs border-b text-n-slate-11 border-n-weak bg-n-alpha-1"
    >
      <span class="i-lucide-eye size-3.5 flex-shrink-0" />
      {{ t('RAMON.EQUIPE.AVISO_ADMIN') }}
    </p>
    <div class="flex flex-1 min-h-0">
      <aside
        class="flex flex-col w-60 flex-shrink-0 overflow-y-auto border-r border-n-weak py-3"
      >
        <template v-for="grupo in grupos" :key="grupo.titulo">
          <template v-if="grupo.canais.length">
            <p
              class="px-4 pt-3 pb-1 text-[10px] tracking-widest uppercase text-n-slate-9"
            >
              {{ t(grupo.titulo) }}
            </p>
            <button
              v-for="canal in grupo.canais"
              :key="canal.id"
              type="button"
              class="flex items-center gap-2 h-8 mx-2 px-2 text-sm text-left rounded-lg hover:bg-n-alpha-2"
              :class="
                canal.id === chat.abertoId
                  ? 'bg-n-alpha-2 text-n-slate-12'
                  : 'text-n-slate-11'
              "
              @click="abrir(canal.id)"
            >
              <span class="text-n-slate-9">{{ prefixo(canal) }}</span>
              <span
                class="truncate"
                :class="{ 'font-semibold text-n-slate-12': canal.nao_lidas }"
              >
                {{ nomeDo(canal) }}
              </span>
              <span
                v-if="canal.nao_lidas"
                class="grid h-4 min-w-4 px-1 ms-auto place-items-center rounded-full bg-n-ruby-9 text-[10px] font-medium leading-none text-white"
              >
                {{ canal.nao_lidas }}
              </span>
            </button>
          </template>
        </template>
        <label class="mx-4 mt-4">
          <span class="sr-only">{{ t('RAMON.EQUIPE.NOVA_CONVERSA') }}</span>
          <select
            v-model="novoColega"
            class="!mb-0 w-full text-sm"
            @change="abrirDireto"
          >
            <option value="">{{ t('RAMON.EQUIPE.NOVA_CONVERSA') }}</option>
            <option v-for="a in colegas" :key="a.id" :value="a.id">
              {{ a.name }}
            </option>
          </select>
        </label>
      </aside>

      <section v-if="aberto" class="flex flex-col flex-1 min-w-0 min-h-0">
        <h2
          class="px-4 py-3 text-base font-semibold border-b text-n-slate-12 border-n-weak"
        >
          {{ prefixo(aberto) }} {{ nomeDo(aberto) }}
        </h2>
        <div
          ref="listaRef"
          class="flex flex-col flex-1 gap-3 p-4 overflow-y-auto"
        >
          <button
            v-if="chat.mais[aberto.id]"
            type="button"
            class="self-center text-xs text-n-slate-11 hover:text-n-slate-12"
            @click="chat.anteriores(aberto.id)"
          >
            {{ t('RAMON.EQUIPE.ANTERIORES') }}
          </button>
          <p v-if="!mensagens.length" class="m-auto text-sm text-n-slate-11">
            {{ t('RAMON.EQUIPE.VAZIO') }}
          </p>
          <div
            v-for="m in mensagens"
            :key="m.id"
            data-testid="chat-mensagem"
            class="max-w-[75%] rounded-lg px-3 py-2"
            :class="
              m.autor.id === meuId
                ? 'self-end bg-n-alpha-2'
                : 'self-start bg-n-alpha-1'
            "
          >
            <p class="text-xs text-n-slate-11">
              {{ m.autor.name }} · {{ hora(m.created_at) }}
            </p>
            <p class="text-sm whitespace-pre-wrap break-words text-n-slate-12">
              {{ m.conteudo }}
            </p>
          </div>
        </div>
        <form
          v-if="aberto.participante"
          class="flex items-end gap-2 p-3 border-t border-n-weak"
          @submit.prevent="enviar"
        >
          <textarea
            v-model="texto"
            data-testid="chat-texto"
            rows="2"
            :placeholder="t('RAMON.EQUIPE.PLACEHOLDER')"
            class="!mb-0 flex-1 rounded-lg bg-n-alpha-black2 p-2 text-sm text-n-slate-12 outline outline-1 outline-n-weak"
            @keydown.enter.exact.prevent="enviar"
          />
          <button
            type="submit"
            :disabled="!texto.trim() || enviando"
            class="rounded-lg bg-n-brand px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
          >
            {{ t('RAMON.EQUIPE.ENVIAR') }}
          </button>
        </form>
        <p
          v-else
          class="p-3 text-xs text-center border-t text-n-slate-11 border-n-weak"
        >
          {{ t('RAMON.EQUIPE.SO_LEITURA') }}
        </p>
      </section>
    </div>
  </div>
</template>

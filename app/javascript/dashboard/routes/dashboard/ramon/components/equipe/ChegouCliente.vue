<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

// Painel da Recepção (Equipe · Fatia 1): uma busca só (agendados de hoje +
// clientes do ADVBOX + "usar como digitado"), motivo e quem atende em cartões;
// embaixo, as chegadas de hoje com o estado de cada uma.
const BUSCA_MIN = 3;
const BUSCA_ESPERA_MS = 350;

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const chegadas = useChegadasStore();

const dialogRef = ref(null);
const buscaRef = ref(null);
const agenda = ref([]);
const advboxFora = ref(false);
const termo = ref('');
const resultados = ref([]);
const buscando = ref(false);
const cliente = ref(null);
const motivoTipo = ref(null);
const motivoTexto = ref('');
const destinatarioId = ref(null);
const sugeridoId = ref(null);
const enviando = ref(false);
const erro = ref(false);

const agents = computed(() =>
  [...(getters['agents/getAgents']?.value ?? [])].sort((a, b) =>
    a.name.localeCompare(b.name, 'pt-BR')
  )
);
const primeiroNome = nome => (nome || '').split(' ')[0];
const destinatario = computed(() =>
  agents.value.find(a => a.id === destinatarioId.value)
);
const motivo = computed(() =>
  motivoTipo.value === 'reuniao'
    ? t('RAMON.CHEGADA.MOTIVO_REUNIAO')
    : motivoTexto.value.trim()
);
const podeEnviar = computed(() => !!(cliente.value && destinatarioId.value));
const rotuloAvisar = computed(() =>
  destinatario.value
    ? t('RAMON.CHEGADA.AVISAR_PESSOA', {
        nome: primeiroNome(destinatario.value.name),
      })
    : t('RAMON.CHEGADA.AVISAR')
);

const semAcento = s =>
  (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const agendaFiltrada = computed(() => {
  const q = semAcento(termo.value.trim());
  return q
    ? agenda.value.filter(item => semAcento(item.cliente_nome).includes(q))
    : agenda.value;
});
const podeUsarDigitado = computed(() => termo.value.trim().length >= 2);

const deHoje = computed(() => [...chegadas.itens].reverse());
const hora = iso =>
  new Date(iso).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
const estados = computed(() => ({
  aguardando: {
    rotulo: t('RAMON.CHEGADA.ESTADO_aguardando'),
    classe: 'bg-n-amber-3 text-n-amber-11',
  },
  escalado: {
    rotulo: t('RAMON.CHEGADA.ESTADO_escalado'),
    classe: 'bg-n-ruby-3 text-n-ruby-11',
  },
  respondido: {
    rotulo: t('RAMON.CHEGADA.ESTADO_respondido'),
    classe: 'bg-n-teal-3 text-n-teal-11',
  },
}));

// Busca no ADVBOX enquanto digita (cota de 500/dia → espera a pessoa parar e
// só a partir de 3 letras); resposta atrasada de uma busca velha é descartada.
let espera = null;
let ultimaBusca = '';
watch(termo, valor => {
  clearTimeout(espera);
  const q = valor.trim();
  if (q.length < BUSCA_MIN) {
    resultados.value = [];
    buscando.value = false;
    return;
  }
  buscando.value = true;
  espera = setTimeout(async () => {
    ultimaBusca = q;
    try {
      const { data } = await RamonCalculosAPI.advboxCustomers(q);
      if (ultimaBusca === q) resultados.value = data.payload;
    } catch {
      advboxFora.value = true;
    } finally {
      if (ultimaBusca === q) buscando.value = false;
    }
  }, BUSCA_ESPERA_MS);
});

const escolher = escolhido => {
  cliente.value = escolhido;
  termo.value = '';
};
const usarAgenda = item => {
  escolher({
    cliente_nome: item.cliente_nome || '',
    advbox_customer_id: item.advbox_customer_id,
    advbox_post_id: item.advbox_post_id,
    origem: item.responsavel_advbox,
  });
  if (item.destinatario_id) {
    sugeridoId.value = item.destinatario_id;
    destinatarioId.value = item.destinatario_id;
  }
};
const usarCliente = c =>
  escolher({ cliente_nome: c.name, advbox_customer_id: c.id });
const usarDigitado = () => escolher({ cliente_nome: termo.value.trim() });
const trocarCliente = () => {
  cliente.value = null;
  buscaRef.value?.focus();
};
const escolherMotivo = tipo => {
  motivoTipo.value = motivoTipo.value === tipo ? null : tipo;
};

const limpar = () => {
  termo.value = '';
  resultados.value = [];
  cliente.value = null;
  motivoTipo.value = null;
  motivoTexto.value = '';
  destinatarioId.value = null;
  sugeridoId.value = null;
};

const abrir = async () => {
  limpar();
  agenda.value = [];
  erro.value = false;
  advboxFora.value = false;
  store.dispatch('agents/get');
  chegadas.carregar().catch(() => {}); // lista de hoje atual p/ 2ª recepcionista
  dialogRef.value?.open();
  try {
    const { data } = await ChegadasAPI.agenda();
    agenda.value = data.payload;
  } catch {
    advboxFora.value = true;
  }
};

const avisar = async () => {
  if (!podeEnviar.value || enviando.value) return;
  enviando.value = true;
  erro.value = false;
  try {
    await chegadas.criar({
      cliente_nome: cliente.value.cliente_nome,
      advbox_customer_id: cliente.value.advbox_customer_id,
      advbox_post_id: cliente.value.advbox_post_id,
      motivo: motivo.value,
      destinatario_id: destinatarioId.value,
    });
    limpar();
  } catch {
    erro.value = true;
  } finally {
    enviando.value = false;
  }
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="chegadas.podeAvisar" class="contents">
    <button
      type="button"
      data-testid="chegou-cliente-botao"
      class="fixed bottom-4 z-50 flex items-center gap-2 rounded-full bg-n-brand px-4 py-2 font-medium text-white shadow-lg ltr:right-20 rtl:left-20"
      @click="abrir"
    >
      <span class="i-lucide-bell-ring size-4" />
      {{ t('RAMON.CHEGADA.BOTAO') }}
    </button>

    <Dialog
      ref="dialogRef"
      width="lg"
      :title="t('RAMON.CHEGADA.TITULO')"
      :confirm-button-label="rotuloAvisar"
      :disable-confirm-button="!podeEnviar"
      :is-loading="enviando"
      @confirm="avisar"
    >
      <div class="flex flex-col gap-6">
        <!-- Quem chegou -->
        <section class="flex flex-col gap-2">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('RAMON.CHEGADA.QUEM_CHEGOU') }}
          </h3>

          <div
            v-if="cliente"
            data-testid="cliente-escolhido"
            class="flex items-center gap-3 rounded-xl bg-n-alpha-2 px-4 py-3 outline outline-1 outline-n-weak"
          >
            <span class="i-lucide-user-round size-5 text-n-slate-11" />
            <div class="min-w-0 flex-1">
              <p class="truncate font-medium text-n-slate-12">
                {{ cliente.cliente_nome }}
              </p>
              <p
                v-if="cliente.advbox_customer_id"
                class="text-xs text-n-slate-11"
              >
                {{ t('RAMON.CHEGADA.CLIENTE_ADVBOX') }}
              </p>
            </div>
            <button
              type="button"
              class="text-sm text-n-iris-11 hover:underline"
              @click="trocarCliente"
            >
              {{ t('RAMON.CHEGADA.TROCAR') }}
            </button>
          </div>

          <template v-else>
            <label
              class="flex items-center gap-2 rounded-xl bg-n-alpha-black2 px-3 py-2.5 outline outline-1 outline-n-weak focus-within:outline-n-brand"
            >
              <span class="i-lucide-search size-4 text-n-slate-10" />
              <input
                ref="buscaRef"
                v-model="termo"
                data-testid="chegada-busca"
                :placeholder="t('RAMON.CHEGADA.BUSCAR_PLACEHOLDER')"
                class="min-w-0 flex-1 bg-transparent text-n-slate-12 outline-none"
                @keydown.enter.prevent="podeUsarDigitado && usarDigitado()"
              />
            </label>

            <p v-if="advboxFora" class="text-sm text-n-ruby-11">
              {{ t('RAMON.CHEGADA.ADVBOX_FORA') }}
            </p>

            <div class="flex flex-col gap-3">
              <div v-if="agendaFiltrada.length" class="flex flex-col gap-1">
                <p
                  class="text-xs font-medium uppercase tracking-wide text-n-slate-10"
                >
                  {{ t('RAMON.CHEGADA.GRUPO_HOJE') }}
                </p>
                <button
                  v-for="item in agendaFiltrada"
                  :key="item.advbox_post_id"
                  type="button"
                  data-testid="agenda-item"
                  class="flex items-center gap-3 rounded-lg px-3 py-2 text-start hover:bg-n-alpha-2"
                  @click="usarAgenda(item)"
                >
                  <span class="size-2 shrink-0 rounded-full bg-n-teal-11" />
                  <span class="min-w-0 flex-1">
                    <span class="block truncate font-medium text-n-slate-12">
                      {{ item.cliente_nome }}
                    </span>
                    <span
                      v-if="item.responsavel_advbox"
                      class="block truncate text-xs text-n-slate-11"
                    >
                      {{ item.responsavel_advbox }}
                    </span>
                  </span>
                </button>
              </div>

              <div v-if="resultados.length" class="flex flex-col gap-1">
                <p
                  class="text-xs font-medium uppercase tracking-wide text-n-slate-10"
                >
                  {{ t('RAMON.CHEGADA.GRUPO_ADVBOX') }}
                </p>
                <button
                  v-for="c in resultados"
                  :key="c.id"
                  type="button"
                  data-testid="advbox-item"
                  class="flex items-center gap-3 rounded-lg px-3 py-2 text-start hover:bg-n-alpha-2"
                  @click="usarCliente(c)"
                >
                  <span
                    class="size-2 shrink-0 rounded-full outline outline-1 outline-n-slate-9"
                  />
                  <span class="truncate text-n-slate-12">{{ c.name }}</span>
                </button>
              </div>

              <p v-if="buscando" class="px-3 text-xs text-n-slate-10">
                {{ t('RAMON.CHEGADA.BUSCANDO') }}
              </p>

              <button
                v-if="podeUsarDigitado"
                type="button"
                data-testid="usar-digitado"
                class="flex items-center gap-3 rounded-lg px-3 py-2 text-start text-n-iris-11 hover:bg-n-alpha-2"
                @click="usarDigitado"
              >
                <span class="i-lucide-plus size-4" />
                {{ t('RAMON.CHEGADA.USAR_DIGITADO', { nome: termo.trim() }) }}
              </button>
            </div>
          </template>
        </section>

        <!-- Motivo -->
        <section class="flex flex-col gap-2">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('RAMON.CHEGADA.MOTIVO_TITULO') }}
          </h3>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="tipo in ['reuniao', 'outro']"
              :key="tipo"
              type="button"
              :data-testid="`motivo-${tipo}`"
              :aria-pressed="motivoTipo === tipo"
              class="rounded-full px-3 py-1 text-sm outline outline-1"
              :class="
                motivoTipo === tipo
                  ? 'bg-n-brand text-white outline-n-brand'
                  : 'text-n-slate-12 outline-n-weak hover:bg-n-alpha-2'
              "
              @click="escolherMotivo(tipo)"
            >
              {{
                tipo === 'reuniao'
                  ? t('RAMON.CHEGADA.MOTIVO_REUNIAO')
                  : t('RAMON.CHEGADA.MOTIVO_OUTRO')
              }}
            </button>
          </div>
          <input
            v-if="motivoTipo === 'outro'"
            v-model="motivoTexto"
            data-testid="motivo-texto"
            :placeholder="t('RAMON.CHEGADA.MOTIVO_OUTRO_PLACEHOLDER')"
            class="rounded-xl bg-n-alpha-black2 px-3 py-2.5 text-n-slate-12 outline outline-1 outline-n-weak focus:outline-n-brand"
          />
        </section>

        <!-- Quem vai atender -->
        <section class="flex flex-col gap-2">
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ t('RAMON.CHEGADA.DESTINATARIO') }}
          </h3>
          <div class="grid grid-cols-4 gap-2 sm:grid-cols-5">
            <button
              v-for="agent in agents"
              :key="agent.id"
              type="button"
              data-testid="atendente"
              :aria-pressed="destinatarioId === agent.id"
              class="relative flex flex-col items-center gap-1.5 rounded-xl px-1 py-3 outline outline-1"
              :class="
                destinatarioId === agent.id
                  ? 'bg-n-alpha-2 outline-2 outline-n-brand'
                  : 'outline-n-weak hover:bg-n-alpha-2'
              "
              @click="destinatarioId = agent.id"
            >
              <Avatar
                :src="agent.thumbnail"
                :name="agent.name"
                :size="40"
                rounded-full
              />
              <span class="w-full truncate text-center text-xs text-n-slate-12">
                {{ primeiroNome(agent.name) }}
              </span>
              <span
                v-if="sugeridoId === agent.id"
                class="absolute -top-2 rounded-full bg-n-teal-3 px-1.5 text-[10px] font-medium text-n-teal-11"
              >
                {{ t('RAMON.CHEGADA.AGENDADO') }}
              </span>
            </button>
          </div>
        </section>

        <p v-if="erro" class="text-sm text-n-ruby-11">
          {{ t('RAMON.CHEGADA.ERRO_AVISAR') }}
        </p>

        <!-- Hoje -->
        <section
          v-if="deHoje.length"
          class="flex flex-col gap-2 border-t border-n-weak pt-4"
        >
          <h3
            class="text-xs font-medium uppercase tracking-wide text-n-slate-10"
          >
            {{ t('RAMON.CHEGADA.HOJE') }}
          </h3>
          <div
            v-for="c in deHoje"
            :key="c.id"
            data-testid="chegada-hoje"
            class="flex gap-3 rounded-lg px-3 py-2"
          >
            <span
              class="w-11 shrink-0 pt-0.5 text-xs tabular-nums text-n-slate-10"
            >
              {{ hora(c.created_at) }}
            </span>
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm text-n-slate-12">
                <span class="font-medium">{{ c.cliente_nome }}</span>
                {{ ` → ${primeiroNome(c.destinatario.name)}` }}
              </p>
              <p v-if="c.resposta" class="text-sm text-n-slate-11">
                {{ `“${c.resposta}”` }}
              </p>
            </div>
            <span
              class="h-fit shrink-0 rounded-full px-2 py-0.5 text-xs font-medium"
              :class="estados[c.estado].classe"
            >
              {{ estados[c.estado].rotulo }}
            </span>
          </div>
        </section>
      </div>
    </Dialog>
  </div>
</template>

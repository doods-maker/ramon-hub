<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useChegadasStore } from 'dashboard/stores/chegadas';
import ChegadasAPI from 'dashboard/api/ramonChegadas';
import RamonCalculosAPI from 'dashboard/api/ramonCalculos';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// Painel da Recepção (Equipe · Fatia 1): escolhe o cliente (agenda do ADVBOX,
// busca ou livre) e quem vai atender; abaixo, as chegadas de hoje com estado.
const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();
const chegadas = useChegadasStore();

const dialogRef = ref(null);
const aba = ref('hoje');
const agenda = ref([]);
const advboxFora = ref(false);
const termo = ref('');
const resultados = ref([]);
const form = ref({});
const enviando = ref(false);

const agents = computed(() => getters['agents/getAgents']?.value ?? []);
const podeEnviar = computed(
  () => form.value.cliente_nome?.trim() && form.value.destinatario_id
);
const deHoje = computed(() => [...chegadas.itens].reverse());

const limpar = () => {
  form.value = { cliente_nome: '', motivo: '', destinatario_id: '' };
};

const abrir = async () => {
  limpar();
  aba.value = 'hoje';
  advboxFora.value = false;
  store.dispatch('agents/get');
  dialogRef.value?.open();
  try {
    const { data } = await ChegadasAPI.agenda();
    agenda.value = data.payload;
  } catch {
    advboxFora.value = true;
  }
};

const usarAgenda = item => {
  form.value = {
    cliente_nome: item.cliente_nome || '',
    motivo: item.notas || '',
    destinatario_id: item.destinatario_id ? String(item.destinatario_id) : '',
    advbox_customer_id: item.advbox_customer_id,
    advbox_post_id: item.advbox_post_id,
  };
  aba.value = 'livre';
};

const buscar = async () => {
  if (termo.value.trim().length < 2) return;
  try {
    const { data } = await RamonCalculosAPI.advboxCustomers(termo.value.trim());
    resultados.value = data.payload;
  } catch {
    advboxFora.value = true;
  }
};

const usarCliente = cliente => {
  form.value = {
    ...form.value,
    cliente_nome: cliente.name,
    advbox_customer_id: cliente.id,
  };
  aba.value = 'livre';
};

const avisar = async () => {
  if (!podeEnviar.value || enviando.value) return;
  enviando.value = true;
  try {
    await chegadas.criar({
      ...form.value,
      destinatario_id: Number(form.value.destinatario_id),
    });
    limpar();
  } finally {
    enviando.value = false;
  }
};

const abas = computed(() => [
  { nome: 'hoje', rotulo: t('RAMON.CHEGADA.ABA_HOJE') },
  { nome: 'buscar', rotulo: t('RAMON.CHEGADA.ABA_BUSCAR') },
  { nome: 'livre', rotulo: t('RAMON.CHEGADA.ABA_LIVRE') },
]);
const estados = computed(() => ({
  aguardando: t('RAMON.CHEGADA.ESTADO_aguardando'),
  escalado: t('RAMON.CHEGADA.ESTADO_escalado'),
  respondido: t('RAMON.CHEGADA.ESTADO_respondido'),
}));
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
      :title="t('RAMON.CHEGADA.TITULO')"
      :confirm-button-label="t('RAMON.CHEGADA.AVISAR')"
      :disable-confirm-button="!podeEnviar"
      :is-loading="enviando"
      @confirm="avisar"
    >
      <div class="flex flex-col gap-4">
        <div class="flex gap-2">
          <button
            v-for="{ nome, rotulo } in abas"
            :key="nome"
            type="button"
            class="rounded-lg px-3 py-1 text-sm"
            :class="
              aba === nome ? 'bg-n-alpha-2 text-n-slate-12' : 'text-n-slate-11'
            "
            @click="aba = nome"
          >
            {{ rotulo }}
          </button>
        </div>

        <p v-if="advboxFora" class="text-sm text-n-ruby-11">
          {{ t('RAMON.CHEGADA.ADVBOX_FORA') }}
        </p>

        <ul v-if="aba === 'hoje'" class="flex flex-col gap-1">
          <li
            v-if="!agenda.length && !advboxFora"
            class="text-sm text-n-slate-11"
          >
            {{ t('RAMON.CHEGADA.HOJE_VAZIO') }}
          </li>
          <li v-for="item in agenda" :key="item.advbox_post_id">
            <button
              type="button"
              data-testid="agenda-item"
              class="w-full rounded-lg px-3 py-2 text-start hover:bg-n-alpha-2"
              @click="usarAgenda(item)"
            >
              <span class="font-medium text-n-slate-12">{{
                item.cliente_nome
              }}</span>
              <span class="block text-xs text-n-slate-11">
                {{ item.responsavel_advbox
                }}{{ item.notas ? ` · ${item.notas}` : '' }}
              </span>
            </button>
          </li>
        </ul>

        <div v-else-if="aba === 'buscar'" class="flex flex-col gap-2">
          <input
            v-model="termo"
            :placeholder="t('RAMON.CHEGADA.BUSCAR_PLACEHOLDER')"
            class="rounded-lg bg-n-alpha-black2 px-3 py-2 text-n-slate-12"
            @keydown.enter.prevent="buscar"
          />
          <button
            v-for="cliente in resultados"
            :key="cliente.id"
            type="button"
            class="rounded-lg px-3 py-2 text-start hover:bg-n-alpha-2"
            @click="usarCliente(cliente)"
          >
            {{ cliente.name }}
          </button>
        </div>

        <div v-else class="flex flex-col gap-2">
          <input
            v-model="form.cliente_nome"
            data-testid="chegada-nome"
            :placeholder="t('RAMON.CHEGADA.NOME')"
            class="rounded-lg bg-n-alpha-black2 px-3 py-2 text-n-slate-12"
          />
          <input
            v-model="form.motivo"
            :placeholder="t('RAMON.CHEGADA.MOTIVO')"
            class="rounded-lg bg-n-alpha-black2 px-3 py-2 text-n-slate-12"
          />
        </div>

        <label class="flex flex-col gap-1 text-sm text-n-slate-11">
          {{ t('RAMON.CHEGADA.DESTINATARIO') }}
          <select
            v-model="form.destinatario_id"
            data-testid="chegada-destinatario"
            class="rounded-lg bg-n-alpha-black2 px-3 py-2 text-n-slate-12"
          >
            <option value="" disabled />
            <option
              v-for="agent in agents"
              :key="agent.id"
              :value="String(agent.id)"
            >
              {{ agent.name }}
            </option>
          </select>
        </label>

        <div
          v-if="deHoje.length"
          class="flex flex-col gap-1 border-t border-n-weak pt-3"
        >
          <p class="text-xs font-medium uppercase text-n-slate-11">
            {{ t('RAMON.CHEGADA.AGUARDANDO') }}
          </p>
          <p v-for="c in deHoje" :key="c.id" class="text-sm text-n-slate-12">
            {{ `${c.cliente_nome} → ${c.destinatario.name} · ` }}
            <span
              :class="
                c.estado === 'escalado' ? 'text-n-ruby-11' : 'text-n-slate-11'
              "
            >
              {{ estados[c.estado] }}
            </span>
            <span v-if="c.resposta" class="block text-n-slate-11">
              {{ `“${c.resposta}”` }}
            </span>
          </p>
        </div>
      </div>
    </Dialog>
  </div>
</template>

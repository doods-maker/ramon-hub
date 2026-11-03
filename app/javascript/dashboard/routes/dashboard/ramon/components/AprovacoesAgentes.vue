<script setup>
// Pedidos de permissão da esteira esperando resposta (ADR 0014). A lista vem
// de 5 em 5 s; quem aprovou em outra aba vê o pedido sumir na rodada seguinte.
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RamonAprovacoesAgenteAPI from 'dashboard/api/ramonAprovacoesAgente';
import Button from 'dashboard/components-next/button/Button.vue';

const INTERVALO_MS = 5000;

const { t } = useI18n();
const pedidos = ref([]);
const respondendo = ref(null);
let relogio = null;

const carregar = async () => {
  try {
    const { data } = await RamonAprovacoesAgenteAPI.get();
    pedidos.value = data;
  } catch {
    // Rede oscilou: a próxima rodada tenta de novo, e a lista atual segue valendo.
  }
};

const responder = async (pedido, decisao) => {
  respondendo.value = pedido.id;
  try {
    await RamonAprovacoesAgenteAPI.update(pedido.id, { decisao });
    pedidos.value = pedidos.value.filter(item => item.id !== pedido.id);
  } catch {
    useAlert(t('RAMON.AGENTES.APROVACOES.ERRO'));
    await carregar();
  } finally {
    respondendo.value = null;
  }
};

onMounted(() => {
  carregar();
  relogio = setInterval(carregar, INTERVALO_MS);
});
onBeforeUnmount(() => clearInterval(relogio));
</script>

<template>
  <ul v-if="pedidos.length" class="flex flex-col gap-2 mb-4">
    <li
      v-for="pedido in pedidos"
      :key="pedido.id"
      class="p-3 border rounded-xl border-n-weak bg-n-solid-1"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <p class="text-sm text-n-slate-12">
          {{
            t('RAMON.AGENTES.APROVACOES.PEDIDO', {
              caso: pedido.caso || '—',
              ferramenta: pedido.ferramenta,
            })
          }}
        </p>
        <div class="flex gap-2">
          <Button
            :label="t('RAMON.AGENTES.APROVACOES.NEGAR')"
            color="ruby"
            size="sm"
            :disabled="respondendo === pedido.id"
            @click="responder(pedido, 'negada')"
          />
          <Button
            :label="t('RAMON.AGENTES.APROVACOES.APROVAR')"
            color="blue"
            size="sm"
            :disabled="respondendo === pedido.id"
            @click="responder(pedido, 'aprovada')"
          />
        </div>
      </div>
      <details class="mt-2 text-xs text-n-slate-11">
        <summary class="cursor-pointer">
          {{ t('RAMON.AGENTES.APROVACOES.DETALHES') }}
        </summary>
        <pre class="mt-2 overflow-auto whitespace-pre-wrap max-h-64">{{
          JSON.stringify(pedido.entrada, null, 2)
        }}</pre>
      </details>
    </li>
  </ul>
</template>

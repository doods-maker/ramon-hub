<script setup>
// Pedidos de permissão da esteira esperando resposta (ADR 0014). A lista vem
// de 5 em 5 s; quem aprovou em outra aba vê o pedido sumir na rodada seguinte.
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RamonAprovacoesAgenteAPI from 'dashboard/api/ramonAprovacoesAgente';
import Button from 'dashboard/components-next/button/Button.vue';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { descreverPedido } from '../helpers/pedidoAgente';

const INTERVALO_MS = 5000;

const { t } = useI18n();
const pedidos = ref([]);
const respondendo = ref(null);
const negando = ref(null);
const motivo = ref('');
let relogio = null;

const cartoes = computed(() =>
  pedidos.value.map(pedido => ({ pedido, ...descreverPedido(pedido) }))
);

const carregar = async () => {
  try {
    const { data } = await RamonAprovacoesAgenteAPI.get();
    pedidos.value = data;
  } catch {
    // Rede oscilou: a próxima rodada tenta de novo, e a lista atual segue valendo.
  }
};

const responder = async (pedido, decisao, corpo = {}) => {
  respondendo.value = pedido.id;
  try {
    await RamonAprovacoesAgenteAPI.update(pedido.id, { decisao, ...corpo });
    pedidos.value = pedidos.value.filter(item => item.id !== pedido.id);
    negando.value = null;
    motivo.value = '';
  } catch {
    useAlert(t('RAMON.AGENTES.APROVACOES.ERRO'));
    await carregar();
  } finally {
    respondendo.value = null;
  }
};

const abrirNegativa = pedido => {
  negando.value = pedido.id;
  motivo.value = '';
};

const confirmarNegativa = pedido =>
  responder(
    pedido,
    'negada',
    motivo.value.trim() ? { motivo: motivo.value } : {}
  );

const espera = pedido =>
  pedido.created_at
    ? dynamicTime(new Date(pedido.created_at).getTime() / 1000)
    : '';

onMounted(() => {
  carregar();
  relogio = setInterval(carregar, INTERVALO_MS);
});
onBeforeUnmount(() => clearInterval(relogio));
</script>

<template>
  <section v-if="cartoes.length" class="mb-4">
    <p class="mb-2 text-sm font-medium text-n-slate-11">
      {{ t('RAMON.AGENTES.APROVACOES.ESPERANDO') }}
      <span
        class="inline-block px-2 ml-1 text-xs font-semibold rounded-full bg-n-amber-9/15 text-n-amber-11"
      >
        {{ cartoes.length }}
      </span>
    </p>
    <ul class="flex flex-col gap-3">
      <li
        v-for="cartao in cartoes"
        :key="cartao.pedido.id"
        class="p-4 border border-solid rounded-xl border-n-weak bg-n-solid-1"
      >
        <div class="flex items-start gap-3">
          <span
            class="grid flex-none rounded-lg size-9 place-items-center bg-n-blue-9/15 text-n-blue-11"
          >
            <span
              :class="cartao.icone"
              class="size-[18px]"
              aria-hidden="true"
            />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-base font-semibold text-n-slate-12">
              {{
                t(`RAMON.AGENTES.APROVACOES.ACOES.${cartao.chave}`, {
                  ferramenta: cartao.ferramenta,
                })
              }}
            </p>
            <p class="text-sm text-n-slate-11">
              <span v-if="cartao.cliente">{{ cartao.cliente }}</span>
              <span v-if="cartao.cliente && cartao.numero"> · </span>
              <span v-if="cartao.numero">
                {{
                  t('RAMON.AGENTES.APROVACOES.CASO', { numero: cartao.numero })
                }}
              </span>
            </p>
          </div>
          <span class="flex-none text-xs text-n-slate-10">
            {{ espera(cartao.pedido) }}
          </span>
        </div>

        <dl
          v-if="cartao.campos.length"
          class="flex flex-wrap gap-x-6 gap-y-1.5 mt-3.5"
        >
          <div v-for="campo in cartao.campos" :key="campo.chave">
            <dt class="text-xs tracking-wide uppercase text-n-slate-10">
              {{ t(`RAMON.AGENTES.APROVACOES.CAMPOS.${campo.chave}`) }}
            </dt>
            <dd class="text-sm font-medium text-n-slate-12">
              {{ campo.valor }}
            </dd>
          </div>
        </dl>

        <p
          v-if="cartao.linha"
          class="px-3 py-2 mt-3 font-mono text-xs break-all rounded-lg bg-n-alpha-1 text-n-slate-12"
        >
          {{ cartao.linha }}
        </p>

        <div
          v-if="cartao.blocos.length"
          class="flex flex-col gap-2.5 px-3.5 py-3 mt-3.5 overflow-auto text-sm rounded-lg max-h-72 bg-n-alpha-1 text-n-slate-12"
        >
          <div v-for="(bloco, indice) in cartao.blocos" :key="indice">
            <p
              v-if="bloco.rotulo"
              class="text-xs font-semibold tracking-wide text-n-slate-11"
            >
              {{ bloco.rotulo }}
            </p>
            <p class="whitespace-pre-line">{{ bloco.texto }}</p>
          </div>
        </div>

        <div v-if="negando === cartao.pedido.id" class="mt-3.5">
          <label class="block text-sm text-n-slate-11">
            {{ t('RAMON.AGENTES.APROVACOES.MOTIVO') }}
            <textarea
              v-model="motivo"
              rows="2"
              maxlength="1000"
              class="block w-full mt-1 mb-0 text-sm"
              :placeholder="t('RAMON.AGENTES.APROVACOES.MOTIVO_EXEMPLO')"
            />
          </label>
        </div>

        <div class="flex flex-wrap items-center gap-2 mt-3.5">
          <details
            class="flex-1 text-xs min-w-44 text-n-slate-10"
            :open="!cartao.conhecida"
          >
            <summary class="cursor-pointer">
              {{ t('RAMON.AGENTES.APROVACOES.DETALHES') }}
            </summary>
            <pre
              class="p-2 mt-2 overflow-auto font-mono rounded-md whitespace-pre-wrap max-h-64 bg-n-alpha-1 text-n-slate-11"
              >{{ JSON.stringify(cartao.pedido.entrada, null, 2) }}</pre
            >
          </details>
          <div v-if="negando === cartao.pedido.id" class="flex gap-2 ms-auto">
            <Button
              :label="t('RAMON.AGENTES.APROVACOES.VOLTAR')"
              variant="faded"
              color="slate"
              size="sm"
              :disabled="respondendo === cartao.pedido.id"
              @click="negando = null"
            />
            <Button
              :label="t('RAMON.AGENTES.APROVACOES.CONFIRMAR_NEGATIVA')"
              color="ruby"
              size="sm"
              :disabled="respondendo === cartao.pedido.id"
              @click="confirmarNegativa(cartao.pedido)"
            />
          </div>
          <div v-else class="flex gap-2 ms-auto">
            <Button
              :label="t('RAMON.AGENTES.APROVACOES.NEGAR')"
              color="ruby"
              size="sm"
              :disabled="respondendo === cartao.pedido.id"
              @click="abrirNegativa(cartao.pedido)"
            />
            <Button
              :label="t('RAMON.AGENTES.APROVACOES.APROVAR')"
              color="blue"
              size="sm"
              :disabled="respondendo === cartao.pedido.id"
              @click="responder(cartao.pedido, 'aprovada')"
            />
          </div>
        </div>
      </li>
    </ul>
  </section>
</template>

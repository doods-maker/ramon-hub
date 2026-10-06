<script setup>
// "Rodar fluxo…" (spec §7): lista os fluxos publicados e ligados com gatilho
// manual e roda o escolhido neste lead/conversa pela API da B1
// (POST ramon_fluxos/:id/rodar). Só admin (RamonFluxoPolicy): quem abre este
// modal já esconde o item de menu para quem não é admin.
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onKeyStroke } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import RamonFluxosAPI from 'dashboard/api/ramonFluxos';
import {
  AVISO,
  FUNDO_JANELA,
  JANELA,
  LINHA,
  TITULO_JANELA,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';

const props = defineProps({
  // o mesmo corpo do POST …/rodar: { lead_id } | { conversation_id } (display_id)
  alvo: { type: Object, required: true },
});
const emit = defineEmits(['fechar']);
const K = 'CAPTAIN_RAMON.FLUXOS.RODAR';
const { t } = useI18n();
const { accountScopedRoute } = useAccount();

const fluxos = ref(null); // null = carregando
const rodando = ref(null);
const erro = ref('');

// fechar (Esc, fundo, botão) não vale enquanto um fluxo está rodando; o fechar do sucesso sai direto
const fechar = () => {
  if (!rodando.value) emit('fechar');
};
onKeyStroke('Escape', fechar);

onMounted(async () => {
  try {
    const { data } = await RamonFluxosAPI.get();
    fluxos.value = data.payload.filter(
      f =>
        f.origem !== 'sistema' &&
        f.gatilho_tipo === 'manual' &&
        f.ativo &&
        f.versao
    );
  } catch (e) {
    fluxos.value = [];
    erro.value = t(`${K}.ERRO_LISTA`);
  }
});

// clique duplo não roda duas vezes
const rodar = async fluxo => {
  if (rodando.value) return;
  rodando.value = fluxo.id;
  erro.value = '';
  try {
    const { data } = await RamonFluxosAPI.rodar(fluxo.id, props.alvo);
    useAlert(t(`${K}.RODOU`, { nome: fluxo.nome }), {
      type: 'link',
      to: accountScopedRoute('captain_automacoes_execucao', {
        fluxoId: fluxo.id,
        execId: data.id,
      }),
      message: t(`${K}.VER_EXECUCAO`),
    });
    emit('fechar');
  } catch (e) {
    erro.value =
      e.response?.data?.erro === 'FLUXO_NAO_RODOU'
        ? t(`${K}.NAO_RODOU`)
        : t(`${K}.ERRO`);
  } finally {
    rodando.value = null;
  }
};
</script>

<template>
  <Teleport to="body">
    <div :class="FUNDO_JANELA" @click.self="fechar">
      <div :class="JANELA" class="!w-[420px]" data-testid="rodar-fluxo">
        <h2 :class="TITULO_JANELA">{{ t(`${K}.TITULO`) }}</h2>
        <p class="mb-3 text-xs text-n-slate-10">{{ t(`${K}.AJUDA`) }}</p>
        <p
          v-if="erro"
          data-testid="rodar-erro"
          :class="[AVISO, TOM.ruby]"
          class="mb-3"
        >
          {{ erro }}
        </p>

        <p v-if="fluxos === null" class="text-sm text-n-slate-10">
          {{ t(`${K}.CARREGANDO`) }}
        </p>
        <div
          v-else-if="!fluxos.length"
          data-testid="rodar-vazio"
          class="text-sm text-n-slate-11"
        >
          <p class="mb-2">{{ t(`${K}.VAZIO`) }}</p>
          <router-link
            :to="accountScopedRoute('captain_automacoes_index')"
            class="text-n-blue-11 hover:underline"
            @click="emit('fechar')"
          >
            {{ t(`${K}.IR_AUTOMACOES`) }}
          </router-link>
        </div>
        <div v-else class="flex flex-col gap-0.5">
          <button
            v-for="f in fluxos"
            :key="f.id"
            type="button"
            data-testid="rodar-fluxo-item"
            :class="LINHA"
            class="flex items-center gap-2"
            :disabled="rodando !== null"
            @click="rodar(f)"
          >
            <i class="i-lucide-hand size-4 shrink-0 text-n-blue-11" />
            <span class="min-w-0 flex-1 truncate">{{ f.nome }}</span>
            <i
              v-if="rodando === f.id"
              class="i-lucide-loader-circle size-4 animate-spin"
            />
          </button>
        </div>

        <div class="mt-4 flex justify-end">
          <Button
            ghost
            slate
            sm
            :label="t('CAPTAIN_RAMON.FLUXOS.FECHAR')"
            @click="fechar"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>

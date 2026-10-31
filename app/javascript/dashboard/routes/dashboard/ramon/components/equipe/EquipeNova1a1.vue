<script setup>
import { computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import EquipeAPI from 'dashboard/api/ramonEquipe';

// Caixa Equipe (ADR 0011): abre (ou reabre) a 1:1 com um colega. Aviso fixo de
// que administradores leem as conversas (decisão do Eduardo, 02/10).
const props = defineProps({
  inboxId: { type: Number, required: true },
});

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const agentes = useMapGetter('agents/getAgents');
const meuId = useMapGetter('getCurrentUserID');
const accountId = useMapGetter('getCurrentAccountId');

const colegas = computed(() => agentes.value.filter(a => a.id !== meuId.value));

onMounted(() => store.dispatch('agents/get'));

const abrir = async event => {
  const userId = Number(event.target.value);
  event.target.value = '';
  if (!userId) return;
  try {
    const { data } = await EquipeAPI.conversa(userId);
    router.push({
      name: 'conversation_through_inbox',
      params: {
        accountId: accountId.value,
        inbox_id: props.inboxId,
        conversation_id: data.id,
      },
    });
  } catch {
    useAlert(t('RAMON.EQUIPE.ERRO'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-1 px-4 pb-2">
    <select
      data-testid="equipe-nova-1a1"
      class="w-full h-8 px-2 text-sm rounded-lg bg-n-alpha-black2 text-n-slate-12 outline outline-1 outline-n-weak"
      @change="abrir"
    >
      <option value="">{{ t('RAMON.EQUIPE.NOVA_1A1') }}</option>
      <option v-for="colega in colegas" :key="colega.id" :value="colega.id">
        {{ colega.available_name || colega.name }}
      </option>
    </select>
    <p class="m-0 text-xs text-n-slate-11">
      {{ t('RAMON.EQUIPE.AVISO_ADMIN') }}
    </p>
  </div>
</template>

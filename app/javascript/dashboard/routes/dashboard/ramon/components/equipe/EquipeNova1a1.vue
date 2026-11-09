<script setup>
import { computed, onMounted, ref, useTemplateRef } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import EquipeAPI from 'dashboard/api/ramonEquipe';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

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

const containerRef = useTemplateRef('containerRef');
const aberto = ref(false);

const colegas = computed(() =>
  agentes.value
    .filter(a => a.id !== meuId.value)
    .map(a => {
      const nome = a.available_name || a.name;
      return {
        action: 'abrir',
        value: a.id,
        label: nome,
        thumbnail: { name: nome, src: a.thumbnail },
      };
    })
);

onMounted(() => store.dispatch('agents/get'));

const abrir = async ({ value: userId }) => {
  aberto.value = false;
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
    <div ref="containerRef" class="relative">
      <!-- Verde do WhatsApp translúcido, igual ao contador de não lidas. -->
      <button
        type="button"
        data-testid="equipe-nova-1a1"
        class="w-full h-9 inline-flex items-center justify-center gap-2 rounded-lg border-0 text-sm font-medium transition-colors bg-[rgb(var(--ramon-nao-lida)/0.16)] hover:bg-[rgb(var(--ramon-nao-lida)/0.24)] text-[rgb(var(--ramon-nao-lida-texto))]"
        @click="aberto = !aberto"
      >
        <span class="i-lucide-message-square-plus size-4" />
        {{ t('RAMON.EQUIPE.NOVA_1A1') }}
      </button>
      <DropdownMenu
        v-if="aberto"
        v-on-click-outside="[
          () => (aberto = false),
          { ignore: [containerRef] },
        ]"
        :menu-items="colegas"
        :thumbnail-size="28"
        show-search
        :search-placeholder="t('RAMON.EQUIPE.BUSCAR_COLEGA')"
        class="top-10 inset-x-0 max-h-96"
        @action="abrir"
      />
    </div>
    <p class="m-0 text-xs text-n-slate-11">
      {{ t('RAMON.EQUIPE.AVISO_ADMIN') }}
    </p>
  </div>
</template>

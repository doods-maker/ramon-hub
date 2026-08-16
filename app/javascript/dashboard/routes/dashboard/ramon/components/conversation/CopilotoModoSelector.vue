<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

defineOptions({ name: 'CopilotoModoSelector' });
const { t } = useI18n();
const store = useStore();
const currentChat = useMapGetter('getSelectedChat');

const MODOS = ['manual', 'rascunho', 'piloto_limitado', 'piloto_total'];
const open = ref(false);
const saving = ref(false);

const modo = computed(() => {
  const m = currentChat.value?.custom_attributes?.copiloto_modo;
  return MODOS.includes(m) ? m : 'rascunho';
});

const escolher = async novoModo => {
  if (saving.value || novoModo === modo.value) return;
  saving.value = true;
  try {
    // backend SUBSTITUI o hash: mandar sempre o merge completo
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes: {
        ...(currentChat.value.custom_attributes || {}),
        copiloto_modo: novoModo,
      },
    });
    open.value = false;
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="relative">
    <button
      type="button"
      data-testid="copiloto-modo-btn"
      class="rounded-full bg-n-iris-9/10 text-n-iris-11 text-xs px-2 py-1"
      @click="open = !open"
    >
      {{
        `✦ ${t('RAMON.COPILOTO.BTN', {
          modo: t(`RAMON.COPILOTO.MODOS.${modo}.NOME`),
        })} ▾`
      }}
    </button>
    <div v-if="open" class="fixed inset-0 z-40" @click="open = false" />
    <div
      v-if="open"
      class="absolute right-0 top-9 z-50 w-80 rounded-xl border border-n-weak bg-n-solid-1 shadow-lg p-3"
    >
      <p class="text-xs font-medium text-n-slate-11 mb-2">
        {{ t('RAMON.COPILOTO.TITULO') }}
      </p>
      <button
        v-for="m in MODOS"
        :key="m"
        type="button"
        :data-testid="`copiloto-modo-opcao-${m}`"
        class="w-full text-left rounded-lg p-2 hover:bg-n-alpha-2"
        :class="{ 'bg-n-alpha-2': m === modo }"
        @click="escolher(m)"
      >
        <p class="text-sm font-medium text-n-slate-12">
          {{ t(`RAMON.COPILOTO.MODOS.${m}.NOME`) }}
        </p>
        <p class="text-xs text-n-slate-11">
          {{ t(`RAMON.COPILOTO.MODOS.${m}.DESC`) }}
        </p>
        <p v-if="m === 'piloto_limitado'" class="text-xs text-n-slate-10 mt-1">
          {{ t('RAMON.COPILOTO.MODOS.piloto_limitado.NOTA') }}
        </p>
      </button>
    </div>
  </div>
</template>

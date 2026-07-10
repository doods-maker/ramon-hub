<script setup>
// Substituto do window.prompt: pergunta um nome no padrão visual da casa.
import { ref, nextTick, onMounted, onBeforeUnmount } from 'vue';

defineProps({
  title: { type: String, required: true },
  placeholder: { type: String, default: '' },
  confirmLabel: { type: String, required: true },
});
const emit = defineEmits(['confirm', 'cancel']);

const name = ref('');
const input = ref(null);

const confirm = () => {
  const value = name.value.trim();
  if (!value) return;
  emit('confirm', value);
};

const onDocKeydown = e => {
  if (e.key === 'Escape') emit('cancel');
};
onMounted(() => {
  document.addEventListener('keydown', onDocKeydown);
  nextTick(() => input.value?.focus());
});
onBeforeUnmount(() => document.removeEventListener('keydown', onDocKeydown));
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="emit('cancel')"
  >
    <div
      class="w-80 max-w-[92vw] p-5 rounded-xl bg-n-solid-2 border border-n-weak"
    >
      <h3 class="mb-3 text-sm text-n-slate-12">{{ title }}</h3>
      <input
        ref="input"
        v-model="name"
        data-testid="name-prompt-input"
        class="w-full px-3 py-2 mb-3 text-sm rounded-lg bg-n-alpha-2 border border-transparent outline-none focus:border-n-slate-8 text-n-slate-12"
        :placeholder="placeholder"
        @keyup.enter="confirm"
      />
      <div class="flex justify-end gap-2">
        <button
          data-testid="name-prompt-cancel"
          class="px-3 py-1.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12"
          @click="emit('cancel')"
        >
          {{ $t('RAMON.MODAL.CANCEL') }}
        </button>
        <button
          data-testid="name-prompt-confirm"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-iris-9 text-white hover:bg-n-iris-10 disabled:opacity-50"
          :disabled="!name.trim()"
          @click="confirm"
        >
          {{ confirmLabel }}
        </button>
      </div>
    </div>
  </div>
</template>

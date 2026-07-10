<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';

const props = defineProps({
  lostReasons: { type: Array, default: () => [] },
});
const emit = defineEmits(['confirmMove', 'cancelMove']);

const reasonId = ref(null);
const detail = ref('');

const selectedReason = computed(() =>
  props.lostReasons.find(r => r.id === reasonId.value)
);

const confirm = () => {
  if (!selectedReason.value) return;
  // Concatena "Motivo — detalhe" quando há um detalhe livre.
  const text = detail.value.trim()
    ? `${selectedReason.value.name} — ${detail.value.trim()}`
    : selectedReason.value.name;
  emit('confirmMove', { lostReason: text });
};

// Esc cancela (reverte o drag), igual ao clique no backdrop.
const onDocKeydown = e => {
  if (e.key === 'Escape') emit('cancelMove');
};
onMounted(() => document.addEventListener('keydown', onDocKeydown));
onBeforeUnmount(() => document.removeEventListener('keydown', onDocKeydown));
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    @click.self="emit('cancelMove')"
  >
    <div
      class="w-80 max-w-[92vw] p-5 rounded-xl bg-n-solid-2 border border-n-weak"
    >
      <h3 class="mb-3 text-sm text-n-slate-12">
        {{ $t('RAMON.FUNIL.LOST.TITLE') }}
      </h3>
      <select
        v-model="reasonId"
        data-testid="lost-reason-select"
        class="w-full px-2 py-1.5 mb-3 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      >
        <option :value="null" disabled>
          {{ $t('RAMON.FUNIL.LOST.PICK') }}
        </option>
        <option v-for="r in lostReasons" :key="r.id" :value="r.id">
          {{ r.name }}
        </option>
      </select>
      <textarea
        v-model="detail"
        data-testid="lost-reason-detail"
        rows="2"
        maxlength="500"
        :placeholder="$t('RAMON.FUNIL.LOST.DETAIL_PLACEHOLDER')"
        class="w-full px-2 py-1.5 mb-3 text-sm rounded-lg resize-none bg-n-alpha-2 text-n-slate-12"
      />
      <div class="flex justify-end gap-2">
        <button
          class="px-3 py-1.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12"
          @click="emit('cancelMove')"
        >
          {{ $t('RAMON.FUNIL.LOST.CANCEL') }}
        </button>
        <button
          data-testid="lost-reason-confirm"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-ruby-9 text-white disabled:opacity-50"
          :disabled="!selectedReason"
          @click="confirm"
        >
          {{ $t('RAMON.FUNIL.LOST.CONFIRM') }}
        </button>
      </div>
    </div>
  </div>
</template>

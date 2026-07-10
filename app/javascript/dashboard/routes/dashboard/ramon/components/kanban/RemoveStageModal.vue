<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';

const props = defineProps({
  stage: { type: Object, required: true },
  stages: { type: Array, default: () => [] },
});
const emit = defineEmits(['confirm', 'cancel']);

const targetId = ref(null);
const options = computed(() =>
  props.stages.filter(s => s.id !== props.stage.id)
);

const confirm = () => {
  if (!targetId.value) return;
  emit('confirm', { id: props.stage.id, moveToStageId: targetId.value });
};

const onDocKeydown = e => {
  if (e.key === 'Escape') emit('cancel');
};
onMounted(() => document.addEventListener('keydown', onDocKeydown));
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
      <h3 class="mb-3 text-sm text-n-slate-12">
        {{ $t('RAMON.FUNIL.STAGE.REMOVE_TITLE', { name: stage.name }) }}
      </h3>
      <select
        v-model="targetId"
        data-testid="remove-target"
        class="w-full px-2 py-1.5 mb-3 text-sm rounded-lg bg-n-alpha-2 text-n-slate-12"
      >
        <option :value="null" disabled>
          {{ $t('RAMON.FUNIL.STAGE.REMOVE_PICK') }}
        </option>
        <option v-for="s in options" :key="s.id" :value="s.id">
          {{ s.name }}
        </option>
      </select>
      <div class="flex justify-end gap-2">
        <button
          class="px-3 py-1.5 text-sm rounded-lg text-n-slate-11 hover:text-n-slate-12"
          @click="emit('cancel')"
        >
          {{ $t('RAMON.FUNIL.STAGE.CANCEL') }}
        </button>
        <button
          data-testid="remove-confirm"
          class="px-3 py-1.5 text-sm rounded-lg bg-n-ruby-9 text-white disabled:opacity-50"
          :disabled="!targetId"
          @click="confirm"
        >
          {{ $t('RAMON.FUNIL.STAGE.REMOVE_CONFIRM') }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { sparklinePath } from '../../helpers/sparkline';

const props = defineProps({
  points: { type: Array, default: () => [] },
  width: { type: Number, default: 240 },
  height: { type: Number, default: 40 },
});

const path = computed(() =>
  sparklinePath(props.points, { width: props.width, height: props.height })
);
</script>

<template>
  <svg
    :width="width"
    :height="height"
    :viewBox="`0 0 ${width} ${height}`"
    class="text-n-iris-9"
  >
    <path
      v-if="path"
      :d="path"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    />
  </svg>
</template>

<script setup>
defineProps({ dados: { type: Object, required: true } });
</script>

<template>
  <div
    :data-papel="dados.papel"
    class="grid w-full max-w-[1240px] grid-cols-1 gap-10 px-7 pb-12 pt-6 xl:grid-cols-[1fr_300px]"
  />
</template>

<script setup>
// Lista clicável de itens do Centro de Comando.
// type='task' → item de tarefa (usa lead_id ao selecionar);
// type='lead' → item de lead/etapa (usa id ao selecionar).
defineProps({
  items: { type: Array, default: () => [] },
  type: {
    type: String,
    default: 'lead',
    validator: value => ['task', 'lead'].includes(value),
  },
});

const emit = defineEmits(['select']);

const targetId = item => (item.lead_id != null ? item.lead_id : item.id);
</script>

<template>
  <ul class="flex flex-col gap-0.5">
    <li v-for="item in items" :key="item.id">
      <button
        type="button"
        class="flex flex-col w-full px-1 py-1 text-left rounded hover:bg-n-alpha-2"
        @click="emit('select', targetId(item))"
      >
        <span class="text-sm truncate text-n-slate-12">
          {{ type === 'task' ? item.lead_name : item.name }}
        </span>
        <span class="text-xs truncate text-n-slate-10">
          <template v-if="type === 'task'">{{ item.title }}</template>
          <template v-else>{{ item.stage_name }}</template>
        </span>
      </button>
    </li>
  </ul>
</template>

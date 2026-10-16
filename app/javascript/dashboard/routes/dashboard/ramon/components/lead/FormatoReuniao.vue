<script setup>
// Seletor Vídeo (Meet) / Ligação pelo WhatsApp da reunião — mesmo par de botões do tipo de tarefa.
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({ modelValue: { type: String, default: 'video' } });
defineEmits(['update:modelValue']);
defineOptions({ name: 'FormatoReuniao' });

const FORMATOS = [
  { id: 'video', label: 'RAMON.TASKS.FORMATO_VIDEO' },
  { id: 'whatsapp', label: 'RAMON.TASKS.FORMATO_WHATSAPP' },
];
</script>

<template>
  <div class="flex gap-1.5" data-testid="formato-reuniao">
    <Button
      v-for="f in FORMATOS"
      :key="f.id"
      :data-testid="`formato-${f.id}`"
      xs
      :variant="modelValue === f.id ? 'solid' : 'faded'"
      :color="modelValue === f.id ? 'blue' : 'slate'"
      :label="$t(f.label)"
      @click="$emit('update:modelValue', f.id)"
    />
  </div>
</template>

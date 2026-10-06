<script setup>
// Passos de IA: perguntar (sim/não), rascunho escrito pela IA, rodar uma skill do Captain.
// Assistentes e skills vêm das APIs do Captain (enterprise); sem elas, aviso e nada quebra.
import { onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CaptainAssistantAPI from 'dashboard/api/captain/assistant';
import CaptainScenariosAPI from 'dashboard/api/captain/scenarios';
import {
  AVISO,
  ROTULO,
  SELECT,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import CampoTexto from './CampoTexto.vue';

const props = defineProps({
  tipo: { type: String, required: true },
  config: { type: Object, required: true },
});
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS.PAINEL';
const { t } = useI18n();
const assistentes = ref([]);
const skills = ref([]);
const semCaptain = ref(false);

const muda = (chave, valor) =>
  emit('update:config', { ...props.config, [chave]: valor });
const numeroOuNada = v => (v === '' ? null : Number(v));

// descarta resposta velha (troca rápida de assistente ou componente desmontado)
let seq = 0;
const carregarSkills = async id => {
  seq += 1;
  const req = seq;
  skills.value = [];
  if (!id) return;
  try {
    const { data } = await CaptainScenariosAPI.get({ assistantId: id });
    if (req !== seq) return;
    skills.value = data.payload || [];
  } catch {
    if (req === seq) semCaptain.value = true;
  }
};

const trocaAssistente = id => {
  emit('update:config', { ...props.config, assistente_id: id, skill_id: null });
  carregarSkills(id);
};

onMounted(async () => {
  if (props.tipo !== 'rodar_skill') return;
  try {
    const { data } = await CaptainAssistantAPI.get();
    assistentes.value = data.payload || [];
  } catch {
    semCaptain.value = true;
    return;
  }
  carregarSkills(props.config.assistente_id);
});
onBeforeUnmount(() => {
  seq += 1;
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <template v-if="tipo === 'perguntar_ia'">
      <CampoTexto
        :rotulo="t(`${K}.PERGUNTA`)"
        :linhas="2"
        :model-value="config.pergunta || ''"
        @update:model-value="v => muda('pergunta', v)"
      />
      <p class="text-xs text-n-slate-10">{{ t(`${K}.PERGUNTA_AJUDA`) }}</p>
    </template>

    <template v-else-if="tipo === 'rascunho_ia'">
      <CampoTexto
        :rotulo="t(`${K}.INSTRUCAO`)"
        :model-value="config.instrucao || ''"
        @update:model-value="v => muda('instrucao', v)"
      />
      <p class="text-xs text-n-slate-10">{{ t(`${K}.INSTRUCAO_AJUDA`) }}</p>
    </template>

    <template v-else>
      <p
        v-if="semCaptain"
        data-testid="ia-sem-captain"
        :class="[AVISO, TOM.ruby]"
      >
        {{ t(`${K}.SEM_CAPTAIN`) }}
      </p>
      <label :class="ROTULO">
        {{ t(`${K}.ASSISTENTE`) }}
        <select
          data-testid="ia-assistente"
          :class="SELECT"
          :value="config.assistente_id ?? ''"
          @change="trocaAssistente(numeroOuNada($event.target.value))"
        >
          <option value="" disabled>{{ t(`${K}.ESCOLHA`) }}</option>
          <option v-for="a in assistentes" :key="a.id" :value="a.id">
            {{ a.name }}
          </option>
        </select>
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.SKILL`) }}
        <select
          data-testid="ia-skill"
          :class="SELECT"
          :disabled="!config.assistente_id"
          :value="config.skill_id ?? ''"
          @change="muda('skill_id', numeroOuNada($event.target.value))"
        >
          <option value="" disabled>{{ t(`${K}.ESCOLHA`) }}</option>
          <option v-for="s in skills" :key="s.id" :value="s.id">
            {{ s.title }}
          </option>
        </select>
      </label>
      <CampoTexto
        :rotulo="t(`${K}.INSTRUCAO_SKILL`)"
        :linhas="2"
        :model-value="config.instrucao || ''"
        @update:model-value="v => muda('instrucao', v)"
      />
      <p class="text-xs text-n-slate-10">{{ t(`${K}.SKILL_AJUDA`) }}</p>
    </template>
  </div>
</template>

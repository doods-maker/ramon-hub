<script setup>
// Escolha: um campo e uma saída por caso ({chave, rotulo, valores}) + "outro".
// Apagar um caso leva a seta junto (deVueFlow poda a porta que sumiu).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  CAMPO,
  CHIP,
  ROTULO,
  SELECT,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { CAMPOS, novaChave } from './fluxo';

const props = defineProps({ config: { type: Object, required: true } });
const emit = defineEmits(['update:config']);
const K = 'CAPTAIN_RAMON.FLUXOS';
const { t } = useI18n();
const novos = ref({});

const casos = () => props.config.casos || [];
const muda = (chave, valor) =>
  emit('update:config', { ...props.config, [chave]: valor });
const mudaCaso = (i, chave, valor) =>
  muda(
    'casos',
    casos().map((c, j) => (j === i ? { ...c, [chave]: valor } : c))
  );
const incluirValor = i => {
  const v = (novos.value[i] || '').trim();
  if (!v) return;
  mudaCaso(i, 'valores', [...(casos()[i].valores || []), v]);
  novos.value[i] = '';
};
const tirarValor = (i, v) =>
  mudaCaso(
    i,
    'valores',
    casos()[i].valores.filter(x => x !== v)
  );
const adicionar = () =>
  muda('casos', [
    ...casos(),
    { chave: novaChave(casos()), rotulo: '', valores: [] },
  ]);
const remover = i =>
  muda(
    'casos',
    casos().filter((_c, j) => j !== i)
  );
</script>

<template>
  <div class="flex flex-col gap-4">
    <label :class="ROTULO">
      {{ t(`${K}.PAINEL.CAMPO_ESCOLHA`) }}
      <select
        :class="SELECT"
        :value="config.campo"
        @change="muda('campo', $event.target.value)"
      >
        <option v-for="campo in CAMPOS" :key="campo" :value="campo">
          {{ t(`${K}.CAMPOS.${campo}`) }}
        </option>
      </select>
    </label>

    <div
      v-for="(caso, i) in config.casos || []"
      :key="caso.chave"
      class="flex flex-col gap-2 border-t border-n-weak pt-3"
    >
      <label :class="ROTULO">
        {{ t(`${K}.PAINEL.ROTULO_CASO`) }}
        <input
          :class="CAMPO"
          :value="caso.rotulo"
          @input="mudaCaso(i, 'rotulo', $event.target.value)"
        />
      </label>
      <label :class="ROTULO">
        {{ t(`${K}.PAINEL.VALORES`) }}
        <input
          v-model="novos[i]"
          :class="CAMPO"
          @keydown.enter.prevent="incluirValor(i)"
        />
      </label>
      <div class="flex flex-wrap gap-1">
        <button
          v-for="v in caso.valores || []"
          :key="v"
          type="button"
          :class="[CHIP, TOM.slate]"
          @click="tirarValor(i, v)"
        >
          {{ v }}
          <i class="i-lucide-x size-3" />
        </button>
      </div>
      <Button
        class="self-end"
        link
        ruby
        xs
        :label="t(`${K}.PAINEL.REMOVER`)"
        @click="remover(i)"
      />
    </div>

    <Button
      class="self-start"
      faded
      slate
      xs
      icon="i-lucide-plus"
      :label="t(`${K}.PAINEL.ADD_CASO`)"
      @click="adicionar"
    />
    <p class="text-xs text-n-slate-10">{{ t(`${K}.PAINEL.OUTRO_AJUDA`) }}</p>
  </div>
</template>

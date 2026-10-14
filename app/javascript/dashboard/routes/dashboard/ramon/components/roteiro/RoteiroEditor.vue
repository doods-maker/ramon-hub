<script setup>
// Roteiro da IA de um escopo (F2): passos comuns da conta (thesisId null) ou de uma tese. Lista em ordem, ↑↓ para
// reordenar, clique abre o passo em sanfona; salvar/remover/reordenar vão direto à API e avisam a tela (mudou).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import RoteiroPassosAPI from 'dashboard/api/roteiroPassos';
import ConfirmModal from '../ConfirmModal.vue';
import RoteiroPassoForm from './RoteiroPassoForm.vue';
import { mensagemErro } from '../../helpers/erro';
import { destinosDe, passosDe } from '../../helpers/roteiro';
import { CHIP, TOM } from '../../helpers/ui';

const props = defineProps({
  // null = passos comuns da conta
  thesisId: { type: Number, default: null },
  // todos os passos da conta (index da API)
  passos: { type: Array, required: true },
  calculadoras: { type: Object, required: true },
});
const emit = defineEmits(['mudou']);
const { t } = useI18n();

const lista = computed(() => passosDe(props.passos, props.thesisId));
const destinos = computed(() => destinosDe(props.passos, props.thesisId));
// id do passo aberto, 'novo' ou null
const aberto = ref(null);
const salvando = ref(false);

const falhou = e => useAlert(mensagemErro(e, t('RAMON.FUNIL.SAVE_ERROR')));

const salvar = async (passo, payload) => {
  if (salvando.value) return;
  salvando.value = true;
  try {
    if (passo) await RoteiroPassosAPI.update(passo.id, payload);
    else
      await RoteiroPassosAPI.create({ ...payload, thesis_id: props.thesisId });
    aberto.value = null;
    useAlert(t('RAMON.ROTEIRO_IA.EDITOR.SALVO'));
    emit('mudou');
  } catch (e) {
    falhou(e);
  } finally {
    salvando.value = false;
  }
};

const mover = async (indice, direcao) => {
  const ids = lista.value.map(p => p.id);
  const alvo = indice + direcao;
  if (alvo < 0 || alvo >= ids.length) return;
  [ids[indice], ids[alvo]] = [ids[alvo], ids[indice]];
  try {
    await RoteiroPassosAPI.reorder(ids);
    emit('mudou');
  } catch (e) {
    falhou(e);
  }
};

const aRemover = ref(null);
const remover = async () => {
  const passo = aRemover.value;
  // fecha antes do await: sem janela para duplo clique
  aRemover.value = null;
  try {
    await RoteiroPassosAPI.delete(passo.id);
    emit('mudou');
  } catch (e) {
    falhou(e);
  }
};

const alternar = passo => {
  aberto.value = aberto.value === passo.id ? null : passo.id;
};
</script>

<template>
  <div class="flex flex-col gap-2" data-testid="roteiro-editor">
    <p
      v-if="!lista.length && aberto !== 'novo'"
      class="m-0 text-xs text-n-slate-10"
    >
      {{ $t('RAMON.ROTEIRO_IA.EDITOR.VAZIO') }}
    </p>
    <ul class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
      <li
        v-for="(passo, indice) in lista"
        :key="passo.id"
        data-testid="roteiro-passo-linha"
        class="flex flex-col gap-2 py-2 first:pt-0"
      >
        <div class="flex items-center gap-2">
          <span
            class="w-5 shrink-0 text-right font-mono text-xs text-n-slate-10"
          >
            {{ indice + 1 }}
          </span>
          <button
            type="button"
            data-testid="roteiro-passo-abrir"
            class="min-w-0 flex-1 truncate p-0 text-left text-sm font-medium text-n-slate-12 hover:text-n-blue-11"
            @click="alternar(passo)"
          >
            {{ passo.titulo }}
          </button>
          <span class="shrink-0 font-mono text-[11px] text-n-slate-10">
            {{ passo.chave }}
          </span>
          <span class="shrink-0" :class="[CHIP, TOM.slate]">
            {{
              $t(
                `RAMON.ROTEIRO_IA.EDITOR.TIPOS.${passo.tipo_resposta.toUpperCase()}`
              )
            }}
          </span>
          <span
            v-if="passo.calculadora"
            class="shrink-0"
            :class="[CHIP, TOM.iris]"
          >
            {{
              $t(
                `RAMON.ROTEIRO_IA.EDITOR.CALCULADORAS.${passo.calculadora.toUpperCase()}`
              )
            }}
          </span>
          <span
            v-if="passo.saidas.length"
            class="shrink-0"
            :class="[CHIP, TOM.blue]"
          >
            {{
              $t('RAMON.ROTEIRO_IA.EDITOR.N_SAIDAS', { n: passo.saidas.length })
            }}
          </span>
          <Button
            data-testid="roteiro-passo-subir"
            xs
            ghost
            slate
            icon="i-lucide-chevron-up"
            :aria-label="$t('RAMON.ROTEIRO_IA.EDITOR.MOVER_CIMA')"
            :disabled="indice === 0"
            @click="mover(indice, -1)"
          />
          <Button
            data-testid="roteiro-passo-descer"
            xs
            ghost
            slate
            icon="i-lucide-chevron-down"
            :aria-label="$t('RAMON.ROTEIRO_IA.EDITOR.MOVER_BAIXO')"
            :disabled="indice === lista.length - 1"
            @click="mover(indice, 1)"
          />
          <Button
            data-testid="roteiro-passo-remover"
            xs
            ghost
            slate
            icon="i-lucide-trash-2"
            :aria-label="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER')"
            :title="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER')"
            @click="aRemover = passo"
          />
        </div>
        <RoteiroPassoForm
          v-if="aberto === passo.id"
          :passo="passo"
          :destinos="destinos"
          :calculadoras="calculadoras"
          :salvando="salvando"
          @salvar="salvar(passo, $event)"
          @cancelar="aberto = null"
        />
      </li>
    </ul>
    <RoteiroPassoForm
      v-if="aberto === 'novo'"
      :passo="null"
      :destinos="destinos"
      :calculadoras="calculadoras"
      :salvando="salvando"
      @salvar="salvar(null, $event)"
      @cancelar="aberto = null"
    />
    <Button
      v-else
      data-testid="roteiro-novo"
      sm
      faded
      slate
      icon="i-lucide-plus"
      class="self-start"
      :label="$t('RAMON.ROTEIRO_IA.EDITOR.NOVO')"
      @click="aberto = 'novo'"
    />
    <ConfirmModal
      v-if="aRemover"
      :title="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER_CONFIRMA')"
      :confirm-label="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER')"
      @confirm="remover"
      @cancel="aRemover = null"
    />
  </div>
</template>

<script setup>
// Pacote da petição: arquivos na ordem do protocolo, com o tipo genérico e o
// nome que o advogado escolhe no sistema do tribunal ao lado. Cada ação
// devolve a petição inteira (emit `atualizar`). Protocolada = só leitura.
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RamonPeticoesAPI from 'dashboard/api/ramonPeticoes';
import Button from 'dashboard/components-next/button/Button.vue';
import SeletorDrive from './SeletorDrive.vue';
import { baixarTodos, erroPeticao, formatarMB } from './helpers';
import { CARTAO, CHIP, SELECT, TITULO, TOM } from '../../helpers/ui';

const props = defineProps({
  peticao: { type: Object, required: true },
  tipos: { type: Array, default: () => [] },
});
const emit = defineEmits(['atualizar']);

const { t } = useI18n();
const enviando = ref(false);
const seletorAberto = ref(false);
const inputArquivo = ref(null);

const executar = async chamada => {
  try {
    const { data } = await chamada();
    emit('atualizar', data);
  } catch (e) {
    useAlert(erroPeticao(e, t));
  }
};

const baixar = arquivo =>
  baixarTodos([arquivo], a => RamonPeticoesAPI.baixarArquivo(a.url)).catch(e =>
    useAlert(erroPeticao(e, t))
  );

const id = () => props.peticao.id;

const mover = (indice, delta) => {
  const ids = props.peticao.arquivos.map(a => a.id);
  [ids[indice], ids[indice + delta]] = [ids[indice + delta], ids[indice]];
  executar(() => RamonPeticoesAPI.reordenar(id(), ids));
};

const trocarTipo = (arquivo, tipo) =>
  executar(() => RamonPeticoesAPI.atualizarArquivo(id(), arquivo.id, { tipo }));

const marcarPrincipal = arquivo =>
  executar(() =>
    RamonPeticoesAPI.atualizarArquivo(id(), arquivo.id, { principal: true })
  );

const remover = arquivo =>
  executar(() => RamonPeticoesAPI.removerArquivo(id(), arquivo.id));

// Um por vez: o backend numera pela ordem de chegada.
const enviar = async evento => {
  const arquivos = [...evento.target.files];
  evento.target.value = '';
  if (!arquivos.length) return;
  enviando.value = true;
  await arquivos.reduce(
    (fila, file) =>
      fila.then(() =>
        executar(() => RamonPeticoesAPI.uploadArquivo(id(), file))
      ),
    Promise.resolve()
  );
  enviando.value = false;
};

const adicionadoDoDrive = data => {
  seletorAberto.value = false;
  emit('atualizar', data);
};
</script>

<template>
  <section :class="CARTAO" class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <p class="m-0" :class="TITULO">{{ t('RAMON.PETICOES.PACOTE') }}</p>
      <div v-if="peticao.status === 'rascunho'" class="flex gap-2">
        <input
          ref="inputArquivo"
          type="file"
          multiple
          accept=".pdf,.jpg,.jpeg,.png"
          class="hidden"
          data-testid="pacote-input"
          @change="enviar"
        />
        <Button
          xs
          faded
          slate
          icon="i-lucide-upload"
          :is-loading="enviando"
          :label="t('RAMON.PETICOES.ENVIAR_COMPUTADOR')"
          @click="inputArquivo.click()"
        />
        <Button
          xs
          faded
          slate
          icon="i-lucide-folder-open"
          :label="t('RAMON.PETICOES.ESCOLHER_DRIVE')"
          @click="seletorAberto = true"
        />
      </div>
    </div>

    <p v-if="!peticao.arquivos.length" class="m-0 text-sm text-n-slate-10">
      {{ t('RAMON.PETICOES.PACOTE_VAZIO') }}
    </p>
    <ul v-else class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
      <li
        v-for="(a, i) in peticao.arquivos"
        :key="a.id"
        class="flex flex-wrap items-center gap-3 py-2 text-sm"
        data-testid="pacote-arquivo"
      >
        <span class="flex min-w-0 flex-1 items-center gap-2">
          <button
            v-if="a.url"
            type="button"
            class="truncate font-mono text-xs text-n-slate-12 hover:underline"
            @click="baixar(a)"
          >
            {{ a.nome_numerado }}
          </button>
          <span v-else class="truncate font-mono text-xs text-n-slate-12">{{
            a.nome_numerado
          }}</span>
          <span class="shrink-0 font-mono text-[11px] text-n-slate-10">{{
            formatarMB(a.tamanho)
          }}</span>
          <span v-if="a.principal" :class="[CHIP, TOM.blue]">
            {{ t('RAMON.PETICOES.PRINCIPAL') }}
          </span>
        </span>

        <template v-if="peticao.status === 'rascunho'">
          <select
            :value="a.tipo"
            :class="SELECT"
            class="!w-48"
            @change="trocarTipo(a, $event.target.value)"
          >
            <option v-for="tipo in tipos" :key="tipo" :value="tipo">
              {{ t(`RAMON.PETICOES.TIPOS.${tipo.toUpperCase()}`) }}
            </option>
          </select>
          <span
            class="w-40 shrink-0 truncate text-xs text-n-slate-10"
            :title="t('RAMON.PETICOES.TIPO_NO_TRIBUNAL')"
          >
            {{ a.tipo_no_tribunal }}
          </span>
          <div class="flex shrink-0 items-center gap-1">
            <Button
              v-if="!a.principal"
              link
              xs
              :label="t('RAMON.PETICOES.MARCAR_PRINCIPAL')"
              @click="marcarPrincipal(a)"
            />
            <Button
              xs
              faded
              slate
              icon="i-lucide-arrow-up"
              :disabled="i === 0"
              :title="t('RAMON.PETICOES.SUBIR')"
              @click="mover(i, -1)"
            />
            <Button
              xs
              faded
              slate
              icon="i-lucide-arrow-down"
              :disabled="i === peticao.arquivos.length - 1"
              :title="t('RAMON.PETICOES.DESCER')"
              @click="mover(i, 1)"
            />
            <Button
              xs
              faded
              ruby
              icon="i-lucide-trash-2"
              :title="t('RAMON.PETICOES.REMOVER')"
              @click="remover(a)"
            />
          </div>
        </template>
        <span v-else class="shrink-0 text-xs text-n-slate-11">
          {{ a.tipo_no_tribunal }}
        </span>
      </li>
    </ul>

    <SeletorDrive
      v-if="seletorAberto"
      :peticao-id="peticao.id"
      :pasta-inicial="peticao.drive_pasta_base_id || ''"
      @adicionado="adicionadoDoDrive"
      @cancel="seletorAberto = false"
    />
  </section>
</template>

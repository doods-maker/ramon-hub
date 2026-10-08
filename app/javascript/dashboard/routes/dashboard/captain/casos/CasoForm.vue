<script setup>
// Janela de criar/editar um caso de teste: falas (a última é da pessoa) e o
// critério do que é resposta boa.
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import {
  CAMPO,
  SELECT,
  TEXTAREA,
  ROTULO,
  TITULO,
  SECAO,
  FUNDO_JANELA,
  JANELA,
  TITULO_JANELA,
  RODAPE_JANELA,
  AVISO,
  TOM,
} from 'dashboard/routes/dashboard/ramon/helpers/ui';
import { paraLista } from './casos';

const props = defineProps({
  caso: { type: Object, default: null },
  ferramentas: { type: Array, default: () => [] },
  salvando: { type: Boolean, default: false },
});
const emit = defineEmits(['salvar', 'remover', 'fechar']);

const { t } = useI18n();

const criterios = props.caso?.criterios || {};
const form = reactive({
  titulo: props.caso?.titulo || '',
  grupo: props.caso?.grupo || '',
  ativo: props.caso?.ativo ?? true,
  mensagens: (props.caso?.mensagens || [{ role: 'user', content: '' }]).map(
    fala => ({ ...fala })
  ),
  deveUsar: (criterios.deve_usar || []).join(', '),
  naoDeveUsar: (criterios.nao_deve_usar || []).join(', '),
  handoff: criterios.handoff || 'indiferente',
  deveConter: (criterios.deve_conter || []).join('\n'),
  naoPodeConter: (criterios.nao_pode_conter || []).join('\n'),
  rubrica: criterios.rubrica || '',
});
const erro = ref('');
const editando = computed(() => Boolean(props.caso?.id));

const adicionarFala = () => {
  const ultima = form.mensagens[form.mensagens.length - 1];
  form.mensagens.push({
    role: ultima?.role === 'user' ? 'assistant' : 'user',
    content: '',
  });
};
const removerFala = indice => form.mensagens.splice(indice, 1);

const salvar = () => {
  const falas = form.mensagens.filter(fala => fala.content.trim());
  if (!form.titulo.trim()) {
    erro.value = t('CAPTAIN_RAMON.CASOS.FORM.ERRO_TITULO');
    return;
  }
  if (!falas.length || falas[falas.length - 1].role !== 'user') {
    erro.value = t('CAPTAIN_RAMON.CASOS.FORM.ERRO_FALAS');
    return;
  }
  erro.value = '';
  emit('salvar', {
    titulo: form.titulo.trim(),
    grupo: form.grupo.trim(),
    ativo: form.ativo,
    mensagens: falas,
    criterios: {
      deve_usar: paraLista(form.deveUsar, /[,\n]/),
      nao_deve_usar: paraLista(form.naoDeveUsar, /[,\n]/),
      handoff: form.handoff,
      deve_conter: paraLista(form.deveConter),
      nao_pode_conter: paraLista(form.naoPodeConter),
      rubrica: form.rubrica.trim(),
    },
  });
};
</script>

<template>
  <div :class="FUNDO_JANELA" @click.self="emit('fechar')">
    <div class="!w-[40rem]" :class="[JANELA]" data-testid="caso-form">
      <h3 :class="TITULO_JANELA">
        {{
          editando
            ? t('CAPTAIN_RAMON.CASOS.FORM.TITULO_EDITAR')
            : t('CAPTAIN_RAMON.CASOS.FORM.TITULO_NOVO')
        }}
      </h3>

      <div class="flex flex-col gap-3">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-[1fr_12rem]">
          <label :class="ROTULO">
            {{ t('CAPTAIN_RAMON.CASOS.FORM.TITULO') }}
            <input
              v-model="form.titulo"
              data-testid="caso-titulo"
              :class="CAMPO"
            />
          </label>
          <label :class="ROTULO">
            {{ t('CAPTAIN_RAMON.CASOS.FORM.GRUPO') }}
            <input v-model="form.grupo" :class="CAMPO" />
          </label>
        </div>

        <div :class="SECAO">
          <p :class="TITULO">{{ t('CAPTAIN_RAMON.CASOS.FORM.FALAS') }}</p>
          <div
            v-for="(fala, indice) in form.mensagens"
            :key="indice"
            class="flex items-start gap-2 mt-2"
            data-testid="caso-fala"
          >
            <select
              v-model="fala.role"
              class="!w-24 shrink-0"
              :class="[SELECT]"
            >
              <option value="user">
                {{ t('CAPTAIN_RAMON.CASOS.FORM.PESSOA') }}
              </option>
              <option value="assistant">
                {{ t('CAPTAIN_RAMON.CASOS.FORM.IA') }}
              </option>
            </select>
            <textarea
              v-model="fala.content"
              rows="2"
              :class="TEXTAREA"
              data-testid="caso-fala-texto"
            />
            <Button
              v-if="form.mensagens.length > 1"
              variant="ghost"
              color="slate"
              size="sm"
              icon="i-lucide-x"
              :aria-label="t('CAPTAIN_RAMON.CASOS.FORM.REMOVER_FALA')"
              @click="removerFala(indice)"
            />
          </div>
          <Button
            variant="link"
            size="sm"
            class="mt-2"
            :label="t('CAPTAIN_RAMON.CASOS.FORM.ADD_FALA')"
            @click="adicionarFala"
          />
        </div>

        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2" :class="[SECAO]">
          <p class="sm:col-span-2" :class="[TITULO]">
            {{ t('CAPTAIN_RAMON.CASOS.FORM.CRITERIOS') }}
          </p>
          <label :class="ROTULO">
            {{ t('CAPTAIN_RAMON.CASOS.FORM.DEVE_USAR') }}
            <input
              v-model="form.deveUsar"
              list="ia-casos-ferramentas"
              :placeholder="t('CAPTAIN_RAMON.CASOS.FORM.DICA_FERRAMENTAS')"
              :class="CAMPO"
              data-testid="caso-deve-usar"
            />
          </label>
          <label :class="ROTULO">
            {{ t('CAPTAIN_RAMON.CASOS.FORM.NAO_DEVE_USAR') }}
            <input
              v-model="form.naoDeveUsar"
              list="ia-casos-ferramentas"
              :placeholder="t('CAPTAIN_RAMON.CASOS.FORM.DICA_FERRAMENTAS')"
              :class="CAMPO"
            />
          </label>
          <datalist id="ia-casos-ferramentas">
            <option v-for="tool in ferramentas" :key="tool.id" :value="tool.id">
              {{ tool.title }}
            </option>
          </datalist>
          <label :class="ROTULO">
            {{ t('CAPTAIN_RAMON.CASOS.FORM.DEVE_CONTER') }}
            <textarea v-model="form.deveConter" rows="2" :class="TEXTAREA" />
          </label>
          <label :class="ROTULO">
            {{ t('CAPTAIN_RAMON.CASOS.FORM.NAO_PODE_CONTER') }}
            <textarea v-model="form.naoPodeConter" rows="2" :class="TEXTAREA" />
          </label>
          <p class="text-[11px] text-n-slate-10 sm:col-span-2 -mt-1">
            {{ t('CAPTAIN_RAMON.CASOS.FORM.DICA_LISTA') }}
          </p>
          <label :class="ROTULO">
            {{ t('CAPTAIN_RAMON.CASOS.FORM.HANDOFF') }}
            <select
              v-model="form.handoff"
              :class="SELECT"
              data-testid="caso-handoff"
            >
              <option
                v-for="opcao in ['indiferente', 'sim', 'nao']"
                :key="opcao"
                :value="opcao"
              >
                {{ t(`CAPTAIN_RAMON.CASOS.FORM.HANDOFF_OPCOES.${opcao}`) }}
              </option>
            </select>
          </label>
          <label class="flex items-center gap-2 text-sm text-n-slate-12 pt-5">
            <Switch v-model="form.ativo" />
            {{ t('CAPTAIN_RAMON.CASOS.FORM.ATIVO') }}
          </label>
          <label class="sm:col-span-2" :class="[ROTULO]">
            {{ t('CAPTAIN_RAMON.CASOS.FORM.RUBRICA') }}
            <textarea
              v-model="form.rubrica"
              rows="3"
              :placeholder="t('CAPTAIN_RAMON.CASOS.FORM.DICA_RUBRICA')"
              :class="TEXTAREA"
            />
          </label>
        </div>

        <p v-if="erro" :class="[AVISO, TOM.ruby]" data-testid="caso-form-erro">
          {{ erro }}
        </p>
      </div>

      <div class="items-center" :class="[RODAPE_JANELA]">
        <Button
          v-if="editando"
          variant="link"
          color="ruby"
          size="sm"
          class="me-auto"
          :label="t('CAPTAIN_RAMON.CASOS.FORM.EXCLUIR')"
          data-testid="caso-excluir"
          @click="emit('remover')"
        />
        <Button
          variant="faded"
          color="slate"
          size="sm"
          :label="t('CAPTAIN_RAMON.CASOS.CANCELAR')"
          @click="emit('fechar')"
        />
        <Button
          size="sm"
          :is-loading="salvando"
          :label="t('CAPTAIN_RAMON.CASOS.FORM.SALVAR')"
          data-testid="caso-salvar"
          @click="salvar"
        />
      </div>
    </div>
  </div>
</template>

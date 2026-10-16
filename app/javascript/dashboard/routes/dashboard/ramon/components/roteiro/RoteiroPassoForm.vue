<script setup>
// Formulário de um passo do roteiro da IA (F2): o que descobrir, como perguntar, tipo, calculadora e as saídas
// (quando → então). "Vai para" e campos da calculadora só apontam para passos que existem — a API confere de novo.
import { computed, reactive, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  ACOES,
  TIPOS,
  listaParaTexto,
  novaSaida,
  payloadDoPasso,
  slugChave,
  sugestoesQuando,
  textoParaLista,
} from '../../helpers/roteiro';
import {
  AVISO,
  CAMPO,
  ROTULO,
  SECAO,
  SELECT,
  TEXTAREA,
  TITULO,
  TOM,
} from '../../helpers/ui';

const props = defineProps({
  // passo salvo (edição) ou null (novo)
  passo: { type: Object, default: null },
  destinos: { type: Array, required: true },
  calculadoras: { type: Object, required: true },
  salvando: { type: Boolean, default: false },
});
const emit = defineEmits(['salvar', 'cancelar']);
const { t } = useI18n();

const stages = useMapGetter('leadConfig/getStages');
const lostReasons = useMapGetter('leadConfig/getLostReasons');
// só etapa aberta: ganho nunca; Perdido só pela saída "Desqualifica" (efeitos do motor)
const etapasAbertas = computed(() =>
  (stages.value || []).filter(s => !s.is_won && !s.is_lost)
);

const comPadroes = saida => ({
  alvo: '',
  motivo: '',
  motivo_perda: '',
  mensagem: '',
  ...saida,
  efeitos: { etiqueta: '', etapa: '', ...(saida.efeitos || {}) },
});

// cópia solta: editar não mexe na lista até salvar
const original = JSON.parse(JSON.stringify(props.passo || {}));
const novo = !props.passo;
const rascunho = reactive({
  titulo: original.titulo || '',
  chave: original.chave || '',
  orientacao: original.orientacao || '',
  sem_perguntar: !!original.sem_perguntar,
  tipo_resposta: original.tipo_resposta || 'sim_nao',
  opcoesTexto: listaParaTexto(original.opcoes),
  calculadora: original.calculadora || '',
  calculadora_campos: { ...(original.calculadora_campos || {}) },
  saidas: (original.saidas || []).map(comPadroes),
});

// a chave nasce do título; depois de salvo fica travada
const sugerirChave = () => {
  if (novo && !rascunho.chave) rascunho.chave = slugChave(rascunho.titulo);
};

const outrosPassos = computed(() =>
  props.destinos.filter(d => d.chave !== original.chave)
);
// campo da calculadora pode vir do próprio passo (ex.: a data respondida agora)
const opcoesDeCampo = computed(() => [
  ...outrosPassos.value,
  ...(rascunho.chave
    ? [
        {
          chave: rascunho.chave,
          titulo: t('RAMON.ROTEIRO_IA.EDITOR.ESTE_PASSO'),
        },
      ]
    : []),
]);
const nomesCalculadoras = computed(() => Object.keys(props.calculadoras));
const camposDaCalculadora = computed(
  () => props.calculadoras[rascunho.calculadora]?.campos || []
);
const sugestoes = computed(() =>
  sugestoesQuando(
    { ...rascunho, opcoes: textoParaLista(rascunho.opcoesTexto) },
    props.calculadoras
  )
);
const ajudaSaidas = computed(() =>
  rascunho.tipo_resposta === 'texto' && !rascunho.calculadora
    ? 'RAMON.ROTEIRO_IA.EDITOR.SAIDAS_AJUDA_TEXTO'
    : 'RAMON.ROTEIRO_IA.EDITOR.SAIDAS_AJUDA'
);
const listaId = useId();
const podeSalvar = computed(
  () => !props.salvando && rascunho.titulo.trim() && rascunho.chave
);

const adicionarSaida = () =>
  rascunho.saidas.push(comPadroes(novaSaida(rascunho.saidas)));
const removerSaida = indice => rascunho.saidas.splice(indice, 1);
const salvar = () =>
  emit('salvar', payloadDoPasso(rascunho, camposDaCalculadora.value));
</script>

<template>
  <div class="flex flex-col gap-3" :class="SECAO" data-testid="roteiro-form">
    <div class="grid gap-3 md:grid-cols-[1fr_16rem]">
      <label :class="ROTULO">
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.TITULO') }}
        <input
          v-model="rascunho.titulo"
          data-testid="roteiro-titulo"
          :class="CAMPO"
          @blur="sugerirChave"
        />
      </label>
      <label :class="ROTULO" :title="$t('RAMON.ROTEIRO_IA.EDITOR.CHAVE_AJUDA')">
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.CHAVE') }}
        <input
          v-model="rascunho.chave"
          data-testid="roteiro-chave"
          class="font-mono"
          :class="CAMPO"
          :disabled="!novo"
        />
      </label>
    </div>
    <p class="m-0" :class="[AVISO, TOM.amber]">
      {{ $t('RAMON.ROTEIRO_IA.EDITOR.FALA_COM_CLIENTE') }}
    </p>
    <label :class="ROTULO">
      {{ $t('RAMON.ROTEIRO_IA.EDITOR.ORIENTACAO') }}
      <textarea
        v-model="rascunho.orientacao"
        data-testid="roteiro-orientacao"
        rows="2"
        class="max-h-48 min-h-16 [field-sizing:content]"
        :class="TEXTAREA"
      />
    </label>
    <label class="flex items-center gap-2 text-sm text-n-slate-12">
      <input
        v-model="rascunho.sem_perguntar"
        type="checkbox"
        class="m-0 accent-n-brand"
        data-testid="roteiro-sem-perguntar"
      />
      {{ $t('RAMON.ROTEIRO_IA.EDITOR.SEM_PERGUNTAR') }}
    </label>
    <div class="grid gap-3 md:grid-cols-3">
      <label :class="ROTULO">
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.TIPO') }}
        <select
          v-model="rascunho.tipo_resposta"
          data-testid="roteiro-tipo"
          :class="SELECT"
        >
          <option v-for="tipo in TIPOS" :key="tipo" :value="tipo">
            {{ $t(`RAMON.ROTEIRO_IA.EDITOR.TIPOS.${tipo.toUpperCase()}`) }}
          </option>
        </select>
      </label>
      <label
        v-if="rascunho.tipo_resposta === 'escolha'"
        class="md:col-span-2"
        :class="ROTULO"
      >
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.OPCOES') }}
        <input
          v-model="rascunho.opcoesTexto"
          data-testid="roteiro-opcoes"
          :class="CAMPO"
        />
      </label>
    </div>
    <div class="grid gap-3 md:grid-cols-3">
      <label :class="ROTULO">
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.CALCULADORA') }}
        <select
          v-model="rascunho.calculadora"
          data-testid="roteiro-calculadora"
          :class="SELECT"
        >
          <option value="">
            {{ $t('RAMON.ROTEIRO_IA.EDITOR.SEM_CALCULADORA') }}
          </option>
          <option v-for="nome in nomesCalculadoras" :key="nome" :value="nome">
            {{
              $t(`RAMON.ROTEIRO_IA.EDITOR.CALCULADORAS.${nome.toUpperCase()}`)
            }}
          </option>
        </select>
      </label>
      <label v-for="campo in camposDaCalculadora" :key="campo" :class="ROTULO">
        {{
          $t('RAMON.ROTEIRO_IA.EDITOR.CAMPO_DA_CALCULADORA', {
            campo: campo.replaceAll('_', ' '),
          })
        }}
        <select
          v-model="rascunho.calculadora_campos[campo]"
          data-testid="roteiro-campo-calculadora"
          :class="SELECT"
        >
          <option value="">—</option>
          <option
            v-for="destino in opcoesDeCampo"
            :key="destino.chave"
            :value="destino.chave"
          >
            {{ destino.titulo }}
          </option>
        </select>
      </label>
    </div>

    <div class="flex flex-col gap-2" :class="SECAO">
      <p class="m-0" :class="TITULO">
        {{ $t('RAMON.ROTEIRO_IA.EDITOR.SAIDAS') }}
      </p>
      <p class="m-0 text-xs text-n-slate-10">{{ $t(ajudaSaidas) }}</p>
      <datalist :id="listaId">
        <option v-for="valor in sugestoes" :key="valor" :value="valor" />
      </datalist>
      <ul class="m-0 flex list-none flex-col divide-y divide-n-weak p-0">
        <li
          v-for="(saida, indice) in rascunho.saidas"
          :key="saida.id"
          data-testid="roteiro-saida"
          class="flex flex-col gap-2 py-2 first:pt-0"
        >
          <div class="flex flex-wrap items-end gap-2">
            <label class="w-36" :class="ROTULO">
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.QUANDO') }}
              <input
                v-model="saida.quando"
                data-testid="roteiro-saida-quando"
                :list="listaId"
                class="font-mono"
                :class="CAMPO"
              />
            </label>
            <label class="w-48" :class="ROTULO">
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.ACAO') }}
              <select
                v-model="saida.acao"
                data-testid="roteiro-saida-acao"
                :class="SELECT"
              >
                <option v-for="acao in ACOES" :key="acao" :value="acao">
                  {{
                    $t(`RAMON.ROTEIRO_IA.EDITOR.ACOES.${acao.toUpperCase()}`)
                  }}
                </option>
              </select>
            </label>
            <label
              v-if="saida.acao === 'ir_para'"
              class="min-w-40 flex-1"
              :class="ROTULO"
            >
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.ALVO') }}
              <select
                v-model="saida.alvo"
                data-testid="roteiro-saida-alvo"
                :class="SELECT"
              >
                <option value="">—</option>
                <option
                  v-for="destino in outrosPassos"
                  :key="destino.chave"
                  :value="destino.chave"
                >
                  {{ destino.titulo }}
                </option>
              </select>
            </label>
            <label
              v-if="['desqualificar', 'humano'].includes(saida.acao)"
              class="min-w-40 flex-1"
              :class="ROTULO"
            >
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.MOTIVO') }}
              <input
                v-model="saida.motivo"
                data-testid="roteiro-saida-motivo"
                :class="CAMPO"
              />
            </label>
            <label
              v-if="saida.acao === 'desqualificar'"
              class="w-48"
              :class="ROTULO"
            >
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.MOTIVO_PERDA') }}
              <select
                v-model="saida.motivo_perda"
                data-testid="roteiro-saida-motivo-perda"
                :class="SELECT"
              >
                <option value="">
                  {{ $t('RAMON.ROTEIRO_IA.EDITOR.MOTIVO_PERDA_PADRAO') }}
                </option>
                <option
                  v-for="motivo in lostReasons"
                  :key="motivo.id"
                  :value="motivo.name"
                >
                  {{ motivo.name }}
                </option>
              </select>
            </label>
            <Button
              data-testid="roteiro-saida-remover"
              xs
              ghost
              slate
              icon="i-lucide-trash-2"
              class="ms-auto"
              :aria-label="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER_SAIDA')"
              :title="$t('RAMON.ROTEIRO_IA.EDITOR.REMOVER_SAIDA')"
              @click="removerSaida(indice)"
            />
          </div>
          <div class="grid gap-2 md:grid-cols-3">
            <label :class="ROTULO">
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.MENSAGEM') }}
              <input
                v-model="saida.mensagem"
                data-testid="roteiro-saida-mensagem"
                :class="CAMPO"
              />
            </label>
            <label :class="ROTULO">
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.ETIQUETA') }}
              <input
                v-model="saida.efeitos.etiqueta"
                data-testid="roteiro-saida-etiqueta"
                class="font-mono"
                :class="CAMPO"
              />
            </label>
            <label :class="ROTULO">
              {{ $t('RAMON.ROTEIRO_IA.EDITOR.ETAPA') }}
              <select
                v-model="saida.efeitos.etapa"
                data-testid="roteiro-saida-etapa"
                :class="SELECT"
              >
                <option value="">
                  {{ $t('RAMON.ROTEIRO_IA.EDITOR.SEM_ETAPA') }}
                </option>
                <option
                  v-for="etapa in etapasAbertas"
                  :key="etapa.id"
                  :value="etapa.name"
                >
                  {{ etapa.name }}
                </option>
              </select>
            </label>
          </div>
        </li>
      </ul>
      <Button
        data-testid="roteiro-nova-saida"
        xs
        faded
        slate
        icon="i-lucide-plus"
        class="self-start"
        :label="$t('RAMON.ROTEIRO_IA.EDITOR.NOVA_SAIDA')"
        @click="adicionarSaida"
      />
    </div>

    <div class="flex justify-end gap-2">
      <Button
        data-testid="roteiro-cancelar"
        sm
        faded
        slate
        :label="$t('RAMON.ROTEIRO_IA.EDITOR.CANCELAR')"
        @click="emit('cancelar')"
      />
      <Button
        data-testid="roteiro-salvar"
        sm
        :label="$t('RAMON.ROTEIRO_IA.EDITOR.SALVAR')"
        :disabled="!podeSalvar"
        @click="salvar"
      />
    </div>
  </div>
</template>

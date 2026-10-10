<script setup>
// Story da Conferência de fases — aprovação visual por print, claro/escuro.
// Sem rede: window.axios responde com dados FICTÍCIOS (nomes inventados).
import { useI18n } from 'vue-i18n';
import ConferenciaFases from './ConferenciaFases.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';

const base = {
  agenda: [],
  tribunal: null,
  sugestao: null,
  painel_marca: null,
  atualizar: false,
  obs: null,
  marcado_em: null,
  marcado_por: null,
  aplicado_em: null,
  aplicado_por: null,
  erro_aplicacao: null,
};

const LINHAS = [
  {
    ...base,
    id: 1,
    lawsuit_id: 101,
    numero: '5003412-18.2025.4.04.7207',
    cliente: 'Alice Fictícia Ramos',
    responsavel: 'Bruna Teste',
    etapa_advbox: 'Aguardando perícia judicial',
    fase_advbox: 'justica',
    painel_titulo: 'Recurso em andamento',
    fase_painel: 'recurso',
    grupo: 'atrasada',
    tribunal: {
      etapa: 'recurso',
      data: '2026-09-22',
      titulo: 'Recurso inominado interposto',
    },
    ultimo_andamento: '2026-10-01',
    sugestao: { etapa: 'Recurso', etapa_id: 12 },
    painel_marca: 'certo',
    atualizar: true,
    marcado_em: '2026-10-08T17:42:00Z',
    marcado_por: 'Bruna Teste',
  },
  {
    ...base,
    id: 2,
    lawsuit_id: 102,
    numero: '5000981-07.2024.4.04.7207',
    cliente: 'Caio Exemplo Duarte',
    responsavel: 'Diego Modelo',
    etapa_advbox: 'Sentença',
    fase_advbox: 'justica',
    painel_titulo: 'Processo concluído',
    fase_painel: 'concluido',
    grupo: 'baixa',
    tribunal: {
      etapa: 'arquivado',
      data: '2026-09-15',
      titulo: 'Baixa definitiva',
    },
    ultimo_andamento: '2026-09-15',
    sugestao: { etapa: 'Arquivado', etapa_id: 30 },
    obs: 'Conferir RPV antes de arquivar',
  },
  {
    ...base,
    id: 3,
    lawsuit_id: 103,
    numero: '5007720-44.2025.4.04.7207',
    cliente: 'Elisa Demonstração Faria',
    responsavel: 'Bruna Teste',
    etapa_advbox: 'Petição inicial',
    fase_advbox: 'inss',
    painel_titulo: 'Na Justiça',
    fase_painel: 'justica',
    grupo: 'diferente',
    agenda: [
      { tipo: 'pericia', quando: '2026-11-04 14:00:00', formato: 'presencial' },
    ],
    painel_marca: 'errado',
    marcado_em: '2026-10-07T12:05:00Z',
    marcado_por: 'Diego Modelo',
  },
  {
    ...base,
    id: 4,
    lawsuit_id: 104,
    numero: '5002255-31.2023.4.04.7207',
    cliente: 'Fábio Simulado Nunes',
    responsavel: 'Diego Modelo',
    etapa_advbox: 'Execução',
    fase_advbox: 'justica',
    painel_titulo: 'Pagamento',
    fase_painel: 'pagamento',
    grupo: 'atrasada',
    tribunal: {
      etapa: 'pagamento',
      data: '2026-08-28',
      titulo: 'RPV expedida',
    },
    ultimo_andamento: '2026-09-03',
    sugestao: { etapa: 'Pagamento', etapa_id: 25 },
    atualizar: true,
    aplicado_em: '2026-10-08T23:10:00Z',
    aplicado_por: 'Gestor Fictício',
  },
  {
    ...base,
    id: 5,
    lawsuit_id: 105,
    numero: '5009034-72.2025.4.04.7207',
    cliente: 'Gabriela Inventada Lopes',
    responsavel: 'Bruna Teste',
    etapa_advbox: 'Contestação',
    fase_advbox: 'justica',
    painel_titulo: 'Na Justiça',
    fase_painel: 'justica',
    grupo: 'igual',
    sugestao: { etapa: 'Recurso', etapa_id: 12 },
    atualizar: true,
    erro_aplicacao: 'ADVBOX respondeu 422 (etapa inexistente)',
  },
];

const RESPOSTA = {
  payload: LINHAS,
  total: 137,
  pagina: 1,
  por_pagina: 50,
  resumo: {
    grupos: { atrasada: 42, baixa: 9, diferente: 31, igual: 55 },
    conferidos: 18,
    errados: 4,
    para_aplicar: 12,
    responsaveis: ['Bruna Teste', 'Diego Modelo'],
  },
  atualizado_em: '2026-10-09T05:10:00Z',
  permissoes: { aplicar: false },
};

let modo = 'agente';
window.axios = {
  get: async () => {
    if (modo === 'vazio') {
      return {
        data: {
          ...RESPOSTA,
          payload: [],
          total: 0,
          atualizado_em: null,
          resumo: {
            grupos: {},
            conferidos: 0,
            errados: 0,
            para_aplicar: 0,
            responsaveis: [],
          },
        },
      };
    }
    return { data: { ...RESPOSTA, permissoes: { aplicar: modo === 'admin' } } };
  },
  patch: async (url, body) => {
    const id = Number(url.split('/').pop());
    const linha = LINHAS.find(l => l.id === id);
    return {
      data: {
        ...linha,
        ...body,
        marcado_em: new Date().toISOString(),
        marcado_por: 'Bruna Teste',
      },
    };
  },
  post: async () => ({ data: { enfileirados: 12 } }),
};

const agente = () => {
  modo = 'agente';
};
const admin = () => {
  modo = 'admin';
};
const vazio = () => {
  modo = 'vazio';
};
</script>

<template>
  <Story title="Ramon/Conferência de fases" :layout="{ type: 'single' }">
    <Variant title="Agente" :init-state="agente">
      <div class="h-screen"><ConferenciaFases /></div>
    </Variant>
    <Variant title="Administrador" :init-state="admin">
      <div class="h-screen"><ConferenciaFases /></div>
    </Variant>
    <Variant title="Não montada" :init-state="vazio">
      <div class="h-screen"><ConferenciaFases /></div>
    </Variant>
  </Story>
</template>

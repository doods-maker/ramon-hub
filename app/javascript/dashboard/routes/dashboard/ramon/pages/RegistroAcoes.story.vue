<script setup>
// Story do Registro de ações — aprovação visual por print, claro/escuro.
// Sem rede: window.axios responde com dados FICTÍCIOS; sem router: a rota
// atual (conta 1) entra por provide, para o link de cada linha montar.
import { provide } from 'vue';
import { routeLocationKey } from 'vue-router';
import { useI18n } from 'vue-i18n';
import RegistroAcoes from './RegistroAcoes.vue';

const { locale } = useI18n({ useScope: 'global' });
locale.value = 'pt_BR';
provide(routeLocationKey, { params: { accountId: 1 }, query: {} });

const ANA = { id: 1, nome: 'Ana Ribeiro' };
const BRUNO = { id: 2, nome: 'Bruno Costa' };
const CARLA = { id: 3, nome: 'Carla Mendes' };

const hoje = (hora, minuto) =>
  new Date(Date.UTC(2026, 9, 6, hora + 3, minuto)).toISOString();

const REGISTROS = [
  {
    id: 12,
    quando: hoje(16, 42),
    tipo: 'lead',
    modelo: 'Lead',
    acao: 'update',
    quem: BRUNO,
    alvo: { lead_id: 41, contato_id: 9, nome: 'Maria Aparecida Souza' },
    mudancas: {
      lead_stage_id: ['Qualificação', 'Proposta enviada'],
      value: ['9800.0', '12400.0'],
    },
  },
  {
    id: 11,
    quando: hoje(16, 5),
    tipo: 'conversa',
    modelo: 'Conversation',
    acao: 'update',
    quem: ANA,
    alvo: { contato_id: 14, nome: 'José Carlos Pereira', conversa: 1287 },
    mudancas: { assignee_id: ['Bruno Costa', 'Carla Mendes'] },
  },
  {
    id: 10,
    quando: hoje(15, 31),
    tipo: 'lead',
    modelo: 'Lead',
    acao: 'update',
    quem: CARLA,
    alvo: { lead_id: 38, contato_id: 12, nome: 'Antônio Ferreira' },
    mudancas: {
      lead_stage_id: ['Reunião marcada', 'Contrato assinado'],
      won_at: [null, hoje(15, 31)],
    },
  },
  {
    id: 9,
    quando: hoje(14, 58),
    tipo: 'contato',
    modelo: 'Contact',
    acao: 'update',
    comentario: 'anonimizado',
    quem: ANA,
    alvo: { contato_id: 22, nome: 'Titular anonimizado #22' },
    mudancas: {
      name: ['[anonimizado]', '[anonimizado]'],
      phone_number: ['[anonimizado]', '[anonimizado]'],
      cpf: ['[anonimizado]', '[anonimizado]'],
    },
  },
  {
    id: 8,
    quando: hoje(14, 20),
    tipo: 'dinheiro',
    modelo: 'MetaComercial',
    acao: 'update',
    quem: ANA,
    alvo: { nome: 'Bruno Costa' },
    mudancas: { meta: [20, 24] },
  },
  {
    id: 7,
    quando: hoje(13, 47),
    tipo: 'conversa',
    modelo: 'Conversation',
    acao: 'update',
    quem: null,
    alvo: { contato_id: 30, nome: 'Rosângela Lima', conversa: 1291 },
    mudancas: { assignee_id: [null, 'Bruno Costa'] },
  },
  {
    id: 6,
    quando: hoje(11, 12),
    tipo: 'lead',
    modelo: 'Lead',
    acao: 'update',
    quem: BRUNO,
    alvo: { lead_id: 35, contato_id: 18, nome: 'Paulo Henrique Alves' },
    mudancas: {
      lead_stage_id: ['Qualificação', 'Perdido'],
      lost_reason: [null, 'Não tem qualidade de segurado'],
    },
  },
  {
    id: 5,
    quando: hoje(10, 3),
    tipo: 'contato',
    modelo: 'Contact',
    acao: 'update',
    quem: CARLA,
    alvo: { contato_id: 25, nome: 'Luciana Martins' },
    mudancas: { phone_number: ['+5548991234567', '+5548998765432'] },
  },
  {
    id: 4,
    quando: hoje(9, 40),
    tipo: 'contato',
    modelo: 'Contact',
    acao: 'destroy',
    comentario: 'mesclado:25',
    quem: CARLA,
    alvo: { contato_id: 25, nome: 'Luciana Martins' },
    mudancas: { name: ['Luciana M.', null] },
  },
  {
    id: 3,
    quando: hoje(9, 2),
    tipo: 'acesso',
    modelo: 'AccountUser',
    acao: 'update',
    quem: ANA,
    alvo: { nome: 'Carla Mendes' },
    mudancas: { role: [0, 1] },
  },
  {
    id: 2,
    quando: hoje(8, 30),
    tipo: 'dinheiro',
    modelo: 'ExtratoFechado',
    acao: 'create',
    quem: ANA,
    alvo: { nome: 'Bruno Costa' },
    mudancas: { papel: [null, 'sdr'], competencia: [null, '2026-09-01'] },
  },
  {
    id: 1,
    quando: hoje(8, 12),
    tipo: 'lead',
    modelo: 'Lead',
    acao: 'destroy',
    quem: BRUNO,
    alvo: { contato_id: 40, nome: 'Fernanda Rocha' },
    mudancas: { lead_stage_id: ['Novo lead', null] },
  },
];

const RESPOSTA = {
  registros: REGISTROS,
  total: 312,
  pagina: 1,
  por_pagina: 50,
  pessoas: [ANA, BRUNO, CARLA],
};

let modo = 'cheio';
window.axios = {
  get: async () => {
    if (modo === 'erro') throw new Error('offline');
    if (modo === 'vazio')
      return { data: { ...RESPOSTA, registros: [], total: 0 } };
    return { data: RESPOSTA };
  },
};

const vazio = () => {
  modo = 'vazio';
};
const erro = () => {
  modo = 'erro';
};
</script>

<template>
  <Story title="Ramon/Registro de ações" :layout="{ type: 'single' }">
    <Variant title="Registro">
      <div class="h-screen"><RegistroAcoes /></div>
    </Variant>
    <Variant title="Vazio" :init-state="vazio">
      <div class="h-screen"><RegistroAcoes /></div>
    </Variant>
    <Variant title="Erro" :init-state="erro">
      <div class="h-screen"><RegistroAcoes /></div>
    </Variant>
  </Story>
</template>

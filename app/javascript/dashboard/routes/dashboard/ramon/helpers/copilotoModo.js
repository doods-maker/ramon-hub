import { TOM } from './ui';

// Mesma lista de Ramon::CopilotoModo::MODOS (spec/services/ramon/copiloto_modo_spec.rb confere as duas).
export const MODOS = [
  'manual',
  'rascunho',
  'piloto_limitado',
  'piloto_total',
  'piloto_ate_qualificacao',
  'piloto_ate_reuniao',
  'piloto_ate_contrato',
];

// Padrão do servidor (env RAMON_COPILOTO_MODO_DEFAULT), vindo do layout.
export const modoDefault = () => {
  const m = window.chatwootConfig?.ramonCopilotoModoDefault;
  return MODOS.includes(m) ? m : 'rascunho';
};

// Modo efetivo da conversa no front — a mesma ordem de Ramon::CopilotoModo.of: atributo da conversa → padrão da caixa
// (inbox.ramon_copiloto_modo) → padrão do servidor.
export const copilotoModoDe = (chat, inbox) => {
  const m = chat?.custom_attributes?.copiloto_modo;
  if (MODOS.includes(m)) return m;
  const daCaixa = inbox?.ramon_copiloto_modo;
  return MODOS.includes(daCaixa) ? daCaixa : modoDefault();
};

// rascunho = azul (nada sai sem humano); piloto = âmbar (limitado) ou vermelho (a IA envia).
export const tomDoModo = modo => {
  if (modo === 'manual') return TOM.slate;
  if (modo === 'rascunho') return TOM.blue;
  return modo === 'piloto_limitado' ? TOM.amber : TOM.ruby;
};

// Kit visual do painel do lead (padrão único, 03/10/2026). Botão = components-next
// Button; o resto (cartão, campo, aba, chip) vem daqui — nunca classe à mão.

// Cartão: um estilo só. Dentro de cartão não há cartão — vira SECAO.
export const CARTAO = 'rounded-xl border border-n-weak bg-n-solid-1 p-3';
// Cartão de status: CARTAO + filete colorido à esquerda (somar a cor da borda).
export const CARTAO_STATUS = `${CARTAO} border-l-4`;
export const FILETE = {
  blue: 'border-l-n-blue-9',
  teal: 'border-l-n-teal-9',
  amber: 'border-l-n-amber-9',
  ruby: 'border-l-n-ruby-9',
};
export const SECAO = 'border-t border-n-weak pt-3';
// Sobrescrito de seção ("ANDAMENTO", "CASO"...); SOBRESCRITO = sem a cor.
export const SOBRESCRITO =
  'text-[10.5px] font-semibold uppercase tracking-widest';
export const TITULO = `${SOBRESCRITO} text-n-slate-10`;

// Campos nativos (input/select/textarea): mesma pele do Input do components-next.
// reset-base tira o input do CSS global (_base.scss: h-10 + mb-4); mb-0 vence
// o seletor de elemento do select/textarea (margem local: !mb-3).
export const CAMPO =
  'reset-base block w-full mb-0 h-8 rounded-lg border-0 bg-n-alpha-black2 px-3 text-sm text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak hover:outline-n-slate-6 focus:outline-n-brand placeholder:text-n-slate-10 disabled:cursor-not-allowed disabled:opacity-50';
// select: a seta do CSS global fica à direita, dentro do padding; py-0 anula o
// py-2 global (senão o texto corta no h-8).
export const SELECT = `${CAMPO} py-0 pr-8`;
export const TEXTAREA = `${CAMPO} h-auto py-2`;
export const ARQUIVO = `${CAMPO} h-auto py-1.5 text-xs file:me-2 file:rounded-md file:border-0 file:bg-n-alpha-2 file:px-2 file:py-0.5 file:text-n-slate-12`;
// Campo que parece texto (select/date nos cartões do Resumo): clicar já edita.
// bg-none/appearance-none tiram a seta global do select; -mx-1 px-1 alinha o
// texto com o rótulo e deixa o realce do hover respirar; !outline-none vence
// o contorno do select global no escuro (.dark select, mais específico);
// field-sizing: o select fica do tamanho da opção escolhida, não da maior.
export const EDITAVEL =
  'reset-base appearance-none [field-sizing:content] h-auto w-auto max-w-full m-0 -mx-1 rounded border-0 bg-transparent bg-none px-1 py-0 text-[13px] text-n-slate-12 !outline-none cursor-pointer hover:bg-n-alpha-2 focus:bg-n-alpha-2';
export const ROTULO = 'flex flex-col gap-1 text-xs text-n-slate-10';

// Abas sublinhadas (abas internas do simulador).
export const ABA =
  'flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 py-2 text-[12.5px]';
export const ABA_ATIVA = 'border-n-blue-9 font-semibold text-n-blue-11';
export const ABA_INATIVA =
  'border-transparent text-n-slate-10 hover:text-n-slate-12';

// Chip/etiqueta: fundo SEMPRE translúcido. Etapa usa .ramon-stage-pill.
export const CHIP =
  'inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[11px] font-medium';
export const TOM = {
  slate: 'bg-n-slate-9/10 text-n-slate-11',
  blue: 'bg-n-blue-9/[0.08] dark:bg-n-blue-9/[0.16] text-n-blue-11',
  teal: 'bg-n-teal-9/15 text-n-teal-11',
  amber: 'bg-n-amber-9/15 text-n-amber-11',
  ruby: 'bg-n-ruby-9/10 text-n-ruby-11',
};
// Navegação do painel do lead: ícone em cima, rótulo curto embaixo; os itens
// dividem a largura (5 cabem nos 400px do painel). Ativo = azul da marca.
export const NAV_ICONE =
  'flex flex-1 min-w-0 flex-col items-center gap-0.5 rounded-lg px-1 py-1.5 text-[11px] leading-4';
export const NAV_ICONE_ATIVO = `${TOM.blue} font-semibold`;
export const NAV_ICONE_INATIVO =
  'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12';

// Aviso em bloco (dentro ou fora de cartão): fundo translúcido, sem borda.
export const AVISO = 'rounded-lg px-3 py-2 text-xs';

// Linha clicável de lista (documento, opção de menu).
export const LINHA =
  'w-full rounded-lg px-2 py-1.5 text-left text-sm hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-60';

// Botão xs compacto (ações rápidas do card do funil): cabe 2 por linha na
// célula das raias (240px) como cabia antes.
export const BOTAO_COMPACTO = '!gap-1 !px-1.5';

// Tecla de atalho dentro de botão (Esteira, fila do Centro): herda a cor do
// botão, então serve no primário e no secundário.
export const ATALHO =
  'rounded border border-current px-1 font-mono text-[10px] leading-4 opacity-60';

// Menu suspenso (dropdown sobre o conteúdo): mesma pele em todos.
export const MENU =
  'rounded-xl border border-n-weak bg-n-solid-2 p-1.5 shadow-lg';

// Janela (modal): casca única. FUNDO escurece a tela (clique nele = cancelar);
// JANELA é a caixa, largura-base w-80 (form maior: !w-96).
export const FUNDO_JANELA =
  'fixed inset-0 z-50 flex items-center justify-center bg-modal-backdrop-light dark:bg-modal-backdrop-dark';
export const JANELA =
  'w-80 max-w-[92vw] max-h-[90vh] overflow-y-auto rounded-xl border border-n-weak bg-n-solid-2 p-5 shadow-xl';
export const TITULO_JANELA = 'mb-3 text-base font-medium text-n-slate-12';
// Rodapé da janela: secundário à esquerda do primário, alinhados à direita.
export const RODAPE_JANELA = 'mt-4 flex justify-end gap-2';

// Regras puras das telas do roteiro da IA (F2). O servidor confere de novo no salvar (Conferencia).

export const TIPOS = ['sim_nao', 'escolha', 'numero', 'data', 'texto'];
export const ACOES = [
  'seguir',
  'ir_para',
  'desqualificar',
  'humano',
  'concluir',
];

// "Recebeu auxílio-doença?" → "recebeu_auxilio_doenca" (mesma regra do model: a-z, 0-9 e _).
export const slugChave = texto =>
  (texto || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 40);

export const textoParaLista = texto =>
  (texto || '')
    .split(',')
    .map(item => item.trim())
    .filter(Boolean);

export const listaParaTexto = lista => (lista || []).join(', ');

const porPosicao = (a, b) => a.position - b.position || a.id - b.id;

// thesisId null = passos comuns da conta.
export const passosDe = (todos, thesisId) =>
  (todos || []).filter(p => p.thesis_id === thesisId).sort(porPosicao);

// Para onde um passo pode apontar ("vai para", campos da calculadora): comum só alcança os comuns (roda em toda
// tese); passo da tese alcança os comuns e os da tese.
export const destinosDe = (todos, thesisId) =>
  thesisId === null
    ? passosDe(todos, null)
    : [...passosDe(todos, null), ...passosDe(todos, thesisId)];

// Sugestões do "quando" (datalist): com calculadora casa o resultado dela; senão os valores do tipo.
export const sugestoesQuando = (passo, calculadoras) => {
  const calc = calculadoras?.[passo.calculadora];
  if (calc) return [...calc.resultados, '*'];
  if (passo.tipo_resposta === 'sim_nao') return ['sim', 'nao', '*'];
  if (passo.tipo_resposta === 'escolha') return [...(passo.opcoes || []), '*'];
  return ['*'];
};

// Próximo id livre (s1, s2…): a IA cita o id nas respostas de texto livre; ids do seed (sim, nao) ficam.
export const novaSaida = saidas => {
  const usados = new Set((saidas || []).map(s => s.id));
  let n = (saidas || []).length + 1;
  while (usados.has(`s${n}`)) n += 1;
  return { id: `s${n}`, quando: '', acao: 'seguir' };
};

// Só os campos que a ação usa; motivo vazio em desqualificar/humano vai vazio para o model recusar com a mensagem.
export const limparSaida = saida => {
  const efeitos = Object.fromEntries(
    Object.entries(saida.efeitos || {}).filter(([, valor]) => valor)
  );
  return {
    id: saida.id,
    quando: (saida.quando || '').trim(),
    acao: saida.acao,
    ...(saida.acao === 'ir_para' ? { alvo: saida.alvo } : {}),
    ...(['desqualificar', 'humano'].includes(saida.acao)
      ? { motivo: (saida.motivo || '').trim() }
      : {}),
    ...(saida.acao === 'desqualificar' && saida.motivo_perda
      ? { motivo_perda: saida.motivo_perda }
      : {}),
    ...(saida.mensagem?.trim() ? { mensagem: saida.mensagem.trim() } : {}),
    ...(Object.keys(efeitos).length ? { efeitos } : {}),
  };
};

// campos = os da calculadora escolhida agora; sobras de uma calculadora anterior ficam de fora
export const payloadDoPasso = (rascunho, campos) => ({
  titulo: rascunho.titulo.trim(),
  chave: rascunho.chave,
  orientacao: rascunho.orientacao,
  tipo_resposta: rascunho.tipo_resposta,
  opcoes:
    rascunho.tipo_resposta === 'escolha'
      ? textoParaLista(rascunho.opcoesTexto)
      : [],
  calculadora: rascunho.calculadora || '',
  calculadora_campos: rascunho.calculadora
    ? Object.fromEntries(
        Object.entries(rascunho.calculadora_campos || {}).filter(
          ([k, v]) => v && (campos || []).includes(k)
        )
      )
    : {},
  saidas: rascunho.saidas.map(limparSaida),
});

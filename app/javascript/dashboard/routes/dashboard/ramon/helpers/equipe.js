// Regras de tela do chat interno Equipe (puras, sem Vue).
import MessageFormatter from 'shared/helpers/MessageFormatter';

export const EMOJIS_REACAO = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

const FUSO = 'America/Sao_Paulo';

export const marcaUsuario = (content, userId) =>
  !!content &&
  (content.includes('mention://todos/') ||
    content.includes(`mention://user/${userId}/`));

export const textoLimpo = content =>
  (content || '').replace(/\[(@[^\]]*)\]\(mention:\/\/[^)]*\)/g, '$1');

export const listaMarcacao = (participantes, meuId, tipo) => {
  const pessoas = (participantes || [])
    .filter(p => p.id !== meuId)
    .map(p => ({
      id: p.id,
      name: p.name,
      thumbnail: p.thumbnail,
      type: 'user',
    }));
  return tipo === 'grupo'
    ? [{ id: 0, name: 'todos', type: 'todos' }, ...pessoas]
    : pessoas;
};

// Quem leu = last_seen_at >= createdAt (segundos); nulo conta como não leu.
export const estadoVisto = ({ createdAt, senderId }, participantes) => {
  const outros = (participantes || []).filter(p => p.id !== senderId);
  const leu = p => !!p.lastSeenAt && p.lastSeenAt >= createdAt;
  const leram = outros.filter(leu).map(p => p.name);
  const faltam = outros.filter(p => !leu(p)).map(p => p.name);
  return {
    todosLeram: outros.length > 0 && faltam.length === 0,
    leram,
    faltam,
    total: outros.length,
  };
};

export const identidadeConversa = (chat, meuId) => {
  const pessoas = chat?.equipe_pessoas || [];
  if (chat?.equipe_tipo !== '1a1' || !pessoas.some(p => p.id === meuId)) {
    return null;
  }
  const outro = pessoas.find(p => p.id !== meuId);
  return outro ? { nome: outro.name, foto: outro.thumbnail } : null;
};

export const resumoReacoes = (reacoes, participantes, meuId) => {
  const grupos = new Map();
  (reacoes || []).forEach(({ userId, userName, emoji }) => {
    const g = grupos.get(emoji) || { emoji, total: 0, nomes: [], minha: false };
    const atual = (participantes || []).find(p => p.id === userId);
    g.total += 1;
    g.nomes.push(atual?.name || userName);
    g.minha = g.minha || userId === meuId;
    grupos.set(emoji, g);
  });
  return [...grupos.values()];
};

const dia = ms =>
  new Intl.DateTimeFormat('en-CA', { timeZone: FUSO }).format(new Date(ms));

export const rotuloDia = (segundos, agoraMs) => {
  const alvo = dia(segundos * 1000);
  if (alvo === dia(agoraMs)) return 'HOJE';
  // ponytail: 24h antes de "agora" cai no dia anterior (Brasil sem horário de verão desde 2019)
  if (alvo === dia(agoraMs - 86400000)) return 'ONTEM';
  const [a, m, d] = alvo.split('-');
  return `${d}/${m}/${a}`;
};

// Hora da lista: hoje 'HH:mm'; senão o rótulo do dia ('ONTEM' ou 'dd/MM/yyyy').
export const horaLista = (segundos, agoraMs) => {
  const rotulo = rotuloDia(segundos, agoraMs);
  if (rotulo !== 'HOJE') return rotulo;
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: FUSO,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(segundos * 1000));
};

export const prefixoPrevia = (message, meuId, tipo) => {
  const voce = message?.sender?.id === meuId;
  return {
    voce,
    nome: !voce && tipo === 'grupo' ? message?.sender?.name || null : null,
  };
};

// Citação: a bolha recebe camelCase e a caixa de escrever, snake_case do store.
export const autorCitacao = (message, meuId, t) => {
  const { voce, nome } = prefixoPrevia(message, meuId, 'grupo');
  return voce ? t('RAMON.EQUIPE.VOCE') : nome;
};

// Apagada: o servidor grava o texto de apagada em content.
export const textoCitacao = (message, t) => {
  if (message?.content) {
    const umaLinha = textoLimpo(message.content).replace(/\s*\n\s*/g, ' ');
    return new MessageFormatter(umaLinha).plainText.trim();
  }
  const anexo = message?.attachments?.[0];
  return anexo
    ? t(`CHAT_LIST.ATTACHMENTS.${anexo.fileType ?? anexo.file_type}.CONTENT`)
    : t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
};

// Filtros da lista do Painel do cliente (lado do escritório). No cliente: a
// lista é pequena (piloto) e já vem inteira do backend.
// ponytail: filtro em memória; paginar/filtrar no backend se passar de centenas.
const DIA = 86400000;
export const DIAS_SEM_ACESSO = 30;

const semAcento = s =>
  (s || '')
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase();

export const FILTROS = {
  nunca_entrou: c => !!c.convidado_em && !c.suspenso_em && !c.dias_acesso,
  sem_acesso: (c, agora) =>
    !!c.ultimo_acesso_em &&
    !c.suspenso_em &&
    agora - new Date(c.ultimo_acesso_em).getTime() >= DIAS_SEM_ACESSO * DIA,
  suspensos: c => !!c.suspenso_em,
  doc_pendente: c => c.docs_pendentes > 0,
};

// busca = nome (sem acento) ou dígitos do CPF; filtro = chave de FILTROS ou null.
export const filtrarClientes = (
  clientes,
  { busca = '', filtro = null, agora = Date.now() } = {}
) => {
  const termo = semAcento(busca.trim());
  const digitos = termo.replace(/\D/g, '');
  return clientes.filter(c => {
    if (filtro && !FILTROS[filtro](c, agora)) return false;
    if (!termo) return true;
    if (semAcento(c.nome).includes(termo)) return true;
    return !!digitos && (c.cpf || '').replace(/\D/g, '').includes(digitos);
  });
};

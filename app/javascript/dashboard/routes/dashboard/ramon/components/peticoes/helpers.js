// Peticionamento · Fase 1: textos do pacote, erros e "Baixar todos".
import { mensagemErro } from '../../helpers/erro';

const MB = 1024 * 1024;
const NUMERO = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });

// 14.2 MB → "14,2 MB"; 11 MB → "11 MB".
export const formatarMB = bytes => `${NUMERO.format((bytes || 0) / MB)} MB`;

// Problema do backend ("sem_principal", "acima_do_limite:12"...) → texto.
// `tribunal` = info do tribunal da petição ({ nome, limite_bytes }).
export const mensagemProblema = (problema, arquivos, tribunal, t) => {
  const [chave, id] = problema.split(':');
  const i18n = `RAMON.PETICOES.PROBLEMAS.${chave.toUpperCase()}`;
  if (chave !== 'acima_do_limite') return t(i18n);

  const arquivo = arquivos.find(a => a.id === Number(id)) || {};
  return t(i18n, {
    nome: arquivo.nome,
    tamanho: formatarMB(arquivo.tamanho),
    tribunal: tribunal?.nome,
    limite: formatarMB(tribunal?.limite_bytes),
  });
};

const salvar = (blob, nome) => {
  const href = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = href;
  link.download = nome;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(href), 1000);
};

// Baixa um a um (sem zip), já com o nome numerado. A API exige os headers do
// token, então um <a href> direto não serve: `buscar(arquivo)` devolve o Blob
// (axios autenticado) e aqui ele vira download.
export const baixarTodos = (arquivos, buscar) =>
  arquivos
    .filter(a => a.url)
    .reduce(
      (fila, a) =>
        fila.then(async () => salvar(await buscar(a), a.nome_numerado)),
      Promise.resolve()
    );

// Códigos de erro do backend → texto; o resto vem pronto do servidor (ou o padrão).
const ERROS = {
  formato: 'RAMON.PETICOES.ERROS.FORMATO',
  protocolada: 'RAMON.PETICOES.ERROS.PROTOCOLADA',
  SO_RESPONSAVEL: 'RAMON.PETICOES.ERROS.SO_RESPONSAVEL',
  DRIVE_OFF: 'RAMON.PETICOES.DRIVE_OFF',
};
export const erroPeticao = (e, t, padrao = 'RAMON.PETICOES.ERRO_ACAO') => {
  const chave = ERROS[e?.response?.data?.error];
  return chave ? t(chave) : mensagemErro(e, t(padrao));
};

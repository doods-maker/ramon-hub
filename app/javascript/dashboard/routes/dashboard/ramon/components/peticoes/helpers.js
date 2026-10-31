// Peticionamento · Fase 1: textos do pacote e "Baixar todos".

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

// Baixa um a um, já com o nome numerado (sem zip); 400 ms entre um e outro
// para o navegador não barrar downloads em série.
export const baixarTodos = arquivos =>
  arquivos
    .filter(a => a.url)
    .forEach((a, i) => {
      setTimeout(() => {
        const link = document.createElement('a');
        link.href = a.url;
        link.download = a.nome_numerado || '';
        document.body.appendChild(link);
        link.click();
        link.remove();
      }, i * 400);
    });

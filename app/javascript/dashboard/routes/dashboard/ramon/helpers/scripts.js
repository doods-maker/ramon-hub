// Roteiros do playbook trazem {{nome}} ("Olá {{nome}}, tudo bem?"): na hora de
// copiar entra o PRIMEIRO nome do lead (contato, senão o nome do lead). Sem
// nome conhecido, o marcador fica como está — melhor que "Olá , tudo bem?".
const MARCADOR = /\{\{\s*nome\s*\}\}/g;

export const preencherScript = (texto, lead) => {
  const conteudo = String(texto ?? '');
  const nome = String(lead?.contact_name || lead?.name || '')
    .trim()
    .split(/\s+/)[0];
  return nome ? conteudo.replace(MARCADOR, nome) : conteudo;
};

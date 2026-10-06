import { parseAPIErrorResponse } from 'dashboard/store/utils/api';

// Mensagem do servidor (422 com `error`/`message`) ou o texto padrão.
export const mensagemErro = (e, padrao) => {
  const msg = parseAPIErrorResponse(e);
  return typeof msg === 'string' && msg ? msg : padrao;
};

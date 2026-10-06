// Filtros de conversa do Chatwoot que não servem à banca (idioma do navegador e
// link de origem são do widget de site; campanha é a do Chatwoot, não a da
// Meta). Saem do menu de filtros; a tese filtra pela etiqueta tese-*.
const FILTROS_OCULTOS = ['browser_language', 'referer', 'campaign_id'];

export const semFiltrosOcultos = tipos =>
  tipos.filter(tipo => !FILTROS_OCULTOS.includes(tipo.attributeKey));

import { TOM } from './ui';

// Cor de cada nível de ferramenta (campo `nivel` do config/agents/tools.yml):
// azul = só consulta · âmbar = prepara Sugestão (o humano aprova) ·
// verde (teal do kit) = rascunho pro cliente · neutro = escrita interna.
// A ordem das chaves é a ordem da legenda na tela de Skills.
export const NIVEL_TOM = {
  consulta: TOM.blue,
  sugestao: TOM.amber,
  rascunho: TOM.teal,
  interna: TOM.slate,
};

// Nome legível + nível pelo id. Fora do catálogo (HTTP personalizada, id
// antigo, ou catálogo que não carregou pra quem não é admin): id cru, neutra.
export const ferramentaInfo = (id, catalogo = []) => {
  const tool = (catalogo || []).find(item => item.id === id);
  return {
    id,
    title: tool?.title || id,
    nivel: tool?.nivel || null,
    tom: NIVEL_TOM[tool?.nivel] || TOM.slate,
  };
};

import tools from '../../../../../../../../config/agents/tools.yml';
import { NIVEL_TOM, ferramentaInfo } from '../ferramentas';
import { TOM } from '../ui';

describe('ferramentas', () => {
  it('toda ferramenta do tools.yml tem um nível com cor', () => {
    tools.forEach(tool => {
      expect(Object.keys(NIVEL_TOM)).toContain(tool.nivel);
    });
  });

  it('rascunho pro cliente = pedir documentos e link do portal', () => {
    const ids = tools.filter(tool => tool.nivel === 'rascunho').map(t => t.id);
    expect(ids.sort()).toEqual(['enviar_link_portal', 'solicitar_documento']);
  });

  it('acha nome e cor no catálogo', () => {
    const catalogo = [
      { id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao' },
    ];
    expect(ferramentaInfo('mover_etapa', catalogo)).toEqual({
      id: 'mover_etapa',
      title: 'Mover de etapa',
      nivel: 'sugestao',
      tom: TOM.amber,
    });
  });

  it('fora do catálogo (HTTP personalizada ou catálogo não carregado) fica neutra com o id cru', () => {
    expect(ferramentaInfo('minha_http', [])).toEqual({
      id: 'minha_http',
      title: 'minha_http',
      nivel: null,
      tom: TOM.slate,
    });
    expect(ferramentaInfo('minha_http', null).title).toBe('minha_http');
  });
});

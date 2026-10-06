import tools from '../../../../../../../../config/agents/tools.yml';
import {
  NIVEL_TOM,
  SISTEMAS,
  agruparPorSistema,
  ferramentaInfo,
} from '../ferramentas';
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

  it('toda ferramenta do tools.yml tem um sistema com seção na tela', () => {
    tools.forEach(tool => {
      expect(SISTEMAS).toContain(tool.sistema);
    });
  });

  it('toda ferramenta *_advbox mexe no AdvBox', () => {
    tools
      .filter(tool => tool.id.endsWith('_advbox'))
      .forEach(tool => {
        expect(tool.sistema).toBe('advbox');
      });
  });

  it('agrupa na ordem da tela e omite sistema sem ferramenta', () => {
    const grupos = agruparPorSistema([
      { id: 'nota', sistema: 'conversa' },
      { id: 'a_advbox', sistema: 'advbox' },
      { id: 'b_advbox', sistema: 'advbox' },
    ]);
    expect(grupos.map(grupo => grupo.sistema)).toEqual(['advbox', 'conversa']);
    expect(grupos[0].ferramentas.map(tool => tool.id)).toEqual([
      'a_advbox',
      'b_advbox',
    ]);
  });
});

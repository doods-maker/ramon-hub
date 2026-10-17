import { mount } from '@vue/test-utils';
import MessageList from '../MessageList.vue';

const decisaoDe = decisao => {
  const wrapper = mount(MessageList, {
    props: {
      messages: [{ sender: 'assistant', content: 'Fica R$ 3.000', decisao }],
    },
  });
  return wrapper.find('[data-testid="testar-decisao"]').text();
};

describe('MessageList: decisão do Perfil no Testar', () => {
  it('ação em Rascunho: o motivo é a ação', () => {
    expect(
      decisaoDe({ valor: 'rascunho', motivo: 'acao:citar_honorario' })
    ).toContain('is set to Draft');
  });

  it('limitado pelo marcador: não diz que a ação está em Rascunho', () => {
    const texto = decisaoDe({
      valor: 'rascunho',
      motivo: 'acao:citar_honorario',
      limitado: true,
    });
    expect(texto).toContain('limited by the marker');
    expect(texto).not.toContain('is set to Draft');
  });
});

import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import Base from '../Base.vue';
import { provideMessageContext } from '../../provider.js';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: [] }),
}));

const montar = (inReplyTo, isEquipe = true) =>
  mount(
    {
      components: { Base },
      setup() {
        provideMessageContext({
          variant: ref('agent'),
          orientation: ref('right'),
          inReplyTo: ref(inReplyTo),
          shouldGroupWithNext: ref(false),
          isEquipe: ref(isEquipe),
          mostrarAutor: ref(false),
          marcadoEquipe: ref(false),
          primeiroDoAutor: ref(false),
          sender: ref(null),
          content: ref('Eu cubro hoje.'),
          attachments: ref([]),
          currentUserId: ref(1),
        });
      },
      template:
        '<Base hide-meta><span class="prose">Eu cubro hoje.</span></Base>',
    },
    {
      global: {
        directives: {
          'dompurify-html': (el, { value }) => {
            el.innerHTML = value;
          },
        },
      },
    }
  );

const citacao = w => w.find('[data-testid="equipe-cita"]');
const colega = { sender: { id: 2, name: 'Thaís' } };

describe('Base: citação na Equipe', () => {
  it('mostra o nome de quem escreveu e o texto, sem o token do @', () => {
    const w = montar({
      ...colega,
      id: 9,
      content: '[@Eduardo](mention://user/1/Eduardo) o cliente chegou?',
    });
    expect(citacao(w).text()).toContain('Thaís');
    expect(citacao(w).text()).toContain('@Eduardo o cliente chegou?');
    expect(citacao(w).text()).not.toContain('mention://');
  });

  it('mostra "Você" quando a mensagem citada é minha', () => {
    const w = montar({
      id: 9,
      sender: { id: 1, name: 'Eduardo' },
      content: 'Oi',
    });
    expect(citacao(w).text()).toContain('RAMON.EQUIPE.VOCE');
    expect(citacao(w).text()).not.toContain('Eduardo');
  });

  it('citação só com anexo mostra o rótulo do anexo', () => {
    const w = montar({
      ...colega,
      id: 9,
      content: null,
      attachments: [{ file_type: 'audio' }],
    });
    expect(citacao(w).text()).toContain('CHAT_LIST.ATTACHMENTS.audio.CONTENT');
  });

  it('citação de mensagem apagada mostra o texto de apagada', () => {
    const w = montar({
      ...colega,
      id: 9,
      content: 'Esta mensagem foi excluída',
      contentAttributes: { deleted: true },
    });
    expect(citacao(w).text()).toContain('Esta mensagem foi excluída');
  });

  it('autor apagado: citação sem nome', () => {
    const w = montar({ id: 9, sender: null, content: 'Oi' });
    expect(citacao(w).findAll('span')).toHaveLength(1);
  });

  it('a citação não é .prose: a reserva da hora só alcança o conteúdo da mensagem', () => {
    const w = montar({ ...colega, id: 9, content: 'Quem cobre o almoço?' });
    expect(citacao(w).find('.prose').exists()).toBe(false);
    expect(citacao(w).classes()).not.toContain('prose');
    expect(w.findAll('.prose')).toHaveLength(1);
    expect(w.find('.prose').text()).toBe('Eu cubro hoje.');
  });
});

describe('Base: citação fora da Equipe', () => {
  it('fica como a nativa: sem nome, com o preview em .prose', () => {
    const w = montar({ ...colega, id: 9, content: 'Oi' }, false);
    expect(citacao(w).exists()).toBe(false);
    expect(w.text()).not.toContain('Thaís');
    expect(w.find('.prose.line-clamp-2').text()).toBe('Oi');
  });
});

import { mount, flushPromises } from '@vue/test-utils';
import MeuDiaAdvbox from '../MeuDiaAdvbox.vue';
import ChegadasAPI from 'dashboard/api/ramonChegadas';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: k => k }) }));
vi.mock('dashboard/api/ramonChegadas', () => ({
  default: { meuDia: vi.fn() },
}));

const payload = () => ({
  hoje: [
    {
      advbox_post_id: 1,
      tarefa: 'AUDIÊNCIA',
      cliente_nome: 'MARIA SILVA',
      data: '2026-11-09',
      prazo: '2026-11-12',
      local: 'Fórum',
      concluida: false,
    },
    {
      advbox_post_id: 2,
      tarefa: 'PERÍCIA',
      cliente_nome: 'JOÃO',
      data: '2026-11-09',
      prazo: null,
      local: null,
      concluida: true,
    },
  ],
  semana: [
    {
      advbox_post_id: 3,
      tarefa: 'PRAZO',
      cliente_nome: 'ANA',
      data: '2026-11-11',
      concluida: false,
    },
    {
      advbox_post_id: 4,
      tarefa: 'PERÍCIA',
      cliente_nome: 'BIA',
      data: '2026-11-11',
      concluida: false,
    },
    {
      advbox_post_id: 5,
      tarefa: 'PRAZO',
      cliente_nome: 'CAIO',
      data: '2026-11-13',
      concluida: false,
    },
  ],
  esteira: [
    {
      advbox_post_id: 8,
      cliente_nome: 'MARIA SILVA',
      situacao: 'Esteira concluída com rascunho.',
      peca: 'Petição inicial — Maria Silva.docx',
    },
    {
      advbox_post_id: 9,
      cliente_nome: 'DIEGO',
      situacao: 'Parou por falta de laudo',
      peca: null,
    },
  ],
});

const montar = async (props = { comAgenda: true }, dados = payload()) => {
  ChegadasAPI.meuDia.mockResolvedValue({ data: { payload: dados } });
  const wrapper = mount(MeuDiaAdvbox, { props });
  await flushPromises();
  return wrapper;
};

describe('MeuDiaAdvbox.vue', () => {
  beforeEach(() => vi.clearAllMocks());

  it('hoje: tarefas do dia com cliente e prazo; concluída riscada', async () => {
    const wrapper = await montar();
    const linhas = wrapper.findAll('[data-testid="meu-dia-hoje"]');
    expect(linhas).toHaveLength(2);
    expect(linhas[0].text()).toContain('AUDIÊNCIA');
    expect(linhas[0].text()).toContain('MARIA SILVA');
    expect(linhas[0].find('[data-testid="meu-dia-prazo"]').exists()).toBe(true);
    expect(linhas[1].classes()).toContain('line-through');
  });

  it('próximos 7 dias agrupados por dia', async () => {
    const wrapper = await montar();
    const dias = wrapper.findAll('[data-testid="meu-dia-dia"]');
    expect(dias).toHaveLength(2);
    expect(dias[0].findAll('[data-testid="meu-dia-semana"]')).toHaveLength(2);
    expect(dias[1].text()).toContain('CAIO');
  });

  it('peças da esteira: peça pronta com busca no Drive; caso parado sem link', async () => {
    const wrapper = await montar();
    const linhas = wrapper.findAll('[data-testid="meu-dia-esteira"]');
    expect(linhas).toHaveLength(2);
    const link = linhas[0].find('a');
    expect(link.text()).toBe('Petição inicial — Maria Silva.docx');
    expect(link.attributes('href')).toBe(
      `https://drive.google.com/drive/search?q=${encodeURIComponent('Petição inicial — Maria Silva.docx')}`
    );
    expect(link.attributes('target')).toBe('_blank');
    expect(linhas[1].find('a').exists()).toBe(false);
    expect(linhas[1].text()).toContain('Parou por falta de laudo');
  });

  it('sem agenda (fora do jurídico): só o bloco da esteira, e nada quando ela está vazia', async () => {
    const comEsteira = await montar({ comAgenda: false });
    expect(comEsteira.find('[data-testid="meu-dia-hoje"]').exists()).toBe(
      false
    );
    expect(comEsteira.findAll('[data-testid="meu-dia-esteira"]')).toHaveLength(
      2
    );

    const vazio = await montar(
      { comAgenda: false },
      { hoje: [], semana: [], esteira: [] }
    );
    expect(vazio.html()).not.toContain('section');
  });

  it('ADVBOX fora: avisa só quem tem a agenda', async () => {
    ChegadasAPI.meuDia.mockRejectedValue(new Error('503'));
    const agenda = mount(MeuDiaAdvbox, { props: { comAgenda: true } });
    await flushPromises();
    expect(agenda.find('[data-testid="meu-dia-fora"]').exists()).toBe(true);

    const semAgenda = mount(MeuDiaAdvbox, { props: { comAgenda: false } });
    await flushPromises();
    expect(semAgenda.html()).not.toContain('section');
  });
});

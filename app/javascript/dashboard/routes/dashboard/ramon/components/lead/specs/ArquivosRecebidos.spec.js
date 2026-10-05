import { mount, flushPromises } from '@vue/test-utils';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import ArquivosRecebidos from '../ArquivosRecebidos.vue';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { getAllAttachments: vi.fn() },
}));

// meio-dia UTC: o dia não muda em nenhum fuso do Brasil
const em = (dia, hora = '12:00') =>
  new Date(`${dia}T${hora}:00Z`).getTime() / 1000;
const anexo = (id, fileType, nome, created, extension = null) => ({
  id,
  file_type: fileType,
  extension,
  data_url: `https://hub.exemplo/rails/active_storage/blobs/redirect/abc/${encodeURIComponent(nome)}`,
  created_at: created,
});

const montar = async payload => {
  ConversationAPI.getAllAttachments.mockResolvedValue({ data: { payload } });
  const wrapper = mount(ArquivosRecebidos, {
    props: { conversationId: 101 },
    global: { mocks: { $t: k => k } },
  });
  await flushPromises();
  return wrapper;
};

describe('ArquivosRecebidos', () => {
  beforeEach(() => vi.clearAllMocks());

  it('busca os anexos da conversa e agrupa por dia (dd/mm/aaaa)', async () => {
    const wrapper = await montar([
      anexo(1, 'audio', 'Áudio.ogg', em('2026-10-03', '15:00')),
      anexo(2, 'image', 'foto laudo.jpg', em('2026-10-03', '14:00')),
      anexo(3, 'file', 'CTPS.pdf', em('2026-10-01'), 'pdf'),
    ]);
    expect(ConversationAPI.getAllAttachments).toHaveBeenCalledWith(101);
    const dias = wrapper.findAll('[data-testid="arquivos-dia"]');
    expect(dias).toHaveLength(2);
    expect(dias[0].text()).toContain('03/10/2026');
    expect(dias[0].findAll('[data-testid="arquivo"]')).toHaveLength(2);
    expect(dias[1].text()).toContain('01/10/2026');
    // nome vem da URL, decodificado
    expect(dias[0].text()).toContain('foto laudo.jpg');
  });

  it.each([
    ['image', 'a.jpg', null, 'i-lucide-image', 'text-n-teal-11', 'IMAGE'],
    ['audio', 'a.ogg', null, 'i-lucide-mic', 'text-n-iris-11', 'AUDIO'],
    ['video', 'a.mp4', null, 'i-lucide-video', 'text-n-amber-11', 'VIDEO'],
    ['file', 'laudo.pdf', null, 'i-lucide-file-text', 'text-n-ruby-11', 'PDF'],
    ['file', 'ctps.docx', 'docx', 'i-lucide-file', 'text-n-blue-11', 'FILE'],
  ])(
    '%s %s → ícone e cor do tipo',
    async (tipo, nome, ext, icone, cor, rotulo) => {
      const wrapper = await montar([
        anexo(1, tipo, nome, em('2026-10-03'), ext),
      ]);
      const tile = wrapper.find('[data-testid="arquivo-tipo"]');
      expect(tile.classes()).toContain(cor);
      expect(tile.find('span').classes()).toContain(icone);
      expect(wrapper.find('[data-testid="arquivo"]').text()).toContain(
        `RAMON.LEAD_PANEL.ARQUIVOS.TIPO.${rotulo}`
      );
    }
  );

  it('botão de baixar aponta pro arquivo', async () => {
    const wrapper = await montar([anexo(1, 'file', 'a.pdf', em('2026-10-03'))]);
    expect(
      wrapper.find('[data-testid="arquivo-baixar"]').attributes('href')
    ).toContain('/a.pdf');
  });

  it('sem anexos: linha de vazio', async () => {
    const wrapper = await montar([]);
    expect(wrapper.find('[data-testid="arquivos-vazio"]').exists()).toBe(true);
  });
});

import {
  EMOJIS_REACAO,
  marcaUsuario,
  textoLimpo,
  listaMarcacao,
  estadoVisto,
  identidadeConversa,
  resumoReacoes,
  rotuloDia,
  horaLista,
  prefixoPrevia,
  autorCitacao,
  textoCitacao,
} from '../equipe';

describe('helpers/equipe', () => {
  it('emojis na ordem', () => {
    expect(EMOJIS_REACAO).toEqual(['👍', '❤️', '😂', '😮', '😢', '🙏']);
  });

  it('marcaUsuario não confunde ids', () => {
    expect(marcaUsuario('[@Ana](mention://user/1/Ana) oi', 1)).toBe(true);
    expect(marcaUsuario('[@Ana](mention://user/12/Ana) oi', 1)).toBe(false);
    expect(marcaUsuario('[@todos](mention://todos/0/todos) oi', 1)).toBe(true);
    expect(marcaUsuario('@todos oi', 1)).toBe(false);
    expect(marcaUsuario(null, 1)).toBe(false);
  });

  it('textoLimpo tira o token', () => {
    expect(
      textoLimpo(
        '[@Dr. Ramon Antonio](mention://user/3/Dr.%20Ramon%20Antonio) ok'
      )
    ).toBe('@Dr. Ramon Antonio ok');
  });

  it('listaMarcacao: grupo traz todos, 1:1 só a outra pessoa, nunca eu', () => {
    const p = [
      { id: 1, name: 'Eu' },
      { id: 2, name: 'Bia' },
    ];
    expect(listaMarcacao(p, 1, 'grupo').map(i => i.name)).toEqual([
      'todos',
      'Bia',
    ]);
    expect(listaMarcacao(p, 1, '1a1').map(i => i.name)).toEqual(['Bia']);
    expect(listaMarcacao([], 1, 'grupo').map(i => i.name)).toEqual(['todos']);
  });

  it('estadoVisto conta quem não é autor', () => {
    const p = [
      { id: 1, name: 'Eu', lastSeenAt: 0 },
      { id: 2, name: 'Ana', lastSeenAt: 100 },
      { id: 3, name: 'Bia', lastSeenAt: 50 },
    ];
    expect(estadoVisto({ createdAt: 80, senderId: 1 }, p, 1)).toEqual({
      todosLeram: false,
      leram: ['Ana'],
      faltam: ['Bia'],
      total: 2,
    });
  });

  it('estadoVisto: nulo não leu; todos leram só com total > 0', () => {
    const p = [
      { id: 1, name: 'Eu', lastSeenAt: null },
      { id: 2, name: 'Ana', lastSeenAt: 100 },
    ];
    expect(estadoVisto({ createdAt: 80, senderId: 2 }, p, 2).faltam).toEqual([
      'Eu',
    ]);
    expect(estadoVisto({ createdAt: 80, senderId: 1 }, p, 1).todosLeram).toBe(
      true
    );
    expect(estadoVisto({ createdAt: 80, senderId: 1 }, [], 1).todosLeram).toBe(
      false
    );
  });

  it('identidadeConversa: 1:1 mostra o outro; admin de fora e grupo usam o contato', () => {
    const chat = {
      equipe_tipo: '1a1',
      equipe_pessoas: [
        { id: 1, name: 'Ana', thumbnail: 'a' },
        { id: 2, name: 'Bia', thumbnail: 'b' },
      ],
    };
    expect(identidadeConversa(chat, 1)).toEqual({ nome: 'Bia', foto: 'b' });
    expect(identidadeConversa(chat, 9)).toBeNull();
    expect(
      identidadeConversa({ equipe_tipo: 'grupo', equipe_pessoas: [] }, 1)
    ).toBeNull();
  });

  it('resumoReacoes agrupa, marca a minha e usa o nome gravado de quem saiu do chat', () => {
    const r = [
      { userId: 1, userName: 'Eu', emoji: '👍' },
      { userId: 9, userName: 'Saiu', emoji: '👍' },
    ];
    expect(resumoReacoes(r, [], 1)).toEqual([
      { emoji: '👍', total: 2, nomes: ['Eu', 'Saiu'], minha: true },
    ]);
  });

  it('prefixoPrevia', () => {
    expect(
      prefixoPrevia({ sender: { id: 1, name: 'Eu' } }, 1, 'grupo')
    ).toEqual({ voce: true, nome: null });
    expect(
      prefixoPrevia({ sender: { id: 2, name: 'Ana' } }, 1, 'grupo')
    ).toEqual({ voce: false, nome: 'Ana' });
    expect(prefixoPrevia({ sender: { id: 2, name: 'Ana' } }, 1, '1a1')).toEqual(
      { voce: false, nome: null }
    );
  });

  it('autorCitacao: "Você" se é minha, nome do colega, nada sem autor', () => {
    const t = k => k;
    expect(autorCitacao({ sender: { id: 1, name: 'Eu' } }, 1, t)).toBe(
      'RAMON.EQUIPE.VOCE'
    );
    expect(autorCitacao({ sender: { id: 2, name: 'Ana' } }, 1, t)).toBe('Ana');
    expect(autorCitacao({ sender: null }, 1, t)).toBeNull();
  });

  it('textoCitacao: texto puro, anexo (snake e camel) e indisponível', () => {
    const t = k => k;
    expect(textoCitacao({ content: 'linha 1\nlinha 2 **forte**' }, t)).toBe(
      'linha 1 linha 2 forte'
    );
    expect(
      textoCitacao({ content: '[@Ana](mention://user/2/Ana) oi' }, t)
    ).toBe('@Ana oi');
    expect(textoCitacao({ attachments: [{ file_type: 'image' }] }, t)).toBe(
      'CHAT_LIST.ATTACHMENTS.image.CONTENT'
    );
    expect(textoCitacao({ attachments: [{ fileType: 'file' }] }, t)).toBe(
      'CHAT_LIST.ATTACHMENTS.file.CONTENT'
    );
    expect(textoCitacao({ attachments: [] }, t)).toBe(
      'CONVERSATION.REPLY_MESSAGE_NOT_FOUND'
    );
  });

  it('rotuloDia compara dias em São Paulo', () => {
    // 2026-11-02 02:30 UTC = 01/11 23:30 em São Paulo
    const agora = Date.UTC(2026, 10, 2, 2, 30);
    const seg = iso => Date.parse(iso) / 1000;
    expect(rotuloDia(seg('2026-11-02T01:00:00Z'), agora)).toBe('HOJE');
    expect(rotuloDia(seg('2026-11-01T14:00:00Z'), agora)).toBe('HOJE');
    expect(rotuloDia(seg('2026-11-01T01:00:00Z'), agora)).toBe('ONTEM');
    expect(rotuloDia(seg('2026-10-20T15:00:00Z'), agora)).toBe('20/10/2026');
  });

  it('horaLista: hoje em HH:mm, ontem em rótulo, antes em data, no fuso de São Paulo', () => {
    // 2026-11-02 02:30 UTC = 01/11 23:30 em São Paulo
    const agora = Date.UTC(2026, 10, 2, 2, 30);
    const seg = iso => Date.parse(iso) / 1000;
    expect(horaLista(seg('2026-11-02T01:00:00Z'), agora)).toBe('22:00');
    expect(horaLista(seg('2026-11-01T17:32:00Z'), agora)).toBe('14:32');
    // virada do dia em São Paulo: 00:00 de 01/11 é hoje, 23:59 de 31/10 é ontem
    expect(horaLista(seg('2026-11-01T03:00:00Z'), agora)).toBe('00:00');
    expect(horaLista(seg('2026-11-01T02:59:00Z'), agora)).toBe('ONTEM');
    expect(horaLista(seg('2026-10-20T15:00:00Z'), agora)).toBe('20/10/2026');
  });
});

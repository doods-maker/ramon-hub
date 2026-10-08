import { referenciaCaso, skillsDoPapel } from '../testar';

const SKILLS = [
  {
    id: 1,
    title: 'Funil hoje',
    enabled: true,
    exemplo: 'Como está o funil?',
    papeis: ['comercial'],
  },
  {
    id: 2,
    title: 'Agenda do dia',
    enabled: true,
    exemplo: 'Agenda?',
    papeis: ['recepção'],
  },
  {
    id: 3,
    title: 'Desligada',
    enabled: false,
    exemplo: 'x',
    papeis: ['recepção'],
  },
  { id: 4, title: 'Sem fala', enabled: true, exemplo: '', papeis: [] },
  {
    id: 5,
    title: 'Consultas no AdvBox',
    enabled: true,
    exemplo: 'Prazos?',
    papeis: [],
  },
];

describe('skillsDoPapel (I-X5)', () => {
  it('só ligadas com fala; as do seu papel primeiro, depois pelo título', () => {
    const lista = skillsDoPapel(SKILLS, [{ name: 'recepção' }]);
    expect(lista.map(skill => [skill.id, skill.meu])).toEqual([
      [2, true],
      [5, false],
      [1, false],
    ]);
  });

  it('sem time (ex.: administrador), todas pelo título', () => {
    expect(skillsDoPapel(SKILLS, []).map(skill => skill.id)).toEqual([2, 5, 1]);
  });
});

describe('referenciaCaso (I-PG4)', () => {
  it('nº do caso no formato que as skills entendem', () => {
    expect(referenciaCaso({ id: 12, name: 'Maria Souza' })).toBe(
      'caso 12 (Maria Souza)'
    );
  });
});

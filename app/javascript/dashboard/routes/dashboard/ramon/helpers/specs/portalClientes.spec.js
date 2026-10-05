import { filtrarClientes } from '../portalClientes';

const agora = new Date('2026-10-05T12:00:00Z').getTime();
const clientes = [
  {
    id: 1,
    nome: 'José Ribeiro',
    cpf: '45678912345',
    convidado_em: '2026-09-01',
    dias_acesso: 0,
    docs_pendentes: 0,
  },
  {
    id: 2,
    nome: 'Maria Souza',
    cpf: '32165498710',
    convidado_em: '2026-08-01',
    dias_acesso: 5,
    ultimo_acesso_em: '2026-08-20T10:00:00Z',
    docs_pendentes: 2,
  },
  {
    id: 3,
    nome: 'Pedro Alves',
    cpf: '65498732155',
    convidado_em: '2026-07-01',
    dias_acesso: 3,
    ultimo_acesso_em: '2026-08-01T10:00:00Z',
    suspenso_em: '2026-10-01',
    docs_pendentes: 0,
  },
];
const ids = opts =>
  filtrarClientes(clientes, { agora, ...opts }).map(c => c.id);

describe('filtrarClientes', () => {
  it('busca por nome sem acento ou por dígitos do CPF', () => {
    expect(ids({ busca: 'jose' })).toEqual([1]);
    expect(ids({ busca: '321.654' })).toEqual([2]);
    expect(ids({ busca: '' })).toEqual([1, 2, 3]);
  });

  it('filtros: nunca entrou, sem acesso há 30+ dias, suspensos, documento pendente', () => {
    expect(ids({ filtro: 'nunca_entrou' })).toEqual([1]);
    expect(ids({ filtro: 'sem_acesso' })).toEqual([2]);
    expect(ids({ filtro: 'suspensos' })).toEqual([3]);
    expect(ids({ filtro: 'doc_pendente' })).toEqual([2]);
  });

  it('combina busca e filtro', () => {
    expect(ids({ filtro: 'doc_pendente', busca: 'pedro' })).toEqual([]);
  });
});

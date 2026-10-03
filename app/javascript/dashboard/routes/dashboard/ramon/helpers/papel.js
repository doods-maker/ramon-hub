// Papel de quem está logado — monta o menu e (Onda 3) a tela Hoje.
// Cosmético: o guard de verdade segue nas rotas e no backend.
const normaliza = nome =>
  (nome || '').normalize('NFD').replace(/\p{M}/gu, '').trim().toLowerCase();

export const papelDe = ({ isAdmin, nomesDosTimes = [] }) => {
  if (isAdmin) return 'gestor';
  const times = nomesDosTimes.map(normaliza);
  if (times.includes('recepcao') || times.includes('controladoria'))
    return 'recepcao';
  if (times.includes('closer')) return 'closer';
  if (times.includes('sdr')) return 'sdr';
  if (times.includes('advogados')) return 'advogada';
  return 'equipe';
};

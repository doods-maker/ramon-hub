// Regras puras da página do Testar.

// I-X5: skills ligadas e com fala de exemplo; as do seu papel (times de que você participa) primeiro,
// depois pelo título. Sem time (ex.: administrador), todas pelo título.
export const skillsDoPapel = (skills, meusTimes) => {
  const meus = new Set((meusTimes || []).map(time => time.name));
  return (skills || [])
    .filter(skill => skill.enabled && skill.exemplo)
    .map(skill => ({
      ...skill,
      meu: (skill.papeis || []).some(papel => meus.has(papel)),
    }))
    .sort(
      (a, b) =>
        Number(b.meu) - Number(a.meu) || a.title.localeCompare(b.title, 'pt-BR')
    );
};

// I-PG4: "caso N" é o lead_id que as skills do Copiloto entendem (assistentes.yml, regra de identificação);
// o nome ajuda a busca do processo no AdvBox (mesma regra do painel do Copiloto, A4 N8).
export const referenciaCaso = lead => `caso ${lead.id} (${lead.name})`;

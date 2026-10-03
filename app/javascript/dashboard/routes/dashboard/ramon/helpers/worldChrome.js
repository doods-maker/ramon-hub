// Título e favicon por mundo (item 11 do 4b). O badge de som do
// faviconHelper.js pode sobrescrever o monograma até a próxima troca de
// rota — cosmético, aceito.
const MONOGRAM = '/brand-assets/ramon-monogram.png';

export const applyWorldChrome = isIntranet => {
  document.title = isIntranet ? 'Intranet · Ramon Antônio' : 'Ramon Antônio';
  document.querySelectorAll('.favicon').forEach(link => {
    link.setAttribute(
      'href',
      isIntranet ? MONOGRAM : `/favicon-${link.getAttribute('sizes')}.png`
    );
  });
};

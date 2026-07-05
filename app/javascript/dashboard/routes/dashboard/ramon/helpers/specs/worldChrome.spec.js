import { applyWorldChrome } from '../worldChrome';

describe('applyWorldChrome', () => {
  beforeEach(() => {
    document.head.innerHTML =
      '<link class="favicon" sizes="32x32" href="/favicon-32x32.png" />' +
      '<link class="favicon" sizes="96x96" href="/favicon-96x96.png" />';
    document.title = 'qualquer';
  });

  it('na intranet: título próprio e favicon monograma', () => {
    applyWorldChrome(true);
    expect(document.title).toBe('Intranet · Ramon Antônio');
    document.querySelectorAll('.favicon').forEach(l => {
      expect(l.getAttribute('href')).toBe('/brand-assets/ramon-monogram.png');
    });
  });

  it('fora da intranet: título e favicons padrão restaurados', () => {
    applyWorldChrome(true);
    applyWorldChrome(false);
    expect(document.title).toBe('Ramon Antônio');
    expect(
      document.querySelector('.favicon[sizes="32x32"]').getAttribute('href')
    ).toBe('/favicon-32x32.png');
  });
});

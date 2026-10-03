import { phoneDigits, waMeUrl, telefoneBr } from '../phone';

describe('phone helpers', () => {
  it('strips non-digits', () => {
    expect(phoneDigits('+55 (48) 99999-0000')).toBe('5548999990000');
    expect(phoneDigits(null)).toBe('');
  });
  it('builds wa.me url', () => {
    expect(waMeUrl('+55 48 99999-0000')).toBe('https://wa.me/5548999990000');
  });
  it('formata celular brasileiro como no mockup', () => {
    expect(telefoneBr('+5548991203381')).toBe('(48) 9 9120-3381');
    expect(telefoneBr('+1 555 0100')).toBe('+1 555 0100');
    expect(telefoneBr(null)).toBe('');
  });
});

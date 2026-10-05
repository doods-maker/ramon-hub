import { phoneDigits, waMeUrl, formatPhoneBr } from '../phone';

describe('phone helpers', () => {
  it('strips non-digits', () => {
    expect(phoneDigits('+55 (48) 99999-0000')).toBe('5548999990000');
    expect(phoneDigits(null)).toBe('');
  });
  it('builds wa.me url', () => {
    expect(waMeUrl('+55 48 99999-0000')).toBe('https://wa.me/5548999990000');
  });
  it('formata telefone do Brasil (celular e fixo); o resto volta como veio', () => {
    expect(formatPhoneBr('+5548998123456')).toBe('+55 (48) 99812-3456');
    expect(formatPhoneBr('+55 48 3622-1234')).toBe('+55 (48) 3622-1234');
    expect(formatPhoneBr('+1 415 555 0100')).toBe('+1 415 555 0100');
    expect(formatPhoneBr(null)).toBe('');
  });
});

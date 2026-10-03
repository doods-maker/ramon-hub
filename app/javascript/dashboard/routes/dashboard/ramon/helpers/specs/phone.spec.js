import { phoneDigits, waMeUrl } from '../phone';

describe('phone helpers', () => {
  it('strips non-digits', () => {
    expect(phoneDigits('+55 (48) 99999-0000')).toBe('5548999990000');
    expect(phoneDigits(null)).toBe('');
  });
  it('builds wa.me url', () => {
    expect(waMeUrl('+55 48 99999-0000')).toBe('https://wa.me/5548999990000');
  });
});

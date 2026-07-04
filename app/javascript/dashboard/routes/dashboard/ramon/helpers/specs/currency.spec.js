import { formatBrl, parseBrlInput } from '../currency';

describe('formatBrl', () => {
  it('formats a number as BRL', () => {
    // Intl usa espaço não separável entre R$ e o número
    expect(formatBrl(1234.56)).toBe('R$ 1.234,56');
  });
  it('returns empty string for null/undefined/empty', () => {
    expect(formatBrl(null)).toBe('');
    expect(formatBrl(undefined)).toBe('');
    expect(formatBrl('')).toBe('');
  });
});

describe('parseBrlInput', () => {
  it('parses pt-BR format with thousands and comma', () => {
    expect(parseBrlInput('1.234,56')).toBe(1234.56);
    expect(parseBrlInput('R$ 1.234,56')).toBe(1234.56);
  });
  it('parses comma-only decimals', () => {
    expect(parseBrlInput('1234,5')).toBe(1234.5);
  });
  it('parses plain numbers (dot decimal, no comma)', () => {
    expect(parseBrlInput('1234.56')).toBe(1234.56);
    expect(parseBrlInput('1500')).toBe(1500);
  });
  it('returns null for empty or garbage', () => {
    expect(parseBrlInput('')).toBeNull();
    expect(parseBrlInput(null)).toBeNull();
    expect(parseBrlInput('abc')).toBeNull();
  });
});

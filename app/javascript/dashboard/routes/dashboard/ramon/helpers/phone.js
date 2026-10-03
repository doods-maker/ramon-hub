export const phoneDigits = phone => (phone || '').replace(/\D/g, '');

export const waMeUrl = phone => `https://wa.me/${phoneDigits(phone)}`;

// "+5548991203381" → "(48) 9 9120-3381"; fora do padrão de celular BR, como veio.
export const telefoneBr = phone => {
  const d = phoneDigits(phone).replace(/^55(?=\d{11}$)/, '');
  if (d.length !== 11) return phone || '';
  return `(${d.slice(0, 2)}) ${d[2]} ${d.slice(3, 7)}-${d.slice(7)}`;
};

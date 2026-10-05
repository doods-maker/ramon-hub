export const phoneDigits = phone => (phone || '').replace(/\D/g, '');

export const waMeUrl = phone => `https://wa.me/${phoneDigits(phone)}`;

// Celular/fixo do Brasil em +55 (DD) NNNNN-NNNN / NNNN-NNNN; outro formato
// (estrangeiro, incompleto) volta como veio.
export const formatPhoneBr = phone => {
  const m = phoneDigits(phone).match(/^55(\d{2})(\d{4,5})(\d{4})$/);
  return m ? `+55 (${m[1]}) ${m[2]}-${m[3]}` : phone || '';
};

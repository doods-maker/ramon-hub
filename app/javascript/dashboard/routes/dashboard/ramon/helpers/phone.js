export const phoneDigits = phone => (phone || '').replace(/\D/g, '');

export const waMeUrl = phone => `https://wa.me/${phoneDigits(phone)}`;

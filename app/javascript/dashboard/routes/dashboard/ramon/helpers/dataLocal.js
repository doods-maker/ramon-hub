// <input type="datetime-local"> quer 'YYYY-MM-DDTHH:mm' no fuso do navegador.
export const paraInputLocal = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const p = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
};

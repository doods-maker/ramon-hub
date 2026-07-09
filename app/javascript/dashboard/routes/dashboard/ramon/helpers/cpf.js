export const stripCpf = text => String(text ?? '').replace(/\D/g, '');

export const formatCpf = digits => {
  const d = stripCpf(digits);
  if (!d) return '';
  return d
    .replace(/^(\d{3})(\d)/, '$1.$2')
    .replace(/^(\d{3})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/\.(\d{3})(\d{1,2})$/, '.$1-$2');
};

// Constrói o atributo `d` de um <path> SVG a partir de uma série de números.
// Y normalizado: menor valor na base, maior no topo. Vazio se < 2 pontos.
export function sparklinePath(points, { width = 240, height = 40 } = {}) {
  if (!Array.isArray(points) || points.length < 2) return '';
  const max = Math.max(...points);
  const min = Math.min(...points);
  const range = max - min || 1;
  const stepX = width / (points.length - 1);
  return points
    .map((value, i) => {
      const x = (i * stepX).toFixed(1);
      const y = (height - ((value - min) / range) * height).toFixed(1);
      return `${i === 0 ? 'M' : 'L'}${x},${y}`;
    })
    .join(' ');
}

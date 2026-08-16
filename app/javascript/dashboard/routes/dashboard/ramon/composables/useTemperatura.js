import { computed } from 'vue';

// ponytail: heurística local sobre as mensagens JÁ carregadas da conversa —
// sem LLM, sem backend. Régua: última incoming <1h = quente; <24h = morna;
// senão fria. Sinal de hesitação ("vou pensar" etc.) numa incoming recente
// rebaixa quente→morna. Upgrade path: janela maior via endpoint se precisar.
const HESITACAO =
  /vou pensar|depois eu vejo|vou conversar|mais pra frente|qualquer coisa eu chamo/i;

export function useTemperatura(messages) {
  const incoming = computed(() =>
    (messages.value || []).filter(m => m.message_type === 0 && !m.private)
  );

  const nivel = computed(() => {
    const last = incoming.value[incoming.value.length - 1];
    if (!last) return null;
    const horas = (Date.now() / 1000 - last.created_at) / 3600;
    let n = 'fria';
    if (horas < 1) n = 'quente';
    else if (horas < 24) n = 'morna';
    const recentes = incoming.value.slice(-3);
    if (n === 'quente' && recentes.some(m => HESITACAO.test(m.content || '')))
      n = 'morna';
    return n;
  });

  const hesitando = computed(() =>
    incoming.value.slice(-3).some(m => HESITACAO.test(m.content || ''))
  );

  return { nivel, hesitando };
}

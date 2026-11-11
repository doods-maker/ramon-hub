// Ponte das aprovações da esteira com o painel dos agentes (ADR 0016). O painel
// só mostra e pede; quem lê e decide é esta página, com a sessão do hub (ADR 0014).
// Contrato das mensagens: plano C do painel, "Contrato da ponte".
import { onBeforeUnmount, onMounted, toValue } from 'vue';
import { useI18n } from 'vue-i18n';
import RamonAprovacoesAgenteAPI from 'dashboard/api/ramonAprovacoesAgente';
import { comAvisoPrimeiro, descreverPedido } from '../helpers/pedidoAgente';

const INTERVALO_MS = 5000;
const OUVINDO_MS = 60000;
const ENTRADA_MAXIMA = 4000;
const ERROS = { 403: 'proibido', 409: 'ja_decidida', 422: 'invalida' };

export const usePonteAprovacoes = (iframeRef, url) => {
  const { t } = useI18n();
  let ouvidoEm = 0;
  let relogio = null;

  const origem = () => {
    try {
      return new URL(toValue(url)).origin;
    } catch {
      return null;
    }
  };
  const painel = () => iframeRef.value?.contentWindow;
  const enviar = msg => {
    if (origem()) painel()?.postMessage({ fonte: 'hub', ...msg }, origem());
  };

  const item = pedido => {
    const d = descreverPedido(pedido);
    const caso = [
      d.cliente,
      d.numero && t('RAMON.AGENTES.APROVACOES.CASO', { numero: d.numero }),
    ];
    return {
      id: pedido.id,
      titulo: t(`RAMON.AGENTES.APROVACOES.ACOES.${d.chave}`, {
        ferramenta: d.ferramenta,
      }),
      linhas: [
        caso.filter(Boolean).join(' · '),
        ...d.campos.map(
          c => `${t(`RAMON.AGENTES.APROVACOES.CAMPOS.${c.chave}`)}: ${c.valor}`
        ),
        d.linha && String(d.linha),
        ...d.blocos.map(b => (b.rotulo ? `${b.rotulo}: ${b.texto}` : b.texto)),
      ].filter(Boolean),
      entrada: JSON.stringify(
        comAvisoPrimeiro(pedido.entrada ?? {}),
        null,
        2
      ).slice(0, ENTRADA_MAXIMA),
      criadoEm: pedido.created_at,
    };
  };

  const mandarLista = async () => {
    try {
      const { data } = await RamonAprovacoesAgenteAPI.get();
      enviar({
        tipo: 'aprovacoes',
        podeDecidir: Boolean(data.pode_decidir),
        itens: data.pedidos.map(item),
      });
    } catch {
      // Rede oscilou: a próxima rodada tenta de novo; o painel segue com a lista que tem.
    }
  };

  const parar = () => {
    clearInterval(relogio);
    relogio = null;
  };

  const rodada = () =>
    Date.now() - ouvidoEm > OUVINDO_MS ? parar() : mandarLista();

  const decidir = async ({ id, decisao, motivo }) => {
    if (!Number.isInteger(id)) return;
    const corpo =
      decisao === 'negada' && typeof motivo === 'string'
        ? { decisao, motivo }
        : { decisao };
    try {
      await RamonAprovacoesAgenteAPI.update(id, corpo);
      enviar({ tipo: 'decidida', id, ok: true });
      mandarLista();
    } catch (erro) {
      enviar({
        tipo: 'decidida',
        id,
        ok: false,
        erro: ERROS[erro?.response?.status] || 'falha',
      });
    }
  };

  const receber = event => {
    const msg = event.data;
    if (!origem() || event.origin !== origem()) return;
    if (!painel() || event.source !== painel()) return;
    if (msg?.fonte !== 'painel-agentes') return;

    if (msg.tipo === 'ouvir') {
      ouvidoEm = Date.now();
      mandarLista();
      relogio ??= setInterval(rodada, INTERVALO_MS);
    } else if (msg.tipo === 'decidir') {
      decidir(msg);
    }
  };

  onMounted(() => window.addEventListener('message', receber));
  onBeforeUnmount(() => {
    window.removeEventListener('message', receber);
    parar();
  });
};

import { createI18n } from 'vue-i18n/dist/vue-i18n.cjs.prod.js';
import en from 'dashboard/i18n/locale/en/ramon.json';
import pt from 'dashboard/i18n/locale/pt_BR/ramon.json';
import enSettings from 'dashboard/i18n/locale/en/settings.json';
import ptSettings from 'dashboard/i18n/locale/pt_BR/settings.json';
import {
  ACOES_CHATWOOT,
  ALCANCES,
  CAMPOS,
  GATILHOS,
  GRUPOS_SISTEMA,
  OPERADORES,
  PALETA,
  PAPEIS,
  PASSOS,
  REGRAS_ADVBOX,
  ROTINAS,
  TIPOS_ATIVIDADE,
} from '../fluxo';
import { MODELOS } from '../modelos';
import { OBRIGATORIOS } from '../validar';

const folhas = (obj, prefixo = '') =>
  Object.entries(obj).flatMap(([k, v]) =>
    typeof v === 'object'
      ? folhas(v, `${prefixo}${k}.`)
      : [[`${prefixo}${k}`, v]]
  );

describe('textos das automações', () => {
  const FLUXOS_EN = en.CAPTAIN_RAMON.FLUXOS;
  const FLUXOS_PT = pt.CAPTAIN_RAMON.FLUXOS;

  it('en e pt_BR têm as mesmas chaves', () => {
    expect(folhas(FLUXOS_PT).map(([k]) => k)).toEqual(
      folhas(FLUXOS_EN).map(([k]) => k)
    );
    expect(ptSettings.SIDEBAR.CAPTAIN_AUTOMACOES).toBe('Automações');
    expect(enSettings.SIDEBAR.CAPTAIN_AUTOMACOES).toBe('Automations');
  });

  it.each([
    ['en', FLUXOS_EN],
    ['pt_BR', FLUXOS_PT],
  ])(
    '%s: sem @ | e chaves soltas (quebra o vue-i18n de produção)',
    (_l, textos) => {
      folhas(textos).forEach(([chave, texto]) => {
        const semPlaceholders = texto.replace(/\{[a-z_]+\}/gi, '');
        expect([chave, /[@|{}]/.test(semPlaceholders)]).toEqual([chave, false]);
      });
    }
  );

  // Trava de sintaxe: o compilador de PRODUÇÃO lança em qualquer erro (o de dev é permissivo).
  it.each([
    ['en', en, FLUXOS_EN],
    ['pt_BR', pt, FLUXOS_PT],
  ])(
    '%s: todas as chaves compilam no vue-i18n de produção',
    (loc, raiz, textos) => {
      const i18n = createI18n({
        legacy: false,
        locale: loc,
        messages: { [loc]: raiz },
        missingWarn: false,
        fallbackWarn: false,
      });
      const params = {
        n: 1,
        id: 1,
        versao: 1,
        numero: 1,
        data: 'x',
        total: 1,
        etapas: 'x',
        caixas: 'x',
        saida: 'x',
        tipo: 'x',
        campo: 'x',
        nome: 'x',
        quando: 'x',
        erro: 'x',
        inicio: 'x',
        fim: 'x',
      };
      const erros = [];
      folhas(textos).forEach(([chave]) => {
        try {
          const k = `CAPTAIN_RAMON.FLUXOS.${chave}`;
          const out = i18n.global.t(k, params);
          if (out === k) erros.push(`${chave}: não resolveu`);
        } catch (e) {
          erros.push(`${chave}: ${e.message}`);
        }
      });
      expect(erros).toEqual([]);
    }
  );

  it('cobre todo o catálogo', () => {
    GATILHOS.forEach(g => expect(FLUXOS_PT.GATILHOS[g.tipo]).toBeTruthy());
    Object.keys(PASSOS).forEach(t =>
      expect(
        [t, FLUXOS_PT.PASSOS[t], FLUXOS_PT.CABECALHO[t]].every(Boolean)
      ).toBe(true)
    );
    PALETA.forEach(g => {
      expect(FLUXOS_PT.GRUPOS[g.grupo]).toBeTruthy();
      g.itens.forEach(i => expect(FLUXOS_PT.PALETA[i.chave]).toBeTruthy());
    });
    ACOES_CHATWOOT.forEach(a =>
      expect(FLUXOS_PT.ACOES_CHATWOOT[a.nome]).toBeTruthy()
    );
    CAMPOS.forEach(c => expect(FLUXOS_PT.CAMPOS[c]).toBeTruthy());
    OPERADORES.forEach(o => expect(FLUXOS_PT.OPERADORES[o]).toBeTruthy());
    MODELOS.forEach(m => expect(FLUXOS_PT.MODELOS[m.chave].NOME).toBeTruthy());
    REGRAS_ADVBOX.forEach(r => expect(FLUXOS_PT.REGRAS_ADVBOX[r]).toBeTruthy());
    PAPEIS.forEach(p => expect(FLUXOS_PT.PAPEIS[p]).toBeTruthy());
    ROTINAS.forEach(r => {
      expect(FLUXOS_PT.ROTINAS[r]).toBeTruthy();
      expect(FLUXOS_PT.ROTINAS_AJUDA[r]).toBeTruthy();
    });
    TIPOS_ATIVIDADE.forEach(k =>
      expect(FLUXOS_PT.TIPOS_ATIVIDADE[k]).toBeTruthy()
    );
    // chaves do HOJE em app/services/ramon/fluxos/sistema.rb: cada uma precisa da dica
    [
      'cadencia',
      'sla_primeira_resposta',
      'lembretes_reuniao',
      'eventos_advbox',
      'lead_ganho',
      'docs_completos',
      'contrato_limpo',
      'copiloto_noturno',
      'chegada_cliente',
      'publicar_pecas',
    ].forEach(k => {
      expect(FLUXOS_PT.SISTEMA.HOJE_DE[k]).toBeTruthy();
      expect(FLUXOS_EN.SISTEMA.HOJE_DE[k]).toBeTruthy();
    });
    GRUPOS_SISTEMA.forEach(g =>
      expect(FLUXOS_PT.SISTEMA.GRUPOS[g]).toBeTruthy()
    );
    ALCANCES.forEach(a => expect(FLUXOS_PT.SISTEMA.ALCANCE[a]).toBeTruthy());
    [
      ...Object.values(OBRIGATORIOS).flat(),
      'tipo_tarefa_id',
      'responsavel_id',
    ].forEach(c =>
      expect([c, Boolean(FLUXOS_PT.CAMPOS_OBRIGATORIOS[c])]).toEqual([c, true])
    );
    [
      'GATILHO_HORA',
      'ADVBOX_ACAO',
      'ADVBOX_DESCRICAO',
      'WEBHOOK_HTTPS',
      'WEBHOOK_ULTIMO',
      'CAMPO_CHAVE',
      'CONTA_QUANDO',
      'CONTA_PASSO',
      'ROTINA_DESCONHECIDA',
      'ROTINA_DE_LEAD',
      'ROTINA_DA_CONTA',
    ].forEach(c => expect(FLUXOS_PT.ERROS[c]).toBeTruthy());
  });
});

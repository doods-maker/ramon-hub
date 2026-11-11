import os, tempfile, unittest, datetime as dt
import agente_hub as ah


class Cfg:
    EDUARDO_EMAIL = 'edu@x.com'
    WEBHOOK_SECRET = 's3'
    CAP_DIA = 2


class TestParse(unittest.TestCase):
    def test_marcadores(self):
        r = ah.parse_pedido('@claude #pesado #tese:aposentadoria monta o dossiê')
        self.assertEqual(r, {'pedido': 'monta o dossiê', 'esforco': 'medium', 'tese': 'aposentadoria'})

    def test_default(self):
        self.assertEqual(ah.parse_pedido('@Claude resume')['esforco'], 'low')


class TestAceita(unittest.TestCase):
    def test_ok(self):
        ok, _ = ah.aceita({'sender_email': 'edu@x.com', 'content': '@claude oi'}, 's3', Cfg)
        self.assertTrue(ok)

    def test_recusa(self):
        for p, h in [({'sender_email': 'o@x.com', 'content': '@claude oi'}, 's3'),
                     ({'sender_email': 'edu@x.com', 'content': 'oi'}, 's3'),
                     ({'sender_email': 'edu@x.com', 'content': '@claude oi'}, 'errado')]:
            self.assertFalse(ah.aceita(p, h, Cfg)[0])

    def test_segredo_vazio_nunca_autentica(self):
        class SemSegredo(Cfg):
            WEBHOOK_SECRET = ''
        for segredo, h in [('', ''), ('', None), ('  ', '  ')]:
            SemSegredo.WEBHOOK_SECRET = segredo
            self.assertFalse(ah.aceita({'sender_email': 'edu@x.com', 'content': '@claude oi'}, h, SemSegredo)[0])


class TestCap(unittest.TestCase):
    def test_cap_e_pausa(self):
        d = tempfile.mkdtemp()
        cap = ah.Cap(d, 2)
        self.assertTrue(cap.pode())
        cap.conta()
        cap.conta()
        self.assertFalse(cap.pode())
        cap2 = ah.Cap(tempfile.mkdtemp(), 5)
        cap2.pausar_ate_amanha()
        self.assertFalse(cap2.pode())


class TestNota(unittest.TestCase):
    def test_formato(self):
        n = ah.formatar_nota('ok', 12.4, 'Resposta.', [{'tipo': 'drive', 'ref': 'https://d/x'}])
        self.assertTrue(n.startswith('🤖 Claude · ok · 12s'))
        self.assertIn('— Ações: drive → https://d/x', n)
        self.assertIn('nenhuma escrita', ah.formatar_nota('ok', 1, 'r', []))

    def test_limite(self):
        self.assertTrue(ah.detecta_limite('Error: usage limit reached'))
        self.assertFalse(ah.detecta_limite('tudo certo'))


class TestExtrair(unittest.TestCase):
    def test_structured_output(self):
        self.assertEqual(ah.extrair_estruturado('{"structured_output": {"resposta": "oi"}}'), {'resposta': 'oi'})

    def test_result_string(self):
        self.assertEqual(ah.extrair_estruturado('{"result": "{\\"resposta\\": \\"oi\\"}"}'), {'resposta': 'oi'})

    def test_lixo(self):
        for s in ['', 'Not logged in', '{quebrado', '{"result": "texto solto"}']:
            self.assertEqual(ah.extrair_estruturado(s), {})


class TestUso(unittest.TestCase):
    def test_tokens_e_custo(self):
        saida = ('{"total_cost_usd": 0.4213, "usage": {"input_tokens": 10, "cache_creation_input_tokens": 200, '
                 '"cache_read_input_tokens": 3000, "output_tokens": 50}, "structured_output": {"resposta": "oi"}}')
        self.assertEqual(ah.extrair_uso(saida), {'input_tokens': 3210, 'output_tokens': 50, 'custo_usd': 0.4213})

    def test_sem_uso(self):
        for s in ['', 'Not logged in', '{quebrado', '{"result": "x"}']:
            self.assertEqual(ah.extrair_uso(s), {})


class TestCmd(unittest.TestCase):
    def test_flags(self):
        cfg = ah.Cfg({'CLAUDE_CODE_OAUTH_TOKEN': 't', 'HUB_URL': 'h', 'ACCOUNT_ID': '2', 'HUB_AGENTE_TOKEN': 'a',
                      'HUB_MCP_TOKEN': 'm', 'WEBHOOK_SECRET': 's', 'EDUARDO_EMAIL': 'e'})
        cmd = ah.montar_cmd(cfg, 'medium')
        readme = open(os.path.join(os.path.dirname(__file__), 'README.md'), encoding='utf-8').read()
        self.assertNotIn(readme, cmd)  # prompt vai por stdin, nunca como argumento
        self.assertNotIn('--bare', cmd)  # --bare ignora CLAUDE_CODE_OAUTH_TOKEN
        self.assertIn('--strict-mcp-config', cmd)
        self.assertIn('--json-schema', cmd)
        self.assertIn('medium', cmd)
        self.assertNotIn('Bash', cmd[cmd.index('--allowedTools') + 1])


class TestTarefa(unittest.TestCase):
    def test_responsavel_por_tarefa_ou_padrao(self):
        cfg = ah.Cfg({'CLAUDE_CODE_OAUTH_TOKEN': 't', 'HUB_URL': 'h', 'ACCOUNT_ID': '2', 'HUB_AGENTE_TOKEN': 'a',
                      'HUB_MCP_TOKEN': 'm', 'WEBHOOK_SECRET': 's', 'EDUARDO_EMAIL': 'e'})
        a = ah.args_tarefa(cfg, {'lawsuit_id': 9, 'texto': 'x', 'responsavel_id': 123}, 'x')
        self.assertEqual((a['processo_id'], a['responsavel_id'], a['criador_id']), (9, 123, cfg.ADVBOX_TAREFA_RESPONSAVEL_ID))
        b = ah.args_tarefa(cfg, {'lawsuit_id': 9, 'texto': 'x'}, 'x')
        self.assertEqual((b['responsavel_id'], b['tipo_tarefa_id']), (cfg.ADVBOX_TAREFA_RESPONSAVEL_ID, cfg.ADVBOX_TAREFA_TIPO_ID))
        c = ah.args_tarefa(cfg, {'lawsuit_id': 9, 'texto': 'x', 'responsavel_id': 'abc'}, 'x')
        self.assertEqual(c['responsavel_id'], cfg.ADVBOX_TAREFA_RESPONSAVEL_ID)

    def test_so_cria_tarefa_no_processo_do_lead_da_conversa(self):
        ta = {'lawsuit_id': 9, 'texto': 'x'}
        self.assertTrue(ah.tarefa_valida(ta, {'advbox_lawsuit_id': 9}))
        self.assertTrue(ah.tarefa_valida({'lawsuit_id': '9', 'texto': 'x'}, {'advbox_lawsuit_id': 9}))
        self.assertFalse(ah.tarefa_valida(ta, {'advbox_lawsuit_id': 7}))   # processo de outro cliente (injeção)
        self.assertFalse(ah.tarefa_valida(ta, {'advbox_lawsuit_id': None}))  # lead sem processo no ADVBOX
        self.assertFalse(ah.tarefa_valida({'lawsuit_id': None, 'texto': 'x'}, {'advbox_lawsuit_id': None}))
        self.assertFalse(ah.tarefa_valida({'lawsuit_id': 9, 'texto': '  '}, {'advbox_lawsuit_id': 9}))
        self.assertFalse(ah.tarefa_valida(None, {'advbox_lawsuit_id': 9}))


class TestArquivo(unittest.TestCase):
    def test_so_sobe_documento_com_conteudo(self):
        doc = {'nome': 'dossie-1-2026-09-16.md', 'conteudo_md': '# Dossiê'}
        self.assertTrue(ah.arquivo_valido({'pedido': 'monta o dossiê pro jurídico'}, doc))
        self.assertFalse(ah.arquivo_valido({'pedido': 'resume este caso em 5 linhas'}, doc))
        self.assertFalse(ah.arquivo_valido({'pedido': 'monta o dossiê'}, {'nome': 'dossie.md', 'conteudo_md': '  '}))
        self.assertFalse(ah.arquivo_valido({'pedido': 'monta o dossiê'}, {'nome': '', 'conteudo_md': 'x'}))
        self.assertFalse(ah.arquivo_valido({'pedido': 'monta o dossiê'}, None))


class TestTokenForaDaUrl(unittest.TestCase):
    class C:
        HUB_URL = 'https://hub'; ACCOUNT_ID = '1'; HUB_AGENTE_TOKEN = 'tok-agente'; HUB_MCP_TOKEN = 'tok-mcp'

    def _capturar(self, chamada):
        from unittest import mock
        resposta = mock.MagicMock()
        resposta.__enter__.return_value.read.return_value = b'{}'
        with mock.patch('urllib.request.urlopen', return_value=resposta) as urlopen:
            chamada()
        return urlopen.call_args[0][0]

    def test_hub_manda_o_token_no_cabecalho(self):
        req = self._capturar(lambda: ah.hub(self.C, 'GET', 'contexto', query={'conversation_id': 7}))
        self.assertNotIn('tok-agente', req.full_url)
        self.assertIn('account_id=1', req.full_url)
        self.assertEqual(req.get_header('X-agente-token'), 'tok-agente')  # urllib guarda o nome capitalizado

    def test_mcp_manda_o_token_no_cabecalho(self):
        req = self._capturar(lambda: ah.mcp_call(self.C, 'advbox_criar_tarefa', {}))
        self.assertNotIn('tok-mcp', req.full_url)
        self.assertEqual(req.get_header('X-mcp-token'), 'tok-mcp')


if __name__ == '__main__':
    unittest.main()

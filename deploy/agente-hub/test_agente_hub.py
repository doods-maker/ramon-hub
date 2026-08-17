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


if __name__ == '__main__':
    unittest.main()

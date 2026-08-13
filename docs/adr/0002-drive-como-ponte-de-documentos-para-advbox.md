# Google Drive como ponte de documentos para o ADVBOX

Queríamos que os documentos coletados na conversa fossem parar automaticamente
no cadastro do cliente no ADVBOX, mas **a API do ADVBOX não tem upload de
documentos** (só `GET /documents` e download; verificado na referência oficial
em 2026-08-13 — sem integração com Drive, e-mail de ingestão ou webhook).
Decidimos: o hub exporta cada documento conferido, renomeado e em PDF, para o
Google Drive (`Clientes\<Nome — CPF>\`, com atalhos diários em
`A enviar ao ADVBOX\<data>\` e sufixo `— COMPLETO` na pasta quando o checklist
fecha); o upload Drive → ADVBOX é ritual manual diário do Eduardo. Se a API do
ADVBOX ganhar upload um dia, a ponte manual é o único pedaço a substituir.

Automação de navegador sobre a interface do ADVBOX foi rejeitada: frágil,
quebra a cada mudança de tela deles.

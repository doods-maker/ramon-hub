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

**Quem marca "recebido" (17/10 e 18/10/2026).** Em 17/10 o doc-match passou a
marcar o item direto quando a IA *vê* o arquivo (foto/PDF no Claude Haiku);
sem visão, só sugere. Em 18/10 o Eduardo restringiu: em lead **ganho** a IA só
sugere, mesmo com visão — ali marcar sobe o arquivo para o Drive, cria o atalho
em `A enviar ao ADVBOX` e pode fechar o checklist, então um erro da IA vira
arquivo errado no cliente. Antes do Ganho continua marcando direto.
